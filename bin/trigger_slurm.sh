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
VAR_MODIF=$3
SITES_MODIF=$4
FRAGMENT_MASS_TOLERANCE=$5
FRAGMENT_ERROR_UNITS=$6
PRECURSOR_MASS_TOLERANCE=$7
PRECURSOR_ERROR_UNITS=$8
MISSED_CLEAVAGES=$9
OUTPUT_FOLDER=${10}
INSTRUMENT_FOLDER=${11}
SEARCH_ENGINE=${12}
NF_PROFILE=${13}
SAMPLEQC_API_KEY=${14}
RAWFILE=${15}
TEST_MODE=${16}
TEST_FOLDER=${17}
NOTIF_EMAIL=${18}
ENABLE_NOTIF_EMAIL=${19}

echo "Workflow: $WORKFLOW"
echo "Work directory: $WORK_DIR"
echo "Variable modifications: $VAR_MODIF"
echo "Site modifications: $SITES_MODIF"
echo "Fragment mass tolerance: $FRAGMENT_MASS_TOLERANCE"
echo "Fragment error units: $FRAGMENT_ERROR_UNITS"
echo "Precursor mass tolerance: $PRECURSOR_MASS_TOLERANCE"
echo "Precursor error units: $PRECURSOR_ERROR_UNITS"
echo "Missed cleavages: $MISSED_CLEAVAGES"
echo "Output folder: $OUTPUT_FOLDER"
echo "Instrument folder: $INSTRUMENT_FOLDER"
echo "Search engine: $SEARCH_ENGINE"
echo "Nextflow profile: $NF_PROFILE"
echo "SampleQC API key: $SAMPLEQC_API_KEY"
echo "Raw file: $RAWFILE"
echo "Test mode: $TEST_MODE"
echo "Test folder: $TEST_FOLDER"
echo "Notification email: $NOTIF_EMAIL"
echo "Enable email notification: $ENABLE_NOTIF_EMAIL"

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