process EXTRACT_DIANN_METRICS {
    
    input:
    path report_tsv
    path qcloud_tsv  
    val checksum
    path config_file
    
    output:
    tuple val(checksum), path("*_QC_*.json"), emit: diann_jsons
    path "diann_metadata.json", emit: metadata
    
    shell:
    '''
    # Copy the parsing script
    cp !{projectDir}/bin/parsing_qcloud.sh .
    source parsing_qcloud.sh
    
    echo "Extracting DIA-NN metrics for checksum: !{checksum}"

    # Extract sample information
    report_basename=$(basename !{report_tsv} .report.tsv)
    sample_id="$report_basename"
    checksum_extracted=$(extract_checksum_from_filename "$sample_id")
    uuid=$(extract_uuid_from_filename "$sample_id")
    reversed_sample_id=$(echo "$sample_id" | rev)
    context_code_reversed=$(echo "$reversed_sample_id" | cut -d'_' -f2)
    context_code=$(echo "$context_code_reversed" | rev)

    # Read QC parameters
    area_qccv=$(extract_qcloud_term "!{config_file}" "area")
    rt_qccv=$(extract_qcloud_term "!{config_file}" "rt") 
    dppm_qccv=$(extract_qcloud_term "!{config_file}" "dppm")

    # Create JSON file names
    area_qcode=$(echo "$area_qccv" | cut -d':' -f2)
    rt_qcode=$(echo "$rt_qccv" | cut -d':' -f2)
    area_json="${uuid}_${context_code}_${checksum_extracted}_QC_${area_qcode}.json"
    rt_json="${uuid}_${context_code}_${checksum_extracted}_QC_${rt_qcode}.json"

    # Initialize JSON files with proper structure
    cat > "$area_json" << EOF
{
  "file" : {
    "checksum" : "$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "$area_qccv"
    },
    "values" : []
  } ]
}
EOF

    cat > "$rt_json" << EOF
{
  "file" : {
    "checksum" : "$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "$rt_qccv"
    },
    "values" : []
  } ]
}
EOF

    echo "Processing peptides with modification-aware matching..."

    # Process each peptide and collect all values
    tail -n +2 !{qcloud_tsv} | while IFS=$'\\t' read -r short long extra; do
        echo "Processing peptide: $short -> $long"
        
        long_clean=$(echo "$long" | awk '{print $1}')
        
        # Try exact match first, then modified match
        result=$(awk -F'\\t' -v peptide="$long_clean" -v pcol="14" -v acol="27" -v rcol="29" '
            $pcol == peptide { 
                area = ($acol == "" || $acol == "0") ? 0 : $acol
                rt = ($rcol == "" || $rcol == "0") ? 0 : $rcol
                print area "," rt ",EXACT"
                exit
            }
            {
                # Try modified match
                clean_seq = $pcol
                gsub(/\\([^)]*\\)/, "", clean_seq)
                if (clean_seq == peptide) {
                    area = ($acol == "" || $acol == "0") ? 0 : $acol
                    rt = ($rcol == "" || $rcol == "0") ? 0 : $rcol
                    print area "," rt ",MODIFIED:" $pcol
                    exit
                }
            }' !{report_tsv})
        
        if [ -n "$result" ]; then
            area=$(echo $result | cut -d',' -f1)
            rt_obs=$(echo $result | cut -d',' -f2)
            match_type=$(echo $result | cut -d',' -f3-)
            echo "Found: $short -> area=$area, rt=$rt_obs ($match_type)"
        else
            echo "Peptide $long_clean not found in report"
            area=0
            rt_obs=0
        fi
        
        # Add values to JSON files using jq
        jq --arg contextSource "$long_clean" --arg value "$area" \\
           '.data[0].values += [{"contextSource": $contextSource, "value": $value}]' \\
           "$area_json" > tmp_area.json && mv tmp_area.json "$area_json"
           
        jq --arg contextSource "$long_clean" --arg value "$rt_obs" \\
           '.data[0].values += [{"contextSource": $contextSource, "value": $value}]' \\
           "$rt_json" > tmp_rt.json && mv tmp_rt.json "$rt_json"
        
    done

    echo '{"diann_metrics_extracted": true, "checksum": "!{checksum}"}' > diann_metadata.json
    
    echo "Generated DIA-NN JSON files:"
    ls -la *_QC_*.json
    
    echo "Final JSON content:"
    cat *_QC_*.json
    '''
}
