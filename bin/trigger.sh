#!/bin/bash -l

# EXAMPLES: 
#./bin/trigger.sh crg prod /users/pr/qsample/atlas/assets 
#./bin/trigger.sh crg test /users/pr/qsample/test/atlas-last/assets BSA 

## INPUT PARAMS

die () {
    echo >&2 "$@"
    exit 1
}

LAB=$1
MODE=$2
ASSETS_FOLDER=$3
DATA=$4

## PARSE CSV FILENAMES
CSV_FILENAME_RUN_MODES=$(ls $3 | grep $LAB | grep "run_modes")
CSV_FILENAME_RUN_MODES=$3/$CSV_FILENAME_RUN_MODES

## PARSE RUN MODES VARIABLES
if [[ $2 = "prod" ]]; then PROD_MODE="true"; elif [[ $2 = "test" ]]; then TEST_MODE="true"; fi
ORIGIN_FOLDER=$(cat $CSV_FILENAME_RUN_MODES | grep $MODE | cut -d',' -f2)
WF_ROOT_FOLDER=$(cat $CSV_FILENAME_RUN_MODES | grep $MODE | cut -d',' -f3)
ATLAS_RUNS_FOLDER=$(cat $CSV_FILENAME_RUN_MODES | grep $MODE | cut -d',' -f4)
LOGS_FOLDER=$(cat $CSV_FILENAME_RUN_MODES | grep $MODE | cut -d',' -f5)
NOTIF_EMAIL=$(cat $CSV_FILENAME_RUN_MODES | grep $MODE | cut -d',' -f6)
ENABLE_NOTIF_EMAIL=$(cat $CSV_FILENAME_RUN_MODES | grep $MODE | cut -d',' -f7)
ENABLE_NF_TOWER=$(cat $CSV_FILENAME_RUN_MODES | grep $MODE | cut -d',' -f8)
if [[ $ENABLE_NF_TOWER = "true" ]]; then WITH_TOWER="-with-tower"; fi
SEC_REACT_WF=$WF_ROOT_FOLDER"/secreact.nf"
METHODS_CSV=$(ls $3 | grep $LAB | grep "methods")      
METHODS_CSV=$3/$METHODS_CSV

## SECRETS FILE CHECK: 
echo $WF_ROOT_FOLDER
SECRETS_FILE=$(ls $WF_ROOT_FOLDER"/conf" | grep "secret")
if [ ! -f "$WF_ROOT_FOLDER/conf/$SECRETS_FILE" ]; then
   echo "[ERROR] There's no SECRETS file in /config folder. Please check."
   exit
fi 
   
## MANAGE TEST DATA
if [ "$TEST_MODE" = true ] ; then

   CSV_FILENAME_TEST_PARAMS=$(ls $3 | grep $LAB | grep "test_params")
   CSV_FILENAME_TEST_PARAMS=$3/$CSV_FILENAME_TEST_PARAMS

   ## Parse test parameters
   TEST_FILE_REMOTE=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d',' -f2)
   TEST_FILENAME=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d',' -f3)
   TEST_NUM_PROTS_REF=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d',' -f5)
   TEST_NUM_PEPTD_REF=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d',' -f6)
   TEST_FILE_REMOTE=$TEST_FILE_REMOTE"/"$TEST_FILENAME

   # Download files and data, if needed
   mkdir -p $ORIGIN_FOLDER
	 
   # Files
   if [ -f "$ORIGIN_FOLDER/$TEST_FILENAME" ] ; then
      echo "[INFO] Test file $ORIGIN_FOLDER/$TEST_FILENAME already downloaded."
   else 
      wget $TEST_FILE_REMOTE -P $ORIGIN_FOLDER
   fi

fi

##################################
################FUNCTIONS#########
##################################

secondary_reaction () {
 echo "Sending secondary reaction workflow for modification $1 and file $2 ..."
 nextflow run ${SEC_REACT_WF} -bg -work-dir $ATLAS_RUNS_FOLDER/$CURRENT_UUID --var_modif "'Oxidation (M)' 'Acetyl (N-term)'" -profile $LAB,small --sec_react_modif "$1" --fragment_mass_tolerance '0.5' --fragment_error_units 'Da' --search_engine comet --rawfile $2 > $3
 sleep 60
}

launch_nf_run () {

      if [ "${10}" = true ]
      then
        INSTRUMENT_FOLDER=$(echo ${FILE_BASENAME} | cut -f 3 -d '.')
      else 
        INSTRUMENT_FOLDER=''
      fi
      ####### LAUNCH TO NEXTFLOW ####### 
      nextflow run $2 $WITH_TOWER -bg -work-dir $ATLAS_RUNS_FOLDER/$CURRENT_UUID --var_modif "$3" --fragment_mass_tolerance "$4" --fragment_error_units "$5" --precursor_mass_tolerance "$6" --precursor_error_units "$7" --missed_cleavages "$8" --output_folder "$9" --instrument_folder "$INSTRUMENT_FOLDER" --search_engine "${11}" -profile $LAB,"${12}" --rawfile ${13} --test_mode $TEST_MODE --test_folder $ORIGIN_FOLDER > ${14}
 
      # Reporting log:
      echo "[INFO] ################################################################"
      echo "[INFO] ~~~~~~~~~~~~~~~~PROCESSING FILE ${FILE_BASENAME}~~~~~~~~~~~~~~~~"
      echo "[INFO] Application name: $1"
      echo "[INFO] Workflow: $2"
      echo "[INFO] Variable modifications: $3"
      echo "[INFO] Fragment mass tolerance: $4"
      echo "[INFO] Fragment error units: $5"
      echo "[INFO] Precursor mass tolerance: $6"
      echo "[INFO] Precursor mass units: $7"
      echo "[INFO] Missed cleavages: $8"
      echo "[INFO] Ouptut folder: $9"
      echo "[INFO] Instrument subfolder: $INSTRUMENT_FOLDER"
      echo "[INFO] Search engine: ${11}"
      echo "[INFO] NF Profile: $LAB,${12}"
      echo "[INFO] Raw file: ${13}"
      echo "[INFO] Log file: ${14}"
      echo "[INFO] Working folder: $ATLAS_RUNS_FOLDER/$CURRENT_UUID"
      echo "[INFO] ###############################################################"
      echo "[INFO] ###############################################################"
      if [ "$ENABLE_NOTIF_EMAIL" = true ] ; then
        echo "[INFO] This file was sent to the QSample pipeline..." | mail -s ${FILE_BASENAME} "$NOTIF_EMAIL"
      fi     

}

launch_all_secondary_reactions () {
      secondary_reaction "'Formyl (N-term)'" ${1} ${2}_formyl_n.log
      secondary_reaction "'Carbamyl (N-term)'" ${1} ${2}_carbamyl_n.log
      secondary_reaction "'Gln->pyro-Glu (N-term Q)'" ${1} ${2}_pyro_glu.log
      secondary_reaction "'Carbamyl (K)'" ${1} ${2}_carbamyl_k.log
      secondary_reaction "'Carbamyl (R)'" ${1} ${2}_carbamyl_r.log
      secondary_reaction "'Formyl (K)'" ${1} ${2}_formyl_k.log
      secondary_reaction "'Formyl (S)'" ${1} ${2}_formyl_s.log
      secondary_reaction "'Formyl (T)'" ${1} ${2}_formyl_t.log
      secondary_reaction "'Deamidated (N)'" ${1} ${2}_deamidated_n.log
}


################FUNCTIONS END


###########################
################KERNEL#####
###########################

DATE_LOG=`date '+%Y-%m-%d %H:%M:%S'`
echo "[INFO] -----------------START---[${DATE_LOG}]"


	LIST_PATTERNS=$(cat ${METHODS_CSV} | cut -d',' -f1 | tail -n +2)

	FILE_TO_PROCESS=$(find ${ORIGIN_FOLDER} \( -iname "*.raw.*" ! -iname "*.undefined" ! -iname "*.filepart" ! -iname "*QBSA*" ! -iname "*QHela*" ! -iname "*sp *" ! -iname "*log*" \) -type f -mtime -7 -printf "%h %f %s\n" | sort -r | awk '{print $1"/"$2}' | head -n1)

	if [ -n "$FILE_TO_PROCESS" ]; then

	 FILE_BASENAME=$(basename $FILE_TO_PROCESS)
	 FILE_ARR=($(echo $FILE_BASENAME | tr "_" "\n"))
	 REQUEST="${FILE_ARR[0]}"
	 QCCODE="${FILE_ARR[1]}"

	 for j in ${LIST_PATTERNS}
	 do

	  if [ "$(echo $REQUEST | grep $j)" ] || [ "$QCCODE" = "$j" ]; then

	    echo "[INFO] Found pattern $j in filename $FILE_BASENAME"

	    CURRENT_UUID=$(uuidgen)
	    CURRENT_UUID_FOLDER=$ATLAS_RUNS_FOLDER/$CURRENT_UUID

            if [ "$PROD_MODE" = "true" ] ; then
                mkdir -p $CURRENT_UUID_FOLDER
                cd $CURRENT_UUID_FOLDER
                mv $FILE_TO_PROCESS $CURRENT_UUID_FOLDER
            fi

	    WF=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f2)
	    NAME=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f3)
	    VAR_MODIF=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f4)
	    FMT=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f5)
	    FEU=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f6)
	    PMT=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f7)
	    PEU=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f8)
	    MC=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f9)
	    OF=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f10)
	    IF=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f11)
	    ENGINE=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f12)
            NF_PROFILE=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f13)
            COMPUTE_SEC_REACT=$(cat ${METHODS_CSV} | grep "^$j," | cut -d',' -f14)

	    ##############LAUNCH NEXTFLOW PROCESSES
            # save num_prtos and peptd with filename encoded and test all script (before general TSV). 
            if [ "$TEST_MODE" = "true" ] ; then
               RAWFILE_TO_PROCESS=$ORIGIN_FOLDER/$TEST_FILENAME
               COMPUTE_SEC_REACT=false
            elif [ "$PROD_MODE" = "true" ] ; then
               RAWFILE_TO_PROCESS=$CURRENT_UUID_FOLDER/${FILE_BASENAME}
               TEST_MODE="false"
            fi
            if [ -f "$RAWFILE_TO_PROCESS" ]; then
             launch_nf_run $NAME $WF_ROOT_FOLDER/$WF".nf" "$VAR_MODIF" $FMT $FEU $PMT $PEU $MC $OF $IF $ENGINE $NF_PROFILE $RAWFILE_TO_PROCESS ${LOGS_FOLDER}/${FILE_BASENAME}.log
             if [ "$(echo $REQUEST | grep $j)" ] && [ "$COMPUTE_SEC_REACT" = true ]; then launch_all_secondary_reactions $CURRENT_UUID_FOLDER/${FILE_BASENAME} ${LOGS_FOLDER}/${FILE_BASENAME}.log; fi
            else 
             echo "[ERROR] File ${RAWFILE_TO_PROCESS} not found."
            fi

	  fi

	 done

	fi

echo "[INFO] -----------------EOF"

################KERNEL END
