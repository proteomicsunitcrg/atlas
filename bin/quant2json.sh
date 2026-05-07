#!/bin/bash
set -ue

if [[ "$#" -ne 5 ]]; then
    echo "[ERROR] Usage: $0 <csvfile> <checksum> <output> <num_prots> <is_diann_file>" >&2
    exit 1
fi

csvfile="$1"
checksum="$2"
output="$3"
num_prots="$4"
is_diann_file="$5"

echo "[DEBUG] quant2json.sh START" >&2
echo "[DEBUG] csvfile: $csvfile" >&2
echo "[DEBUG] checksum: $checksum" >&2
echo "[DEBUG] output: $output" >&2
echo "[DEBUG] num_prots: $num_prots" >&2
echo "[DEBUG] is_diann_file: $is_diann_file" >&2

if [[ ! -s "$csvfile" ]]; then
    echo "[ERROR] Input file not found or empty: $csvfile" >&2
    exit 1
fi

if ! [[ "$num_prots" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] num_prots must be an integer: $num_prots" >&2
    exit 1
fi

json_escape() {
    printf '%s' "$1" \
    | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/ /g; s/\r//g'
}

is_nonzero_number() {
    awk -v x="$1" 'BEGIN { exit !(x+0 != 0) }'
}

get_col_index() {
    local file="$1"
    local colname="$2"

    awk -F'\t' -v colname="$colname" '
        NR == 1 {
            for (i = 1; i <= NF; i++) {
                if ($i == colname) {
                    print i
                    found = 1
                    exit
                }
            }
        }
        END {
            if (!found) exit 1
        }
    ' "$file" || true
}

if [[ "$is_diann_file" == true ]]; then

    prot_col="$(get_col_index "$csvfile" "Protein.Group")"
    descr_col="$(get_col_index "$csvfile" "Protein.Names")"
    abund_col="$(get_col_index "$csvfile" "PG.MaxLFQ")"

    if [[ -z "$prot_col" || -z "$descr_col" || -z "$abund_col" ]]; then
        echo "[ERROR] DIA-NN required columns not found in: $csvfile" >&2
        echo "[ERROR] Expected columns: Protein.Group, Protein.Names, PG.MaxLFQ" >&2
        echo "[ERROR] First line of file:" >&2
        head -n 1 "$csvfile" >&2
        exit 1
    fi

    echo "[DEBUG] DIA-NN Protein.Group column: $prot_col" >&2
    echo "[DEBUG] DIA-NN Protein.Names column: $descr_col" >&2
    echo "[DEBUG] DIA-NN PG.MaxLFQ column: $abund_col" >&2

    mapfile -t all_prots < <(
        tail -n +2 "$csvfile" \
        | sort -r -g -k "$abund_col" -t $'\t' \
        | awk -F'\t' -v c="$prot_col" '{print $c}' \
        | cut -d ";" -f1
    )

    mapfile -t all_descr < <(
        tail -n +2 "$csvfile" \
        | sort -r -g -k "$abund_col" -t $'\t' \
        | awk -F'\t' -v c="$descr_col" '{print $c}' \
        | cut -d ";" -f1
    )

    mapfile -t all_abund < <(
        tail -n +2 "$csvfile" \
        | sort -r -g -k "$abund_col" -t $'\t' \
        | awk -F'\t' -v c="$abund_col" '{print $c}' \
        | cut -d ";" -f1
    )

else

    tmpfile="$(mktemp)"
    sed '1,3d' "$csvfile" > "$tmpfile"

    mapfile -t all_prots < <(
        sort -r -g -k 5 -t $'\t' "$tmpfile" \
        | awk -F'\t' '{print $1}' \
        | tr -d '"' \
        | awk -F'|' '{print $2}'
    )

    mapfile -t all_descr < <(
        sort -r -g -k 5 -t $'\t' "$tmpfile" \
        | awk -F'\t' '{print $1}' \
        | tr -d '"' \
        | awk -F'|' '{print $3}'
    )

    mapfile -t all_abund < <(
        sort -r -g -k 5 -t $'\t' "$tmpfile" \
        | awk -F'\t' '{print $5}'
    )

    rm -f "$tmpfile"
fi

echo "[DEBUG] Parsed proteins: ${#all_prots[@]}" >&2
echo "[DEBUG] Parsed descriptions: ${#all_descr[@]}" >&2
echo "[DEBUG] Parsed abundances: ${#all_abund[@]}" >&2

if [[ "${#all_prots[@]}" -ne "${#all_descr[@]}" || "${#all_prots[@]}" -ne "${#all_abund[@]}" ]]; then
    echo "[ERROR] Parsed arrays have different lengths" >&2
    exit 1
fi

count_prot=0
count_cont=0
written_prot=0
written_cont=0
first=true

printf '{"file":{"checksum":"%s"},"quant":[' "$(json_escape "$checksum")" > "$output"

for i in "${!all_prots[@]}"; do
    accession="${all_prots[$i]}"
    description="${all_descr[$i]:-}"
    abundance="${all_abund[$i]}"

    if [[ -z "$accession" || -z "$abundance" ]]; then
        continue
    fi

    if ! is_nonzero_number "$abundance"; then
        continue
    fi

    if [[ "$accession" == *"CON_"* ]]; then
        contaminant=true

        if (( count_cont >= num_prots )); then
            continue
        fi

        ((count_cont+=1))
        ((written_cont+=1))
    else
        contaminant=false

        if (( count_prot >= num_prots )); then
            continue
        fi

        ((count_prot+=1))
        ((written_prot+=1))
    fi

    accession="$(json_escape "$accession")"
    description="$(json_escape "$description")"

    if [[ "$first" == true ]]; then
        first=false
    else
        printf ',' >> "$output"
    fi

    printf '{"accession":"%s","description":"%s","abundance":%s,"contaminant":%s}' \
        "$accession" "$description" "$abundance" "$contaminant" >> "$output"
done

printf ']}' >> "$output"

echo "[DEBUG] Non-contaminant proteins written: $written_prot" >&2
echo "[DEBUG] Contaminant proteins written: $written_cont" >&2
echo "[DEBUG] Output JSON: $output" >&2
echo "[DEBUG] quant2json.sh DONE" >&2