#!/bin/bash
#SBATCH --job-name=qsample
#SBATCH --no-requeue
#SBATCH -p genoa64
#SBATCH --qos=pipelines

# Configure bash
set -e          # Exit immediately on error
set -u          # Exit immediately if using undefined variables
set -o pipefail # Ensure pipelines return non-zero status if any command fails

# Check if input parameter is provided
if [ "$#" -ne 1 ]; then
   echo "Usage: $0 <path-to-zip-file>"
   exit 1
fi

ZIP_FILE=$1

# Validate if the provided file exists
if [ ! -f "$ZIP_FILE" ]; then
   echo "Error: File '$ZIP_FILE' not found!"
   exit 1
fi


# Define the log file
LOG_FILE="/users/pr/proteomics/mygit/qcloud2-pipeline-logs/qcloud2_trigger_submit_slurm.log"

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
nextflow run /users/pr/proteomics/mygit/qcloud2-pipeline/qcloud.nf --zipfiles "$ZIP_FILE" & pid=$!

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