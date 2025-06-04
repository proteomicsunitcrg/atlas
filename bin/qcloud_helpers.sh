#!/bin/bash

# Extract sample_id and labsysid from mzML filename
get_sample_info() {
    local mzml_filename="$1"
    local sample_id=$(basename "$mzml_filename" | cut -f 1 -d '.')
    local reversed_filename=$(echo "$sample_id" | rev)
    local reversed_first_3_underscores=$(echo "$reversed_filename" | cut -d'_' -f1-3 | rev)
    local labsysid=$(echo "$reversed_first_3_underscores" | cut -d'_' -f1)
    echo "$sample_id|$labsysid"
}

# Generate insert file JSON
generate_insert_file_json() {
    local creation_date="$1"
    local sample_id="$2"
    local checksum="$3"
    echo '{"creationDate": "'$creation_date'","filename": "'$sample_id'","checksum": "'$checksum'"}' > insert_file_string
}

# Upload multiple JSONs to QCloud
upload_qc_jsons() {
    local checksum="$1"
    local access_token="$2"
    local api_url="$3"
    shift 3
    local ids=("$@")
    for id in "${ids[@]}"; do
        echo "[INFO] Insert data: $id"
        curl -s -X POST -H "Authorization: $access_token" \
             "$api_url" \
             -H "Content-Type: application/json" \
             --data @"${checksum}_${id}.json"
    done
}
