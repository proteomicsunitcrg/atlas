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
ENABLE_SLACK=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f8)
SLACK_URL_HOOK=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f9)
ENABLE_NOTIF_EMAIL=$(cat $CSV_FILENAME_RUN_MODES | grep -E "^$MODE[^;]*;" | cut -d';' -f10)
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
  curl -X POST -H 'Content-type: application/json' -d "$payload" "$hook" > /dev/null 2>&1
}

launch_nf_run() {
    # 🔹 Capturar tots els arguments com un array (parells key, value)
    declare -A PARAMS
    declare -a ORDERED_KEYS  # Llista per mantenir l'ordre original

    while [[ $# -gt 0 ]]; do
        key="$1"   # Primer element és la key
        value="$2"  # Segon element és el valor
        shift 2  # Avançar dos elements

        # Comprovació de valors per debug
        if [[ -z "$key" ]]; then
            echo "[ERROR] Clau buida detectada, saltant entrada."
            continue
        fi

        PARAMS["$key"]="$value"
        ORDERED_KEYS+=("$key")  # Guardem l'ordre original
    done

    exit 1  # 🔴 Debug: Parar execució aquí per comprovar valors abans d'executar Nextflow

    # 🔹 Generar els arguments dinàmics per Nextflow
    NF_ARGS=()
    for key in "${ORDERED_KEYS[@]}"; do
        NF_ARGS+=("--$key" "${PARAMS[$key]}")
    done

    # 🔹 Executar Nextflow segons l'executor (SLURM o SGE)
    if [[ "${PARAMS[executor]}" == "slurm" ]]; then
        echo "[INFO] Launching Nextflow with SLURM..."
        sbatch --output="${PARAMS[log_file]}.out" --error="${PARAMS[log_file]}.err" \
            nextflow run "${PARAMS[workflow]}" -bg "${NF_ARGS[@]}"
    elif [[ "${PARAMS[executor]}" == "sge" ]]; then
        echo "[INFO] Launching Nextflow with SGE..."
        nextflow run "${PARAMS[workflow]}" -bg "${NF_ARGS[@]}"
    else
        echo "[ERROR] Unknown executor: ${PARAMS[executor]}"
        exit 1
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

         if [ "$PROD_MODE" = "true" ]; then
            mkdir -p "$CURRENT_UUID_FOLDER"
            cd "$CURRENT_UUID_FOLDER" || exit
            mv "$FILE_TO_PROCESS" "$CURRENT_UUID_FOLDER"
         fi

         # 🔹 Llegeix el header del CSV
         IFS=';' read -r -a headers < <(head -n 1 "$METHODS_CSV")

         # 🔹 Busca la línia on el camp "pattern" coincideix amb "$j"
         values=$(grep "^$j;" "$METHODS_CSV")

         if [ -z "$values" ]; then
            echo "[ERROR] No matching pattern $j found in $METHODS_CSV"
            exit 1
         fi

         # 🔹 Assegurar que Bash suporta arrays associatius
         declare -A PARAMS  # Reiniciar array associatiu per evitar valors heretats

         # 🔹 Assignem valors als headers corresponents usant "cut"
         for i in "${!headers[@]}"; do
            field=$((i + 1))  # Els camps en `cut` comencen en 1, no en 0
            key="${headers[i]}"
            value=$(echo "$values" | cut -d';' -f"$field" | tr -d '\r')  # Eliminar caràcters especials com \r

            # **Si la clau està buida, l'ignorem per evitar errors**
            if [[ -z "$key" ]]; then
               echo "[ERROR] Clau buida detectada al header! Index: $i"
               continue
            fi

            # **Si el valor és buit, inicialitzar-lo com a ""**
            [[ -z "$value" ]] && value=""
            PARAMS["$key"]="$value"
         done

         # 🔹 Creant array d'arguments per launch_nf_run
         ARGS=()
         echo "[INFO] Final arguments to launch_nf_run:"
         for key in "${headers[@]}"; do
            echo "[INFO] $key: '${PARAMS[$key]}'"
            ARGS+=("$key" "${PARAMS[$key]}")
         done

         # 🔹 Cridar la funció amb els arguments dinàmics
         launch_nf_run "${ARGS[@]}"

      fi


  

   done
      else
      echo "[INFO] No files to process!"
fi

echo "[INFO] -----------------EOF"

################KERNEL END
