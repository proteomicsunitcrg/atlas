#!/bin/bash -l

# Author: Roger Olivella
# Created: 30/03/2021

##############################
################HARDCODES##### 
##############################

TEST_MODE=false

if [ "$TEST_MODE" = false ] ; then
 LOGS_FOLDER=/users/pr/qsample/logs
 ORIGIN_FOLDER=/users/pr/backuppr/scratch
 TIME=-7
 SLEEP_PROCESS=900
 ATLAS_RUNS_FOLDER=/users/pr/qsample/atlas-runs
 ATLAS_CSV=/users/pr/qsample/atlas/assets/atlas.csv
 SEC_REACT_WF=/users/pr/qsample/atlas/secreact.nf
 WF_ROOT_FOLDER=/users/pr/qsample/atlas

elif [ "$TEST_MODE" = true ] ; then
 #Remeber to edit atlas test repo
 LOGS_FOLDER=/users/pr/qsample/test/logs
 ORIGIN_FOLDER=/users/pr/qsample/test/toy-dataset/files_to_process
 TIME=-7777
 SLEEP_PROCESS=60
 ATLAS_RUNS_FOLDER=/users/pr/qsample/atlas-runs
 ATLAS_CSV=/users/pr/qsample/test/atlas-trigger/assets/atlas.csv
 SEC_REACT_WF=/users/pr/qsample/test/atlas-trigger/secreact.nf
 WF_ROOT_FOLDER=/users/pr/qsample/test/atlas-trigger
fi

################HARCODES END


##################################
################FUNCTIONS#########
##################################

secondary_reaction () {
 echo "Sending secondary reaction workflow for modification $1 and file $2 ..."
 nextflow run ${SEC_REACT_WF} -bg -work-dir $ATLAS_RUNS_FOLDER/$CURRENT_UUID --var_modif "'Oxidation (M)' 'Acetyl (N-term)'" --sec_react_modif "$1" --fragment_mass_tolerance '0.5' --fragment_error_units 'Da' --search_engine comet --rawfile $2 > $3
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
      nextflow run $2 -with-tower -bg -work-dir $ATLAS_RUNS_FOLDER/$CURRENT_UUID --var_modif "$3" --fragment_mass_tolerance "$4" --fragment_error_units "$5" --precursor_mass_tolerance "$6" --precursor_error_units "$7" --missed_cleavages "$8" --output_folder "$9" --instrument_folder "$INSTRUMENT_FOLDER" --search_engine "${11}" --rawfile ${12} > ${13}
    
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
      echo "[INFO] Raw file: ${12}"
      echo "[INFO] Log file: ${13}"
      echo "[INFO] Working folder: $ATLAS_RUNS_FOLDER/$CURRENT_UUID"
      echo "[INFO] ###############################################################"
      echo "[INFO] ###############################################################"
      echo "[INFO] This file was sent to the QSample pipeline..." | mail -s ${FILE_BASENAME} "roger.olivella@crg.eu"
      sleep ${SLEEP_PROCESS}

}

launch_all_secondary_reactions (){
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

LIST_PATTERNS=$(cat ${ATLAS_CSV} | cut -d',' -f1 | tail -n +2)

FILE_TO_PROCESS=$(find ${ORIGIN_FOLDER} \( -iname "*.raw.*" ! -iname "*.undefined" ! -iname "*.filepart" ! -iname "*QBSA*" ! -iname "*QHela*" ! -iname "*sp *" \) -type f -mtime -7 -printf "%h %f %s\n" | sort -r | awk '{print $1"/"$2}' | head -n1)

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
    
   if [ "$TEST_MODE" = false ] ; then
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
  
   ###############LAUNCH NEXTFLOW PROCESSES
   if [ "$TEST_MODE" = false ] ; then
    launch_nf_run $NAME $WF_ROOT_FOLDER/$WF".nf" "$VAR_MODIF" $FMT $FEU $PMT $PEU $MC $OF $IF $ENGINE $CURRENT_UUID_FOLDER/${FILE_BASENAME} ${LOGS_FOLDER}/${FILE_BASENAME}.log
    if [ "$(echo $REQUEST | grep $j)" ]; then launch_all_secondary_reactions $CURRENT_UUID_FOLDER/${FILE_BASENAME} ${LOGS_FOLDER}/${FILE_BASENAME}.log; fi
   elif [ "$TEST_MODE" = true ] ; then
    echo "FAKE launch_nf_run..."
    if [ "$(echo $REQUEST | grep $j)" ]; then echo "FAKE launch_all_secondary_reactions..."; fi
   fi 
 fi

done

echo "[INFO] -----------------EOF"

################KERNEL END
