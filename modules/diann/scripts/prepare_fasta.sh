#!/usr/bin/env bash
# Usage: prepare_fasta.sh <databases_folder> <organism>
# Returns: Path to copied FASTA file (basename only)

set -euo pipefail

databases_folder="$1"
organism="$2"

fasta_dir="${databases_folder}/${organism}/current"

if [[ ! -d "$fasta_dir" ]]; then
    echo "[ERROR] FASTA directory not found: $fasta_dir" >&2
    exit 1
fi

# <--- Find first .fasta file
first_fasta=""
for candidate in "${fasta_dir}"/*.fasta; do
    if [[ -e "$candidate" ]]; then
        first_fasta="$candidate"
        break
    fi
done

if [[ -z "$first_fasta" ]]; then
    echo "[ERROR] No FASTA found for organism '${organism}' in ${fasta_dir}" >&2
    exit 1
fi

# <--- Copy to current directory
fasta_basename=$(basename "$first_fasta")
cp "$first_fasta" .

echo "$fasta_basename"