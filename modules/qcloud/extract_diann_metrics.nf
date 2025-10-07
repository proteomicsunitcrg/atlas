process EXTRACT_DIANN_METRICS {
    
    input:
    path report_tsv
    path report_stats_tsv
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

    echo "Extracted components:"
    echo "  UUID: $uuid"
    echo "  Context code: $context_code" 
    echo "  Checksum: $checksum_extracted"

    # Read QC parameters from config file (existing)
    area_qccv=$(extract_qcloud_term "!{config_file}" "area")
    rt_qccv=$(extract_qcloud_term "!{config_file}" "rt") 
    dppm_qccv=$(extract_qcloud_term "!{config_file}" "dppm")
    
    # Read new QC parameters for stats metrics from config file
    median_mass_acc_ms1_qccv=$(extract_qcloud_term "!{config_file}" "median_mass_acc_ms1")
    median_mass_acc_ms2_qccv=$(extract_qcloud_term "!{config_file}" "median_mass_acc_ms2")
    points_per_peak_qccv=$(extract_qcloud_term "!{config_file}" "points_per_peak")
    median_fwhm_qccv=$(extract_qcloud_term "!{config_file}" "median_fwhm")
    
    # Read context sources from config file
    median_mass_acc_ms1_context=$(extract_context_value "!{config_file}" "median_mass_acc_ms1")
    median_mass_acc_ms2_context=$(extract_context_value "!{config_file}" "median_mass_acc_ms2")
    points_per_peak_context=$(extract_context_value "!{config_file}" "points_per_peak")
    median_fwhm_context=$(extract_context_value "!{config_file}" "median_fwhm")
    
    # Set QC parameters for new metrics (Proteins.identified and Precursors.identified)
    proteins_identified_qccv="QC:9000001"
    precursors_identified_qccv="QC:9000001"
    proteins_identified_context="QC:0000032"
    precursors_identified_context="QC:0000031"
    
    # Extract metrics from report.stats.tsv
    if [ -f "!{report_stats_tsv}" ]; then
        echo "Processing report.stats.tsv file: !{report_stats_tsv}"
        
        # Extract FWHM.scans (Points per peak = FWHM.scans * 3)
        # First, let's debug what columns are available
        echo "DEBUG: Available columns in report.stats.tsv:"
        head -1 !{report_stats_tsv} | tr '\\t' '\\n' | nl
        
        # Try different possible column names for FWHM scans
        fwhm_scans=$(awk -F'\\t' 'NR==1 {for(i=1;i<=NF;i++) if($i=="FWHM.scans" || $i=="FWHM.Scans") col=i} NR==2 {if(col) print $col; else print ""}' !{report_stats_tsv})
        
        echo "DEBUG: Extracted FWHM.scans value: '$fwhm_scans'"
        
        # Use awk for calculation instead of bc, with error handling
        if [ -n "$fwhm_scans" ] && [ "$fwhm_scans" != "" ] && [ "$fwhm_scans" != "0" ]; then
            points_per_peak=$(awk -v val="$fwhm_scans" 'BEGIN {printf "%.3f", val * 3}')
            echo "DEBUG: Calculated points_per_peak: $fwhm_scans * 3 = $points_per_peak"
        else
            points_per_peak=0
            echo "DEBUG: FWHM.scans not found or empty, setting points_per_peak to 0"
        fi
        
        # Extract FWHM.RT (Median FWHM = FWHM.RT * 60 sec)
        fwhm_rt=$(awk -F'\\t' 'NR==1 {for(i=1;i<=NF;i++) if($i=="FWHM.RT") col=i} NR==2 {if(col) print $col; else print ""}' !{report_stats_tsv})
        
        echo "DEBUG: Extracted FWHM.RT value: '$fwhm_rt'"
        
        # Use awk for calculation instead of bc, with error handling
        if [ -n "$fwhm_rt" ] && [ "$fwhm_rt" != "" ] && [ "$fwhm_rt" != "0" ]; then
            median_fwhm=$(awk -v val="$fwhm_rt" 'BEGIN {printf "%.3f", val * 60}')
            echo "DEBUG: Calculated median_fwhm: $fwhm_rt * 60 = $median_fwhm"
        else
            median_fwhm=0
            echo "DEBUG: FWHM.RT not found or empty, setting median_fwhm to 0"
        fi
        
        # Extract Median.Mass.Acc.MS1
        median_mass_acc_ms1=$(awk -F'\\t' 'NR==1 {for(i=1;i<=NF;i++) if($i=="Median.Mass.Acc.MS1") col=i} NR==2 {if(col) print $col; else print ""}' !{report_stats_tsv})
        echo "DEBUG: Extracted Median.Mass.Acc.MS1 value: '$median_mass_acc_ms1'"
        if [ -z "$median_mass_acc_ms1" ] || [ "$median_mass_acc_ms1" = "" ]; then
            median_mass_acc_ms1=0
            echo "DEBUG: Median.Mass.Acc.MS1 not found or empty, setting to 0"
        fi
        
        # Extract Median.Mass.Acc.MS2
        median_mass_acc_ms2=$(awk -F'\\t' 'NR==1 {for(i=1;i<=NF;i++) if($i=="Median.Mass.Acc.MS2") col=i} NR==2 {if(col) print $col; else print ""}' !{report_stats_tsv})
        echo "DEBUG: Extracted Median.Mass.Acc.MS2 value: '$median_mass_acc_ms2'"
        if [ -z "$median_mass_acc_ms2" ] || [ "$median_mass_acc_ms2" = "" ]; then
            median_mass_acc_ms2=0
            echo "DEBUG: Median.Mass.Acc.MS2 not found or empty, setting to 0"
        fi
        
        # Extract Proteins.Identified (note: uppercase I)
        proteins_identified=$(awk -F'\\t' 'NR==1 {for(i=1;i<=NF;i++) if($i=="Proteins.Identified") col=i} NR==2 {if(col) print $col; else print ""}' !{report_stats_tsv})
        echo "DEBUG: Extracted Proteins.Identified value: '$proteins_identified'"
        if [ -z "$proteins_identified" ] || [ "$proteins_identified" = "" ]; then
            proteins_identified=0
            echo "DEBUG: Proteins.Identified not found or empty, setting to 0"
        fi
        
        # Extract Precursors.Identified (note: uppercase I)
        precursors_identified=$(awk -F'\\t' 'NR==1 {for(i=1;i<=NF;i++) if($i=="Precursors.Identified") col=i} NR==2 {if(col) print $col; else print ""}' !{report_stats_tsv})
        echo "DEBUG: Extracted Precursors.Identified value: '$precursors_identified'"
        if [ -z "$precursors_identified" ] || [ "$precursors_identified" = "" ]; then
            precursors_identified=0
            echo "DEBUG: Precursors.Identified not found or empty, setting to 0"
        fi
        
        echo "Extracted stats metrics:"
        echo "  FWHM.scans: $fwhm_scans -> Points per peak: $points_per_peak"
        echo "  FWHM.RT: $fwhm_rt -> Median FWHM: $median_fwhm"
        echo "  Median.Mass.Acc.MS1: $median_mass_acc_ms1"
        echo "  Median.Mass.Acc.MS2: $median_mass_acc_ms2"
        echo "  Proteins.Identified: $proteins_identified"
        echo "  Precursors.Identified: $precursors_identified"
    else
        echo "Warning: report.stats.tsv file not found"
        points_per_peak=0
        median_fwhm=0
        median_mass_acc_ms1=0
        median_mass_acc_ms2=0
        proteins_identified=0
        precursors_identified=0
    fi

    echo "QC parameters from config:"
    echo "  Area: $area_qccv"
    echo "  RT: $rt_qccv" 
    echo "  dppm: $dppm_qccv"
    echo "  Points per peak: $points_per_peak_qccv (context: $points_per_peak_context)"
    echo "  Median FWHM: $median_fwhm_qccv (context: $median_fwhm_context)"
    echo "  Median mass accuracy MS1: $median_mass_acc_ms1_qccv (context: $median_mass_acc_ms1_context)"
    echo "  Median mass accuracy MS2: $median_mass_acc_ms2_qccv (context: $median_mass_acc_ms2_context)"
    echo "  Proteins identified: $proteins_identified_qccv (context: $proteins_identified_context)"
    echo "  Precursors identified: $precursors_identified_qccv (context: $precursors_identified_context)"

    # Create JSON file names using config values
    # For existing metrics, use qCCV codes (qcloud_terms)
    area_qcode=$(echo "$area_qccv" | cut -d':' -f2)
    rt_qcode=$(echo "$rt_qccv" | cut -d':' -f2)
    
    # For new stats metrics, use context codes (qcloud_contexts) for filenames
    points_per_peak_qcode=$(echo "$points_per_peak_context" | cut -d':' -f2)
    median_fwhm_qcode=$(echo "$median_fwhm_context" | cut -d':' -f2)
    median_mass_acc_ms1_qcode=$(echo "$median_mass_acc_ms1_context" | cut -d':' -f2)
    median_mass_acc_ms2_qcode=$(echo "$median_mass_acc_ms2_context" | cut -d':' -f2)
    
    area_json="${uuid}_${context_code}_${checksum_extracted}_QC_${area_qcode}.json"
    rt_json="${uuid}_${context_code}_${checksum_extracted}_QC_${rt_qcode}.json"
    
    # New JSON files for stats metrics (using context codes for filenames)
    points_per_peak_json="${uuid}_${context_code}_${checksum_extracted}_QC_${points_per_peak_qcode}.json"
    median_fwhm_json="${uuid}_${context_code}_${checksum_extracted}_QC_${median_fwhm_qcode}.json"
    median_mass_acc_ms1_json="${uuid}_${context_code}_${checksum_extracted}_QC_${median_mass_acc_ms1_qcode}.json"
    median_mass_acc_ms2_json="${uuid}_${context_code}_${checksum_extracted}_QC_${median_mass_acc_ms2_qcode}.json"
    
    # JSON files for new metrics (Proteins.identified and Precursors.identified)
    proteins_identified_qcode=$(echo "$proteins_identified_context" | cut -d':' -f2)
    precursors_identified_qcode=$(echo "$precursors_identified_context" | cut -d':' -f2)
    proteins_identified_json="${uuid}_${context_code}_${checksum_extracted}_QC_${proteins_identified_qcode}.json"
    precursors_identified_json="${uuid}_${context_code}_${checksum_extracted}_QC_${precursors_identified_qcode}.json"

    echo "JSON files to create:"
    echo "  Area: $area_json (using qCCV code: $area_qcode)"
    echo "  RT: $rt_json (using qCCV code: $rt_qcode) - VALUES CONVERTED TO SECONDS"
    echo "  Points per peak: $points_per_peak_json (using context code: $points_per_peak_qcode)"
    echo "  Median FWHM: $median_fwhm_json (using context code: $median_fwhm_qcode)"
    echo "  Median mass accuracy MS1: $median_mass_acc_ms1_json (using context code: $median_mass_acc_ms1_qcode)"
    echo "  Median mass accuracy MS2: $median_mass_acc_ms2_json (using context code: $median_mass_acc_ms2_qcode)"
    echo "  Proteins identified: $proteins_identified_json (using context code: $proteins_identified_qcode)"
    echo "  Precursors identified: $precursors_identified_json (using context code: $precursors_identified_qcode)"
    echo "  Note: dppm JSON (QC:1000014) excluded as per requirements"
    echo "  Note: New stats metrics use context codes (qcloud_contexts) for filenames"

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

    # Initialize new JSON files for stats metrics using config values
    cat > "$points_per_peak_json" << EOF
{
  "file" : {
    "checksum" : "$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "$points_per_peak_qccv"
    },
    "values" : [ {
      "value" : "$points_per_peak",
      "contextSource" : "$points_per_peak_context"
    } ]
  } ]
}
EOF

    cat > "$median_fwhm_json" << EOF
{
  "file" : {
    "checksum" : "$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "$median_fwhm_qccv"
    },
    "values" : [ {
      "value" : "$median_fwhm",
      "contextSource" : "$median_fwhm_context"
    } ]
  } ]
}
EOF

    cat > "$median_mass_acc_ms1_json" << EOF
{
  "file" : {
    "checksum" : "$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "$median_mass_acc_ms1_qccv"
    },
    "values" : [ {
      "value" : "$median_mass_acc_ms1",
      "contextSource" : "$median_mass_acc_ms1_context"
    } ]
  } ]
}
EOF

    cat > "$median_mass_acc_ms2_json" << EOF
{
  "file" : {
    "checksum" : "$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "$median_mass_acc_ms2_qccv"
    },
    "values" : [ {
      "value" : "$median_mass_acc_ms2",
      "contextSource" : "$median_mass_acc_ms2_context"
    } ]
  } ]
}
EOF

    cat > "$proteins_identified_json" << EOF
{
  "file" : {
    "checksum" : "$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "$proteins_identified_qccv"
    },
    "values" : [ {
      "value" : "$proteins_identified",
      "contextSource" : "$proteins_identified_context"
    } ]
  } ]
}
EOF

    cat > "$precursors_identified_json" << EOF
{
  "file" : {
    "checksum" : "$checksum_extracted"
  },
  "data" : [ {
    "parameter" : {
      "qCCV" : "$precursors_identified_qccv"
    },
    "values" : [ {
      "value" : "$precursors_identified",
      "contextSource" : "$precursors_identified_context"
    } ]
  } ]
}
EOF

    echo "Processing peptides with REAL Mass.Evidence extraction for individual dppm values..."

    # Process each peptide and collect all values
    tail -n +2 !{qcloud_tsv} | while IFS=$'\\t' read -r short long extra; do
        echo "Processing peptide: $short -> $long"
        
        # Use automated peptide mapping function to get correct contextSource
        long_clean=$(get_openms_peptide_name "!{config_file}" "$short" "$sample_id")

        echo "DEBUG: Mapped $short -> $long_clean using automated function"
        
        # Extract area, RT, and REAL Mass.Evidence (column 42) for each peptide
        result=$(awk -F'\\t' -v peptide="$long_clean" -v pcol="14" -v acol="27" -v rcol="30" -v mass_ev_col="42" '
            $pcol == peptide { 
                area = ($acol == "" || $acol == "0") ? 0 : $acol
                rt = ($rcol == "" || $rcol == "0") ? 0 : $rcol
                mass_evidence = ($mass_ev_col == "" || $mass_ev_col == "0") ? 0 : $mass_ev_col
                print area "," rt "," mass_evidence ",EXACT"
                exit
            }
            {
                # Try modified match
                clean_seq = $pcol
                gsub(/\\([^)]*\\)/, "", clean_seq)
                if (clean_seq == peptide) {
                    area = ($acol == "" || $acol == "0") ? 0 : $acol
                    rt = ($rcol == "" || $rcol == "0") ? 0 : $rcol
                    mass_evidence = ($mass_ev_col == "" || $mass_ev_col == "0") ? 0 : $mass_ev_col
                    print area "," rt "," mass_evidence ",MODIFIED:" $pcol
                    exit
                }
            }' !{report_tsv})
        
        if [ -n "$result" ]; then
            area_raw=$(echo $result | cut -d',' -f1)
            rt_obs_minutes=$(echo $result | cut -d',' -f2)
            mass_evidence=$(echo $result | cut -d',' -f3)
            match_type=$(echo $result | cut -d',' -f4-)
            
            # Format area value: convert from "2.2683e+08" to "2.2683E8" format (removing leading zeros)
            if [ -n "$area_raw" ] && [ "$area_raw" != "" ] && [ "$area_raw" != "0" ]; then
                area=$(convert_to_e_notation "$area_raw")
                echo "DEBUG: Area formatting: $area_raw -> $area"
            else
                area=0
                echo "DEBUG: Area value empty or zero, setting to 0"
            fi
                      
            # Convert RT from minutes to seconds (multiply by 60)
            if [ -n "$rt_obs_minutes" ] && [ "$rt_obs_minutes" != "" ] && [ "$rt_obs_minutes" != "0" ]; then
                rt_obs=$(awk -v val="$rt_obs_minutes" 'BEGIN {printf "%.3f", val * 60}')
                echo "DEBUG: RT conversion: $rt_obs_minutes min * 60 = $rt_obs sec"
            else
                rt_obs=0
                echo "DEBUG: RT value empty or zero, setting to 0"
            fi
            
            # Use Mass.Evidence as the dppm value (REAL individual mass accuracy)
            dppm="$mass_evidence"
            
            echo "Found: $short -> area=$area, rt=$rt_obs sec (converted from $rt_obs_minutes min), dppm=$dppm ($match_type)"
        else
            echo "Peptide $long_clean not found in report"
            area=0
            rt_obs=0  # Already in seconds (0)
            dppm=0
        fi
        
        echo "Final values for $short: area=$area, rt=$rt_obs sec (converted from minutes), dppm=$dppm ppm"
        
        # Add values to JSON files using jq (dppm processing removed as per requirements)
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
    
    echo "QC Summary:"
    echo "  Peptides processed: $(tail -n +2 !{qcloud_tsv} | wc -l)"
    echo "  Using REAL Mass.Evidence values for individual peptide mass accuracy"
    echo "  RT values converted from minutes to seconds (column 30 * 60)"
    
    echo "Final JSON content for new metrics:"
    echo "Points per peak JSON:"
    cat "$points_per_peak_json"
    
    echo "Median FWHM JSON:"
    cat "$median_fwhm_json"
    
    echo "Median mass accuracy MS1 JSON:"
    cat "$median_mass_acc_ms1_json"
    
    echo "Median mass accuracy MS2 JSON:"
    cat "$median_mass_acc_ms2_json"
    
    echo "Proteins identified JSON:"
    cat "$proteins_identified_json"
    
    echo "Precursors identified JSON:"
    cat "$precursors_identified_json"
    '''
}
