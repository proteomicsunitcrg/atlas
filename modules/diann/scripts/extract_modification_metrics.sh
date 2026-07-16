#!/usr/bin/env bash
#
# Extract DIA-NN modification metrics from report.parquet using DuckDB.
# Modification targets are read from the DIA-NN CFG file.
#
set -euo pipefail

REPORT_FILE="$1"
CONFIG_FILE="$2"
OUTPUT_FILE="$3"
DUCKDB_BIN="${4:-duckdb}"
QVALUE_CUTOFF="${5:-0.01}"

if [[ ! -f "$REPORT_FILE" ]]; then
    echo "ERROR: Report file not found: $REPORT_FILE" >&2
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: DIA-NN config file not found: $CONFIG_FILE" >&2
    exit 1
fi

if ! command -v "$DUCKDB_BIN" &> /dev/null; then
    echo "ERROR: DuckDB not found at: $DUCKDB_BIN" >&2
    echo "Please install DuckDB or set params.duckdb_path in config" >&2
    exit 1
fi

cat > "$OUTPUT_FILE" <<'HEADER'
metric_type	unimod	residue	configured_residues	value	qvalue_cutoff
HEADER

peptide_hits=$("$DUCKDB_BIN" -noheader -csv <<SQL
SELECT count(DISTINCT "Modified.Sequence")
FROM read_parquet('$REPORT_FILE')
WHERE "Q.Value" <= CAST('$QVALUE_CUTOFF' AS DOUBLE);
SQL
)

printf "peptide_hits\tNA\tNA\tNA\t%s\t%s\n" "$peptide_hits" "$QVALUE_CUTOFF" >> "$OUTPUT_FILE"

total_area=$("$DUCKDB_BIN" -noheader -csv <<SQL
SELECT COALESCE(sum("Precursor.Quantity"), 0)
FROM read_parquet('$REPORT_FILE')
WHERE "Q.Value" <= CAST('$QVALUE_CUTOFF' AS DOUBLE);
SQL
)

printf "total_area\tNA\tNA\tNA\t%s\t%s\n" "$total_area" "$QVALUE_CUTOFF" >> "$OUTPUT_FILE"

while read -r unimod residues; do
    [[ -z "$unimod" || -z "$residues" ]] && continue

    residue_patterns=()

    for (( i=0; i<${#residues}; i++ )); do
        residue="${residues:$i:1}"
        pattern="${residue}\\(${unimod}\\)"
        residue_patterns+=("${pattern}")

        site_count=$("$DUCKDB_BIN" -noheader -csv <<SQL
WITH unique_sequences AS (
    SELECT DISTINCT "Modified.Sequence" AS modified_sequence
    FROM read_parquet('$REPORT_FILE')
    WHERE "Q.Value" <= CAST('$QVALUE_CUTOFF' AS DOUBLE)
)
SELECT count(*)
FROM unique_sequences,
     unnest(regexp_extract_all(modified_sequence, '$pattern')) AS matches(hit);
SQL
)

        printf "site_count\t%s\t%s\t%s\t%s\t%s\n" \
            "$unimod" "$residue" "$residues" "$site_count" "$QVALUE_CUTOFF" >> "$OUTPUT_FILE"
    done

    combined_pattern="$(printf "%s\n" "${residue_patterns[@]}" | paste -sd'|' -)"

    modified_peptidoforms=$("$DUCKDB_BIN" -noheader -csv <<SQL
WITH unique_sequences AS (
    SELECT DISTINCT "Modified.Sequence" AS modified_sequence
    FROM read_parquet('$REPORT_FILE')
    WHERE "Q.Value" <= CAST('$QVALUE_CUTOFF' AS DOUBLE)
)
SELECT count(*)
FROM unique_sequences
WHERE regexp_matches(modified_sequence, '$combined_pattern');
SQL
)

    printf "modified_peptidoforms\t%s\tNA\t%s\t%s\t%s\n" \
        "$unimod" "$residues" "$modified_peptidoforms" "$QVALUE_CUTOFF"

    modified_area=$("$DUCKDB_BIN" -noheader -csv <<SQL
SELECT COALESCE(sum("Precursor.Quantity"), 0)
FROM read_parquet('$REPORT_FILE')
WHERE "Q.Value" <= CAST('$QVALUE_CUTOFF' AS DOUBLE)
  AND regexp_matches("Modified.Sequence", '$combined_pattern');
SQL
)

    printf "modified_area\t%s\tNA\t%s\t%s\t%s\n" \
        "$unimod" "$residues" "$modified_area" "$QVALUE_CUTOFF"

done < <(
    awk '
        $1 == "--var-mod" {
            split($2, fields, ",")
            gsub(/"/, "", fields[3])
            if (fields[1] ~ /^UniMod:[0-9]+$/ && fields[3] ~ /^[A-Z]+$/) {
                print fields[1], fields[3]
            }
        }
    ' "$CONFIG_FILE"
) >> "$OUTPUT_FILE"
