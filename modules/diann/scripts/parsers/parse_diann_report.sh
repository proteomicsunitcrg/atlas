#!/usr/bin/env bash
#
# Parse DIA-NN report with format auto-detection based on parser_version
# Usage: parse_diann_report.sh <report_file> <parser_version> <duckdb_bin>
#
set -euo pipefail

REPORT_FILE="$1"
PARSER_VERSION="$2"
DUCKDB_BIN="${3:-duckdb}"

# Get script directory (we're already in parsers/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate inputs
if [[ ! -f "$REPORT_FILE" ]]; then
    echo "ERROR: Report file not found: $REPORT_FILE" >&2
    exit 1
fi

if [[ -z "$PARSER_VERSION" ]]; then
    echo "ERROR: parser_version not provided" >&2
    exit 1
fi

# Dispatch to appropriate parser
case "$PARSER_VERSION" in
    tsv)
        exec bash "${SCRIPT_DIR}/parse_tsv.sh" "$REPORT_FILE"
        ;;
    parquet)
        exec bash "${SCRIPT_DIR}/parse_parquet.sh" "$REPORT_FILE" "$DUCKDB_BIN"
        ;;
    sqlite)
        exec bash "${SCRIPT_DIR}/parse_sqlite.sh" "$REPORT_FILE" "$DUCKDB_BIN"
        ;;
    *)
        echo "ERROR: Unknown parser_version: $PARSER_VERSION" >&2
        echo "Expected: tsv, parquet, or sqlite" >&2
        exit 1
        ;;
esac