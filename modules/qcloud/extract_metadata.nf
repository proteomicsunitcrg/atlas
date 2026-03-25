process EXTRACT_METADATA {
    label 'clitools'
    tag { "${mzml_file}" }
    
    input:
    tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
    
    output:
    path "metadata.json", emit: metadata_json
    tuple val(basename_mzml), path("*_QC_*.json"), emit: qc_jsons, optional: true
    
    script:
    """
    # Copy bash scripts to working directory
    cp ${projectDir}/bin/parsing_qcloud.sh .
    
    # Make scripts executable
    chmod +x parsing_qcloud.sh
    
    # Source the bash functions
    source parsing_qcloud.sh
    
    # Use config file from params
    config_file="${params.home_dir}/mygit/atlas-config/atlas-main/conf/tools/qcloud.config"
    
    echo "Extracting general metrics using config-driven approach..."
    echo "Using config file: \$config_file"
    
    # Clean the filename first to remove .mzML.SP_Bovine extension
    original_filename="${mzml_file}"
    
    # Remove .mzML.database AND .raw to get the proper sample ID
    clean_sample_id=\$(echo "${basename_mzml}" | sed 's/\\.mzML.*\$//' | sed 's/\\.raw\$//')
    
    echo "Original filename: \$original_filename"
    echo "Cleaned sample ID: \$clean_sample_id"
    echo "File size: \$(du -hs "\$original_filename" | cut -f1)"
    
    # Extract UUID and checksum from the CLEANED filename
    uuid=\$(extract_uuid_from_filename "\$clean_sample_id")
    checksum_extracted=\$(extract_checksum_from_filename "\$clean_sample_id")
    
    # Extract context code using reverse parsing (like DIA-NN process)
    reversed_sample_id=\$(echo "\$clean_sample_id" | rev)
    context_code_reversed=\$(echo "\$reversed_sample_id" | cut -d'_' -f2)
    context_code=\$(echo "\$context_code_reversed" | rev)
    
    echo "Extracted UUID: \$uuid"
    echo "Extracted checksum: \$checksum_extracted"
    echo "Extracted context code: \$context_code"
    
    # Read QC parameters from config using the same functions as extract_diann_metrics
    # Use direct extraction like the working extract_diann_metrics module
    tic_qccv=\$(extract_qcloud_term "\$config_file" "tic")
    mit_ms1_qccv=\$(extract_qcloud_term "\$config_file" "mit_ms1")
    mit_ms2_qccv=\$(extract_qcloud_term "\$config_file" "mit_ms2")
    ms2_count_qccv=\$(extract_qcloud_term "\$config_file" "ms2_scan_count")
    
    # Read context sources from config file using the same functions as extract_diann_metrics
    tic_context=\$(extract_context_value "\$config_file" "tic")
    mit_ms1_context=\$(extract_context_value "\$config_file" "mit_ms1")
    mit_ms2_context=\$(extract_context_value "\$config_file" "mit_ms2")
    ms2_count_context=\$(extract_context_value "\$config_file" "ms2_scan_count")
    
    echo "QC parameters from config:"
    echo "  TIC: \$tic_qccv (context: \$tic_context)"
    echo "  MIT MS1: \$mit_ms1_qccv (context: \$mit_ms1_context)"
    echo "  MIT MS2: \$mit_ms2_qccv (context: \$mit_ms2_context)"
    echo "  MS2 count: \$ms2_count_qccv (context: \$ms2_count_context)"
    
    # Extract TIC using grep and scale down by 10^10 to match old pipeline format
    echo "Extracting TIC from large mzML file..."
    tic=\$(grep 'MS:1000285' "\$original_filename" | \\
          grep -o 'value="[^"]*"' | \\
          sed 's/value="//g; s/"//g' | \\
          awk '{sum+=\$1} END{printf "%.2f", sum/10000000000}')
    echo "TIC: \$tic"
    
    # Detect instrument vendor for MIT interpretation
    echo ""
    echo "Detecting instrument type..."
    if grep -q "Bruker" "\$original_filename"; then
        instrument_vendor="Bruker"
        echo "WARNING: Bruker instrument detected"
        echo "    Note: Ion injection time (MS:1000927) is typically not available in Bruker mzML files"
        echo "    This is expected behavior - Bruker timsTOF uses TIMS (Trapped Ion Mobility)"
        echo "    with a different ion accumulation mechanism than Thermo instruments"
        echo "    MIT MS1/MS2 will be set to 0 (not applicable)"
    elif grep -q "Thermo" "\$original_filename"; then
        instrument_vendor="Thermo"
        echo "INFO: Thermo instrument detected - Ion injection time should be available"
    else
        instrument_vendor="Unknown"
        echo "WARNING: Unknown instrument vendor - MIT extraction may fail"
    fi
    echo ""
    
    # Extract MIT MS1 (Ion Injection Time)
    echo "Extracting MIT MS1..."
    # Try MS:1000927 (ion injection time) first
    mit_ms1_temp=\$(median_from_mzml 1 MS:1000927 "\$original_filename")   
    
    # If not found or zero, try MS:1000016 (scan start time) as fallback
    if [[ -z "\$mit_ms1_temp" || "\$mit_ms1_temp" == "0" ]]; then
        echo "  MS:1000927 not found for MS1, trying MS:1000016 (scan start time)..."
        mit_ms1_temp=\$(median_from_mzml 1 MS:1000016 "\$original_filename")   
    fi
    
    # Convert from seconds to milliseconds if value < 1 (likely in seconds)
    if [[ -n "\$mit_ms1_temp" && "\$mit_ms1_temp" != "" ]]; then
        mit_ms1=\$(awk -v val="\$mit_ms1_temp" 'BEGIN {if(val < 1 && val > 0) print val*1000; else print val}')
        echo "  INFO: MIT MS1: \$mit_ms1 ms"
    else
        mit_ms1="0"
        if [ "\$instrument_vendor" == "Bruker" ]; then
            echo "  INFO: MIT MS1: 0 (not applicable for Bruker TIMS instruments)"
        else
            echo "  WARNING: MIT MS1: Not found in mzML (value=0)"
        fi
    fi
    
    # Extract MIT MS2 (Ion Injection Time)
    echo "Extracting MIT MS2..."
    mit_ms2_temp=\$(median_from_mzml 2 MS:1000927 "\$original_filename")   
    
    if [[ -z "\$mit_ms2_temp" || "\$mit_ms2_temp" == "0" ]]; then
        echo "  MS:1000927 not found for MS2, trying MS:1000016..."
        mit_ms2_temp=\$(median_from_mzml 2 MS:1000016 "\$original_filename")   
    fi
    
    if [[ -n "\$mit_ms2_temp" && "\$mit_ms2_temp" != "" ]]; then
        mit_ms2=\$(awk -v val="\$mit_ms2_temp" 'BEGIN {if(val < 1 && val > 0) print val*1000; else print val}')
        echo "  INFO: MIT MS2: \$mit_ms2 ms"
    else
        mit_ms2="0"
        if [ "\$instrument_vendor" == "Bruker" ]; then
            echo "  INFO: MIT MS2: 0 (not applicable for Bruker TIMS instruments)"
        else
            echo "  WARNING: MIT MS2: Not found in mzML (value=0)"
        fi
    fi
    
    # Extract MS2 scan count using grep
    echo "Extracting MS2 scan count..."
    ms2_scan_count=\$(grep -c 'MS:1000511.*value="2"' "\$original_filename" || echo "0")
    echo "MS2 scan count: \$ms2_scan_count"
    
    # Set defaults if extraction failed
    tic=\${tic:-0}
    mit_ms1=\${mit_ms1:-0}
    mit_ms2=\${mit_ms2:-0}
    ms2_scan_count=\${ms2_scan_count:-0}
    
    echo "Final values: TIC=\$tic, MIT_MS1=\$mit_ms1, MIT_MS2=\$mit_ms2, MS2_scans=\$ms2_scan_count"
    
    # Create JSON file names using context codes (same pattern as extract_diann_metrics)
    tic_qcode=\$(echo "\$tic_context" | cut -d':' -f2)
    mit_ms1_qcode=\$(echo "\$mit_ms1_context" | cut -d':' -f2)
    mit_ms2_qcode=\$(echo "\$mit_ms2_context" | cut -d':' -f2)
    ms2_count_qcode=\$(echo "\$ms2_count_context" | cut -d':' -f2)
    
    tic_json="\${uuid}_\${context_code}_\${checksum_extracted}_QC_\${tic_qcode}.json"
    mit_ms1_json="\${uuid}_\${context_code}_\${checksum_extracted}_QC_\${mit_ms1_qcode}.json"
    mit_ms2_json="\${uuid}_\${context_code}_\${checksum_extracted}_QC_\${mit_ms2_qcode}.json"
    ms2_count_json="\${uuid}_\${context_code}_\${checksum_extracted}_QC_\${ms2_count_qcode}.json"
    
    echo "JSON files to create:"
    echo "  TIC: \$tic_json (using context code: \$tic_qcode)"
    echo "  MIT MS1: \$mit_ms1_json (using context code: \$mit_ms1_qcode)"
    echo "  MIT MS2: \$mit_ms2_json (using context code: \$mit_ms2_qcode)"
    echo "  MS2 count: \$ms2_count_json (using context code: \$ms2_count_qcode)"
    
    # Create TIC JSON
    cat > "\$tic_json" << EOF
{
  "file" : {
    "checksum" : "\$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "\$tic_qccv"
    },
    "values" : [ {
      "value" : "\$tic",
      "contextSource" : "\$tic_context"
    } ]
  } ]
}
EOF

    # Create MIT MS1 and MS2 JSONs ONLY for non-Bruker instruments
    # For Bruker, skip these files as MIT is not applicable (TIMS technology)
    if [ "\$instrument_vendor" != "Bruker" ]; then
        echo "Creating MIT JSON files for \$instrument_vendor instrument..."
        
        # Create MIT MS1 JSON
        cat > "\$mit_ms1_json" << EOF
{
  "file" : {
    "checksum" : "\$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "\$mit_ms1_qccv"
    },
    "values" : [ {
      "value" : "\$mit_ms1",
      "contextSource" : "\$mit_ms1_context"
    } ]
  } ]
}
EOF

        # Create MIT MS2 JSON
        cat > "\$mit_ms2_json" << EOF
{
  "file" : {
    "checksum" : "\$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "\$mit_ms2_qccv"
    },
    "values" : [ {
      "value" : "\$mit_ms2",
      "contextSource" : "\$mit_ms2_context"
    } ]
  } ]
}
EOF
        
        echo "INFO: MIT JSON files created for \$instrument_vendor"
    else
        echo "WARNING: Skipping MIT JSON creation for Bruker instrument (not applicable)"
        echo "    MIT metrics are not available for Bruker timsTOF TIMS technology"
    fi

    # Create MS2 scan count JSON
    cat > "\$ms2_count_json" << EOF
{
  "file" : {
    "checksum" : "\$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "\$ms2_count_qccv"
    },
    "values" : [ {
      "value" : "\$ms2_scan_count",
      "contextSource" : "\$ms2_count_context"
    } ]
  } ]
}
EOF

    # Get creation date
    # Extract creation date from mzML using memory-efficient grep approach (avoiding xmllint OOM issues)
    echo "Extracting creation date from mzML startTimeStamp using grep..."

    # Method 1: Try to extract startTimeStamp from run element using grep
    # Look for patterns like: <run ... startTimeStamp="2025-09-20T17:24:10.119059Z" ...>
    echo "Searching for startTimeStamp pattern in mzML file..."
    start_timestamp=\$(grep -o 'startTimeStamp="[^"]*"' "\$original_filename" | head -1 | cut -d'"' -f2 2>/dev/null)

    if [[ -n "\$start_timestamp" && "\$start_timestamp" != "" ]]; then
        echo "Found startTimeStamp in mzML: \$start_timestamp"
        
        # Convert from ISO format (2025-09-23T17:24:10.119059Z) to standard format (2025-09-23 17:24:10)
        creation_date=\$(echo "\$start_timestamp" | sed 's/T/ /g; s/Z\$//g; s/\\.[0-9]*\$//g')
        echo "Converted to standard format: \$creation_date"
    else
        echo "Warning: startTimeStamp not found with first grep pattern, trying broader search..."
        
        # Method 1b: Try a broader grep pattern for startTimeStamp
        start_timestamp=\$(grep 'startTimeStamp=' "\$original_filename" | head -1 | grep -o 'startTimeStamp="[^"]*"' | cut -d'"' -f2 2>/dev/null)
        
        if [[ -n "\$start_timestamp" && "\$start_timestamp" != "" ]]; then
            echo "Found startTimeStamp with broader search: \$start_timestamp"
            creation_date=\$(echo "\$start_timestamp" | sed 's/T/ /g; s/Z\$//g; s/\\.[0-9]*\$//g')
            echo "Converted to standard format: \$creation_date"
        else
            echo "Warning: startTimeStamp still not found, trying alternative methods..."
            
            # Method 2: Try to extract from creationDate attribute if present
            creation_timestamp=\$(grep -o 'creationDate="[^"]*"' "\$original_filename" | head -1 | cut -d'"' -f2 2>/dev/null)
            
            if [[ -n "\$creation_timestamp" && "\$creation_timestamp" != "" ]]; then
                echo "Found creationDate attribute: \$creation_timestamp"
                creation_date=\$(echo "\$creation_timestamp" | sed 's/T/ /g; s/Z\$//g; s/\\.[0-9]*\$//g')
                echo "Converted to standard format: \$creation_date"
            else
                echo "Warning: No timestamp found in mzML metadata, trying filename extraction..."
                
                # Method 3: Try to extract date from filename as fallback
                filename=\$(basename "\$original_filename")
                echo "Analyzing filename for date pattern: \$filename"
                
                # Use grep to extract date pattern (more reliable than bash regex)
                date_str=\$(echo "\$filename" | grep -o '20[0-9][0-9][0-9][0-9][0-9][0-9]' | head -1)
                
                if [[ -n "\$date_str" && "\$date_str" != "" ]]; then
                    echo "Found date pattern in filename: \$date_str"
                    creation_date="\${date_str:0:4}-\${date_str:4:2}-\${date_str:6:2} 00:00:00"
                    echo "Extracted date from filename: \$creation_date"
                else
                    echo "Warning: Could not extract date from mzML or filename, using file modification time"
                    creation_date=\$(stat -c %y "\$original_filename" | cut -d'.' -f1)
                    echo "Using file modification time: \$creation_date"
                fi
            fi
        fi
    fi
    
    # Create metadata JSON
    cat > metadata.json << EOF
{
  "checksum": "\$checksum_extracted",
  "uuid": "\$uuid",
  "context_code": "\$context_code",
  "sample_id": "\$clean_sample_id",
  "creation_date": "\$creation_date",
  "mzml_file": "\$original_filename",
  "file_size": "\$(du -hs "\$original_filename" | cut -f1)",
  "tic": "\$tic",
  "mit_ms1": "\$mit_ms1",
  "mit_ms2": "\$mit_ms2",
  "ms2_scan_count": "\$ms2_scan_count"
}
EOF

    echo "Metadata extraction completed for \$original_filename"
    echo "Generated files:"
    ls -la *_QC_*.json metadata.json
    
    echo "File count check:"
    qc_file_count=\$(ls -1 *_QC_*.json 2>/dev/null | wc -l)
    
    # Expected file count depends on instrument type
    if [ "\$instrument_vendor" == "Bruker" ]; then
        expected_count=2
        echo "Number of QC JSON files created: \$qc_file_count (expected 2 for Bruker: TIC + MS2 count)"
    else
        expected_count=4
        echo "Number of QC JSON files created: \$qc_file_count (expected 4 for \$instrument_vendor: TIC + MIT MS1 + MIT MS2 + MS2 count)"
    fi
    
    # Verify expected files exist
    echo "File existence check:"
    
    # TIC and MS2 count are always expected
    for expected_file in "\$tic_json" "\$ms2_count_json"; do
        if [[ -f "\$expected_file" ]]; then
            echo "  [OK] \$expected_file exists"
        else
            echo "  [MISSING] \$expected_file"
        fi
    done
    
    # MIT files only expected for non-Bruker instruments
    if [ "\$instrument_vendor" != "Bruker" ]; then
        for expected_file in "\$mit_ms1_json" "\$mit_ms2_json"; do
            if [[ -f "\$expected_file" ]]; then
                echo "  [OK] \$expected_file exists"
            else
                echo "  [MISSING] \$expected_file"
            fi
        done
    else
        echo "  [SKIPPED] \$mit_ms1_json (Bruker instrument)"
        echo "  [SKIPPED] \$mit_ms2_json (Bruker instrument)"
    fi
    """
}
