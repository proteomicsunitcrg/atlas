#!/bin/bash
#SBATCH --job-name=qsample
#SBATCH --no-requeue
#SBATCH --mem=1G
#SBATCH -p genoa64
#SBATCH --qos=pipelines

# Configure bash
set -e          # Exit immediately on error
set -u          # Exit immediately if using undefined variables
set -o pipefail # Ensure pipelines return non-zero status if any command fails
set -x

declare -A PARAMS  # Create an associative array

# Extract workflow script (first argument) and ensure it's a valid path
WORKFLOW_SCRIPT="$1"
shift  # Remove workflow from the list

# Check if WORKFLOW_SCRIPT is a valid file
if [[ ! -f "$WORKFLOW_SCRIPT" ]]; then
    echo "[ERROR] Workflow script '$WORKFLOW_SCRIPT' not found!"
    exit 1
fi

# Extract LAB (second argument)
LAB="$1"
shift  # Remove LAB from the list

echo "[DEBUG] Workflow script = '$WORKFLOW_SCRIPT'"
echo "[DEBUG] LAB = '$LAB'"

declare -A PARAMS  # Define associative array

# Process remaining arguments as key-value pairs
while [[ $# -gt 0 ]]; do
    key="$1"
    shift  

    if [[ $# -eq 0 ]]; then
        echo "[ERROR] Missing value for key: $key"
        exit 1
    fi

    value="$1"
    shift  

    key="${key#--}"

    echo "[DEBUG] Assigning PARAMS[$key]='$value'"
    
    PARAMS["$key"]="$value"
done


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

nextflow run "$WORKFLOW_SCRIPT" -work-dir "${PARAMS[workdir]}" \
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
  -profile "${PARAMS[executor]:-}_${PARAMS[nf_profile]:-},$LAB" \
  --sampleqc_api_key "${PARAMS[sampleqc_api_key]:-}" \
  --rawfile "${PARAMS[rawfile]:-}" \
  --test_mode "${PARAMS[test_mode]:-}" \
  --test_folder "${PARAMS[test_folder]:-}" \
  --notif_email "${PARAMS[notif_email]:-}" \
  --enable_notif_email "${PARAMS[enable_notif_email]:-}" & pid=$!

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