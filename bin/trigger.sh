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
MTIME_VAR=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f10)
NUM_MAX_PROC=$(grep -E "^${MODE}[^;]*;" "${CSV_FILENAME_RUN_MODES}" | cut -d';' -f11)
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

            elif [[ "${PARAMS[executor]}" == "local" ]]; then
                echo "[INFO] Launching Nextflow in LOCAL mode..."

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

                    echo "[INFO] Successfully triggered pipeline (local)"
                    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') Pipeline launched: $FILE_BASENAME" >> "$LOG_FILE"

                    if [ "$ENABLE_SLACK" = "true" ]; then
                        MESSAGE=":house_with_garden: :white_check_mark: - Sent file to local pipeline: $FILE_BASENAME"
                        notify_slack "$MESSAGE" "$SLACK_URL_HOOK"
                    fi
                else
                    echo "[ERROR] Nextflow run (local) failed."
                    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') Pipeline error: $FILE_BASENAME" >> "$LOG_FILE"
                    if [ "$ENABLE_SLACK" = "true" ]; then
                        MESSAGE=":x: :house_with_garden: - Error in local pipeline: $FILE_BASENAME"
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
    [[ -n "${PARAMS[executor]}" && -n "${PARAMS[nf_profile]}" ]] && echo "[INFO] NF Profile                : ${PARAMS[nf_profile]},${PARAMS[executor]},$LAB"
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

extract_qccode_and_request() {

    echo "[DEBUG] ----------------- extract_qccode_and_request() -----------------"

    local file_path="$1"
    local filename
    local filename_core
    local reversed

    filename=$(basename "$file_path")

    echo "[DEBUG] Input filename: $filename"

    ###########################################################################
    # STEP 1 — Strip vendor-specific extensions
    #
    # We normalize the filename by removing vendor-specific tails such as:
    #   *.raw.*
    #   *.d.*
    #   *.mzML.*
    #
    # Examples:
    #   2025NK071_MASR_025_01_2ug.raw.SP_Human  ->  2025NK071_MASR_025_01_2ug
    #   T068474_QC01_..._b118a..._QC01_662522fd.d.zip  ->  T068474_QC01_..._b118a..._QC01_662522fd
    ###########################################################################
    filename_core="${filename%%.raw*}"
    filename_core="${filename_core%%.d.*}"
    filename_core="${filename_core%%.mzML*}"

    echo "[DEBUG] After stripping vendor extensions: $filename_core"


    ###########################################################################
    # STEP 2 — HARD PRIORITY OVERRIDE FOR QCloud CODES
    #
    # We always prioritize:
    #   1) QC01
    #   2) QC02
    #   3) QCD1
    #   4) QCD2
    #
    # If any of these tags appear ANYWHERE in the (normalized) filename_core,
    # we immediately set QCCODE to that value and return.
    #
    # This guarantees that genuine QCloud runs are never confused with
    # other naming schemes (NK, MQ, etc.).
    ###########################################################################

    if echo "$filename_core" | grep -q "QC01"; then
        QCCODE="QC01"
        REQUEST=""
        echo "[INFO] Priority QCloud match: QC01 detected (highest priority)."
        echo "[DEBUG] Early exit from extract_qccode_and_request() with QCCODE='$QCCODE'"
        return
    fi

    if echo "$filename_core" | grep -q "QC02"; then
        QCCODE="QC02"
        REQUEST=""
        echo "[INFO] Priority QCloud match: QC02 detected."
        echo "[DEBUG] Early exit from extract_qccode_and_request() with QCCODE='$QCCODE'"
        return
    fi

    if echo "$filename_core" | grep -q "QCD1"; then
        QCCODE="QCD1"
        REQUEST=""
        echo "[INFO] Priority QCloud match: QCD1 detected."
        echo "[DEBUG] Early exit from extract_qccode_and_request() with QCCODE='$QCCODE'"
        return
    fi

    if echo "$filename_core" | grep -q "QCD2"; then
        QCCODE="QCD2"
        REQUEST=""
        echo "[INFO] Priority QCloud match: QCD2 detected."
        echo "[DEBUG] Early exit from extract_qccode_and_request() with QCCODE='$QCCODE'"
        return
    fi

    ###########################################################################
    # STEP 2.5 — SAMPLEQC PATTERN DETECTION (QCHL, QCDL, QCGL, etc.)
    #
    # Detects 4-character sampleqc codes that appear after the first underscore.
    # Pattern: QC[A-Z]{2} (exactly 4 characters starting with "QC")
    #
    # Examples:
    #   20260216_QCHL_W08_R1_01_Histones_1ug.raw.SP_Human → QCHL
    #   20260216_QCDL_W08_R1_01_Digestion_1ug.raw.SP_Human → QCDL
    #
    # These are distinct from QCloud codes (QC01, QC02, QCD1, QCD2) and
    # take priority over regular REQUEST patterns (NK, MQ, LA, etc.).
    ###########################################################################
    
    local sampleqc_pattern=$(echo "$filename_core" | cut -d'_' -f2 | grep -E '^QC[A-Z]{2}$')
    
    if [[ -n "$sampleqc_pattern" ]]; then
        QCCODE="$sampleqc_pattern"
        REQUEST=""
        echo "[INFO] SampleQC pattern detected: $QCCODE"
        echo "[DEBUG] Early exit from extract_qccode_and_request() with QCCODE='$QCCODE'"
        echo "[DEBUG] ----------------------------------------------------------------"
        return
    fi

    ###########################################################################
    # STEP 3 — Reverse-based parsing for generic QCloud-like patterns
    #
    # If we reached this point, there is no explicit QC01/QC02/QCD1/QCD2
    # string in the filename. However, we still try to detect any QCloud
    # QC code (QCxx or QCDx) using the generic pattern:
    #
    #   QC[digits]
    #   QCD[digits]
    #
    # We do this by:
    #   1) Reversing the filename_core
    #   2) Splitting by "_"
    #   3) Reversing each part again and checking if it matches the regex
    ###########################################################################
    reversed=$(echo "$filename_core" | rev)
    echo "[DEBUG] Reversed filename core: $reversed"

    local qccode_regex='^QCD?[0-9]+$'
    local found_qc=""

    IFS='_' read -ra parts <<< "$reversed"

    echo "[DEBUG] Searching reversed filename components for QC codes..."
    for i in "${!parts[@]}"; do
        local part_normal
        part_normal=$(echo "${parts[$i]}" | rev)
        echo "[DEBUG]   Component $i: reversed='${parts[$i]}' -> normal='$part_normal'"

        if [[ "$part_normal" =~ $qccode_regex ]]; then
            echo "[DEBUG]   → Matched QCloud-style QC code: $part_normal"
            found_qc="$part_normal"
            break
        fi
    done

    ###########################################################################
    # CASE A — QCloud-style file detected by regex (no hard priority used)
    ###########################################################################
    if [[ -n "$found_qc" ]]; then
        QCCODE="$found_qc"
        REQUEST=""

        echo "[INFO] QCloud-style filename detected via regex."
        echo "[INFO] Extracted QC code: $QCCODE"
        echo "[DEBUG] Exiting extract_qccode_and_request() in QCloud mode."
        echo "[DEBUG] ----------------------------------------------------------------"
        return
    fi


    ###########################################################################
    # CASE B — Non-QCloud / Atlas / QSample file
    #
    # These follow patterns like:
    #
    #   2025NK071_MASR_025_01_2ug.raw.SP_Human
    #
    # where:
    #   - REQUEST = first block before "_": e.g. "2025NK071"
    #   - pattern embedded in REQUEST = two or three uppercase letters,
    #     such as NK, MQ, LA, etc., which correspond to the "pattern"
    #     column in the methods TSV (MQ, LA, LB, MG, ...).
    ###########################################################################

    echo "[DEBUG] No QCloud QC code found → switching to non-QCloud parser."

    # Split the NORMAL (non-reversed) filename core by "_"
    local file_arr=($(echo "$filename_core" | tr "_" "\n"))
    REQUEST="${file_arr[0]}"

    echo "[DEBUG] REQUEST extracted from filename: $REQUEST"

    ###########################################################################
    # PATTERN EXTRACTION FOR NON-QCloud FILES
    #
    # We search for 2–3 consecutive uppercase letters inside REQUEST.
    # This is robust enough for patterns like:
    #   2025NK071  → NK
    #   2024MQ52A  → MQ
    #   2024LA843  → LA
    #
    # These two/three-letter codes must match the 'pattern' column in the
    # methods CSV/TSV (MQ, LA, LB, MG, etc.), which your main loop uses.
    ###########################################################################
    QCCODE=$(echo "$REQUEST" | grep -oE '[A-Z]{2,3}' | head -n 1)

    if [[ -z "$QCCODE" ]]; then
        echo "[WARNING] No 2–3 letter pattern detected inside REQUEST."
        echo "[WARNING] Filename might not follow Atlas/QSample conventions."
    else
        echo "[INFO] Non-QCloud pattern detected."
        echo "[INFO] REQUEST: $REQUEST | PATTERN/QCCODE: $QCCODE"
    fi

    echo "[DEBUG] Finished non-QCloud parsing."
    echo "[DEBUG] RETURN VALUES → REQUEST='$REQUEST' | QCCODE='$QCCODE'"
    echo "[DEBUG] ----------------------------------------------------------------"
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
    FILE_TO_PROCESS=$(find ${ORIGIN_FOLDER} \( -iname "*.raw.*" ! -iname "*.mzML.*" ! -iname "*.undefined" ! -iname "*.filepart" ! -iname "*log*" -o -iname "*mzml*" -o -iname "*.d.zip" -o -type d -iname "*.d" -o -type d -iname "*.d.*" \) -mtime $MTIME_VAR -print | sort -r | head -n1)
else
    echo "[WARNING] Exceeded max. num. of concurrent jobs defined by user: $NUM_CONCURRENT_PROC. Skipping pipeline triggering until num. of jobs drops below $NUM_MAX_PROC."
fi

if [ -n "$FILE_TO_PROCESS" ]; then
    
    FILE_BASENAME=$(basename "$FILE_TO_PROCESS")
    extract_qccode_and_request "$FILE_TO_PROCESS"

    MATCH_FOUND=false
    
    for j in ${LIST_PATTERNS}
    do
        if [ "$(echo $REQUEST | grep $j)" ] || [ "$QCCODE" = "$j" ]; then

            MATCH_FOUND=true
            
            echo "[INFO] Found pattern $j in filename $FILE_BASENAME"
            
            # BUGFIX: Break after first match to prevent multiple job submissions
            # Without this, overlapping patterns in methods.csv (e.g., "SP_Bov" and "SP_Bovine")
            # would both match the same file and trigger duplicate jobs
            
            CURRENT_UUID=$(uuidgen)
            CURRENT_UUID_FOLDER=$ATLAS_RUNS_FOLDER/$CURRENT_UUID
            
            if [ "$PROD_MODE" = "true" ]; then
                mkdir -p "$CURRENT_UUID_FOLDER"
                cd "$CURRENT_UUID_FOLDER" || exit
                mv "$FILE_TO_PROCESS" "$CURRENT_UUID_FOLDER"

                # Auto-unzip .d.zip files
                if [[ "$FILE_BASENAME" =~ \.d\.zip$ ]]; then
                    echo "[INFO] Unzipping $FILE_BASENAME..."
                    unzip -q "$CURRENT_UUID_FOLDER/$FILE_BASENAME" -d "$CURRENT_UUID_FOLDER"
                    rm "$CURRENT_UUID_FOLDER/$FILE_BASENAME"
                    # Find the actual .d directory that was extracted
                    EXTRACTED_D=$(find "$CURRENT_UUID_FOLDER" -maxdepth 1 -type d -name "*.d" | head -n1)
                    if [[ -n "$EXTRACTED_D" ]]; then
                        FILE_BASENAME=$(basename "$EXTRACTED_D")
                        echo "[INFO] Using unzipped directory: $FILE_BASENAME"
                    else
                        echo "[ERROR] Could not find extracted .d directory"
                        exit 1
                    fi
                fi
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
            
            # Exit loop after processing first matching pattern
            break
            
        fi
        
    done

    if [ "$MATCH_FOUND" = false ]; then
        echo ""
        echo "[WARNING] ───────────────────────────────────────────────────────────────"
        echo "[WARNING] No matching pattern found for detected code: \"$QCCODE\""
        echo "[WARNING] or REQUEST prefix: \"$REQUEST\""
        echo "[WARNING] Therefore, NO pipeline will be triggered for the file:"
        echo "          $FILE_BASENAME"
        echo ""
        echo "[WARNING] Please check that this code exists in the METHODS TSV file:"
        echo "          $METHODS_CSV"
        echo "[WARNING] If this is expected, simply ignore this message."
        echo "[WARNING] ───────────────────────────────────────────────────────────────"
        echo ""
    fi

else
    echo "[INFO] No files to process!"
fi

echo "[INFO] -----------------EOF"

################KERNEL END
