#!/usr/bin/env bash
# Usage: find_spectral_library.sh <speclib_folder> <fasta_basename> <version_filter> <legacy_filter>
# Returns: Path to spectral library or empty string

set -euo pipefail

speclib_folder="$1"
fasta_basename="$2"      # e.g., "uniprot_human_reviewed"
version_filter="$3"      # e.g., "232" (from DIA-NN 2.3.2)
legacy_filter="$4"       # e.g., "NK" or "MK"

existing_lib=""

# <--- Strategy 1: New naming convention (diann_X_Y_Z)
if [[ "$version_filter" =~ ^[0-9]{3}$ ]]; then
    v_normalized="${version_filter:0:1}_${version_filter:1:1}_${version_filter:2:1}"
    
    # Try .speclib first, then .parquet
    for ext in speclib parquet; do
        for lib in "${speclib_folder}"/*"${fasta_basename}"*"diann_${v_normalized}"*"${legacy_filter}"*.${ext}; do
            if [[ -e "$lib" ]]; then
                existing_lib="$lib"
                break 2
            fi
        done
    done
fi

# <--- Strategy 2: Legacy naming (fallback)
if [[ -z "$existing_lib" ]]; then
    for ext in speclib parquet; do
        for lib in "${speclib_folder}"/*"${fasta_basename}"*"${legacy_filter}"*.${ext}; do
            if [[ -e "$lib" ]]; then
                existing_lib="$lib"
                break 2
            fi
        done
    done
fi

# <--- Return result (may be empty)
echo "$existing_lib"