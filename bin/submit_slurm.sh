#!/bin/bash
#SBATCH --job-name=qsample
#SBATCH --no-requeue
#SBATCH -p genoa64
#SBATCH --qos=pipelines

# Configure bash
set -e          # Exit immediately on error
set -u          # Exit immediately if using undefined variables
set -o pipefail # Ensure pipelines return non-zero status if any command fails

# Input parameters: 
WORKFLOW_SCRIPT=$1
WITH_TOWER=$2
BACKGROUND=$3
WITH_REPORT=$4
WORK_DIR=$5
VAR_MODIF=$6
SITES_MODIF=$7
FRAGMENT_MASS_TOLERANCE=$8
FRAGMENT_ERROR_UNITS=$9
PRECURSOR_MASS_TOLERANCE=${10}
PRECURSOR_ERROR_UNITS=${11}
MISSED_CLEAVAGES=${12}
OUTPUT_FOLDER=${13}
INSTRUMENT_FOLDER=${14}
SEARCH_ENGINE=${15}
PROFILE=${16}
SAMPLEQC_API_KEY=${17}
RAWFILE=${18}
TEST_MODE=${19}
TEST_FOLDER=${20}
NOTIF_EMAIL=${21}
ENABLE_NOTIF_EMAIL=${22}

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
export PATH="$PATH:/users/pr/proteomics/mysoftware/nextflow"
export NXF_VER="22.04.4"
export NFX_TEMP="$HOME/temp"
log "Nextflow environment configured."

# Java setup
export JAVA_HOME="/users/pr/proteomics/mysoftware/java/jdk-18.0.1.1"
export PATH="/users/pr/proteomics/mysoftware/java/jdk-18.0.1.1/bin:$PATH"
export LD_LIBRARY_PATH="/users/pr/proteomics/mysoftware/java/jdk-18.0.1.1/lib:${LD_LIBRARY_PATH:-}"
log "Java environment configured."

# Start the Nextflow pipeline and log its output
log "Starting Nextflow pipeline."
nextflow run "$WORKFLOW_SCRIPT" $WITH_TOWER $BACKGROUND $WITH_REPORT -work-dir "$WORK_DIR" \
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
  -profile "$PROFILE" \
  --sampleqc_api_key "$SAMPLEQC_API_KEY" \
  --rawfile "$RAWFILE" \
  --test_mode "$TEST_MODE" \
  --test_folder "$TEST_FOLDER" \
  --notif_email "$NOTIF_EMAIL" \
  --enable_notif_email "$ENABLE_NOTIF_EMAIL" & pid=$!

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
