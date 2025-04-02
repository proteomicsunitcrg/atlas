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

    # Capture all arguments as an array (key-value pairs)
    declare -A PARAMS
    declare -a ORDERED_KEYS  # List to maintain the original order
      
    while [[ $# -gt 0 ]]; do
        key="$1"
        value="$2"
        shift 2
        if [[ -z "$key" ]]; then
            echo "[ERROR] Empty key detected, skipping entry."
            continue
        fi
        PARAMS["$key"]="$value"
        ORDERED_KEYS+=("$key")
    done
    
    WF_SCRIPT="${WF_ROOT_FOLDER}/${PARAMS[workflow]}.nf"
    
    # Build a custom -profile using the script's LAB
    PROFILE_ARG="-profile '${PARAMS[nf_profile]},${LAB}'"
    
    # Manually build -work-dir using ATLAS_RUNS_FOLDER and CURRENT_UUID
    WORK_DIR_ARG="-work-dir '${ATLAS_RUNS_FOLDER}/${CURRENT_UUID}'"
    
    # Ensure that log_file is correctly generated within launch_nf_run
    LOG_FILE="${LOGS_FOLDER}/${FILE_BASENAME}.log"
    
    # Calculate INSTRUMENT_FOLDER based on output_folder
    if [[ "${PARAMS[output_folder]}" == "true" ]]; then
        INSTRUMENT_FOLDER=$(echo "${FILE_BASENAME}" | cut -f 3 -d '.')
    else
        INSTRUMENT_FOLDER=''
    fi
    
    # Define keys to exclude from NF_ARG
    EXCLUDE_KEYS=("pattern" "executor" "is_instrument_folder_in_filename" "workflow" "name" "nf_profile")
    
    # Generate dynamic arguments for Nextflow
    NF_ARGS=()
    
    for key in "${ORDERED_KEYS[@]}"; do
        if [[ " ${EXCLUDE_KEYS[*]} " =~ " $key " ]]; then
            continue
        fi
        
        # If the value contains spaces, enclose it in double quotes
        if [[ "${PARAMS[$key]}" =~ \  ]]; then
            value="\"${PARAMS[$key]}\""
        else
            value="'${PARAMS[$key]}'"
        fi
        
        NF_ARGS+=("--$key" "$value")
        
    done
    
    # Manually add -profile, -work-dir, and --instrument_folder
    NF_ARGS+=("$PROFILE_ARG")
    NF_ARGS+=("$WORK_DIR_ARG")
    NF_ARGS+=("--instrument_folder '$INSTRUMENT_FOLDER'")
    
    # Add the script's global variables
    NF_ARGS+=("--test_mode '$TEST_MODE'")
    NF_ARGS+=("--test_folder '$ORIGIN_FOLDER'")
    NF_ARGS+=("--notif_email '$NOTIF_EMAIL'")
    NF_ARGS+=("--enable_notif_email '$ENABLE_NOTIF_EMAIL'")
        
    ##################### WRAPPED
    if [[ "${PARAMS[executor]}" == "wrapped" ]]; then
        
        CMD="sbatch \
            --output='${LOGS_FOLDER}/atlas-trigger-slurm-${FILE_BASENAME}.out' \
            --error='${LOGS_FOLDER}/atlas-trigger-slurm-${FILE_BASENAME}.err' \
            ${WF_ROOT_FOLDER}/bin/trigger_slurm.sh \
            '${WF_ROOT_FOLDER}/${PARAMS[workflow]}.nf' \
            '$LAB' \
            --workdir '${ATLAS_RUNS_FOLDER}/${CURRENT_UUID}'"

        # Add all additional arguments from ARGS, properly escaping special characters
        for arg in "${ARGS[@]}"; do
            # Ensure special characters are correctly quoted
            if [[ "$arg" =~ [\(\)] ]]; then
                CMD+=" \"${arg}\""
            else
                CMD+=" '$arg'"
            fi
        done

        # Execute the command
        output=$(bash -l -c "$CMD" 2>&1)
        exit_code=$?
        if [ $exit_code -eq 0 ]; then 
            # SEND JOB TO CLUSTER
            echo "[INFO] :) Successfully triggered pipeline"
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') :) Successfully triggered Nextflow pipeline for $FILE_BASENAME" >> "$LOG_FILE"
            if [ "$ENABLE_SLACK" = "true" ]; then
                MESSAGE=":globe_with_meridians: :white_check_mark: - Sent file pipeline: $FILE_BASENAME"
                notify_slack "$MESSAGE" "$SLACK_URL_HOOK"
            fi
        else
            echo "[ERROR] sbatch failed with exit code $exit_code"
            echo "[ERROR] Execution output:"
            echo "$output"
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') :( Error sending file to pipeline for $TARGET_FILE" >> "$LOG_FILE"
            if [ "$ENABLE_SLACK" = "true" ]; then
                MESSAGE=":x: :globe_with_meridians: - Error sending file to pipeline: $FILE_BASENAME"
                notify_slack "$MESSAGE" "$SLACK_URL_HOOK"
            fi
        fi
        ##################### DIRECT
        elif [[ "${PARAMS[executor]}" == "direct" ]]; then
            echo "[INFO] Launching Nextflow with DIRECT mode..."

            # Ensure key parameters have default values if missing
            LOG_FILE="${PARAMS[logfile]:-$LOGS_FOLDER/${FILE_BASENAME}.log}"
            TEST_MODE="${PARAMS[test_mode]:-false}"
            TEST_FOLDER="${PARAMS[test_folder]:-$ORIGIN_FOLDER}"
            NOTIF_EMAIL="${PARAMS[notif_email]:-$NOTIF_EMAIL}"
            ENABLE_NOTIF_EMAIL="${PARAMS[enable_notif_email]:-$ENABLE_NOTIF_EMAIL}"

            if nextflow run "${WF_ROOT_FOLDER}/${PARAMS[workflow]}.nf" -bg \
                -work-dir "${PARAMS[workdir]:-$ATLAS_RUNS_FOLDER/$CURRENT_UUID}" \
                --var_modif "${PARAMS[var_modif]:-}" \
                --sites_modif "${PARAMS[sites_modif]:-}" \
                --fragment_mass_tolerance "${PARAMS[fragment_mass_tolerance]:-}" \
                --fragment_error_units "${PARAMS[fragment_error_units]:-}" \
                --precursor_mass_tolerance "${PARAMS[precursor_mass_tolerance]:-}" \
                --precursor_error_units "${PARAMS[precursor_error_units]:-}" \
                --missed_cleavages "${PARAMS[missed_cleavages]:-}" \
                --output_folder "${PARAMS[output_folder]:-}" \
                --instrument_folder "${PARAMS[instrument_folder]:-}" \
                --search_engine "${PARAMS[search_engine]:-}" \
                -profile "${PARAMS[nf_profile]:-},$LAB" \
                --sampleqc_api_key "${PARAMS[sampleqc_api_key]:-}" \
                --rawfile "${PARAMS[rawfile]:-}" \
                --test_mode "$TEST_MODE" \
                --test_folder "$TEST_FOLDER" \
                --notif_email "$NOTIF_EMAIL" \
                --enable_notif_email "$ENABLE_NOTIF_EMAIL" \
                > "$LOG_FILE"; then
                echo "[INFO] :) Successfully triggered pipeline"
                echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') :) Successfully triggered Nextflow pipeline for $FILE_BASENAME" >> "$LOG_FILE"
                if [ "$ENABLE_SLACK" = "true" ]; then
                MESSAGE=":globe_with_meridians: :white_check_mark: - Sent file to pipeline: $FILE_BASENAME"
                notify_slack "$MESSAGE" "$SLACK_URL_HOOK"
                fi
            else
                    echo "[ERROR] nextflow run failed with exit code $exit_code"
                    echo "[ERROR] Execution output:"
                    echo "$output"
                    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') :( Error sending file to pipeline for $TARGET_FILE" >> "$LOG_FILE"
                    if [ "$ENABLE_SLACK" = "true" ]; then
                        MESSAGE=":globe_with_meridians: :x: - Error sending file to pipeline: $FILE_BASENAME"
                        notify_slack "$MESSAGE" "$SLACK_URL_HOOK"
                    fi
            fi

    else
        echo "[ERROR] Unknown executor: ${PARAMS[executor]}"
        exit 1
    fi
    
    echo ""
    echo "   █████╗ ████████╗██╗      █████╗ ███████╗ "
    echo "  ██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝ "
    echo "  ███████║   ██║   ██║     ███████║███████╗ "
    echo "  ██╔══██║   ██║   ██║     ██╔══██║╚════██║ "
    echo "  ██║  ██║   ██║   ███████╗██║  ██║███████║ "
    echo "  ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝ "
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "                              ATLAS PIPELINE                                    "
    echo "--------------------------------------------------------------------------------"

    [[ -n "$FILE_BASENAME" ]] && echo "[INFO] Processing File           : ${FILE_BASENAME}"
    echo "--------------------------------------------------------------------------------"

    [[ -n "${PARAMS[name]}" ]] && echo "[INFO] Application Name          : ${PARAMS[name]}"
    [[ -n "$WF_SCRIPT" ]] && echo "[INFO] Workflow Script           : $WF_SCRIPT"
    [[ -n "${PARAMS[var_modif]}" ]] && echo "[INFO] Variable Modifications    : ${PARAMS[var_modif]}"
    [[ -n "${PARAMS[sites_modif]}" ]] && echo "[INFO] Site Modifications        : ${PARAMS[sites_modif]}"
    [[ -n "${PARAMS[fragment_mass_tolerance]}" ]] && echo "[INFO] Fragment Mass Tolerance   : ${PARAMS[fragment_mass_tolerance]}"
    [[ -n "${PARAMS[fragment_error_units]}" ]] && echo "[INFO] Fragment Error Units      : ${PARAMS[fragment_error_units]}"
    [[ -n "${PARAMS[precursor_mass_tolerance]}" ]] && echo "[INFO] Precursor Mass Tolerance  : ${PARAMS[precursor_mass_tolerance]}"
    [[ -n "${PARAMS[precursor_error_units]}" ]] && echo "[INFO] Precursor Mass Units      : ${PARAMS[precursor_error_units]}"
    [[ -n "${PARAMS[missed_cleavages]}" ]] && echo "[INFO] Missed Cleavages          : ${PARAMS[missed_cleavages]}"
    [[ -n "${PARAMS[output_folder]}" ]] && echo "[INFO] Output Folder             : ${PARAMS[output_folder]}"
    [[ -n "${PARAMS[search_engine]}" ]] && echo "[INFO] Search Engine             : ${PARAMS[search_engine]}"
    [[ -n "${PARAMS[executor]}" && -n "${PARAMS[nf_profile]}" ]] && echo "[INFO] NF Profile                : ${PARAMS[executor]}_${PARAMS[nf_profile]},$LAB"
    [[ -n "${PARAMS[sampleqc_api_key]}" ]] && echo "[INFO] SampleQC API Key          : ${PARAMS[sampleqc_api_key]}"
    [[ -n "${PARAMS[rawfile]}" ]] && echo "[INFO] Raw File                  : ${PARAMS[rawfile]}"

    if [[ "${PARAMS[executor]}" == "slurm" ]]; then
        [[ -n "$LOGS_FOLDER" && -n "$FILE_BASENAME" ]] && echo "[INFO] Slurm Output Log          : ${LOGS_FOLDER}/atlas-trigger-slurm-${FILE_BASENAME}.out"
        [[ -n "$LOGS_FOLDER" && -n "$FILE_BASENAME" ]] && echo "[INFO] Slurm Error Log           : ${LOGS_FOLDER}/atlas-trigger-slurm-${FILE_BASENAME}.err"
    else
        [[ -n "$LOG_FILE" ]] && echo "[INFO] Log File                  : ${LOG_FILE}"
    fi

    [[ -n "$ATLAS_RUNS_FOLDER" && -n "$CURRENT_UUID" ]] && echo "[INFO] Working Folder            : $ATLAS_RUNS_FOLDER/$CURRENT_UUID"

    echo "--------------------------------------------------------------------------------"

    
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
            
            # Read the CSV header
            IFS=';' read -r -a headers < <(head -n 1 "$METHODS_CSV")
            
            # Find the line where the 'pattern' field matches '$j
            values=$(grep "^$j;" "$METHODS_CSV")
            
            if [ -z "$values" ]; then
                echo "[ERROR] No matching pattern $j found in $METHODS_CSV"
                exit 1
            fi
            
            declare -A PARAMS  # Reset associative array to avoid inherited values
            
            # Assign values to the corresponding headers using 'cut'
            for i in "${!headers[@]}"; do
                field=$((i + 1))  # Fields in cut start at 1, not 0
                key="${headers[i]}"
                value=$(echo "$values" | cut -d';' -f"$field" | tr -d '\r')  # Remove special characters like \r
                
                # If the key is empty, ignore it to prevent errors
                if [[ -z "$key" ]]; then
                    echo "[ERROR] Clau buida detectada al header! Index: $i"
                    continue
                fi
                
                # If the value is empty, initialize it as ""
                [[ -z "$value" ]] && value=""
                PARAMS["$key"]="$value"
            done
            
            # Creating an array of arguments for launch_nf_run
            ARGS=()
            for key in "${headers[@]}"; do
                ARGS+=("$key" "${PARAMS[$key]}")
            done
            
            # Assign RAWFILE_TO_PROCESS based on TEST/PROD
            if [ "$TEST_MODE" = "true" ]; then
                RAWFILE_TO_PROCESS=$ORIGIN_FOLDER/$TEST_FILENAME
                elif [ "$PROD_MODE" = "true" ]; then
                RAWFILE_TO_PROCESS=$CURRENT_UUID_FOLDER/${FILE_BASENAME}
                TEST_MODE="false"
            fi
            
            # Add RAWFILE_TO_PROCESS to ARGS
            ARGS+=("rawfile" "$RAWFILE_TO_PROCESS")
            
            # Check if RAWFILE_TO_PROCESS exists before executing
            if [ -f "$RAWFILE_TO_PROCESS" ] || [ -d "$RAWFILE_TO_PROCESS" ]; then
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