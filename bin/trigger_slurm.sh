#!/bin/bash
#SBATCH --job-name=qsample
#SBATCH --no-requeue
#SBATCH --mem=16G
#SBATCH -p genoa64
#SBATCH --qos=pipelines

# Configure bash
set -e          # Exit immediately on error
set -u          # Exit immediately if using undefined variables
set -o pipefail # Ensure pipelines return non-zero status if any command fails


CSV_FILE="$1"
PATTERN="$2"
#etc.

# maximum variables from here to avoid env issues
IFS=";" read -r _ WORKFLOW NAME VAR_MODIF SITES_MODIF FRAGMENT_MASS_TOLERANCE FRAGMENT_ERROR_UNITS \
    PRECURSOR_MASS_TOLERANCE PRECURSOR_ERROR_UNITS MISSED_CLEAVAGES OUTPUT_FOLDER IS_INSTRUMENT_FOLDER_IN_FILENAME \
    SEARCH_ENGINE NF_PROFILE SAMPLEQC_API_KEY EXECUTOR < <(awk -F';' -v pat="$PATTERN" '$1 == pat' "$CSV_FILE")

echo "===================== VARIABLES ASSIGNADES ====================="
echo "WORKFLOW_SCRIPT: '$WORKFLOW'"
echo "EXPERIMENT_NAME: '$NAME'"
echo "VAR_MODIF: '$VAR_MODIF'"
echo "SITES_MODIF: '$SITES_MODIF'"
echo "FRAGMENT_MASS_TOLERANCE: '$FRAGMENT_MASS_TOLERANCE'"
echo "FRAGMENT_ERROR_UNITS: '$FRAGMENT_ERROR_UNITS'"
echo "PRECURSOR_MASS_TOLERANCE: '$PRECURSOR_MASS_TOLERANCE'"
echo "PRECURSOR_ERROR_UNITS: '$PRECURSOR_ERROR_UNITS'"
echo "MISSED_CLEAVAGES: '$MISSED_CLEAVAGES'"
echo "OUTPUT_FOLDER: '$OUTPUT_FOLDER'"
echo "SEARCH_ENGINE: '$SEARCH_ENGINE'"
echo "PROFILE: '$NF_PROFILE'"
echo "EXECUTOR: '$EXECUTOR'"
echo "==============================================================="

exit 1

nextflow run "$WORKFLOW_SCRIPT" $WITH_TOWER -bg -with-report -work-dir "$WORK_DIR" \
  --var_modif "$VAR_MODIF" \
  --sites_modif "$SITES_MODIF" \
  --fragment_mass_tolerance "$FRAGMENT_MASS_TOLERANCE" \
  --fragment_error_units "$FRAGMENT_ERROR_UNITS" \
  --precursor_mass_tolerance "$PRECURSOR_MASS_TOLERANCE" \
  --precursor_error_units "$PRECURSOR_ERROR_UNITS" \
  --missed_cleavages "$MISSED_CLEAVAGES" \
  --output_folder "$OUTPUT_FOLDER" \
  --instrument_folder "$INSTRUMENT_FOLDER" \
  --search_engine "$SEARCH_ENGINE" \
   -profile "${EXECUTOR}_${PROFILE},$LAB" \
  --sampleqc_api_key "$SAMPLEQC_API_KEY" \
  --rawfile "$RAWFILE" \
  --test_mode "$TEST_MODE" \
  --test_folder "$TEST_FOLDER" \
  --notif_email "$NOTIF_EMAIL" \
  --enable_notif_email "$ENABLE_NOTIF_EMAIL" & pid=$!

exit 1

# Define the log file
LOG_FILE="/users/pr/proteomics/mygit/atlas-logs/atlas_submit_slurm.log"

# Logging function
log() {
   local log_text="$1"
   echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $log_text" | tee -a "$LOG_FILE"
}

# Trap function to handle SIGTERM and propagate it to child processes
_term() {
   log "Caught SIGTERM signal!"
   if [[ -n "${pid:-}" ]]; then
      kill -s SIGTERM "$pid" || true
      wait "$pid" || true
   fi
}

trap _term TERM

# Log the start of the script
log "Script started."

# Nextflow setup
export PATH="$PATH:/users/pr/proteomics/mysoftware/nextflow/"
export NXF_VER="22.04.4"
export NFX_TEMP="$HOME/temp"
log "Nextflow environment configured."

# Java setup
export JAVA_HOME="/users/pr/proteomics/mysoftware/java/jdk-18.0.1.1"
export PATH="/users/pr/proteomics/mysoftware/java/jdk-18.0.1.1/bin:$PATH"
export LD_LIBRARY_PATH="/users/pr/proteomics/mysoftware/java/jdk-18.0.1.1/lib:${LD_LIBRARY_PATH:-}"
log "Java environment configured."

echo "Start Nextflow CL: $(date)"

nextflow run "$WORKFLOW_SCRIPT" $WITH_TOWER -bg -with-report -work-dir "$WORK_DIR" \
  --var_modif "$VAR_MODIF" \
  --sites_modif "$SITES_MODIF" \
  --fragment_mass_tolerance "$FRAGMENT_MASS_TOLERANCE" \
  --fragment_error_units "$FRAGMENT_ERROR_UNITS" \
  --precursor_mass_tolerance "$PRECURSOR_MASS_TOLERANCE" \
  --precursor_error_units "$PRECURSOR_ERROR_UNITS" \
  --missed_cleavages "$MISSED_CLEAVAGES" \
  --output_folder "$OUTPUT_FOLDER" \
  --instrument_folder "$INSTRUMENT_FOLDER" \
  --search_engine "$SEARCH_ENGINE" \
   -profile "${EXECUTOR}_${PROFILE},$LAB" \
  --sampleqc_api_key "$SAMPLEQC_API_KEY" \
  --rawfile "$RAWFILE" \
  --test_mode "$TEST_MODE" \
  --test_folder "$TEST_FOLDER" \
  --notif_email "$NOTIF_EMAIL" \
  --enable_notif_email "$ENABLE_NOTIF_EMAIL" & pid=$!

echo "End Nextflow CL: $(date)"

# Wait for the pipeline to finish
log "Waiting for Nextflow process (PID: $pid)"
wait "$pid"

# Capture and log the exit status
status=$?
if [ $status -eq 0 ]; then
   log "Nextflow pipeline completed successfully."
else
   log "Nextflow pipeline failed with status $status."
fi

# Exit with the status of the pipeline
log "Process $pid finished with status $status."
exit $status