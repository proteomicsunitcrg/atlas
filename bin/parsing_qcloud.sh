#!/bin/bash

### ------------------------------
### EXTRACTION AND PARSING FUNCTIONS
### ------------------------------

# Function: Extract median injection time (MIT) from mzML file
# Inputs: 
#   $1 - mzML file
#   $2 - CV accession for ms level
#   $3 - ms level value (e.g. 1 or 2)
#   $4 - CV accession for injection time
# Output:
#   Prints the median injection time (numeric) to stdout
get_mit(){
  mzml_file=$1
  cv_ms_level=$2
  ms_level=$3
  cv_it=$4
  curr_dir=$(pwd)
  basename=$(basename $curr_dir/$mzml_file | cut -f 1 -d '.')

  xmllint --xpath '//*[local-name()="spectrum"]/*[@accession="'$cv_ms_level'"][@value="'$ms_level'"]/../*[local-name()="scanList"]/*[local-name()="scan"]/*[local-name()="cvParam"][@accession="'$cv_it'"]/@value' $mzml_file > $curr_dir/$basename.it.str

  grep -o '\".*\"' $curr_dir/$basename.it.str | sed 's/"//g' > $curr_dir/$basename.it.num

  datamash median 1 < $curr_dir/$basename.it.num
}

# Function: Convert scientific notation to readable format using sed
# Input: 
#   $1 - numeric value in scientific notation
# Output:
#   Echoes the value with exponent as *10^
convert_scientific_notation(){
  value=$1
  echo $value | sed 's/[eE]+*/\*10\^/'
}

# Function: Convert CSV file to JSON format for QC analysis
# Inputs:
#   $1 - input CSV file
#   $2 - basename for JSON output
# Output:
#   Writes a structured JSON file: <basename>.json
set_csv_to_json(){
  csv_file=$1
  basename_sh=$2
  jq --slurp --raw-input --raw-output '
    split("\n") | .[3:] | map(split(",")) |
    map({"RT": .[0],"mz": .[1],"RTobs": .[2],"dRT": .[3],"mzobs": .[4],"dppm": .[5],"intensity": .[6],"area": .[7]}) |
    del(..|nulls)' $csv_file > "${basename_sh}.json"
}

### ------------------------------
### JSON ACCESS FUNCTIONS
### ------------------------------

# Get 'area' value from JSON by mass
# $1 - mass value (prefix match)
# $2 - full path to JSON file
get_qc_area_from_json(){
  mass=$1
  json_path=$2 
  jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | .area' "$json_path"
}

# Function: Get 'area' from JSON by mass and RT
# Inputs:
#   $1 - mass prefix
#   $2 - RT prefix
#   $3 - JSON base name
# Output:
#   Prints matching area(s) to stdout
get_qc_area_from_json_by_mass_and_rt(){
  mass=$1
  rt=$2
  basename_sh=$3 
  jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | select(.RT | tostring | startswith("'$rt'")) | .area' "${basename_sh}.json"
}

# Get 'dppm' values from JSON by mass
# $1 - mass prefix
# $2 - full path to JSON file
get_qc_dppm_from_json(){
  mass=$1
  json_path=$2
  jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | .dppm' "$json_path"
}

# Function: Get 'dppm' values from JSON by mass and RT
# Inputs:
#   $1 - mass prefix
#   $2 - RT prefix
#   $3 - JSON base name
# Output:
#   Prints matching dppm values
get_qc_dppm_from_json_by_mass_and_rt(){
  mass=$1
  rt=$2
  basename_sh=$3 
  jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | select(.RT | tostring | startswith("'$rt'")) | .dppm' "${basename_sh}.json"
}

# Get 'RTobs' from JSON by mass
# $1 - mass prefix
# $2 - full path to JSON file
get_qc_RTobs_from_json(){
  mass=$1
  json_path=$2
  jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | .RTobs' "$json_path"
}

# Function: Get 'RTobs' from JSON by mass and RT
# Inputs:
#   $1 - mass prefix
#   $2 - RT prefix
#   $3 - JSON base name
# Output:
#   Prints matching RTobs values
get_qc_RTobs_from_json_by_mass_and_rt(){
  mass=$1
  rt=$2
  basename_sh=$3 
  jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | select(.RT | tostring | startswith("'$rt'")) | .RTobs' "${basename_sh}.json"
}

# Function: Extract value from QCloud JSON using peptide and sample ID
# Inputs:
#   $1 - JSON file
#   $2 - peptide name
#   $3 - sample ID
# Output:
#   Prints the value at .data[peptide][sample_id]
get_value_from_qcloud_json(){
  json_file=$1
  peptide=$2
  sample_id=$3
  jq -r --arg pep "$peptide" --arg sid "$sample_id" \
      '.data[$pep][$sid]' "$json_file"
}

### ------------------------------
### JSON CREATION FUNCTIONS
### ------------------------------

# Function: Create an empty generic QC JSON
# Inputs:
#   $1 - checksum ID
#   $2 - category
#   $3 - parameter ID
# Output:
#   Creates empty JSON: <checksum>_<param_id>.json
create_qcloud_json(){
  checksum=$1
  category=$2
  param_id=$3
  param_id_underscore=$(echo "$param_id" | tr ':' '_')
  echo "{}" > "${checksum}_${param_id_underscore}.json"
}

# Function: Create empty JSON for monitored peptides
# Inputs:
#   $1 - checksum ID
#   $2 - parameter ID
# Output:
#   Creates empty JSON: <checksum>_<param_id>.json
create_qcloud_json_monitored_peptides(){
  checksum=$1
  param_id=$2
  param_id_underscore=$(echo "$param_id" | tr ':' '_')
  echo "{}" > "${checksum}_${param_id_underscore}.json"
}


# Function: Create full QCloud JSON with parameter metadata
# Inputs:
#   $1 - checksum ID
#   $2 - qCCV ID
#   $3 - contextSource string
# Output:
#   Creates: <checksum>_<contextSource>.json
create_full_qcloud_json(){
  checksum=$1
  qccv=$2
  contextsource=$3
  contextsource_underscore=$(echo $contextsource | tr : _)
  json_basename="${checksum}_${contextsource_underscore}"
  echo '{"file":{"checksum":"'$checksum'"},"data":[{"parameter":{"qCCV":"'$qccv'"},"values" : [{}]}]}' > "${json_basename}.txt"
  jq . "${json_basename}.txt" > "${json_basename}.json"
}

# Function: Create structured JSON for monitored peptides with qCCV
# Inputs:
#   $1 - checksum ID
#   $2 - qCCV ID
# Output:
#   Creates: <checksum>_<qCCV>.json
create_full_qcloud_json_monitored_peptides(){
  checksum=$1
  qccv=$2
  qccv_underscore=$(echo $qccv | tr : _)
  json_basename="${checksum}_${qccv_underscore}"
  echo '{"file":{"checksum":"'$checksum'"},"data":[{"parameter":{"qCCV":"'$qccv'"},"values" : []}]}' > "${json_basename}.txt"
  jq . "${json_basename}.txt" > "${json_basename}.json"
}

### ------------------------------
### JSON VALUE INSERTION FUNCTIONS
### ------------------------------

# Function: Set a numeric value into a QC JSON
# Inputs:
#   $1 - checksum
#   $2 - value to set
#   $3 - category
#   $4 - file ID (used in file name)
# Output:
#   Updates JSON: <checksum>_<file_id>.json
set_value_to_qcloud_json(){
  checksum=$1
  value=$2
  category=$3
  file_id=$4
  file_id_underscore=$(echo "$file_id" | tr ':' '_')
  json_file="${checksum}_${file_id_underscore}.json"
  jq --arg v "$value" '.value = ($v|tonumber)' "$json_file" > tmp.json && mv tmp.json "$json_file"
}

# Function: Set a value into structured QC JSON with contextSource
# Inputs:
#   $1 - checksum
#   $2 - value
#   $3 - qCCV ID
#   $4 - contextSource
# Output:
#   Updates JSON: <checksum>_<contextSource>.json
set_value_to_qcloud_json_with_context(){
  checksum=$1
  value=$2
  qccv=$3
  contextsource=$4
  contextsource_underscore=$(echo $contextsource | tr : _)
  json_basename="${checksum}_${contextsource_underscore}"
  jq '.data[].values[] += {"value":"'$value'","contextSource":"'$contextsource'"}' "${json_basename}.json" | sponge "${json_basename}.json"
}

# Function: Set peptide-specific value in monitored peptides JSON
# Inputs:
#   $1 - checksum ID (used in file name)
#   $2 - numeric value to assign
#   $3 - parameter ID (e.g. "QC:1000894")
#   $4 - peptide name (used as key in JSON)
# Output:
#   Updates or creates JSON file named <checksum>_<param_id>.json, 
#   replacing ":" with "_" in the param ID to ensure valid file naming.
#   The JSON structure is a flat map with peptide keys and numeric values.
set_value_to_qcloud_json_monitored_peptides() {
  checksum=$1
  value=$2
  param_id=$3
  peptide=$4

  # Replace ":" with "_" to create a valid filename
  param_id_underscore=$(echo "$param_id" | tr ':' '_')
  json_out="${checksum}_${param_id_underscore}.json"

  # Create empty JSON file if it does not exist
  if [ ! -f "$json_out" ]; then
    echo "{}" > "$json_out"
  fi

  # Insert or update peptide-specific value using jq
  jq --arg v "$value" --arg p "$peptide" '.[$p] = ($v|tonumber)' "$json_out" > tmp.json && mv tmp.json "$json_out"
}

# Function: Add value to monitored peptides JSON with contextSource
# Inputs:
#   $1 - checksum
#   $2 - value
#   $3 - qCCV ID
#   $4 - contextSource string
# Output:
#   Appends to values array in JSON
set_value_to_qcloud_json_monitored_peptides_with_context(){
  checksum=$1
  value=$2
  qccv=$3
  contextsource=$4
  qccv_underscore=$(echo $qccv | tr : _)
  json_basename="${checksum}_${qccv_underscore}"
  jq '.data[].values += [{"value":"'$value'","contextSource":"'$contextsource'"}]' "${json_basename}.json" | sponge "${json_basename}.json"
}

extract_peptide_metrics() {
    local mz_base=$1
    local peptide=$2
    local json_path=$3
    local checksum=$4

    local json_area_id="QC:1001844"
    local json_rt_id="QC:1000894"
    local json_dppm_id="QC:1000014"

    echo "[DEBUG] --- extract_peptide_metrics ---"
    echo "[DEBUG] mz_base: $mz_base"
    echo "[DEBUG] peptide: $peptide"
    echo "[DEBUG] json_path: $json_path"
    echo "[DEBUG] checksum: $checksum"

    local mz
    mz=$(echo "$mz_base" | awk '{printf "%.1f", $1}')
    echo "[DEBUG] formatted m/z: $mz"

    if [[ ! -f "$json_path" ]]; then
        echo "[WARNING] JSON file $json_path not found. Skipping $peptide"
        return 1
    fi

    echo "[DEBUG] Using JSON file: $json_path"

    area=$(get_qc_area_from_json "$mz" "$json_path")
    echo "[DEBUG] Raw area: $area"
    area=$(convert_scientific_notation "$area")
    echo "[DEBUG] Area after conversion: $area"

    rt=$(get_qc_RTobs_from_json "$mz" "$json_path")
    echo "[DEBUG] RT: $rt"
    dppm=$(get_qc_dppm_from_json "$mz" "$json_path")
    echo "[DEBUG] dppm: $dppm"

    : "${area:=0}"
    : "${rt:=0}"
    : "${dppm:=0}"

    echo "[DEBUG] Final values -> Area: $area | RT: $rt | dppm: $dppm"

    set_value_to_qcloud_json_monitored_peptides "$checksum" "$area" "$json_area_id" "$peptide"
    set_value_to_qcloud_json_monitored_peptides "$checksum" "$rt" "$json_rt_id" "$peptide"
    set_value_to_qcloud_json_monitored_peptides "$checksum" "$dppm" "$json_dppm_id" "$peptide"
}

extract_peptide_metrics_qcsummary() {
    local json_path=$1
    local peptide=$2
    local sample_id=$3      
    local checksum=$4
    local param_id=$5

    echo "[DEBUG] --- extract_peptide_metrics_qcsummary ---"
    echo "[DEBUG] json_path: $json_path"
    echo "[DEBUG] peptide: $peptide"
    echo "[DEBUG] sample_id: $sample_id"
    echo "[DEBUG] checksum: $checksum"
    echo "[DEBUG] param_id: $param_id"

    # Normalize sample_id in case it includes .raw.mzML (safety fallback)
    sample_id=$(echo "$sample_id" | sed 's/\.raw\.mzML$//')

    if [[ -z "$sample_id" ]]; then
        echo "[ERROR] sample_id is empty! Please provide the mzML basename."
        return 1
    fi

    local value
    value=$(jq -r --arg pep "$peptide" --arg sid "$sample_id" '.data[$pep][$sid]' "$json_path")

    echo "[DEBUG] Lookup: .data[\"$peptide\"][\"$sample_id\"]"
    echo "[DEBUG] Raw jq result: $value"

    if [[ "$value" == "null" ]]; then
        echo "[WARNING] No exact match for [$peptide], trying prefix match..."

        local key_match
        key_match=$(jq -r --arg pep "$peptide" '.data | keys[] | select(startswith($pep))' "$json_path" | head -n1)

        echo "[DEBUG] Found key match by prefix: $key_match"

        if [[ -n "$key_match" ]]; then
            value=$(jq -r --arg km "$key_match" --arg sid "$sample_id" '.data[$km][$sid]' "$json_path")
            echo "[DEBUG] Retrieved value from prefix key: $value"
        fi
    fi

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "[WARNING] No value found for [$peptide] in [$sample_id] from $json_path"
        value=0
    fi

    echo "[DEBUG] Final value: $value"

    # Write value to JSON file with checksum and param_id for later use
    set_value_to_qcloud_json_monitored_peptides "$checksum" "$value" "$param_id" "$peptide"
}

# Function: Extract and store TIC, MIT MS1 and MIT MS2 using config parameters
# Inputs:
#   $1 - mzML file
#   $2 - config file path
# Output:
#   Creates JSON files and returns values
extract_general_metrics(){
  local mzml_file=$1
  local config_file=$2

  echo "[DEBUG] --- extract_general_metrics ---"
  echo "[DEBUG] mzML: $mzml_file"
  echo "[DEBUG] config: $config_file"

  # Extract information from filename
  local basename_file=$(basename "$mzml_file")
  local sample_id=$(extract_sample_id_from_filename "$basename_file")
  local checksum=$(extract_checksum_from_filename "$sample_id")
  local uuid=$(extract_uuid_from_filename "$sample_id")

  echo "[DEBUG] Extracted from filename:"
  echo "[DEBUG] Sample ID: $sample_id"
  echo "[DEBUG] Checksum: $checksum"
  echo "[DEBUG] UUID: $uuid"

  # Parse config file to get ontology references (with better newline handling)
  local cv_total_tic=$(grep -A 10 "ms_params.*=" "$config_file" | grep "total_tic" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local cv_ms_level=$(grep -A 10 "ms_params.*=" "$config_file" | grep "ms_type" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local cv_injection_time=$(grep -A 10 "ms_params.*=" "$config_file" | grep "injection_time" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')

  # Parse QC parameter IDs from config (with better newline handling)
  local param_id_tic=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep -w "tic" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local param_id_mit_ms1=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep "mit_ms1" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local param_id_mit_ms2=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep "mit_ms2" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')

  # Parse QC context IDs from config (with better newline handling)
  local context_id_tic=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep -w "tic" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local context_id_mit_ms1=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep "mit_ms1" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local context_id_mit_ms2=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep "mit_ms2" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')

  echo "[DEBUG] Parsed from config:"
  echo "[DEBUG] CV TIC: '$cv_total_tic'"
  echo "[DEBUG] CV MS level: '$cv_ms_level'" 
  echo "[DEBUG] CV injection time: '$cv_injection_time'"
  echo "[DEBUG] QC param IDs - TIC: '$param_id_tic', MS1: '$param_id_mit_ms1', MS2: '$param_id_mit_ms2'"
  echo "[DEBUG] QC context IDs - TIC: '$context_id_tic', MS1: '$context_id_mit_ms1', MS2: '$context_id_mit_ms2'"

  # TIC extraction using xmllint approach
  echo "[DEBUG] Starting TIC extraction using xmllint..."
  local tic
  tic=$(get_tic "$mzml_file" "$cv_total_tic")
  echo "[DEBUG] TIC raw value: $tic"
  : "${tic:=0}"
  echo "[DEBUG] TIC (final): $tic"

  # MIT MS1
  echo "[DEBUG] Extracting MIT MS1..."
  local mit_ms1
  mit_ms1=$(get_mit "$mzml_file" "$cv_ms_level" "1" "$cv_injection_time")
  echo "[DEBUG] MIT MS1 raw value: $mit_ms1"
  : "${mit_ms1:=0}"
  echo "[DEBUG] MIT MS1 (final): $mit_ms1"

  # MIT MS2
  echo "[DEBUG] Extracting MIT MS2..."
  local mit_ms2
  mit_ms2=$(get_mit "$mzml_file" "$cv_ms_level" "2" "$cv_injection_time")
  echo "[DEBUG] MIT MS2 raw value: $mit_ms2"
  : "${mit_ms2:=0}"
  echo "[DEBUG] MIT MS2 (final): $mit_ms2"

  # Create JSON files with proper QCloud structure
  echo "[DEBUG] Creating QCloud JSON files with proper structure..."
  
  create_qcloud_json_with_header "$checksum" "$param_id_tic" "$context_id_tic" "$tic" "$uuid"
  create_qcloud_json_with_header "$checksum" "$param_id_mit_ms1" "$context_id_mit_ms1" "$mit_ms1" "$uuid"
  create_qcloud_json_with_header "$checksum" "$param_id_mit_ms2" "$context_id_mit_ms2" "$mit_ms2" "$uuid"

  echo "[DEBUG] QCloud JSON files created successfully"
  echo "[DEBUG] --- extract_general_metrics DONE ---"
  
  # Return the values for use in metadata.json
  echo "$tic,$mit_ms1,$mit_ms2,$checksum,$uuid"
} 

# Function: Create QCloud JSON with proper header structure
# Inputs:
#   $1 - checksum (from filename, not file hash)
#   $2 - qCCV parameter ID
#   $3 - contextSource ID
#   $4 - value
#   $5 - uuid (for filename)
create_qcloud_json_with_header() {
    local checksum=$1
    local qccv=$2
    local context_source=$3
    local value=$4
    local uuid=$5
    
    # Clean up any newlines/carriage returns from inputs
    context_source=$(echo "$context_source" | tr -d '\n\r')
    qccv=$(echo "$qccv" | tr -d '\n\r')
    
    # Extract just the numeric part from contextSource for filename (e.g., "QC:1000927" -> "1000927")
    local context_code=$(echo "$context_source" | cut -d':' -f2)
    
    # Create filename using contextSource: {uuid}_{checksum}_QC_{context_code}.json
    local output_file="${uuid}_${checksum}_QC_${context_code}.json"
    
    echo "[DEBUG] Creating file: '$output_file'" >&2
    echo "[DEBUG] qCCV: '$qccv'" >&2
    echo "[DEBUG] contextSource: '$context_source'" >&2
    
    cat > "$output_file" << EOF
{
  "file" : {
    "checksum" : "$checksum"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "$qccv"
    },
    "values" : [ {
      "value" : "$value",
      "contextSource" : "$context_source"
    } ]
  } ]
}
EOF

    echo "[DEBUG] Created JSON file: $output_file" >&2
}

# Function: Extract Total Ion Current (TIC) from mzML file using xmllint
# Inputs: 
#   $1 - mzML file
#   $2 - CV accession for TIC (e.g., "MS:1000285")
# Output:
#   Prints the total TIC value (sum of all TIC values) as integer to stdout
get_tic(){
  local mzml_file=$1
  local cv_tic=$2
  local curr_dir=$(pwd)
  local basename=$(basename "$curr_dir/$mzml_file" | cut -f 1 -d '.')

  echo "[DEBUG] --- get_tic ---" >&2
  echo "[DEBUG] mzML file: $mzml_file" >&2
  echo "[DEBUG] CV TIC accession: $cv_tic" >&2

  # Extract TIC values using xmllint (similar to get_mit approach)
  xmllint --xpath '//*[@accession="'$cv_tic'"]/@value' "$mzml_file" > "$curr_dir/$basename.tic.str" 2>/dev/null

  # Extract numeric values and sum them, converting scientific notation to full numbers
  grep -o '".*"' "$curr_dir/$basename.tic.str" | sed 's/"//g' > "$curr_dir/$basename.tic.num"

  # Sum all TIC values using awk with printf to avoid scientific notation
  awk '{sum+=$1} END{printf "%.0f", sum}' "$curr_dir/$basename.tic.num"
}

# Function: Extract checksum from filename by reversing and taking first element
# Input: filename like "2019_QC01_ref_6583a564-93dd-4500-a101-b2fe56496b25_QC01_93d2a97b9d0b35c9668663223bdef998"
# Output: checksum (last part: "93d2a97b9d0b35c9668663223bdef998")
extract_checksum_from_filename() {
    local filename=$1
    echo "$filename" | rev | cut -d'_' -f1 | rev
}

# Function: Extract UUID from filename by reversing and taking third element
# Input: filename like "2019_QC01_ref_6583a564-93dd-4500-a101-b2fe56496b25_QC01_93d2a97b9d0b35c9668663223bdef998"
# Output: UUID (third from end: "6583a564-93dd-4500-a101-b2fe56496b25")
extract_uuid_from_filename() {
    local filename=$1
    echo "$filename" | rev | cut -d'_' -f3 | rev
}

# Function: Extract sample ID from filename (everything except extension)
# Input: filename like "2019_QC01_ref_6583a564-93dd-4500-a101-b2fe56496b25_QC01_93d2a97b9d0b35c9668663223bdef998.raw.mzML"
# Output: sample_id without extension
extract_sample_id_from_filename() {
    local filename=$1
    basename "$filename" .mzML | sed 's/\.raw$//'
}