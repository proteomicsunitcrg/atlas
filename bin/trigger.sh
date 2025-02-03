#!/bin/bash -l

## INPUT PARAMS
die () {
    echo >&2 "$@"
    exit 1
}

LAB=$1
MODE=$2
ASSETS_FOLDER=$3
DATA=$4

if [ ! -d "$ASSETS_FOLDER" ]; then
  echo "[ERROR]"$ASSETS_FOLDER" does not exist."
  exit 1
fi

## PARSE CSV FILENAMES
CSV_FILENAME_RUN_MODES=$(ls $3 | grep $LAB | grep "run_modes")
CSV_FILENAME_RUN_MODES=$3/$CSV_FILENAME_RUN_MODES

## PARSE RUN MODES VARIABLES
if [[ $2 = "prod" ]]; then PROD_MODE="true"; elif [[ $2 = "test" ]]; then TEST_MODE="true"; fi
ORIGIN_FOLDER=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f2)
echo "[INFO] Origin folder is "$ORIGIN_FOLDER
WF_ROOT_FOLDER=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f3)
ATLAS_RUNS_FOLDER=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f4)
LOGS_FOLDER=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f5)
NOTIF_EMAIL=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f6)
ENABLE_NOTIF_EMAIL=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f7)
ENABLE_NF_TOWER=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f8)
ENABLE_SLACK=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f9)
SLACK_URL_HOOK=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f10)
MTIME_VAR=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f11)
NUM_MAX_PROC=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f12)
if [[ $ENABLE_NF_TOWER = "true" ]]; then WITH_TOWER="-with-tower"; fi
METHODS_CSV=$(ls $3 | grep $LAB | grep "methods")      
METHODS_CSV=$3/$METHODS_CSV

## MANAGE TEST DATA
if [ "$TEST_MODE" = true ] ; then

   CSV_FILENAME_TEST_PARAMS=$(ls $3 | grep $LAB | grep "test_params")
   CSV_FILENAME_TEST_PARAMS=$3/$CSV_FILENAME_TEST_PARAMS

   ## Parse test parameters
   TEST_FILE_REMOTE=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d';' -f2)
   TEST_FILENAME=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d';' -f3)
   TEST_NUM_PROTS_REF=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d';' -f5)
   TEST_NUM_PEPTD_REF=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d';' -f6)
   TEST_FILE_REMOTE=$TEST_FILE_REMOTE"/"$TEST_FILENAME

   # Create data folder, if applies
   mkdir -p $ORIGIN_FOLDER

   # Clean test data folder, if applies
   rm $ORIGIN_FOLDER/* 2>/dev/null && echo "[INFO] Test files cleaned at $ORIGIN_FOLDER" || echo "[INFO] No files to clean at "$ORIGIN_FOLDER

   # Download files and data, if applies
   if [ -f "$ORIGIN_FOLDER/$TEST_FILENAME" ] ; then
      echo "[INFO] Test file $ORIGIN_FOLDER/$TEST_FILENAME already downloaded."
   else 
      curl -o $ORIGIN_FOLDER"/"$TEST_FILENAME $TEST_FILE_REMOTE -L
   fi

fi

##################################
################FUNCTIONS#########
##################################

# Slack notification: 
notify_slack() {
  local text="$1"
  local hook="$2"
  local payload=$(printf '{"text": "%s"}' "$(echo "$text" | sed ':a;N;$!ba;s/\n/\\n/g')")
  curl -X POST -H 'Content-type: application/json' -d "$payload" "$hook"
}

launch_nf_run () {

      if [ "${10}" = true ]
      then
        INSTRUMENT_FOLDER=$(echo ${FILE_BASENAME} | cut -f 3 -d '.')
      else 
        INSTRUMENT_FOLDER=''
      fi

      ####### LAUNCH TO NEXTFLOW ####### 
      nextflow run $2 $WITH_TOWER -bg -with-report -work-dir $ATLAS_RUNS_FOLDER/$CURRENT_UUID --var_modif "$3" --sites_modif "$4" --fragment_mass_tolerance "$5" --fragment_error_units "$6" --precursor_mass_tolerance "$7" --precursor_error_units "$8" --missed_cleavages "$9" --output_folder "${10}" --instrument_folder "$INSTRUMENT_FOLDER" --search_engine "${12}" -profile $LAB,"${13}" --sampleqc_api_key ${14} --rawfile ${15} --test_mode $TEST_MODE --test_folder $ORIGIN_FOLDER --notif_email $NOTIF_EMAIL --enable_notif_email $ENABLE_NOTIF_EMAIL > ${16}
 
      # Reporting log:
      echo "[INFO] ################################################################"
      echo "[INFO] ~~~~~~~~~~~~~~~~PROCESSING FILE ${FILE_BASENAME}~~~~~~~~~~~~~~~~"
      echo "[INFO] Application name: $1"
      echo "[INFO] Workflow: $2"
      echo "[INFO] Variable modifications: $3"
      echo "[INFO] Site modifications: $4"
      echo "[INFO] Fragment mass tolerance: $5"
      echo "[INFO] Fragment error units: $6"
      echo "[INFO] Precursor mass tolerance: $7"
      echo "[INFO] Precursor mass units: $8"
      echo "[INFO] Missed cleavages: $9"
      echo "[INFO] Ouptut folder: ${10}"
      echo "[INFO] Instrument subfolder: $INSTRUMENT_FOLDER"
      echo "[INFO] Search engine: ${12}"
      echo "[INFO] NF Profile: $LAB,${13}"
      echo "[INFO] SampleQC api key: ${14}"
      echo "[INFO] Raw file: ${15}"
      echo "[INFO] Log file: ${16}"
      echo "[INFO] Working folder: $ATLAS_RUNS_FOLDER/$CURRENT_UUID"
      echo "[INFO] ###############################################################"
      echo "[INFO] ###############################################################"
      
      if [ "$ENABLE_NOTIF_EMAIL" = true ] ; then
        echo "[INFO] This file was sent to the atlas pipeline..." | mail -s ${FILE_BASENAME} "$NOTIF_EMAIL"
	      HOOKURL=$(cat /users/pr/proteomics/.proteomics_pipelines_notifications_hook_url)
	      MESSAGE=":qsample: :white_check_mark: - Sent file to pipeline: $FILE_BASENAME"
        notify_slack "$MESSAGE" "$HOOKURL"
      fi

      if [ "$ENABLE_SLACK" = true ] ; then
	      MESSAGE=":qsample: :white_check_mark: - Sent file to pipeline: $FILE_BASENAME"
         notify_slack "$MESSAGE" "$SLACK_URL_HOOK"
      fi
}

################FUNCTIONS END


###########################
################KERNEL#####
###########################

DATE_LOG=`date '+%Y-%m-%d %H:%M:%S'`
echo "[INFO] -----------------START---[${DATE_LOG}]"

LIST_PATTERNS=$(cat ${METHODS_CSV} | cut -d';' -f1 | tail -n +2)

FILE_TO_PROCESS=""
NUM_CONCURRENT_PROC=$(ps aux | grep nextflow | grep java | wc -l);
if [ "$NUM_CONCURRENT_PROC" -lt $NUM_MAX_PROC ]; then
   echo "[INFO] Max. num. of concurrent jobs below the defined by user: $NUM_CONCURRENT_PROC. Triggering the pipeline..."
   FILE_TO_PROCESS=$(find ${ORIGIN_FOLDER} \( -iname "*.raw.*" ! -iname "*.mzML.*" ! -iname "*.undefined" ! -iname "*.filepart" ! -iname "*log*" -o -iname "*mzml*" -o -type d -iname "*.d" \) -mtime $MTIME_VAR -print | sort -r | head -n1)
else
   echo "[WARNING] Exceeded max. num. of concurrent jobs defined by user: $NUM_CONCURRENT_PROC. Skipping pipeline triggering until num. of jobs drops below $NUM_MAX_PROC."
fi

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

      WF=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f2)
      NAME=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f3)
      VAR_MODIF=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f4)
      SITES_MODIF=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f5)
      FMT=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f6)
      FEU=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f7)
      PMT=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f8)
      PEU=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f9)
      MC=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f10)
      OF=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f11)
      IF=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f12)
      ENGINE=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f13)
      NF_PROFILE=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f14)
      SAMPLEQC_API_KEY=$(cat ${METHODS_CSV} | grep "^$j;" | cut -d';' -f15)

      ##############LAUNCH NEXTFLOW PROCESSES
      # save num_prtos and peptd with filename encoded and test all script (before general TSV). 
      if [ "$TEST_MODE" = "true" ] ; then
         RAWFILE_TO_PROCESS=$ORIGIN_FOLDER/$TEST_FILENAME
      elif [ "$PROD_MODE" = "true" ] ; then
         RAWFILE_TO_PROCESS=$CURRENT_UUID_FOLDER/${FILE_BASENAME}
         TEST_MODE="false"
      fi
      if [ -f "$RAWFILE_TO_PROCESS" ] || [ -d "$RAWFILE_TO_PROCESS" ]; then
         #### here the NF process is launched!
         launch_nf_run "$NAME" $WF_ROOT_FOLDER/$WF".nf" "$VAR_MODIF" "$SITES_MODIF" "$FMT" "$FEU" "$PMT" "$PEU" "$MC" "$OF" "$IF" "$ENGINE" "$NF_PROFILE" "$SAMPLEQC_API_KEY" $RAWFILE_TO_PROCESS ${LOGS_FOLDER}/${FILE_BASENAME}.log
      else 
         echo "[ERROR] ${RAWFILE_TO_PROCESS} not found."
      fi
   fi
   done
      else
      echo "[INFO] No files to process!"
fi

echo "[INFO] -----------------EOF"

################KERNEL END
