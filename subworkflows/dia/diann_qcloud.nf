nextflow.enable.dsl=2

// =========================
// DIA-NN standard process
// =========================
process diann {
    label 'diann'
    tag  { "${mzml_file}" }

    input:
    path mzml_file

    output:
    path "*report.tsv", emit: report_tsv

    container "${params.diann_img}"

    shell:
    '''
    # Copy spectra file:
    filename_sh=!{mzml_file}
    diann_cfg_sh=!{params.diann_cfg}
    diann_speclib_folder_sh=!{params.diann_speclib_folder}
    diann_name_speclib_filter_sh=!{params.diann_name_speclib_filter}
    diann_exec_cmd_sh=!{params.diann_exec_cmd}
    databases_folder_sh=!{params.databases_folder}

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

    if [[ -n "$existing_spec_lib" ]]; then
      echo "Running DIA-NN with existing spectral library..."
      "$diann_exec_cmd_sh" \
        --cfg "$diann_cfg_sh" \
        --f "$diann_filename" \
        --out "$output_file" \
        --lib "$existing_spec_lib" \
        --fasta "$fastafile" \
        --out-lib "${basename_sh}.parquet"
    else
      echo "Running DIA-NN with library prediction..."
      "$diann_exec_cmd_sh" \
        --cfg "$diann_cfg_sh" \
        --f "$diann_filename" \
        --out "$output_file" \
        --fasta "$fastafile" \
        --fasta-search \
        --gen-spec-lib \
        --predictor
    fi
    '''
}

// =========================
// DIA-NN Bruker process
// =========================
process diann_bruker {
    label 'diann_bruker'
    tag  { "${folder}" }

    input:
    path d_folder

    output:
    path "*report.tsv", emit: report_tsv
    path "chromatography-data.sqlite", emit: sqlite_file    

    container "${params.diann_img}"

    shell:
    '''
    bruker_folder_sh="!{d_folder}"
    echo "Bruker folder: $bruker_folder_sh"
    diann_cfg_bruker_sh=!{params.diann_cfg_bruker}
    diann_speclib_folder_sh=!{params.diann_speclib_folder}
    echo "CFG file: $diann_cfg_bruker_sh"
    diann_exec_cmd_bruker_sh=!{params.diann_exec_cmd_bruker}
    diann_name_speclib_filter_sh=!{params.diann_name_speclib_filter}
    databases_folder_sh=!{params.databases_folder}

    # Extract filename info:
    basename_sh=$(basename "$bruker_folder_sh" .d)
    extension_sh="d"

    # Extract the organism taking into account the file type:
    organism_sh=$(echo "$bruker_folder_sh" | cut -d'.' -f2)

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
    cp $bruker_folder_sh/chromatography-data.sqlite .

    # Check for existing predicted spectral libraries
    existing_spec_lib=$(find "$diann_speclib_folder_sh" -type f -name "*${fastafilename}*${diann_name_speclib_filter_sh}*")

    if [[ -n "$existing_spec_lib" ]]; then
      echo "Running DIA-NN Bruker with existing spectral library..."
      "$diann_exec_cmd_bruker_sh" \
        --cfg "$diann_cfg_bruker_sh" \
        --f "$bruker_folder_sh" \
        --out "$output_file" \
        --lib "$existing_spec_lib" \
        --fasta "$fastafile" \
        --out-lib "${basename_sh}.parquet"
    else
      echo "Running DIA-NN Bruker with library prediction..."
      "$diann_exec_cmd_bruker_sh" \
        --cfg "$diann_cfg_bruker_sh" \
        --f "$bruker_folder_sh" \
        --out "$output_file" \
        --fasta "$fastafile" \
        --fasta-search \
        --gen-spec-lib \
        --predictor
    fi
    '''
}

// =========================
// Wrapper workflow for QCloud
// =========================
workflow diann_qcloud {
    take:
    rawfile_ch

    main:
    diann(rawfile_ch)

    emit:
    report_tsv = diann.out.report_tsv
}
