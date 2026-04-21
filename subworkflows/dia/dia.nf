nextflow.enable.dsl=2

// =========================
// DIA-NN standard process
// =========================
process diann {
    label 'diann'
    tag { "${mzml_file}" }
    container "${container_img}"

    input:
    path mzml_file
    val container_img
    val config_file
    val parser_version
    val diann_executable
    val diann_version_filter

    output:
    path "*report.tsv", emit: report_tsv
    path "*report.stats.tsv", emit: report_stats_tsv

    shell:
    '''
    set -euo pipefail

    filename_sh="!{mzml_file}"
    diann_cfg_sh="!{config_file}"
    diann_speclib_folder_sh="!{params.diann_speclib_folder}"
    diann_exec_cmd_sh="!{diann_executable}"
    diann_version_filter_sh="!{diann_version_filter}"
    diann_name_speclib_filter_sh="!{params.diann_name_speclib_filter}"
    databases_folder_sh="!{params.databases_folder}"

    pattern_sh="QCD1"
    param_name_sh="qvalue"
    param_value_sh="0.1"

    echo "CFG file: $diann_cfg_sh"
    echo "Spectra complete filename: $filename_sh"
    echo "[INFO] Spectral library filter from DIA-NN version: $diann_version_filter_sh"

    if [[ ! -f "$filename_sh" ]]; then
        echo "[ERROR] Input file not found: $filename_sh" >&2
        exit 1
    fi

    if [[ ! -f "$diann_cfg_sh" ]]; then
        echo "[ERROR] DIA-NN config file not found: $diann_cfg_sh" >&2
        exit 1
    fi

    if [[ ! -d "$diann_speclib_folder_sh" ]]; then
        echo "[ERROR] Spectral library folder not found: $diann_speclib_folder_sh" >&2
        exit 1
    fi

    if [[ ! -d "$databases_folder_sh" ]]; then
        echo "[ERROR] Databases folder not found: $databases_folder_sh" >&2
        exit 1
    fi

    basename_with_ext_sh=$(basename "$filename_sh")
    basename_sh="${basename_with_ext_sh%%.*}"
    organism_sh="${filename_sh##*.}"

    if [[ -z "$basename_sh" ]]; then
        echo "[ERROR] Could not extract basename from: $filename_sh" >&2
        exit 1
    fi

    if [[ -z "$organism_sh" ]]; then
        echo "[ERROR] Could not extract organism from: $filename_sh" >&2
        exit 1
    fi

    file_ext_sh=""
    case "$filename_sh" in
        *.raw.*)
            file_ext_sh="raw"
            ;;
        *.raw)
            file_ext_sh="raw"
            ;;
        *.mzML.*)
            file_ext_sh="mzML"
            ;;
        *.mzML)
            file_ext_sh="mzML"
            ;;
        *)
            echo "[ERROR] Unsupported file format: $filename_sh (expected .raw or .mzML)" >&2
            exit 1
            ;;
    esac

    echo "[DEBUG] Detected file extension: $file_ext_sh"

    fasta_dir_sh="${databases_folder_sh}/${organism_sh}/current"

    if [[ ! -d "$fasta_dir_sh" ]]; then
        echo "[ERROR] FASTA directory not found: $fasta_dir_sh" >&2
        exit 1
    fi

    first_fasta_path=""
    for fasta_candidate in "$fasta_dir_sh"/*.fasta; do
        if [[ -e "$fasta_candidate" ]]; then
            first_fasta_path="$fasta_candidate"
            break
        fi
    done

    if [[ -z "$first_fasta_path" ]]; then
        echo "[ERROR] No FASTA found for organism '$organism_sh' in $fasta_dir_sh" >&2
        exit 1
    fi

    fastafile=$(basename "$first_fasta_path")
    fastafilename="${fastafile%.*}"
    cp "$first_fasta_path" .
    echo "Fasta complete filename: $fastafile"

    diann_filename="${basename_sh}.${file_ext_sh}"

    if [[ "$filename_sh" != "$diann_filename" ]]; then
        cp "$filename_sh" "$diann_filename"
        echo "Renamed spectra file from $filename_sh to: $diann_filename"
    else
        echo "Spectra filename already correct: $diann_filename"
    fi

    output_file="${basename_sh}.report.tsv"
    echo "Output TSV report: $output_file"

    if [[ -n "$diann_version_filter_sh" ]] && [[ "$diann_version_filter_sh" != "null" ]]; then
        filter_to_use="$diann_version_filter_sh"
        echo "[INFO] Using version-derived spectral library filter: $filter_to_use"
    else
        filter_to_use="$diann_name_speclib_filter_sh"
        echo "[INFO] Using legacy spectral library filter: $filter_to_use"
    fi

    existing_spec_lib=""
    version_normalized=""

    if [[ "$filter_to_use" == [0-9][0-9][0-9] ]]; then
        version_normalized="${filter_to_use:0:1}_${filter_to_use:1:1}_${filter_to_use:2:1}"
        echo "[DEBUG] Normalized version from filter '$filter_to_use': $version_normalized"

        for lib_candidate in "$diann_speclib_folder_sh"/*"${fastafilename}"*"diann_${version_normalized}"*"${diann_name_speclib_filter_sh}"*.speclib; do
            if [[ -e "$lib_candidate" ]]; then
                existing_spec_lib="$lib_candidate"
                break
            fi
        done

        if [[ -z "$existing_spec_lib" ]]; then
            for lib_candidate in "$diann_speclib_folder_sh"/*"${fastafilename}"*"diann_${version_normalized}"*"${diann_name_speclib_filter_sh}"*.parquet; do
                if [[ -e "$lib_candidate" ]]; then
                    existing_spec_lib="$lib_candidate"
                    break
                fi
            done
        fi

        if [[ -n "$existing_spec_lib" ]]; then
            echo "[INFO] Found spectral library with new naming convention: $(basename "$existing_spec_lib")"
        fi
    fi

    if [[ -z "$existing_spec_lib" ]]; then
        echo "[DEBUG] Searching with legacy pattern: *${fastafilename}*${filter_to_use}*"

        for lib_candidate in "$diann_speclib_folder_sh"/*"${fastafilename}"*"${filter_to_use}"*.speclib; do
            if [[ -e "$lib_candidate" ]]; then
                existing_spec_lib="$lib_candidate"
                break
            fi
        done

        if [[ -z "$existing_spec_lib" ]]; then
            for lib_candidate in "$diann_speclib_folder_sh"/*"${fastafilename}"*"${filter_to_use}"*.parquet; do
                if [[ -e "$lib_candidate" ]]; then
                    existing_spec_lib="$lib_candidate"
                    break
                fi
            done
        fi

        if [[ -n "$existing_spec_lib" ]]; then
            echo "[INFO] Found spectral library with legacy naming convention: $(basename "$existing_spec_lib")"
        fi
    fi

    if [[ -z "$existing_spec_lib" ]]; then
        echo "[WARNING] No existing spectral library found for organism '$fastafilename' with filter '$filter_to_use'"
        echo "[INFO] Will generate new spectral library from FASTA"
    fi

    use_conditional_param="false"
    if [[ "$basename_sh" == *"$pattern_sh"* ]]; then
        use_conditional_param="true"
        echo "[INFO] Pattern '$pattern_sh' detected - adding parameter: --${param_name_sh} ${param_value_sh}"
    fi

    diann_cmd=(
        "$diann_exec_cmd_sh"
        --cfg "$diann_cfg_sh"
        --f "$diann_filename"
        --out "$output_file"
        --fasta "$fastafile"
    )

    if [[ -n "$existing_spec_lib" ]]; then
        echo "Running DIA-NN with existing spectral library..."
        diann_cmd+=( --lib "$existing_spec_lib" --out-lib "${basename_sh}.parquet" )
    else
        echo "Running DIA-NN with library prediction..."
        diann_cmd+=( --fasta-search --gen-spec-lib --predictor )
    fi

    if [[ "$use_conditional_param" == "true" ]]; then
        diann_cmd+=( --"${param_name_sh}" "${param_value_sh}" )
    fi

    "${diann_cmd[@]}"
    '''
}

// =========================
// DIA-NN Bruker process
// =========================
process diann_bruker {
    label 'diann_bruker'
    tag { "${d_folder}" }
    container "${container_img}"

    input:
    path d_folder
    val container_img
    val config_file
    val parser_version
    val diann_executable
    val diann_version_filter

    output:
    path "*report.tsv", emit: report_tsv
    path "*report.stats.tsv", emit: report_stats_tsv
    path "chromatography-data.sqlite", emit: sqlite_file

    shell:
    '''
    set -euo pipefail

    bruker_folder_sh="!{d_folder}"
    diann_speclib_folder_sh="!{params.diann_speclib_folder}"
    diann_exec_cmd_bruker_sh="!{diann_executable}"
    diann_version_filter_sh="!{diann_version_filter}"
    diann_name_speclib_filter_sh="!{params.diann_name_speclib_filter}"
    databases_folder_sh="!{params.databases_folder}"

    pattern_sh="QCD1"
    param_name_sh="qvalue"
    param_value_sh="0.1"

    echo "Bruker folder: $bruker_folder_sh"

    if [[ -n "!{params.diann_cfg_bruker}" ]] && [[ -f "!{params.diann_cfg_bruker}" ]]; then
        diann_cfg_bruker_sh="!{params.diann_cfg_bruker}"
        echo "Using Bruker-specific CFG file: $diann_cfg_bruker_sh"
    else
        diann_cfg_bruker_sh="!{config_file}"
        echo "Using default Bruker CFG file: $diann_cfg_bruker_sh"
    fi

    echo "[INFO] Spectral library filter from DIA-NN version: $diann_version_filter_sh"

    if [[ ! -d "$bruker_folder_sh" ]]; then
        echo "[ERROR] Bruker folder not found: $bruker_folder_sh" >&2
        exit 1
    fi

    if [[ ! -f "$diann_cfg_bruker_sh" ]]; then
        echo "[ERROR] DIA-NN Bruker config file not found: $diann_cfg_bruker_sh" >&2
        exit 1
    fi

    if [[ ! -d "$diann_speclib_folder_sh" ]]; then
        echo "[ERROR] Spectral library folder not found: $diann_speclib_folder_sh" >&2
        exit 1
    fi

    if [[ ! -d "$databases_folder_sh" ]]; then
        echo "[ERROR] Databases folder not found: $databases_folder_sh" >&2
        exit 1
    fi

    folder_name_sh=$(basename "$bruker_folder_sh")

    case "$folder_name_sh" in
        *.d.*)
            basename_sh="${folder_name_sh%%.d.*}"
            organism_sh="${folder_name_sh#*.d.}"
            ;;
        *.d)
            basename_sh="${folder_name_sh%.d}"
            organism_sh=""
            ;;
        *)
            echo "[ERROR] Unsupported Bruker folder naming: $folder_name_sh" >&2
            echo "[ERROR] Expected something like sample.d.SP_Bovine or sample.d" >&2
            exit 1
            ;;
    esac

    if [[ -z "$basename_sh" ]]; then
        echo "[ERROR] Could not extract basename from: $folder_name_sh" >&2
        exit 1
    fi

    if [[ -z "$organism_sh" ]]; then
        echo "[ERROR] Could not extract organism from: $folder_name_sh" >&2
        echo "[ERROR] Expected Bruker folder name to include organism suffix after .d." >&2
        exit 1
    fi

    echo "[DEBUG] Bruker folder basename: $basename_sh"
    echo "[DEBUG] Extracted organism: $organism_sh"

    diann_folder="${basename_sh}.d"
    echo "Creating DIA-NN compatible folder: $diann_folder"
    ln -sfn "$bruker_folder_sh" "$diann_folder"

    fasta_dir_sh="${databases_folder_sh}/${organism_sh}/current"

    if [[ ! -d "$fasta_dir_sh" ]]; then
        echo "[ERROR] FASTA directory not found: $fasta_dir_sh" >&2
        exit 1
    fi

    first_fasta_path=""
    for fasta_candidate in "$fasta_dir_sh"/*.fasta; do
        if [[ -e "$fasta_candidate" ]]; then
            first_fasta_path="$fasta_candidate"
            break
        fi
    done

    if [[ -z "$first_fasta_path" ]]; then
        echo "[ERROR] No FASTA found for organism '$organism_sh' in $fasta_dir_sh" >&2
        exit 1
    fi

    fastafile=$(basename "$first_fasta_path")
    fastafilename="${fastafile%.*}"
    cp "$first_fasta_path" .
    echo "Fasta complete filename: $fastafile"

    output_file="${basename_sh}.report.tsv"
    echo "Output TSV report: $output_file"

    if [[ ! -f "$diann_folder/chromatography-data.sqlite" ]]; then
        echo "[ERROR] chromatography-data.sqlite not found in $diann_folder" >&2
        exit 1
    fi

    cp "$diann_folder/chromatography-data.sqlite" .

    if [[ -n "$diann_version_filter_sh" ]] && [[ "$diann_version_filter_sh" != "null" ]]; then
        filter_to_use="$diann_version_filter_sh"
        echo "[INFO] Using version-derived spectral library filter: $filter_to_use"
    else
        filter_to_use="$diann_name_speclib_filter_sh"
        echo "[INFO] Using legacy spectral library filter: $filter_to_use"
    fi

    existing_spec_lib=""
    version_normalized=""

    if [[ "$filter_to_use" == [0-9][0-9][0-9] ]]; then
        version_normalized="${filter_to_use:0:1}_${filter_to_use:1:1}_${filter_to_use:2:1}"
        echo "[DEBUG] Normalized version from filter '$filter_to_use': $version_normalized"

        for lib_candidate in "$diann_speclib_folder_sh"/*"${fastafilename}"*"diann_${version_normalized}"*"${diann_name_speclib_filter_sh}"*.speclib; do
            if [[ -e "$lib_candidate" ]]; then
                existing_spec_lib="$lib_candidate"
                break
            fi
        done

        if [[ -z "$existing_spec_lib" ]]; then
            for lib_candidate in "$diann_speclib_folder_sh"/*"${fastafilename}"*"diann_${version_normalized}"*"${diann_name_speclib_filter_sh}"*.parquet; do
                if [[ -e "$lib_candidate" ]]; then
                    existing_spec_lib="$lib_candidate"
                    break
                fi
            done
        fi

        if [[ -n "$existing_spec_lib" ]]; then
            echo "[INFO] Found spectral library with new naming convention: $(basename "$existing_spec_lib")"
        fi
    fi

    if [[ -z "$existing_spec_lib" ]]; then
        echo "[DEBUG] Searching with legacy pattern: *${fastafilename}*${filter_to_use}*"

        for lib_candidate in "$diann_speclib_folder_sh"/*"${fastafilename}"*"${filter_to_use}"*.speclib; do
            if [[ -e "$lib_candidate" ]]; then
                existing_spec_lib="$lib_candidate"
                break
            fi
        done

        if [[ -z "$existing_spec_lib" ]]; then
            for lib_candidate in "$diann_speclib_folder_sh"/*"${fastafilename}"*"${filter_to_use}"*.parquet; do
                if [[ -e "$lib_candidate" ]]; then
                    existing_spec_lib="$lib_candidate"
                    break
                fi
            done
        fi

        if [[ -n "$existing_spec_lib" ]]; then
            echo "[INFO] Found spectral library with legacy naming convention: $(basename "$existing_spec_lib")"
        fi
    fi

    if [[ -z "$existing_spec_lib" ]]; then
        echo "[WARNING] No existing spectral library found for organism '$fastafilename' with filter '$filter_to_use'"
        echo "[INFO] Will generate new spectral library from FASTA"
    fi

    use_conditional_param="false"
    if [[ "$basename_sh" == *"$pattern_sh"* ]]; then
        use_conditional_param="true"
        echo "[INFO] Pattern '$pattern_sh' detected - adding parameter: --${param_name_sh} ${param_value_sh}"
    fi

    diann_cmd=(
        "$diann_exec_cmd_bruker_sh"
        --cfg "$diann_cfg_bruker_sh"
        --f "$diann_folder"
        --out "$output_file"
        --fasta "$fastafile"
    )

    if [[ -n "$existing_spec_lib" ]]; then
        echo "Running DIA-NN Bruker with existing spectral library..."
        diann_cmd+=( --lib "$existing_spec_lib" --out-lib "${basename_sh}.parquet" )
    else
        echo "Running DIA-NN Bruker with library prediction..."
        diann_cmd+=( --fasta-search --gen-spec-lib --predictor )
    fi

    if [[ "$use_conditional_param" == "true" ]]; then
        diann_cmd+=( --"${param_name_sh}" "${param_value_sh}" )
    fi

    "${diann_cmd[@]}"
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
    diann_executable
    diann_version_filter

    main:
    diann(
        rawfile_ch,
        container_img,
        config_file,
        parser_version,
        diann_executable,
        diann_version_filter
    )

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
    diann_executable
    diann_version_filter

    main:
    diann_bruker(
        bruker_folder_ch,
        container_img,
        config_file,
        parser_version,
        diann_executable,
        diann_version_filter
    )

    emit:
    report_tsv = diann_bruker.out.report_tsv
    report_stats_tsv = diann_bruker.out.report_stats_tsv
    sqlite_file = diann_bruker.out.sqlite_file
}