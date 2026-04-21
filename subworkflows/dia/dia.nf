databases_folder        = params.databases_folder
diann_speclib_folder    = params.diann_speclib_folder
diann_exec_cmd          = params.diann_exec_cmd
diann_exec_cmd_bruker   = params.diann_exec_cmd_bruker
diann_cfg               = params.diann_cfg
diann_cfg_bruker        = params.diann_cfg_bruker
diann_name_speclib_filter = params.diann_name_speclib_filter

process diann {
    label 'diann'
    tag  { "${mzml_file}" }
    container { container_img } 

    input:
    file(mzml_file)
    val container_img
    val config_file
    val parser_version
    val diann_executable
    val diann_version_filter

    output:
    file("*report.tsv")

    shell:
    '''
    # Copy spectra file: 
    filename_sh=!{mzml_file}
    diann_cfg_sh=!{config_file}
    diann_speclib_folder_sh=!{diann_speclib_folder}
    diann_version_filter_sh=!{diann_version_filter}  
    diann_name_speclib_filter_sh=!{diann_name_speclib_filter}  
    diann_exec_cmd_sh=!{diann_executable}
    
    echo "[INFO] Spectral library filter from DIA-NN version: $diann_version_filter_sh"

    echo "CFG file: "$diann_cfg_sh
    echo "[DEBUG] Container: !{container_img}"
    echo "[DEBUG] Config received: !{config_file}"
    echo "[DEBUG] Parser version: !{parser_version}"

    # Extract filename info:
    basename_sh=$(basename $filename_sh | cut -f 1 -d '.')
    extension_sh=$(basename $filename_sh | cut -f 2 -d '.') 
    organism_sh=$(echo ${filename_sh##*.})

    # Load fasta file:
    databases_folder_sh=!{databases_folder}
    fastafile=$(basename ${databases_folder_sh}/${organism_sh}/current/*.fasta)
    fastafilename=$(echo ${fastafile%.*})
    fasta_orig_path=${databases_folder_sh}/${organism_sh}/current/${fastafile}
    cp $fasta_orig_path .
    echo "Fasta complete filename: "$fastafile

    # Rename spectra file for DIA-NN:
    diann_filename=$basename_sh"."$extension_sh
    mv $filename_sh $diann_filename
    echo "Spectra filename for DIA-NN: "$diann_filename

    # Output files:
    output_file=${basename_sh}".report.tsv"
    echo "Output TSV report: "$output_file

    # Check for existing predicted spectral libraries
    # Use version-derived filter if available, otherwise fall back to legacy filter
    if [[ -n "$diann_version_filter_sh" && "$diann_version_filter_sh" != "null" ]]; then
        filter_to_use="$diann_version_filter_sh"
        echo "[INFO] Using version-derived spectral library filter: $filter_to_use"
    else
        filter_to_use="$diann_name_speclib_filter_sh"
        echo "[INFO] Using legacy spectral library filter: $filter_to_use"
    fi
    
    # Multi-pattern search for spectral libraries
    # Pattern 1: New naming convention with DIA-NN version embedded
    # Format: sp_human_2025_01_diann_1_9_2_astral.predicted.speclib
    existing_spec_lib=""

    # Extract version components from filter (e.g., "192" -> "1_9_2", "232" -> "2_3_2")
    if [[ "$filter_to_use" =~ ^[0-9]+$ ]]; then
        # Convert numeric filter to underscore format: 192 -> 1_9_2
        version_normalized=$(echo "$filter_to_use" | sed 's/\(.\)\(.\)\(.\)/\1_\2_\3/')
        echo "[DEBUG] Normalized version from filter '$filter_to_use': $version_normalized"
        
        # Search for new format: organism + diann_version + filter_name
        existing_spec_lib=$(find "$diann_speclib_folder_sh" -type f \
            \( -name "*${fastafilename}*diann_${version_normalized}*${diann_name_speclib_filter_sh}*.speclib" \
            -o -name "*${fastafilename}*diann_${version_normalized}*${diann_name_speclib_filter_sh}*.parquet" \) \
            2>/dev/null | head -n 1)
        
        if [[ -n "$existing_spec_lib" ]]; then
            echo "[INFO] Found spectral library with new naming convention: $(basename "$existing_spec_lib")"
        fi
    fi

    # Pattern 2: Legacy naming convention with numeric filter only
    # Format: sp_human_192_predicted.parquet or sp_human_192_astral.predicted.speclib
    if [[ -z "$existing_spec_lib" ]]; then
        echo "[DEBUG] Searching with legacy pattern: *${fastafilename}*${filter_to_use}*"
        existing_spec_lib=$(find "$diann_speclib_folder_sh" -type f \
            \( -name "*${fastafilename}*${filter_to_use}*.speclib" \
            -o -name "*${fastafilename}*${filter_to_use}*.parquet" \) \
            2>/dev/null | head -n 1)
        
        if [[ -n "$existing_spec_lib" ]]; then
            echo "[INFO] Found spectral library with legacy naming convention: $(basename "$existing_spec_lib")"
        fi
    fi

    # Final check
    if [[ -z "$existing_spec_lib" ]]; then
        echo "[WARNING] No existing spectral library found for organism '$fastafilename' with filter '$filter_to_use'"
        echo "[INFO] Will generate new spectral library from FASTA"
    fi

    if [[ -n "$existing_spec_lib" ]]; then
      echo "Running DIA-NN command line with already existing spectral library..."
      "$diann_exec_cmd_sh" \
        --cfg "$diann_cfg_sh" \
        --f "$diann_filename" \
        --out "$output_file" \
        --lib "$existing_spec_lib" \
        --fasta "$fastafile" \
        --out-lib "${basename_sh}.parquet"
    else
      echo "Running DIA-NN command line with lib prediction..."
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

process diann_bruker {
    label 'diann_bruker'
    tag  { "${folder}" }

    input:
    tuple val(folder), val(base), val(d_folder)
    val diann_version_filter 

    output:
    file("*report.tsv")
    path("chromatography-data.sqlite"), emit: sqlite_file    

    shell:
    '''
    bruker_folder_sh="!{d_folder}"
    echo "Bruker folder: $bruker_folder_sh"
    diann_cfg_bruker_sh=!{diann_cfg_bruker}
    diann_speclib_folder_sh=!{diann_speclib_folder}
    echo "CFG file: "$diann_cfg_bruker_sh
    diann_exec_cmd_bruker_sh=!{diann_exec_cmd_bruker}
    diann_version_filter_sh=!{diann_version_filter} 
    diann_name_speclib_filter_sh=!{diann_name_speclib_filter} 
    
    echo "[INFO] Spectral library filter from DIA-NN version: $diann_version_filter_sh"

    # Extract filename info:
    basename_sh=$(basename "$bruker_folder_sh" .d)
    extension_sh="d"

    # Extract the organism taking into account the file type:
    organism_sh=$(echo "$bruker_folder_sh" | cut -d'.' -f2)

    # Load fasta file:
    databases_folder_sh=!{params.databases_folder}
    fastafile=$(basename ${databases_folder_sh}/${organism_sh}/current/*.fasta)
    fastafilename=$(echo ${fastafile%.*})
    fasta_orig_path=${databases_folder_sh}/${organism_sh}/current/${fastafile}
    cp $fasta_orig_path .
    echo "Fasta complete filename: "$fastafile

    # Output files:
    output_file=$basename_sh".report.tsv"
    echo "Output TSV report: "$output_file

    # Copy the SQLite file to the current working directory
    cp $bruker_folder_sh/chromatography-data.sqlite .

    # Check for existing predicted spectral libraries
    # Use version-derived filter if available, otherwise fall back to legacy filter
    if [[ -n "$diann_version_filter_sh" && "$diann_version_filter_sh" != "null" ]]; then
        filter_to_use="$diann_version_filter_sh"
        echo "[INFO] Using version-derived spectral library filter: $filter_to_use"
    else
        filter_to_use="$diann_name_speclib_filter_sh"
        echo "[INFO] Using legacy spectral library filter: $filter_to_use"
    fi
    
    # Multi-pattern search for spectral libraries
    # Pattern 1: New naming convention with DIA-NN version embedded
    # Format: sp_human_2025_01_diann_1_9_2_astral.predicted.speclib
    existing_spec_lib=""

    # Extract version components from filter (e.g., "192" -> "1_9_2", "232" -> "2_3_2")
    if [[ "$filter_to_use" =~ ^[0-9]+$ ]]; then
        # Convert numeric filter to underscore format: 192 -> 1_9_2
        version_normalized=$(echo "$filter_to_use" | sed 's/\(.\)\(.\)\(.\)/\1_\2_\3/')
        echo "[DEBUG] Normalized version from filter '$filter_to_use': $version_normalized"
        
        # Search for new format: organism + diann_version + filter_name
        existing_spec_lib=$(find "$diann_speclib_folder_sh" -type f \
            \( -name "*${fastafilename}*diann_${version_normalized}*${diann_name_speclib_filter_sh}*.speclib" \
            -o -name "*${fastafilename}*diann_${version_normalized}*${diann_name_speclib_filter_sh}*.parquet" \) \
            2>/dev/null | head -n 1)
        
        if [[ -n "$existing_spec_lib" ]]; then
            echo "[INFO] Found spectral library with new naming convention: $(basename "$existing_spec_lib")"
        fi
    fi

    # Pattern 2: Legacy naming convention with numeric filter only
    # Format: sp_human_192_predicted.parquet or sp_human_192_astral.predicted.speclib
    if [[ -z "$existing_spec_lib" ]]; then
        echo "[DEBUG] Searching with legacy pattern: *${fastafilename}*${filter_to_use}*"
        existing_spec_lib=$(find "$diann_speclib_folder_sh" -type f \
            \( -name "*${fastafilename}*${filter_to_use}*.speclib" \
            -o -name "*${fastafilename}*${filter_to_use}*.parquet" \) \
            2>/dev/null | head -n 1)
        
        if [[ -n "$existing_spec_lib" ]]; then
            echo "[INFO] Found spectral library with legacy naming convention: $(basename "$existing_spec_lib")"
        fi
    fi

    # Final check
    if [[ -z "$existing_spec_lib" ]]; then
        echo "[WARNING] No existing spectral library found for organism '$fastafilename' with filter '$filter_to_use'"
        echo "[INFO] Will generate new spectral library from FASTA"
    fi

    if [[ -n "$existing_spec_lib" ]]; then
      echo "Running DIA-NN command line with already existing spectral library..."
      "$diann_exec_cmd_bruker_sh" \
        --cfg "$diann_cfg_bruker_sh" \
        --f "$bruker_folder_sh" \
        --out "$output_file" \
        --lib "$existing_spec_lib" \
        --fasta "$fastafile" \
        --out-lib "${basename_sh}.parquet"
     else
      echo "Running DIA-NN command line with lib prediction..."
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
