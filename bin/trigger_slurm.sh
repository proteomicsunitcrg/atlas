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
set -x

WORKFLOW=$1
WORK_DIR=$2
SEARCH_ENGINE=$3
PROFILE=$4
EXECUTOR=$5
LAB=$6
RAWFILE=$7
OUTPUT_FOLDER=$8

echo "===================== RECEIVED PARAMS ========================="
echo "WORKFLOW_SCRIPT: '$WORKFLOW'"
echo "WORK_DIR: '$WORK_DIR'"
echo "SEARCH_ENGINE: '$SEARCH_ENGINE'"
echo "PROFILE: '$PROFILE'"
echo "EXECUTOR: '$EXECUTOR'"
echo "LAB: '$LAB'"
echo "RAWFILE: '$RAWFILE'"
echo "OUTPUT_FOLDER: '$OUTPUT_FOLDER'"
echo "==============================================================="

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

nextflow run "${WORKFLOW}" -work-dir "${WORK_DIR}" -profile "${EXECUTOR}_${PROFILE},${LAB}" --search_engine "${SEARCH_ENGINE}" --rawfile "${RAWFILE}" --output_folder "${OUTPUT_FOLDER}"

#nextflow run /users/pr/proteomics/mygit/hello-world  & pid=$!
#nextflow run "$WORKFLOW" $WITH_TOWER -bg -with-report -work-dir "$WORK_DIR" \
#  --var_modif "$VAR_MODIF" \
#  --sites_modif "$SITES_MODIF" \
#  --fragment_mass_tolerance "$FRAGMENT_MASS_TOLERANCE" \
#  --fragment_error_units "$FRAGMENT_ERROR_UNITS" \
#  --precursor_mass_tolerance "$PRECURSOR_MASS_TOLERANCE" \
#  --precursor_error_units "$PRECURSOR_ERROR_UNITS" \
#  --missed_cleavages "$MISSED_CLEAVAGES" \
#  --output_folder "$OUTPUT_FOLDER" \
#  --instrument_folder "$INSTRUMENT_FOLDER" \
#  --search_engine "$SEARCH_ENGINE" \
#   -profile "${EXECUTOR}_${PROFILE},$LAB" \
#  --sampleqc_api_key "$SAMPLEQC_API_KEY" \
#  --rawfile "$RAWFILE" \
#  --test_mode "$TEST_MODE" \
#  --test_folder "$TEST_FOLDER" \
#  --notif_email "$NOTIF_EMAIL" \
#  --enable_notif_email "$ENABLE_NOTIF_EMAIL" & pid=$!

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