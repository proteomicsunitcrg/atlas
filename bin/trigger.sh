#!/bin/bash -l

##############################
################RUN MODES##### 
##############################

TEST_MODE=false
DEBUG_MODE=false
DEBUG_MODE_FAKE=false
PROD_MODE=false

if [[ $1 = "test" ]]; then

    echo "[INFO] Running in test mode..."
    source ../conf/trigger_test.cf

    if [[ $2 = "fast" ]]; then
    	TEST_FILENAME=$TEST_FILENAME_FAST
    	TEST_FILE_REMOTE=$TEST_FILE_REMOTE_FAST
    	NUM_PROTS_REF=$NUM_PROTS_REF_FAST
    	NUM_PEPTD_REF=$NUM_PEPTD_REF_FAST
    elif [[ $2 = "dda" ]]; then
    	TEST_FILENAME=$TEST_FILENAME_DDA
        TEST_FILE_REMOTE=$TEST_FILE_REMOTE_DDA
        NUM_PROTS_REF=$NUM_PROTS_REF_DDA
        NUM_PEPTD_REF=$NUM_PEPTD_REF_DDA
    elif [[ $2 = "silac" ]]; then
        TEST_FILENAME=$TEST_FILENAME_SILAC
        TEST_FILE_REMOTE=$TEST_FILE_REMOTE_SILAC
        NUM_PROTS_REF=$NUM_PROTS_REF_SILAC
        NUM_PEPTD_REF=$NUM_PEPTD_REF_SILAC
    elif [[ $2 = "diann" ]]; then
        TEST_FILENAME=$TEST_FILENAME_DIANN
        TEST_FILE_REMOTE=$TEST_FILE_REMOTE_DIANN
        NUM_PROTS_REF=$NUM_PROTS_REF_DIANN
        NUM_PEPTD_REF=$NUM_PEPTD_REF_DIANN
    elif [[ $2 = "diaumpire" ]]; then
        TEST_FILENAME=$TEST_FILENAME_DIAUMPIRE
        TEST_FILE_REMOTE=$TEST_FILE_REMOTE_DIAUMPIRE
        NUM_PROTS_REF=$NUM_PROTS_REF_DIAUMPIRE
        NUM_PEPTD_REF=$NUM_PEPTD_REF_DIAUMPIRE
    fi


elif [[ $1 = "debug" ]]; then
    echo "[INFO] Running in debug mode..."
    source ../conf/trigger_debug.cf
    if [[ $2 = "fake" ]]; then
      DEBUG_MODE_FAKE=true
    fi

else

    echo "[INFO] Running in production mode..."
    source ../conf/trigger_prod.cf
fi


################RUN MODES END


##################################
################FUNCTIONS#########
##################################

secondary_reaction () {
 echo "Sending secondary reaction workflow for modification $1 and file $2 ..."
 nextflow run ${SEC_REACT_WF} -bg -work-dir $ATLAS_RUNS_FOLDER/$CURRENT_UUID --var_modif "'Oxidation (M)' 'Acetyl (N-term)'" -profile small --sec_react_modif "$1" --fragment_mass_tolerance '0.5' --fragment_error_units 'Da' --search_engine comet --rawfile $2 > $3
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
      nextflow run $2 -with-tower -bg -work-dir $ATLAS_RUNS_FOLDER/$CURRENT_UUID --var_modif "$3" --fragment_mass_tolerance "$4" --fragment_error_units "$5" --precursor_mass_tolerance "$6" --precursor_error_units "$7" --missed_cleavages "$8" --output_folder "$9" --instrument_folder "$INSTRUMENT_FOLDER" --search_engine "${11}" -profile "${12}" --rawfile ${13} > ${14}
 
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
      echo "[INFO] NF Profile: ${12}"
      echo "[INFO] Raw file: ${13}"
      echo "[INFO] Log file: ${14}"
      echo "[INFO] Working folder: $ATLAS_RUNS_FOLDER/$CURRENT_UUID"
      echo "[INFO] ###############################################################"
      echo "[INFO] ###############################################################"
      echo "[INFO] This file was sent to the QSample pipeline..." | mail -s ${FILE_BASENAME} "roger.olivella@crg.eu"

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

if [ "$TEST_MODE" = true ] ; then

	 mkdir -p $WF_ROOT_FOLDER/$TEST_SUBFOLDER
      	 cd $WF_ROOT_FOLDER/$TEST_SUBFOLDER
	 
 	 if [ -f "$WF_ROOT_FOLDER/$TEST_SUBFOLDER/$TEST_FILENAME" ] ; then
            echo "[INFO] Test file $WF_ROOT_FOLDER/$TEST_SUBFOLDER/$TEST_FILENAME already downloaded."
         else 
            wget $TEST_FILE_REMOTE
         fi

         echo "[INFO] Cheking Nextflow installation..."
         NF_VER=`nextflow -v`

         if [[ $NF_VER == *"nextflow"* ]]; then

                echo "[INFO] Nextflow present!"
      
                if [[ $2 = "fast" ]]; then
                        echo "[INFO] Running DDA fast test, please do not stop this process..."
                        nextflow run $WF_ROOT_FOLDER/"main.nf" --var_modif "'Oxidation (M)' 'Acetyl (N-term)'" -with-tower --fragment_mass_tolerance "0.5" --fragment_error_units "Da" --precursor_mass_tolerance "7" --precursor_error_units "ppm" --missed_cleavages "3" --search_engine "comet" --rawfile $WF_ROOT_FOLDER/$TEST_SUBFOLDER/$TEST_FILENAME -profile small --test_mode --test_folder $WF_ROOT_FOLDER/$TEST_SUBFOLDER
                elif [[ $2 = "dda" ]]; then
                 	echo "[INFO] Running DDA test, please do not stop this process..."
                	nextflow run $WF_ROOT_FOLDER/"main.nf" --var_modif "'Oxidation (M)' 'Acetyl (N-term)'" -with-tower --fragment_mass_tolerance "0.5" --fragment_error_units "Da" --precursor_mass_tolerance "7" --precursor_error_units "ppm" --missed_cleavages "3" --search_engine "comet" --rawfile $WF_ROOT_FOLDER/$TEST_SUBFOLDER/$TEST_FILENAME -profile medium --test_mode --test_folder $WF_ROOT_FOLDER/$TEST_SUBFOLDER
                elif [[ $2 = "silac" ]]; then
                        echo "[INFO] Running SILAC big test, please do not stop this process..."
                        nextflow run $WF_ROOT_FOLDER/"main.nf" --var_modif "'Oxidation (M)' 'Acetyl (N-term)' 'Label:13C(6)15N(4) (R)' 'Label:13C(6)15N(2) (K)' 'Label:13C(6) (K)' 'Label:13C(6) (R)'" -with-tower --fragment_mass_tolerance "0.5" --fragment_error_units "Da" --precursor_mass_tolerance "7" --precursor_error_units "ppm" --missed_cleavages "3" --search_engine "comet" --rawfile $WF_ROOT_FOLDER/$TEST_SUBFOLDER/$TEST_FILENAME -profile big --test_mode --test_folder $WF_ROOT_FOLDER/$TEST_SUBFOLDER
               elif [[ $2 = "diann" ]]; then
                        echo "[INFO] Running DIA-NN test, please do not stop this process..."
                        nextflow run $WF_ROOT_FOLDER/"diann.nf" --var_modif "'Oxidation (M)' 'Acetyl (N-term)'" --rawfile $WF_ROOT_FOLDER/$TEST_SUBFOLDER/$TEST_FILENAME -with-tower -profile medium --test_mode --test_folder $WF_ROOT_FOLDER/$TEST_SUBFOLDER
                elif [[ $2 = "diaumpire" ]]; then
                        echo "[INFO] Running DIA UMPIRE test, please do not stop this process..."
                        nextflow run $WF_ROOT_FOLDER/"diaumpire.nf" --search_engine "comet" --var_modif "'Oxidation (M)' 'Acetyl (N-term)'" --rawfile $WF_ROOT_FOLDER/$TEST_SUBFOLDER/$TEST_FILENAME -with-tower -profile medium --test_mode --test_folder $WF_ROOT_FOLDER/$TEST_SUBFOLDER           
                fi

         	FILE_BASENAME=`basename $WF_ROOT_FOLDER/$TEST_SUBFOLDER/$TEST_FILENAME |  cut -f 1 -d '.'`
         	NUM_PROTS_COMP=`cat $FILE_BASENAME".num_prots"`
         	NUM_PEPTD_COMP=`cat $FILE_BASENAME".num_peptd"`
                echo "[INFO] Removing result files..."
                rm $FILE_BASENAME".num_prots"
                rm $FILE_BASENAME".num_peptd"

         	if [ "$NUM_PROTS_REF" = "$NUM_PROTS_COMP" ]; then
            		echo "[INFO] TEST SUCCESSFUL! :) Tested run gave same number of proteins as the reference value."
         	else
            		echo "[ERROR] TEST UNSUCCESSFUL! :( Tested run DOES NOT gave same number of proteins as the reference value ($NUM_PROTS_REF). Please check."
         	fi

         	if [ "$NUM_PEPTD_REF" = "$NUM_PEPTD_COMP" ]; then
            		echo "[INFO] TEST SUCCESSFUL! :) Tested run gave same number of peptides as the reference value."
         	else
            		echo "[ERROR] TEST UNSUCCESSFUL! :( Tested run DOES NOT gave same number of peptides as the reference value ($NUM_PEPTD_REF). Please check."
         	fi
         else
         	echo "[ERROR] Nextflow not present. Please install it from https://www.nextflow.io."
         fi
   
elif [ "$DEBUG_MODE" = true ] || [ "$PROD_MODE" = true ]; then

	LIST_PATTERNS=$(cat ${ATLAS_CSV} | cut -d',' -f1 | tail -n +2)

	FILE_TO_PROCESS=$(find ${ORIGIN_FOLDER} \( -iname "*.raw.*" ! -iname "*.undefined" ! -iname "*.filepart" ! -iname "*QBSA*" ! -iname "*QHela*" ! -iname "*sp *" \) -type f -mtime -7 -printf "%h %f %s\n" | sort -r | awk '{print $1"/"$2}' | head -n1)

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

	    if [ "$DEBUG_MODE_FAKE" = false ] ; then
	     mkdir -p $CURRENT_UUID_FOLDER
	     cd $CURRENT_UUID_FOLDER
	     mv $FILE_TO_PROCESS $CURRENT_UUID_FOLDER
	    fi

	    WF=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f2)
	    NAME=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f3)
	    VAR_MODIF=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f4)
	    FMT=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f5)
	    FEU=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f6)
	    PMT=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f7)
	    PEU=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f8)
	    MC=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f9)
	    OF=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f10)
	    IF=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f11)
	    ENGINE=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f12)
            NF_PROFILE=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f13)
            COMPUTE_SEC_REACT=$(cat ${ATLAS_CSV} | grep "^$j," | cut -d',' -f14)

	    ###############LAUNCH NEXTFLOW PROCESSES
	    if [ "$DEBUG_MODE" = false ] ; then
	     launch_nf_run $NAME $WF_ROOT_FOLDER/$WF".nf" "$VAR_MODIF" $FMT $FEU $PMT $PEU $MC $OF $IF $ENGINE $NF_PROFILE $CURRENT_UUID_FOLDER/${FILE_BASENAME} ${LOGS_FOLDER}/${FILE_BASENAME}.log
	     if [ "$(echo $REQUEST | grep $j)" ] && [ "$COMPUTE_SEC_REACT" = true ]; then launch_all_secondary_reactions $CURRENT_UUID_FOLDER/${FILE_BASENAME} ${LOGS_FOLDER}/${FILE_BASENAME}.log; fi
	    elif [ "$DEBUG_MODE" = true ] ; then
             if [ "$DEBUG_MODE_FAKE" = true ] ; then
 		echo "FAKE launch_nf_run..."
                if [ "$(echo $REQUEST | grep $j)" ] && [ "$COMPUTE_SEC_REACT" = true ]; then echo "FAKE launch_all_secondary_reactions..."; fi
             else
                launch_nf_run $NAME $WF_ROOT_FOLDER/$WF".nf" "$VAR_MODIF" $FMT $FEU $PMT $PEU $MC $OF $IF $ENGINE $NF_PROFILE $CURRENT_UUID_FOLDER/${FILE_BASENAME} ${LOGS_FOLDER}/${FILE_BASENAME}.log
                if [ "$(echo $REQUEST | grep $j)" ] && [ "$COMPUTE_SEC_REACT" = true ]; then launch_all_secondary_reactions $CURRENT_UUID_FOLDER/${FILE_BASENAME} ${LOGS_FOLDER}/${FILE_BASENAME}.log; fi 
             fi 
	    fi

	  fi

	 done

	fi

fi



echo "[INFO] -----------------EOF"

################KERNEL END
