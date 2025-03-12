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
    echo "[ERROR]""$ASSETS_FOLDER"" does not exist."
    exit 1
fi


## PARSE CSV FILENAMES
CSV_FILENAME_RUN_MODES=$(ls $3 | grep $LAB | grep "run_modes")
CSV_FILENAME_RUN_MODES=$3/$CSV_FILENAME_RUN_MODES

## PARSE RUN MODES VARIABLES
if [[ $2 = "prod" ]]; then PROD_MODE="true"; elif [[ $2 = "test" ]]; then TEST_MODE="true"; fi
ORIGIN_FOLDER=$(grep -E "^${MODE}[^;]*;" "$CSV_FILENAME_RUN_MODES" | cut -d';' -f2)
echo "[INFO] Origin folder is ""$ORIGIN_FOLDER"
WF_ROOT_FOLDER=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f3)
ATLAS_RUNS_FOLDER=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f4)
LOGS_FOLDER=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f5)
NOTIF_EMAIL=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f6)
ENABLE_NOTIF_EMAIL=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f7)
ENABLE_SLACK=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f8)
SLACK_URL_HOOK=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f9)
ENABLE_NOTIF_EMAIL=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f10)
MTIME_VAR=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f11)
NUM_MAX_PROC=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f12)
METHODS_CSV=$(ls $3 | grep $LAB | grep "methods")
METHODS_CSV=$3/$METHODS_CSV

## MANAGE TEST DATA
if [ "$TEST_MODE" = true ] ; then
    
    CSV_FILENAME_TEST_PARAMS=$(ls $3 | grep $LAB | grep "test_params")
    CSV_FILENAME_TEST_PARAMS=$3/$CSV_FILENAME_TEST_PARAMS
    
    ## Parse test parameters
    TEST_FILE_REMOTE=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d';' -f2)
    TEST_FILENAME=$(cat $CSV_FILENAME_TEST_PARAMS | grep $DATA | cut -d';' -f3)
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
    
    echo "[DEBUG] Nombre total d'arguments rebuts: $#"
    
    while [[ $# -gt 0 ]]; do
        key="$1"
        value="$2"
        shift 2
        
        if [[ -z "$key" ]]; then
            echo "[ERROR] Clau buida detectada, saltant entrada."
            continue
        fi
        
        echo "[DEBUG] Afegint PARAMS[$key]='$value'"
        PARAMS["$key"]="$value"
        ORDERED_KEYS+=("$key")
    done
    
    # ✅ Construir el path complet al workflow de Nextflow
    WF_SCRIPT="${WF_ROOT_FOLDER}/${PARAMS[workflow]}.nf"
    echo "[DEBUG] Workflow script seleccionat: $WF_SCRIPT"
    
    # 🔹 Construir -profile personalitzat usant el LAB de l’script
    EXECUTOR="${PARAMS[executor]}"
    PROFILE="${PARAMS[nf_profile]}"
    PROFILE_ARG="-profile '${EXECUTOR}_${PROFILE},${LAB}'"
    echo "[DEBUG] Afegint a NF_ARGS: $PROFILE_ARG"
    
    # ✅ Construir -work-dir manualment amb ATLAS_RUNS_FOLDER i CURRENT_UUID
    WORK_DIR_ARG="-work-dir '${ATLAS_RUNS_FOLDER}/${CURRENT_UUID}'"
    echo "[DEBUG] Afegint a NF_ARGS: $WORK_DIR_ARG"
    
    # 🔹 Assegurar que `log_file` es genera correctament dins `launch_nf_run`
    LOG_FILE="${LOGS_FOLDER}/${FILE_BASENAME}.log"
    echo "[DEBUG] Log file assignat a: $LOG_FILE"
    
    # ✅ Calcular INSTRUMENT_FOLDER segons output_folder
    if [[ "${PARAMS[output_folder]}" == "true" ]]; then
        INSTRUMENT_FOLDER=$(echo "${FILE_BASENAME}" | cut -f 3 -d '.')
    else
        INSTRUMENT_FOLDER=''
    fi
    echo "[DEBUG] Assignant INSTRUMENT_FOLDER='$INSTRUMENT_FOLDER'"
    
    # 🔹 Definir claus a excloure de NF_ARGS
    EXCLUDE_KEYS=("pattern" "executor" "is_instrument_folder_in_filename" "workflow" "name" "nf_profile")
    
    # 🔹 Generar els arguments dinàmics per Nextflow
    NF_ARGS=()
    echo "[DEBUG] Creant arguments per Nextflow..."
    
    for key in "${ORDERED_KEYS[@]}"; do
        if [[ " ${EXCLUDE_KEYS[*]} " =~ " $key " ]]; then
            echo "[DEBUG] Ometent --$key (No necessari per Nextflow)"
            continue
        fi
        
        # ✅ Si el valor conté espais, envoltar-lo amb cometes dobles
        if [[ "${PARAMS[$key]}" =~ \  ]]; then
            value="\"${PARAMS[$key]}\""
        else
            value="'${PARAMS[$key]}'"
        fi
        
        NF_ARGS+=("--$key" "$value")
        
        echo "[DEBUG] Afegit a NF_ARGS: --$key $value"
    done
    
    # ✅ Afegir manualment -profile, -work-dir i --instrument_folder
    NF_ARGS+=("$PROFILE_ARG")
    NF_ARGS+=("$WORK_DIR_ARG")
    NF_ARGS+=("--instrument_folder '$INSTRUMENT_FOLDER'")
    
    # ✅ Afegir les variables globals de l’script
    NF_ARGS+=("--test_mode '$TEST_MODE'")
    NF_ARGS+=("--test_folder '$ORIGIN_FOLDER'")
    NF_ARGS+=("--notif_email '$NOTIF_EMAIL'")
    NF_ARGS+=("--enable_notif_email '$ENABLE_NOTIF_EMAIL'")
    
    # 🔹 Depuració final abans d'executar Nextflow
    echo "[INFO] Arguments finals per Nextflow:"
    echo "nextflow run '$WF_SCRIPT' -bg ${NF_ARGS[*]}"
    
    # 🔹 Executar Nextflow segons l'executor
    if [[ "${PARAMS[executor]}" == "slurm" ]]; then
        
        CMD="sbatch \
            --output='/users/pr/proteomics/mygit/atlas-logs/atlas-trigger-slurm-${FILE_BASENAME}.out' \
            --error='/users/pr/proteomics/mygit/atlas-logs/atlas-trigger-slurm-${FILE_BASENAME}.err' \
            /users/pr/proteomics/mygit/atlas-test/bin/trigger_slurm.sh \
            '/users/pr/proteomics/mygit/atlas-test/${PARAMS[workflow]}.nf' \
            '$LAB' \
            --workdir '${ATLAS_RUNS_FOLDER}/${CURRENT_UUID}'"

        # Add all additional arguments from ARGS
        for arg in "${ARGS[@]}"; do
            CMD+=" '$arg'"
        done

        # Debugging: Print the final command before executing
        echo "[DEBUG] Executing: $CMD"

        # Execute the command
        output=$(bash -l -c "$CMD" 2>&1)
        exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            # SEND JOB TO CLUSTER
            echo "[INFO] :) Successfully triggered pipeline"
            #echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') :) Successfully triggered Nextflow pipeline for $TARGET_FILE" >> "$LOG_FILE"
            #MESSAGE=${1:-:logo_qcloudrgb-02: :white_check_mark: - Sent file to pipeline: $FILES_BASENAME}
            #notify_slack "$MESSAGE" "$hook_url"
        else
            echo "[ERROR] sbatch failed with exit code $exit_code"
            echo "[ERROR] Execution output:"
            echo "$output"
            #echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') :( Error sending file to pipeline for $TARGET_FILE" >> "$LOG_FILE"
            #MESSAGE=${1:-:x: :logo_qcloudrgb-02: - Error sending file to pipeline: $FILES_BASENAME}
            #notify_slack "$MESSAGE" "$hook_url"
        fi
        elif [[ "${PARAMS[executor]}" == "sge" ]]; then
        echo "[INFO] Launching Nextflow with SGE..."
        #nextflow run "${PARAMS[workflow]}" -bg "${NF_ARGS[@]}" > "$LOG_FILE" 2>&1
    else
        echo "[ERROR] Unknown executor: ${PARAMS[executor]}"
        exit 1
    fi
    
    # 🔹 Reporting log
    echo "[INFO] ################################################################################################"
    echo "[INFO]                PROCESSING FILE: ${FILE_BASENAME}"
    echo "[INFO] ################################################################################################"
    echo "[INFO] Application name        : ${PARAMS[name]}"
    echo "[INFO] Workflow script         : $WF_SCRIPT"
    echo "[INFO] Variable modifications  : ${PARAMS[var_modif]}"
    echo "[INFO] Site modifications      : ${PARAMS[sites_modif]}"
    echo "[INFO] Fragment mass tolerance : ${PARAMS[fragment_mass_tolerance]}"
    echo "[INFO] Fragment error units    : ${PARAMS[fragment_error_units]}"
    echo "[INFO] Precursor mass tolerance: ${PARAMS[precursor_mass_tolerance]}"
    echo "[INFO] Precursor mass units    : ${PARAMS[precursor_error_units]}"
    echo "[INFO] Missed cleavages        : ${PARAMS[missed_cleavages]}"
    echo "[INFO] Output folder           : ${PARAMS[output_folder]}"
    echo "[INFO] Search engine           : ${PARAMS[search_engine]}"
    echo "[INFO] NF Profile              : ${PARAMS[executor]}_${PARAMS[nf_profile]},$LAB"
    echo "[INFO] SampleQC API key        : ${PARAMS[sampleqc_api_key]}"
    echo "[INFO] Raw file                : ${PARAMS[rawfile]}"
    if [[ "${PARAMS[executor]}" == "slurm" ]]; then
        echo "[INFO] Slurm Output Log        : /users/pr/proteomics/mygit/atlas-logs/atlas-trigger-slurm-${FILE_BASENAME}.out"
        echo "[INFO] Slurm Error Log         : /users/pr/proteomics/mygit/atlas-logs/atlas-trigger-slurm-${FILE_BASENAME}.err"
    else
        echo "[INFO] Log file                : ${LOG_FILE}"
    fi
    echo "[INFO] Working folder          : $ATLAS_RUNS_FOLDER/$CURRENT_UUID"
    echo "[INFO] ################################################################"
    echo "[INFO] ################################################################################################"
    
    # 🔹 Notificació per email
    if [ "$ENABLE_NOTIF_EMAIL" = "true" ]; then
        echo "[INFO] Sending notification email to: ${PARAMS[notif_email]}"
        echo "[INFO] This file was sent to the Atlas pipeline..." | mail -s "Pipeline Notification: ${FILE_BASENAME}" "${PARAMS[notif_email]}"
    fi
    
}


################FUNCTIONS END


###########################
################KERNEL#####
###########################

DATE_LOG=$(date '+%Y-%m-%d %H:%M:%S')
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
            
            # 🔹 Assignar RAWFILE_TO_PROCESS segons TEST/PROD
            if [ "$TEST_MODE" = "true" ]; then
                RAWFILE_TO_PROCESS=$ORIGIN_FOLDER/$TEST_FILENAME
                elif [ "$PROD_MODE" = "true" ]; then
                RAWFILE_TO_PROCESS=$CURRENT_UUID_FOLDER/${FILE_BASENAME}
                TEST_MODE="false"
            fi
            
            # 🔹 Afegir RAWFILE_TO_PROCESS a ARGS
            ARGS+=("rawfile" "$RAWFILE_TO_PROCESS")
            
            # 🔹 Comprovar si RAWFILE_TO_PROCESS existeix abans d'executar
            if [ -f "$RAWFILE_TO_PROCESS" ] || [ -d "$RAWFILE_TO_PROCESS" ]; then
                echo "[DEBUG] Afegint rawfile a ARGS: $RAWFILE_TO_PROCESS"
                launch_nf_run "${ARGS[@]}"
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