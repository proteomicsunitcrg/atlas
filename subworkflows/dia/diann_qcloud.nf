nextflow.enable.dsl=2

// =========================
// DIA-NN standard process
// =========================
process diann {
    label 'diann'
    tag  { "${mzml_file}" }

    path mzml_file
    val container_img
    val config_file
    val parser_version

    output:
    path "*report.tsv", emit: report_tsv
    path "*report.stats.tsv", emit: report_stats_tsv

    container { container_img }

    shell:
    '''
    # Copy spectra file:
    filename_sh=!{mzml_file}
    diann_cfg_sh=!{params.diann_cfg}
    diann_speclib_folder_sh=!{params.diann_speclib_folder}
    diann_name_speclib_filter_sh=!{params.diann_name_speclib_filter}
    diann_exec_cmd_sh=!{params.diann_exec_cmd}
    databases_folder_sh=!{params.databases_folder}
    
    # Conditional parameter configuration (hardcoded)
    pattern_sh="QCD1"
    param_name_sh="qvalue"
    param_value_sh="0.1"

    echo "CFG file: $diann_cfg_sh"
    echo "Spectra complete filename: $filename_sh"

    # Extract filename info:
    basename_sh=$(basename $filename_sh | cut -f 1 -d '.')
    extension_sh=$(basename $filename_sh | cut -f 2 -d '.')
    organism_sh=$(echo ${filename_sh##*.})

    # Load fasta file:
    fastafile=$(basename ${databases_folder_sh}/${organism_sh}/current/*.fasta)
    fastafilename=$(echo ${fastafile%.*})
    fasta_orig_path=${databases_folder_sh}/${organism_sh}/current/${fastafile}
    cp $fasta_orig_path .
    echo "Fasta complete filename: $fastafile"

    # Rename spectra file for DIA-NN:
    diann_filename=$basename_sh.$extension_sh
    cp $filename_sh $diann_filename
    echo "Spectra filename for DIA-NN: $diann_filename"

    # Output files:
    output_file=${basename_sh}.report.tsv
    echo "Output TSV report: $output_file"

    # Check for existing predicted spectral libraries
    existing_spec_lib=$(find "$diann_speclib_folder_sh" -type f -name "*${fastafilename}*${diann_name_speclib_filter_sh}*")

    # Conditional parameter logic - ALWAYS add for QCD1
    conditional_param=""
    if [[ "$basename_sh" == *"$pattern_sh"* ]]; then
      conditional_param="--${param_name_sh} ${param_value_sh}"
      echo "[INFO] Pattern '$pattern_sh' detected - adding parameter: $conditional_param"
    fi

    if [[ -n "$existing_spec_lib" ]]; then
      echo "Running DIA-NN with existing spectral library..."
      "$diann_exec_cmd_sh" \
        --cfg "$diann_cfg_sh" \
        --f "$diann_filename" \
        --out "$output_file" \
        --lib "$existing_spec_lib" \
        --fasta "$fastafile" \
        --out-lib "${basename_sh}.parquet" \
        $conditional_param
    else
      echo "Running DIA-NN with library prediction..."
      "$diann_exec_cmd_sh" \
        --cfg "$diann_cfg_sh" \
        --f "$diann_filename" \
        --out "$output_file" \
        --fasta "$fastafile" \
        --fasta-search \
        --gen-spec-lib \
        --predictor \
        $conditional_param
    fi
    '''
}

// =========================
// DIA-NN Bruker process
// =========================
process diann_bruker {
    label 'diann_bruker'
    tag { "${d_folder}" }

    input:
    path d_folder
    val container_img
    val config_file
    val parser_version

    output:
    path "*report.tsv", emit: report_tsv
    path "*report.stats.tsv", emit: report_stats_tsv
    path "chromatography-data.sqlite", emit: sqlite_file

    container { container_img }

    shell:
    '''
    bruker_folder_sh="!{d_folder}"
    echo "Bruker folder: $bruker_folder_sh"
    
    # Use Bruker-specific configuration if available, otherwise fall back to regular config
    if [ -n "!{params.diann_cfg_bruker}" ] && [ -f "!{params.diann_cfg_bruker}" ]; then
        diann_cfg_bruker_sh=!{params.diann_cfg_bruker}
        echo "Using Bruker-specific CFG file: $diann_cfg_bruker_sh"
    else
        # Fallback to default Bruker config path
        diann_cfg_bruker_sh="!{params.diann_cfg_bruker}"
        echo "Using default Bruker CFG file: $diann_cfg_bruker_sh"
    fi
    
    diann_speclib_folder_sh=!{params.diann_speclib_folder}
    diann_exec_cmd_bruker_sh=!{params.diann_exec_cmd}
    diann_name_speclib_filter_sh=!{params.diann_name_speclib_filter}
    databases_folder_sh=!{params.databases_folder}
    
    # Conditional parameter configuration (hardcoded)
    pattern_sh="QCD1"
    param_name_sh="qvalue"
    param_value_sh="0.1"

    # Extract filename info:
    # Get the base name without .d.SP_Bovine suffix  
    basename_sh=$(basename "$bruker_folder_sh")
    basename_sh=${basename_sh%%.d.*}
    extension_sh="d"

    # Extract the organism from Bruker folder name (everything after .d.)
    organism_sh=${bruker_folder_sh##*.d.}
    echo "Extracted organism: $organism_sh"
    
    # Create a properly named .d folder for DIA-NN (it expects .d extension)
    diann_folder="${basename_sh}.d"
    echo "Creating DIA-NN compatible folder: $diann_folder"
    ln -sf "$bruker_folder_sh" "$diann_folder"

    # Load fasta file:
    fastafile=$(basename ${databases_folder_sh}/${organism_sh}/current/*.fasta)
    fastafilename=$(echo ${fastafile%.*})
    fasta_orig_path=${databases_folder_sh}/${organism_sh}/current/${fastafile}
    cp $fasta_orig_path .
    echo "Fasta complete filename: $fastafile"

    # Output files:
    output_file=$basename_sh.report.tsv
    echo "Output TSV report: $output_file"

    # Copy the SQLite file to the current working directory
    cp $diann_folder/chromatography-data.sqlite .

    # Check for existing predicted spectral libraries
    existing_spec_lib=$(find "$diann_speclib_folder_sh" -type f -name "*${fastafilename}*${diann_name_speclib_filter_sh}*")

    # Conditional parameter logic - ALWAYS add for QCD1
    conditional_param=""
    if [[ "$basename_sh" == *"$pattern_sh"* ]]; then
      conditional_param="--${param_name_sh} ${param_value_sh}"
      echo "[INFO] Pattern '$pattern_sh' detected - adding parameter: $conditional_param"
    fi

    if [[ -n "$existing_spec_lib" ]]; then
      echo "Running DIA-NN Bruker with existing spectral library..."
      "$diann_exec_cmd_bruker_sh" \
        --cfg "$diann_cfg_bruker_sh" \
        --f "$diann_folder" \
        --out "$output_file" \
        --lib "$existing_spec_lib" \
        --fasta "$fastafile" \
        --out-lib "${basename_sh}.parquet" \
        $conditional_param
    else
      echo "Running DIA-NN Bruker with library prediction..."
      "$diann_exec_cmd_bruker_sh" \
        --cfg "$diann_cfg_bruker_sh" \
        --f "$diann_folder" \
        --out "$output_file" \
        --fasta "$fastafile" \
        --fasta-search \
        --gen-spec-lib \
        --predictor \
        $conditional_param
    fi
    '''
}

// =========================
// Wrapper workflow for QCloud
// =========================
workflow diann_qcloud {
    take:
    rawfile_ch
    container_img
    config_file
    parser_version

    main:
    diann(rawfile_ch, container_img, config_file, parser_version)

    emit:
    report_tsv = diann.out.report_tsv
    report_stats_tsv = diann.out.report_stats_tsv
}

// =========================
// Wrapper workflow for QCloud - Bruker
// =========================
workflow diann_bruker_qcloud {
    take:
    bruker_folder_ch
    container_img
    config_file
    parser_version

    main:
    diann_bruker(bruker_folder_ch, container_img, config_file, parser_version)

    emit:
    report_tsv = diann_bruker.out.report_tsv
    report_stats_tsv = diann_bruker.out.report_stats_tsv
    sqlite_file = diann_bruker.out.sqlite_file
}