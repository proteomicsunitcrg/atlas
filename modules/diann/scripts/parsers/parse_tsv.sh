#!/usr/bin/env bash
#
# Parse TSV format DIA-NN report (versions 1.9.2)
# Simply passes through the TSV file to stdout
#
set -euo pipefail

REPORT_FILE="$1"

if [[ ! -f "$REPORT_FILE" ]]; then
    echo "ERROR: Report file not found: $REPORT_FILE" >&2
    exit 1
fi

# TSV files are already in the correct format - pass through
cat "$REPORT_FILE"