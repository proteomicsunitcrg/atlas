nextflow.enable.dsl=2

process DIANN_RUN {
    label 'diann'
    tag "${meta.basename}"
    container "${container_img}"

    input:
    tuple val(meta), path(input_file)      // <--- meta: [basename, organism, fileType]
    val container_img
    val config_file
    val parser_version                     //  report format (tsv, parquet, sqlite)
    val diann_executable
    val diann_version_filter              // <--- e.g., "232"
    val legacy_filter                     // <--- e.g., "NK", "MK"
    path databases_folder
    path speclib_folder

    output:
    tuple val(meta), path("${meta.basename}.report.tsv"), emit: report_tsv
    tuple val(meta), path("*report.stats.tsv"), emit: report_stats_tsv
    tuple val(meta), path("chromatography-data.sqlite"), emit: sqlite_file, optional: true

    script:
    def is_bruker = meta.fileType == 'bruker'
    def basename = meta.basename
    def organism = meta.organism
    
    // <--- Conditional parameter: QCD1 pattern adds --qvalue 0.1
    def extra_params = basename.contains('QCD1') ? "--qvalue 0.1" : ""
    
    """
    set -euo pipefail
    
    echo "[INFO] Processing ${basename} (${meta.fileType}) for organism ${organism}"
    
    # ============================================
    # STEP 1: Prepare FASTA
    # ============================================
    fasta_file=\$(bash ${moduleDir}/scripts/prepare_fasta.sh \
        "${databases_folder}" \
        "${organism}")
    
    fasta_basename="\${fasta_file%.*}"
    echo "[INFO] Using FASTA: \${fasta_file}"
    
    # ============================================
    # STEP 2: Find spectral library
    # ============================================
    spectral_lib=\$(bash ${moduleDir}/scripts/find_spectral_library.sh \
        "${speclib_folder}" \
        "\${fasta_basename}" \
        "${diann_version_filter}" \
        "${legacy_filter}")
    
    if [[ -n "\${spectral_lib}" ]]; then
        echo "[INFO] Found existing spectral library: \${spectral_lib}"
    else
        echo "[WARNING] No spectral library found - will generate from FASTA"
    fi
    
    # ============================================
    # STEP 3: Prepare input for DIA-NN
    # ============================================
    if [[ "${is_bruker}" == "true" ]]; then
        # <--- Bruker: .d folder
        diann_input="${basename}.d"
        ln -sfn "${input_file}" "\${diann_input}"
        
        # <--- Copy SQLite file
        if [[ -f "\${diann_input}/chromatography-data.sqlite" ]]; then
            cp "\${diann_input}/chromatography-data.sqlite" .
        else
            echo "[ERROR] chromatography-data.sqlite not found in \${diann_input}" >&2
            exit 1
        fi
        
    else
        # <--- Thermo: .raw or .mzML file
        diann_input="${basename}.${meta.fileType}"
        cp "${input_file}" "\${diann_input}"
    fi
    
    echo "[INFO] DIA-NN input: \${diann_input}"
    
    # ============================================
    # STEP 4: Build DIA-NN command
    # ============================================
    diann_cmd="${diann_executable} \
        --cfg ${config_file} \
        --f \${diann_input} \
        --out ${basename}.report.tsv \
        --fasta \${fasta_file}"
    
    # <--- Add library or prediction flags
    if [[ -n "\${spectral_lib}" ]]; then
        diann_cmd="\${diann_cmd} --lib \${spectral_lib} --out-lib ${basename}.parquet"
    else
        diann_cmd="\${diann_cmd} --fasta-search --gen-spec-lib --predictor"
    fi
    
    # <--- Add conditional params (QCD1, etc.)
    if [[ -n "${extra_params}" ]]; then
        echo "[INFO] Adding conditional parameter: ${extra_params}"
        diann_cmd="\${diann_cmd} ${extra_params}"
    fi
    
    # ============================================
    # STEP 5: Execute DIA-NN
    # ============================================
    echo "[INFO] Running DIA-NN..."
    echo "[CMD] \${diann_cmd}"
    
    eval "\${diann_cmd}"
    
    echo "[INFO] DIA-NN completed successfully"
    
    # ============================================
    # STEP 6: Parse DIA-NN report (using configured parser_version)
    # ============================================
    echo "[INFO] Using parser version: ${parser_version}"
    
    case "${parser_version}" in
        parquet)
            echo "[INFO] Converting Parquet report to TSV..."
            bash ${moduleDir}/scripts/parsers/parse_diann_report.sh \
                "${basename}.report.parquet" \
                "parquet" \
                "${params.duckdb_path}" \
                > "${basename}.report.tsv"
            ;;
            
        sqlite)
            echo "[INFO] Converting SQLite report to TSV..."
            bash ${moduleDir}/scripts/parsers/parse_diann_report.sh \
                "${basename}.report.sqlite" \
                "sqlite" \
                "${params.duckdb_path}" \
                > "${basename}.report.tsv"
            ;;
            
        tsv)
            echo "[INFO] TSV report already generated - no conversion needed"
            ;;
            
        *)
            echo "[ERROR] Unknown parser_version: ${parser_version}" >&2
            echo "[ERROR] Valid values: parquet, sqlite, tsv" >&2
            exit 1
            ;;
    esac
    
    echo "[INFO] Report parsing completed: ${basename}.report.tsv"
    """
}