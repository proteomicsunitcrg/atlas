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

# Function: Extract peptide metrics from QC summary JSON and create QCloud JSON
extract_peptide_metrics_qcsummary() {
    local json_file=$1
    local peptide_short_name=$2
    local sample_id=$3
    local checksum=$4
    local qccv=$5
    local config_file=$6
    
    echo "[DEBUG] extract_peptide_metrics_qcsummary: $json_file, peptide: $peptide_short_name, qccv: $qccv"
    
    # Extract the metric type from qccv for filename
    local qcode=$(echo "$qccv" | sed 's/QC://')

    # Parse filename by reversing and splitting by underscore
    local reversed_sample_id=$(echo "$sample_id" | rev)
    local checksum_reversed=$(echo "$reversed_sample_id" | cut -d'_' -f1)
    local context_code_reversed=$(echo "$reversed_sample_id" | cut -d'_' -f2)
    local uuid_reversed=$(echo "$reversed_sample_id" | cut -d'_' -f3)

    # Reverse them back to get original values
    local checksum_extracted=$(echo "$checksum_reversed" | rev)
    local context_code=$(echo "$context_code_reversed" | rev)
    local uuid=$(echo "$uuid_reversed" | rev)

    echo "[DEBUG] Parsed from sample_id: UUID=$uuid, Context=$context_code, Checksum=$checksum_extracted"

    # Create filename in correct format: uuid_context_checksum_QC_qcode.json
    local output_file="${uuid}_${context_code}_${checksum}_QC_${qcode}.json"
    
    echo "[DEBUG] Output file: $output_file"
    
    # Get the OpenMS notation name from config mapping
    local long_name=$(get_openms_peptide_name "$config_file" "$peptide_short_name")
    
    echo "[DEBUG] OpenMS name for $peptide_short_name: $long_name"
    
    # Extract the value from the JSON file - use short_name for lookup
    local value=$(jq -r --arg peptide "$peptide_short_name" --arg sample "$sample_id" '.data[$peptide][$sample] // "null"' "$json_file")
    
    echo "[DEBUG] Extracted value for $peptide_short_name: $value"
    
    if [[ "$value" == "null" || -z "$value" ]]; then
        echo "[WARNING] No value found for peptide $peptide_short_name in $json_file - skipping"
        return 0  # Continue processing instead of failing
    fi
    
    # Create or update the QCloud JSON file
    if [[ ! -f "$output_file" ]]; then
        # Create new file with proper structure
        cat > "$output_file" << EOF
{
  "file": {
    "checksum": "$checksum"
  },
  "data": [
    {
      "parameter": {
        "qCCV": "$qccv"
      },
      "values": [
        {
          "contextSource": "$long_name",
          "value": "$value"
        }
      ]
    }
  ]
}
EOF
    else
        # Add to existing file (append to values array)
        local temp_file=$(mktemp)
        jq --arg contextSource "$long_name" --arg value "$value" \
           '.data[0].values += [{"contextSource": $contextSource, "value": $value}]' \
           "$output_file" > "$temp_file" && mv "$temp_file" "$output_file"
    fi
    
    echo "[DEBUG] Updated $output_file with $peptide_short_name data"
}

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
  local param_id_ms2_count=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep "ms2_scan_count" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')

  # Parse QC context IDs from config (with better newline handling)
  local context_id_tic=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep -w "tic" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local context_id_mit_ms1=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep "mit_ms1" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local context_id_mit_ms2=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep "mit_ms2" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local context_id_ms2_count=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep "ms2_scan_count" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')

  echo "[DEBUG] Parsed from config:"
  echo "[DEBUG] CV TIC: '$cv_total_tic'"
  echo "[DEBUG] CV MS level: '$cv_ms_level'" 
  echo "[DEBUG] CV injection time: '$cv_injection_time'"
  echo "[DEBUG] QC param IDs - TIC: '$param_id_tic', MS1: '$param_id_mit_ms1', MS2: '$param_id_mit_ms2', MS2 scan count: '$param_id_ms2_count'"
  echo "[DEBUG] QC context IDs - TIC: '$context_id_tic', MS1: '$context_id_mit_ms1', MS2: '$context_id_mit_ms2', MS2 scan count: '$context_id_ms2_count'"

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

  # MS2 scan count
  echo "[DEBUG] Extracting MS2 scan count..."
  local ms2_scan_count
  ms2_scan_count=$(get_msn_scan_count "$mzml_file" "$cv_ms_level" "2")
  echo "[DEBUG] MS2 scan count raw value: $ms2_scan_count"
  : "${ms2_scan_count:=0}"
  echo "[DEBUG] MS2 scan count (final): $ms2_scan_count"

  # Create JSON files with proper QCloud structure
  echo "[DEBUG] Creating QCloud JSON files with proper structure..."
  
  create_qcloud_json_with_header "$checksum" "$param_id_tic" "$context_id_tic" "$tic" "$uuid" "$sample_id"
  create_qcloud_json_with_header "$checksum" "$param_id_mit_ms1" "$context_id_mit_ms1" "$mit_ms1" "$uuid" "$sample_id"
  create_qcloud_json_with_header "$checksum" "$param_id_mit_ms2" "$context_id_mit_ms2" "$mit_ms2" "$uuid" "$sample_id"
  create_qcloud_json_with_header "$checksum" "$param_id_ms2_count" "$context_id_ms2_count" "$ms2_scan_count" "$uuid" "$sample_id"

  echo "[DEBUG] QCloud JSON files created successfully"
  echo "[DEBUG] --- extract_general_metrics DONE ---"
  
  # Return the values for use in metadata.json
  echo "$tic,$mit_ms1,$mit_ms2,$ms2_scan_count,$checksum,$uuid"
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
    local sample_id=$6  # Add sample_id parameter
    
    # Clean up any newlines/carriage returns from inputs
    context_source=$(echo "$context_source" | tr -d '\n\r')
    qccv=$(echo "$qccv" | tr -d '\n\r')
    
    # Extract context code (QC01) using reverse parsing like in peptides
    local reversed_sample_id=$(echo "$sample_id" | rev)
    local context_code_reversed=$(echo "$reversed_sample_id" | cut -d'_' -f2)
    local context_code=$(echo "$context_code_reversed" | rev)
    
    # Extract just the numeric part from context_source for filename (e.g., "QC:1000927" -> "1000927")
    local qcode=$(echo "$context_source" | cut -d':' -f2)
    
    # Create filename with correct format: {uuid}_{context_code}_{checksum}_QC_{qcode}.json
    local output_file="${uuid}_${context_code}_${checksum}_QC_${qcode}.json"
    
    echo "[DEBUG] Creating file: '$output_file'" >&2
    echo "[DEBUG] qCCV: '$qccv'" >&2
    echo "[DEBUG] contextSource: '$context_source'" >&2
    echo "[DEBUG] Context code from sample_id: '$context_code'" >&2
    
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

# Function: Count MSN scans in mzML file
# Inputs: 
#   $1 - mzML file
#   $2 - CV accession for ms level (e.g., "MS:1000511")
#   $3 - ms level value (1 or 2)
# Output:
#   Prints the count of MSN scans (numeric) to stdout
get_msn_scan_count(){
  mzml_file=$1
  cv_ms_level=$2
  ms_level=$3

  # Direct count using xmllint's count() function - most efficient
  xmllint --xpath "count(//*[@accession='$cv_ms_level' and @value='$ms_level'])" "$mzml_file" 2>/dev/null || echo "0"
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

# Function: Process peptides from msnbasexic JSON outputs
# Inputs:
#   $1 - mzML file (for extracting sample info)
#   $2 - config file path (passed from Nextflow)
#   $3 - peptides TSV file path (passed from Nextflow)
#   $4+ - msnbasexic JSON files (individual files)
# Output:
#   Creates QCloud JSON files for each peptide/metric combination
process_peptides_from_msnbasexic() {
    local mzml_file=$1
    local config_file=$2
    local peptides_file=$3
    shift 3  # Remove first 3 arguments, rest are JSON files
    local json_files=("$@")  # Array of JSON files
    
    echo "[DEBUG] --- process_peptides_from_msnbasexic ---"
    echo "[DEBUG] mzML: $mzml_file"
    echo "[DEBUG] config: $config_file"
    echo "[DEBUG] peptides_file: $peptides_file"
    echo "[DEBUG] JSON files: ${json_files[*]}"
    
    # Extract information from filename
    local basename_file=$(basename "$mzml_file")
    local sample_id=$(extract_sample_id_from_filename "$basename_file")
    local checksum=$(extract_checksum_from_filename "$sample_id")
    local uuid=$(extract_uuid_from_filename "$sample_id")
    
    echo "[DEBUG] Sample info - ID: $sample_id, Checksum: $checksum, UUID: $uuid"
    
    # Parse QC term IDs from config (the actual values we need)
    local area_qccv=$(grep "\barea\b.*:" "$config_file" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
    local rt_qccv=$(grep "\brt\b.*:" "$config_file" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
    local dppm_qccv=$(grep "\bdppm\b.*:" "$config_file" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
    local fwhm_qccv=$(grep "\bfwhm\b.*:" "$config_file" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')

    echo "[DEBUG] QC mappings - Area: $area_qccv, RT: $rt_qccv, dppm: $dppm_qccv, FWHM: $fwhm_qccv"
    
    # Find specific JSON files by direct pattern matching (more flexible)
    local area_json=""
    local rt_json=""
    local dppm_json=""
    local fwhm_json=""
    
    for json_file in "${json_files[@]}"; do
        case "$json_file" in
            *Total_Area*) area_json="$json_file" ;;           # Prefer raw area values
            *Log2_Total_Area*) 
                if [[ -z "$area_json" ]]; then                # Fallback to log2 if no raw area
                    area_json="$json_file"
                fi
                ;;
            *Observed_RT_sec*) rt_json="$json_file" ;;
            *dmz_ppm*) dppm_json="$json_file" ;;
            *FWHM*) fwhm_json="$json_file" ;;
        esac
    done
    
    echo "[DEBUG] Found JSON files:"
    echo "[DEBUG] Area JSON: $area_json"
    echo "[DEBUG] RT JSON: $rt_json"
    echo "[DEBUG] dppm JSON: $dppm_json"
    echo "[DEBUG] FWHM JSON: $fwhm_json"
    
    # Check if peptides file exists
    if [[ ! -f "$peptides_file" ]]; then
        echo "[ERROR] Peptides file not found: $peptides_file"
        return 1
    fi
    
    echo "[DEBUG] Peptides file found successfully!"
    
    # Process each peptide
    while IFS=':' read -r peptide_name mz_value rt_value; do
        echo "[DEBUG] Processing peptide: $peptide_name (m/z: $mz_value, RT: $rt_value)"
        
        # Extract values for each metric using your existing function
        if [[ -f "$area_json" ]]; then
            echo "[DEBUG] Extracting area for $peptide_name from $area_json"
            extract_peptide_metrics_qcsummary "$area_json" "$peptide_name" "$sample_id" "$checksum" "$area_qccv" "$config_file"
        fi

        if [[ -f "$rt_json" ]]; then
            echo "[DEBUG] Extracting RT for $peptide_name from $rt_json"
            extract_peptide_metrics_qcsummary "$rt_json" "$peptide_name" "$sample_id" "$checksum" "$rt_qccv" "$config_file"
        fi

        if [[ -f "$dppm_json" ]]; then
            echo "[DEBUG] Extracting dppm for $peptide_name from $dppm_json"
            extract_peptide_metrics_qcsummary "$dppm_json" "$peptide_name" "$sample_id" "$checksum" "$dppm_qccv" "$config_file"
        fi

        if [[ -f "$fwhm_json" ]]; then
            echo "[DEBUG] Extracting FWHM for $peptide_name from $fwhm_json"
            extract_peptide_metrics_qcsummary "$fwhm_json" "$peptide_name" "$sample_id" "$checksum" "$fwhm_qccv" "$config_file" 
        fi
        
    done < <(read_peptides_from_tsv "$peptides_file")
    
    echo "[DEBUG] --- process_peptides_from_msnbasexic DONE ---"
}

# Function: Read peptides from TSV file
# Input: TSV file path
# Output: Prints peptide information (short_name:mz_M0:rt_teoretical)
# Assumes TSV structure: short_name	long_name	mz_M0	mz_M1	mz_M2	ms2_mz	rt_teoretical
read_peptides_from_tsv() {
    local tsv_file=$1
    
    echo "[DEBUG] Reading peptides from: $tsv_file" >&2
    
    # Skip header line and extract columns by position using awk (more reliable than read)
    # Column 1: short_name, Column 3: mz_M0, Column 7: rt_teoretical
    tail -n +2 "$tsv_file" | awk -F'\t' '{print $1 ":" $3 ":" $7}'
}

# Function: Get OpenMS notation peptide name from config mapping
get_openms_peptide_name() {
    local config_file=$1
    local simple_name=$2
    
    echo "[DEBUG] Looking up OpenMS name for: $simple_name" >&2
    
    # Extract the OpenMS name from config mapping
    local openms_name=$(grep -A 20 "peptide_name_mapping_openms_notation" "$config_file" | grep "\"$simple_name\":" | sed 's/.*: *"\([^"]*\)".*/\1/')
    
    if [[ -z "$openms_name" ]]; then
        echo "[WARNING] No OpenMS mapping found for $simple_name, using simple name" >&2
        echo "$simple_name"
    else
        echo "[DEBUG] Found OpenMS name: $openms_name" >&2
        echo "$openms_name"
    fi
}


#!/bin/bash

# Function: Submit all QCloud data (file metadata + metrics data)
submit_all_qcloud_data() {
    local sample_id=$1
    local config_file=$2
    shift 2  # Remove sample_id and config_file, rest are JSON files
    local json_files=("$@")
    
    echo "[DEBUG] --- submit_all_qcloud_data ---"
    echo "[DEBUG] Sample ID: $sample_id"
    echo "[DEBUG] Config file: $config_file"
    echo "[DEBUG] JSON files available: ${json_files[*]}"
    
    # Use existing API URL parameters (no need to extract from config)
    local signin_url="${url_api_qcloud_signin}"
    local api_user="${url_api_qcloud_user}"
    local api_pass="${url_api_qcloud_pass}"
    local insert_file_url="${url_api_qcloud_insert_file}"
    local insert_data_url="${url_api_qcloud_insert_data}"
    
    # Use your existing context source for monitored peptides
    local context_source=$(extract_context_value "$config_file" "monitored_peptides")
    
    echo "[DEBUG] API URLs - Signin: $signin_url, Insert File: $insert_file_url, Insert Data: $insert_data_url"
    echo "[DEBUG] Context source: $context_source"
    
    # Extract sample information
    local checksum=$(extract_checksum_from_filename "$sample_id")
    local labsysid=$(extract_uuid_from_filename "$sample_id")
    
    echo "[DEBUG] Sample info - Checksum: $checksum, LabSysID: $labsysid"
    
    # Get access token using your existing function
    echo "Getting access token..."
    if ! access_token=$(source api.sh; get_api_access_token_qcloud "$signin_url" "$api_user" "$api_pass"); then
        echo "ERROR: Failed to get access token"
        return 1
    fi
    
    # Step 1: Insert file metadata (if we have a file metadata JSON)
    local file_metadata_json=""
    for json_file in "${json_files[@]}"; do
        if [[ "$json_file" == *"file_metadata"* ]]; then
            file_metadata_json="$json_file"
            break
        fi
    done
    
    if [[ -n "$file_metadata_json" && -f "$file_metadata_json" ]]; then
        echo "Inserting file metadata to QCloud..."
        submit_file_metadata "$file_metadata_json" "$access_token" "$insert_file_url" "$context_source" "$labsysid"
    else
        echo "[INFO] No file metadata JSON found, skipping file metadata insertion"
    fi
    
    # Step 2: Insert all metrics data using your existing qcloud_terms
    echo "Inserting metrics data to QCloud..."
    submit_metrics_data "$access_token" "$insert_data_url" "$config_file" "${json_files[@]}"
    
    echo "[DEBUG] --- submit_all_qcloud_data DONE ---"
}

# Function: Submit file metadata (same as before)
submit_file_metadata() {
    local json_file=$1
    local access_token=$2
    local insert_file_url=$3
    local context_source=$4
    local labsysid=$5
    
    echo "[DEBUG] Submitting file metadata: $json_file"
    
    local api_url="${insert_file_url}/${context_source}/${labsysid}"
    echo "DEBUG: Using URL: $api_url"
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST \
        -H "Authorization: $access_token" \
        -H "Content-Type: application/json" \
        "$api_url" \
        --data @"$json_file")

    local http_code=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    local body=$(echo $response | sed -e 's/HTTPSTATUS:.*//')

    echo "HTTP Status: $http_code"
    echo "Response: $body"

    if [[ $http_code -ne 200 && $http_code -ne 201 ]]; then
        echo "ERROR: Failed to insert file metadata (HTTP $http_code)"
        echo "Response: $body"
        return 1
    fi
    
    echo "Successfully submitted file metadata"
}

# Function: Submit metrics data using your existing qcloud_terms
submit_metrics_data() {
    local access_token=$1
    local insert_data_url=$2
    local config_file=$3
    shift 3
    local json_files=("$@")
    
    # Extract QC codes from your existing qcloud_terms
    local qc_codes=(
        $(extract_qcloud_term "$config_file" "tic")
        $(extract_qcloud_term "$config_file" "mit_ms1")
        $(extract_qcloud_term "$config_file" "mit_ms2")
        $(extract_qcloud_term "$config_file" "ms2_scan_count")
        $(extract_qcloud_term "$config_file" "num_prot_ungrouped")
        $(extract_qcloud_term "$config_file" "num_pept_ungrouped")
        $(extract_qcloud_term "$config_file" "num_psm")
        $(extract_qcloud_term "$config_file" "area")
        $(extract_qcloud_term "$config_file" "rt")
        $(extract_qcloud_term "$config_file" "dppm")
        $(extract_qcloud_term "$config_file" "fwhm")
    )
    
    echo "[DEBUG] QC codes to submit: ${qc_codes[*]}"
    
    # Submit each QC parameter
    for qc_code in "${qc_codes[@]}"; do
        # Convert QC:1001844 to QC_1001844 for filename matching
        local param_code=$(echo "$qc_code" | sed 's/:/_/g')
        
        # Find corresponding JSON file
        local json_file=""
        for file in "${json_files[@]}"; do
            if [[ "$file" == *"${param_code}.json" ]]; then
                json_file="$file"
                break
            fi
        done
        
        if [[ -n "$json_file" && -f "$json_file" ]]; then
            echo "Posting $json_file for parameter $qc_code"
            
            # Show JSON content for debugging
            echo "DEBUG: Content of $json_file:"
            head -5 "$json_file"
            
            response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST \
                -H "Authorization: $access_token" \
                -H "Content-Type: application/json" \
                "$insert_data_url" \
                --data @"$json_file")

            local http_code=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
            local body=$(echo $response | sed -e 's/HTTPSTATUS:.*//')

            echo "HTTP Status: $http_code"
            echo "Response: $body"

            if [[ $http_code -ne 200 && $http_code -ne 201 ]]; then
                echo "WARNING: Failed to post $json_file (HTTP $http_code)"
                echo "Response: $body"
            else
                echo "Successfully posted $json_file"
            fi
        else
            echo "WARNING: JSON file for parameter $qc_code not found. Skipping."
        fi
    done
}

# Helper function: Extract QCloud term values from your existing config
extract_qcloud_term() {
    local config_file=$1
    local term_key=$2
    
    grep -A 10 "qcloud_terms.*=" "$config_file" | grep -w "$term_key" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r'
}

# Helper function: Extract context values from your existing config
extract_context_value() {
    local config_file=$1
    local context_key=$2
    
    grep -A 10 "qcloud_contexts.*=" "$config_file" | grep -w "$context_key" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r'
}

# Function: Count rows in TSV files (excluding header)
# Inputs: 
#   $1 - TSV file path
# Output:
#   Prints the count of data rows (excluding header) to stdout
count_tsv_rows(){
  local tsv_file=$1
  
  echo "[DEBUG] Counting rows in: $tsv_file" >&2  # ✅ Send to stderr
  
  if [[ ! -f "$tsv_file" ]]; then
    echo "[WARNING] TSV file not found: $tsv_file" >&2  # ✅ Send to stderr
    echo "0"
    return 1
  fi
  
  # Count lines excluding header (subtract 1 for header row)
  local total_lines=$(wc -l < "$tsv_file")
  local data_rows=$((total_lines - 1))
  
  echo "[DEBUG] Total lines: $total_lines, Data rows: $data_rows" >&2  # ✅ Send to stderr
  
  # Ensure we don't return negative numbers
  if [[ $data_rows -lt 0 ]]; then
    echo "0"
  else
    echo "$data_rows"  # ✅ Only the number goes to stdout
  fi
}

# Function: Extract FragPipe metrics (protein, peptide, PSM counts) and create QCloud JSONs
# Inputs:
#   $1 - protein.tsv file
#   $2 - peptide.tsv file  
#   $3 - psm.tsv file
#   $4 - config file path
#   $5 - sample_id (passed from Nextflow)
# Output:
#   Creates QCloud JSON files and returns values
extract_fragpipe_metrics(){
  local protein_tsv=$1
  local peptide_tsv=$2
  local psm_tsv=$3
  local config_file=$4
  local sample_id=$5

  echo "[DEBUG] --- extract_fragpipe_metrics ---"
  echo "[DEBUG] Protein TSV: $protein_tsv"
  echo "[DEBUG] Peptide TSV: $peptide_tsv"
  echo "[DEBUG] PSM TSV: $psm_tsv"
  echo "[DEBUG] Config: $config_file"
  echo "[DEBUG] Sample ID: $sample_id"

  # Extract sample information
  local checksum=$(extract_checksum_from_filename "$sample_id")
  local uuid=$(extract_uuid_from_filename "$sample_id")

  echo "[DEBUG] Sample info - Checksum: $checksum, UUID: $uuid"

  # Parse QC parameter IDs from config
  local param_id_num_prot=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep "num_prot_ungrouped" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local param_id_num_pept=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep "num_pept_ungrouped" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local param_id_num_psm=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep "num_psm" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')

  # Parse QC context IDs from config
  local context_id_num_prot=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep "num_prot_ungrouped" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local context_id_num_pept=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep "num_pept_ungrouped" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
  local context_id_num_psm=$(grep -A 10 "qcloud_contexts.*=" "$config_file" | grep "num_psm" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')

  echo "[DEBUG] QC param IDs - Proteins: '$param_id_num_prot', Peptides: '$param_id_num_pept', PSMs: '$param_id_num_psm'"
  echo "[DEBUG] QC context IDs - Proteins: '$context_id_num_prot', Peptides: '$context_id_num_pept', PSMs: '$context_id_num_psm'"

  # Count rows in each TSV file
  echo "[DEBUG] Counting protein rows..."
  local num_proteins
  num_proteins=$(count_tsv_rows "$protein_tsv")
  : "${num_proteins:=0}"
  echo "[DEBUG] Number of proteins (final): $num_proteins"

  echo "[DEBUG] Counting peptide rows..."
  local num_peptides
  num_peptides=$(count_tsv_rows "$peptide_tsv")
  : "${num_peptides:=0}"
  echo "[DEBUG] Number of peptides (final): $num_peptides"

  echo "[DEBUG] Counting PSM rows..."
  local num_psms
  num_psms=$(count_tsv_rows "$psm_tsv")
  : "${num_psms:=0}"
  echo "[DEBUG] Number of PSMs (final): $num_psms"

  # Create QCloud JSON files
  echo "[DEBUG] Creating QCloud JSON files for FragPipe metrics..."
  create_qcloud_json_with_header "$checksum" "$param_id_num_prot" "$context_id_num_prot" "$num_proteins" "$uuid" "$sample_id"
  create_qcloud_json_with_header "$checksum" "$param_id_num_pept" "$context_id_num_pept" "$num_peptides" "$uuid" "$sample_id"
  create_qcloud_json_with_header "$checksum" "$param_id_num_psm" "$context_id_num_psm" "$num_psms" "$uuid" "$sample_id"

  echo "[DEBUG] FragPipe QCloud JSON files created successfully"
  echo "[DEBUG] --- extract_fragpipe_metrics DONE ---"
  
  # Return the values
  echo "$num_proteins,$num_peptides,$num_psms,$checksum,$uuid"
}
