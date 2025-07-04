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
# Inputs:
#   $1 - JSON file path (msnbasexic output)
#   $2 - peptide short name (e.g., "LVN")
#   $3 - sample ID
#   $4 - checksum
#   $5 - QC CV term (e.g., "QC:1001844")
#   $6 - config file path
# Output:
#   Creates/updates QCloud JSON file with proper structure
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
    local output_file="${checksum}_QC_${qcode}.json"
    
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
    local area_qccv=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep -w "area" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
    local rt_qccv=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep -w "rt" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
    local dppm_qccv=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep -w "dppm" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')
    local fwhm_qccv=$(grep -A 10 "qcloud_terms.*=" "$config_file" | grep -w "fwhm" | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | tr -d '\n\r')

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
