#!/usr/bin/env bash
#
# Parse Parquet format DIA-NN report (versions 2.2.0+)
# Converts Parquet to TSV using DuckDB
#
set -euo pipefail

REPORT_FILE="$1"
DUCKDB_BIN="${2:-duckdb}"

if [[ ! -f "$REPORT_FILE" ]]; then
    echo "ERROR: Report file not found: $REPORT_FILE" >&2
    exit 1
fi

# Check if DuckDB is available
if ! command -v "$DUCKDB_BIN" &> /dev/null; then
    echo "ERROR: DuckDB not found at: $DUCKDB_BIN" >&2
    echo "Please install DuckDB or set params.duckdb_path in config" >&2
    exit 1
fi

# Convert Parquet to TSV using DuckDB
"$DUCKDB_BIN" -csv -separator $'\t' <<SQL
SELECT * FROM read_parquet('$REPORT_FILE');
SQL