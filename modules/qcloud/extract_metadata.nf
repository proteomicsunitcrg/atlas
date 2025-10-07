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
    config_file="${params.home_dir}/mygit/atlas-config/atlas-test/conf/tools/qcloud.config"
    
    echo "Extracting general metrics using config-driven approach..."
    echo "Using config file: \$config_file"
    
    # Clean the filename first to remove .mzML.SP_Bovine extension
    original_filename="${mzml_file}"
    
    # Remove .mzML.SP_Bovine to get the proper sample ID
    clean_sample_id=\$(echo "${basename_mzml}" | sed 's/\\.mzML.*\$//')
    
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
    
    # Extract TIC using grep
    echo "Extracting TIC from large mzML file..."
    tic=\$(grep 'MS:1000285' "\$original_filename" | \\
          grep -o 'value="[^"]*"' | \\
          sed 's/value="//g; s/"//g' | \\
          awk '{sum+=\$1} END{printf "%.0f", sum}')
    echo "TIC: \$tic"
    
    # Extract MIT MS1
    echo "Extracting MIT MS1..."
    mit_ms1=\$(grep -A 20 'MS:1000511.*value="1"' "\$original_filename" | \\
              grep 'MS:1000927' | \\
              grep -o 'value="[0-9.]*"' | \\
              sed 's/value="//g; s/"//g' | \\
              awk '{sum+=\$1; count++} END{if(count>0) printf "%.6f", sum/count; else print "0"}')
    echo "MIT MS1: \$mit_ms1"
    
    # Extract MIT MS2
    echo "Extracting MIT MS2..."
    mit_ms2=\$(grep -A 20 'MS:1000511.*value="2"' "\$original_filename" | \\
              grep 'MS:1000927' | \\
              grep -o 'value="[0-9.]*"' | \\
              sed 's/value="//g; s/"//g' | \\
              awk '{sum+=\$1; count++} END{if(count>0) printf "%.6f", sum/count; else print "0"}')
    echo "MIT MS2: \$mit_ms2"
    
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
    echo "Number of QC JSON files created: \$qc_file_count (should be 4)"
    
    # Verify each expected file exists
    echo "File existence check:"
    for expected_file in "\$tic_json" "\$mit_ms1_json" "\$mit_ms2_json" "\$ms2_count_json"; do
        if [[ -f "\$expected_file" ]]; then
            echo "  ✓ \$expected_file exists"
        else
            echo "  ✗ \$expected_file MISSING"
        fi
    done
    """
}
