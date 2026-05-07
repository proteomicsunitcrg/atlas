#!/bin/bash

get_num_prot_groups_diann(){
    tsv_file="$1"

    echo "[DEBUG] get_num_prot_groups_diann: Processing file $tsv_file" >&2

    if [[ ! -s "$tsv_file" ]]; then
        echo "[ERROR] Input file not found or empty: $tsv_file" >&2
        return 1
    fi

    result=$(awk -F'\t' '
        NR == 1 {
            col = 0
            for (i = 1; i <= NF; i++) {
                if ($i == "Protein.Group") { col = i; break }
            }
            if (col == 0) {
                print "[ERROR] Column Protein.Group not found" > "/dev/stderr"
                exit 1
            }
            print "[DEBUG] Found Protein.Group at column " col > "/dev/stderr"
            next
        }
        $col != "" {
            n = split($col, a, ";")
            for (i = 1; i <= n; i++) {
                if (a[i] != "") print a[i]
            }
        }
    ' "$tsv_file" | sort -u | wc -l)

    echo "[DEBUG] get_num_prot_groups_diann: Result = $result" >&2
    echo "$result"
}

get_num_peptidoforms_diann(){
    tsv_file="$1"

    echo "[DEBUG] get_num_peptidoforms_diann: Processing file $tsv_file" >&2

    if [[ ! -s "$tsv_file" ]]; then
        echo "[ERROR] Input file not found or empty: $tsv_file" >&2
        return 1
    fi

    result=$(awk -F'\t' '
        NR == 1 {
            col = 0
            for (i = 1; i <= NF; i++) {
                if ($i == "Modified.Sequence") { col = i; break }
            }
            if (col == 0) {
                print "[ERROR] Column Modified.Sequence not found" > "/dev/stderr"
                exit 1
            }
            print "[DEBUG] Found Modified.Sequence at column " col > "/dev/stderr"
            next
        }
        $col != "" {
            print $col
        }
    ' "$tsv_file" | sort -u | wc -l)

    echo "[DEBUG] get_num_peptidoforms_diann: Result = $result" >&2
    echo "$result"
}


get_num_charges_diann(){
    tsv_file="$1"
    charge="$2"

    echo "[DEBUG] get_num_charges_diann: Processing file $tsv_file, charge $charge" >&2

    if [[ ! -s "$tsv_file" ]]; then
        echo "[ERROR] Input file not found or empty: $tsv_file" >&2
        return 1
    fi

    if [[ -z "$charge" ]]; then
        echo "[ERROR] Charge argument is empty" >&2
        return 1
    fi

    result=$(awk -F'\t' -v charge="$charge" '
        NR == 1 {
            col = 0
            for (i = 1; i <= NF; i++) {
                if ($i == "Precursor.Charge") { col = i; break }
            }
            if (col == 0) {
                print "[ERROR] Column Precursor.Charge not found" > "/dev/stderr"
                exit 1
            }
            print "[DEBUG] Found Precursor.Charge at column " col > "/dev/stderr"
            next
        }
        $col == charge {
            count++
        }
        END {
            print count + 0
        }
    ' "$tsv_file")

    echo "[DEBUG] get_num_charges_diann: Result = $result" >&2
    echo "$result"
}


get_peptidoform_miscleavages_counts_diann(){
    tsv_file="$1"
    curr_dir="$(pwd)"
    basename="$(basename "$tsv_file" .report.tsv)"

    seq_file="$curr_dir/$basename.seq"
    miscleavages_tsv="$curr_dir/$basename.miscleavages.tsv"

    echo "[DEBUG] ===== get_peptidoform_miscleavages_counts_diann START =====" >&2
    echo "[DEBUG] Input file: $tsv_file" >&2
    echo "[DEBUG] Current directory: $curr_dir" >&2
    echo "[DEBUG] Basename: $basename" >&2
    echo "[DEBUG] Sequence file: $seq_file" >&2
    echo "[DEBUG] Miscleavages TSV: $miscleavages_tsv" >&2

    if [[ ! -s "$tsv_file" ]]; then
        echo "[ERROR] Input file not found or empty: $tsv_file" >&2
        return 1
    fi

    echo "[DEBUG] Extracting Stripped.Sequence column..." >&2

    awk -F'\t' '
        NR == 1 {
            col = 0
            for (i = 1; i <= NF; i++) {
                if ($i == "Stripped.Sequence") { col = i; break }
            }
            if (col == 0) {
                print "[ERROR] Column Stripped.Sequence not found" > "/dev/stderr"
                exit 1
            }
            print "[DEBUG] Found Stripped.Sequence at column " col > "/dev/stderr"
            next
        }
        $col != "" {
            print $col
        }
    ' "$tsv_file" | sort -u > "$seq_file"

    seq_count=$(wc -l < "$seq_file")
    echo "[DEBUG] Unique sequences found: $seq_count" >&2

    if [[ "$seq_count" -eq 0 ]]; then
        echo "[ERROR] No sequences found in Stripped.Sequence column" >&2
        return 1
    fi

    echo "[DEBUG] Computing miscleavages..." >&2

    > "$miscleavages_tsv"

    processed=0

    while IFS= read -r line; do
        missed=0

        for (( i=0; i<${#line}; i++ )); do
            pair="${line:$i:2}"

            if [[ $pair == K? && $pair != KP && $pair != K\( ]] || \
               [[ $pair == R? && $pair != RP && $pair != R\( ]]; then
                ((missed+=1))
            fi
        done

        printf "%s\t%s\n" "$line" "$missed" >> "$miscleavages_tsv"

        ((processed+=1))

        if (( processed % 10000 == 0 )); then
            echo "[DEBUG] Processed $processed sequences..." >&2
        fi
    done < "$seq_file"

    echo "[DEBUG] Finished processing $processed sequences" >&2

    echo "[DEBUG] Counting miscleavages by category..." >&2

    count_0=$(awk '$2 == 0 {c++} END {print c+0}' "$miscleavages_tsv")
    count_1=$(awk '$2 == 1 {c++} END {print c+0}' "$miscleavages_tsv")
    count_2=$(awk '$2 == 2 {c++} END {print c+0}' "$miscleavages_tsv")
    count_3=$(awk '$2 == 3 {c++} END {print c+0}' "$miscleavages_tsv")

    printf "%s\n" "$count_0" > "$curr_dir/$basename.miscleavages.0"
    printf "%s\n" "$count_1" > "$curr_dir/$basename.miscleavages.1"
    printf "%s\n" "$count_2" > "$curr_dir/$basename.miscleavages.2"
    printf "%s\n" "$count_3" > "$curr_dir/$basename.miscleavages.3"

    echo "[DEBUG] Miscleavages 0: $count_0" >&2
    echo "[DEBUG] Miscleavages 1: $count_1" >&2
    echo "[DEBUG] Miscleavages 2: $count_2" >&2
    echo "[DEBUG] Miscleavages 3: $count_3" >&2

    echo "[DEBUG] Output written:" >&2
    echo "[DEBUG]   $curr_dir/$basename.miscleavages.0" >&2
    echo "[DEBUG]   $curr_dir/$basename.miscleavages.1" >&2
    echo "[DEBUG]   $curr_dir/$basename.miscleavages.2" >&2
    echo "[DEBUG]   $curr_dir/$basename.miscleavages.3" >&2

    echo "[DEBUG] ===== get_peptidoform_miscleavages_counts_diann DONE =====" >&2
}