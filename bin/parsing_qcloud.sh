#!/bin/bash

# Extract a value from a QCloud JSON (structured output from msnbasexic.R)
# Args:
#   1 - JSON file path
#   2 - peptide name (e.g., LVN)
#   3 - sample id (e.g., 190215_Q_QC01_01_32)
get_value_from_qcloud_json() {
    local json_file=$1
    local peptide=$2
    local sample_id=$3

    jq -r --arg pep "$peptide" --arg sid "$sample_id" \
        '.data[$pep][$sid]' "$json_file"
}

# Create empty QC json file
create_qcloud_json() {
    local checksum=$1
    local category=$2
    local param_id=$3
    echo "{}" > "${checksum}_${param_id}.json"
}

# Set value into QC JSON file (non-peptide-specific, e.g., TIC, MIT)
set_value_to_qcloud_json() {
    local checksum=$1
    local value=$2
    local category=$3
    local file_id=$4
    jq --arg v "$value" '.value = ($v|tonumber)' "${checksum}_${file_id}.json" > tmp.json && mv tmp.json "${checksum}_${file_id}.json"
}

# Create JSON for monitored peptides (structure)
create_qcloud_json_monitored_peptides() {
    local checksum=$1
    local param_id=$2
    echo "{}" > "${checksum}_${param_id}.json"
}

# Set peptide-specific value into QC JSON file
set_value_to_qcloud_json_monitored_peptides() {
    local checksum=$1
    local value=$2
    local param_id=$3
    local peptide=$4
    jq --arg v "$value" --arg p "$peptide" '.[$p] = ($v|tonumber)' "${checksum}_${param_id}.json" > tmp.json && mv tmp.json "${checksum}_${param_id}.json"
}
