#!/usr/bin/env bash
# Usage: find_spectral_library.sh <speclib_folder> <fasta_basename> <version_filter> <legacy_filter> [subfolder]
# Returns: Path to spectral library or empty string

set -euo pipefail

speclib_folder="$1"
fasta_basename="$2"      # e.g., "uniprot_human_reviewed"
version_filter="$3"      # e.g., "232" (from DIA-NN 2.3.2)
legacy_filter="$4"       # e.g., "NK" or "MK"
subfolder="${5:-}"       # e.g., "phospho" -- libraries built with extra var-mods
                         # (like NY's phospho search) live in their own subfolder
                         # so organism+instrument matching never picks a library
                         # built for a different variable-modification set.

existing_lib=""

# Fundamental rule: a spectral library is only ever loaded from the folder for
# the exact DIA-NN version running the search, i.e. <speclib_folder>/diann_X_Y_Z/
# (e.g. atlas-libs/diann_2_3_2/). No cross-version fallback, no top-level scan:
# the on-disk .speclib/.parquet format is tied to the DIA-NN version that wrote
# it (DIA-NN 1.9.2 cannot load a library produced by 2.3.2 -- "version 10 of
# the .speclib format is not supported"), so guessing across versions is unsafe.
# If nothing exists for this version, the caller regenerates from FASTA.

# Within that version folder, match by organism only, ignoring the FASTA's
# year/date suffix (e.g. "sp_human_2026_01" -> "sp_human",
# "sp_bovine_2014a" -> "sp_bovine"): the shared FASTA's year drifts
# independently of when each per-version library was last (re)generated, and
# the version folder already guarantees format compatibility -- there is
# currently only one library per organism per version folder, so matching on
# organism alone is safe.
organism="$fasta_basename"
if [[ "$fasta_basename" =~ ^(.*)_[0-9]{4}.*$ ]]; then
    organism="${BASH_REMATCH[1]}"
fi

if [[ "$version_filter" =~ ^[0-9]{3}$ ]]; then
    v_normalized="${version_filter:0:1}_${version_filter:1:1}_${version_filter:2:1}"
    version_folder="${speclib_folder}/diann_${v_normalized}"

    if [[ -n "$subfolder" ]]; then
        version_folder="${version_folder}/${subfolder}"
    fi

    if [[ -d "$version_folder" ]]; then
        # Try .speclib first, then .parquet
        for ext in speclib parquet; do
            while IFS= read -r -d '' lib; do
                existing_lib="$lib"
                break
            done < <(find -L "${version_folder}" -maxdepth 1 -type f -name "*.${ext}" -print0 | \
                while IFS= read -r -d '' f; do
                    base="$(basename "$f")"
                    if [[ "$base" == *"${organism}"*"${legacy_filter}"* ]]; then
                        printf '%s\0' "$f"
                    fi
                done)
            [[ -n "$existing_lib" ]] && break
        done
    fi
fi

# <--- Return result (may be empty)
echo "$existing_lib"