//API:
url_api_qcloud_signin             = params.url_api_qcloud_signin
url_api_qcloud_user               = params.url_api_qcloud_user
url_api_qcloud_pass               = params.url_api_qcloud_pass
url_api_qcloud_insert_data        = params.url_api_qcloud_insert_data
url_api_qcloud_insert_file        = params.url_api_qcloud_insert_file

//Bash scripts folder:
binfolder                  = "$baseDir/bin"
instrument_folder          = params.instrument_folder

process insertDataToQCloud {
    tag { "${mzml_file}" }
    label 'clitools'
    
    errorStrategy 'retry'
    maxRetries 2

    input:
    tuple val(filename), val(basename), val(path)
    tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
    val(json_files)

    script:
    """
    set -euo pipefail

    echo "Starting QCloud insertion process..."
    echo "Processing file: ${mzml_file}"
    echo "JSON files input: ${json_files}"

    # [Previous validation code remains the same...]
    
    # Check if required files exist
    if [[ ! -f "${mzml_file}" ]]; then
        echo "ERROR: mzML file ${mzml_file} not found"
        exit 1
    fi

    # Check if required scripts exist
    if [[ ! -f "${binfolder}/utils.sh" ]]; then
        echo "ERROR: utils.sh not found in ${binfolder}"
        exit 1
    fi

    if [[ ! -f "${binfolder}/parsing.sh" ]]; then
        echo "ERROR: parsing.sh not found in ${binfolder}"
        exit 1
    fi

    if [[ ! -f "${binfolder}/parsing_qcloud.sh" ]]; then
        echo "ERROR: parsing_qcloud.sh not found in ${binfolder}"
        exit 1
    fi

    # Clean up JSON file list from Nextflow
    json_files_clean=\$(echo '${json_files}' | sed 's/[][]//g' | tr ',' '\\n' | awk '{\$1=\$1; print}')

    echo "JSON files to process:"
    echo "\$json_files_clean"

    # Core metadata extraction with error checking
    echo "Extracting core metadata..."

    if ! checksum=\$(source ${binfolder}/utils.sh; get_checksum ${path} ${filename}); then
        echo "ERROR: Failed to get checksum"
        exit 1
    fi

    if ! total_tic=\$(source ${binfolder}/parsing.sh; get_mzml_param_by_cv ${mzml_file} MS:1000285); then
        echo "ERROR: Failed to get total TIC"
        exit 1
    fi
    total_tic=\$(echo "\$total_tic * 0.0000000001" | bc -l)

    if ! mit_ms1=\$(source ${binfolder}/parsing_qcloud.sh; get_mit ${mzml_file} MS:1000511 1 MS:1000927); then
        echo "ERROR: Failed to get MIT MS1"
        exit 1
    fi

    if ! mit_ms2=\$(source ${binfolder}/parsing_qcloud.sh; get_mit ${mzml_file} MS:1000511 2 MS:1000927); then
        echo "ERROR: Failed to get MIT MS2"
        exit 1
    fi

    if ! creation_date=\$(source ${binfolder}/utils.sh; get_mzml_date ${mzml_file}); then
        echo "ERROR: Failed to get creation date"
        exit 1
    fi

    # Parse filename info
    basename_sh=\$(basename ${mzml_file} | cut -f 1 -d '.')
    reversed_filename=\$(echo \$basename_sh | rev)
    first_3_underscores=\$(echo \$reversed_filename | cut -d'_' -f1-3)
    reversed_first_3_underscores=\$(echo \$first_3_underscores | rev)
    rest_of_filename=\$(echo \$reversed_filename | cut -d'_' -f4-)
    reversed_rest_of_filename=\$(echo \$rest_of_filename | rev)
    labsysid=\$(echo \$reversed_first_3_underscores | cut -d'_' -f1)

    # DEBUGGING: Print the labsysid to understand what we're getting
    echo "DEBUG: labsysid extracted: '\$labsysid'"
    echo "DEBUG: Full filename breakdown:"
    echo "  basename_sh: \$basename_sh"
    echo "  reversed_filename: \$reversed_filename"
    echo "  first_3_underscores: \$first_3_underscores"
    echo "  reversed_first_3_underscores: \$reversed_first_3_underscores"

    # FIXED: Check if labsysid is a valid UUID format
    uuid_regex='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\$'
    if [[ ! \$labsysid =~ \$uuid_regex ]]; then
        echo "ERROR: labsysid '\$labsysid' is not a valid UUID format"
        echo "The API expects a UUID like: 550e8400-e29b-41d4-a716-446655440000"
        echo "But got: \$labsysid"
        
        # Option 1: Try to find UUID in filename
        echo "Searching for UUID pattern in filename..."
        uuid_from_filename=\$(echo "\$basename_sh" | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -1)
        
        if [[ -n "\$uuid_from_filename" ]]; then
            echo "Found UUID in filename: \$uuid_from_filename"
            labsysid="\$uuid_from_filename"
        else
            echo "No UUID found in filename. You need to either:"
            echo "1. Ensure your filename contains a valid UUID"
            echo "2. Modify the parsing logic to extract the correct UUID"
            echo "3. Use a different API endpoint that accepts non-UUID identifiers"
            exit 1
        fi
    fi

    echo "Using labsysid: \$labsysid"

    insert_file_string='{"creationDate": "'\$creation_date'","filename": "'\$reversed_rest_of_filename'","checksum": "'\$checksum'"}'
    echo \$insert_file_string > insert_file_string

    # DEBUGGING: Show the JSON content
    echo "DEBUG: File metadata JSON:"
    cat insert_file_string

    # Define peptides
    peptides=(
        "582.3 LVN"
        "722.3 YIC"
        "653.3 HLV"
        "756.4 VPQ"
        "554.2 EAC"
        "751.8 EYE"
        "583.8 ECC"
        "710.3 SLH"
        "488.5 TCV"
        "517.7 NEC"
    )

    # Extract clean sample ID
    sample_id_file=${mzml_file}
    sample_id_name=\$(basename "\$sample_id_file")
    sample_id=\${sample_id_name%.raw.mzML}

    # Load functions
    source ${binfolder}/parsing_qcloud.sh

    # Process JSON files
    while IFS= read -r json_file; do
        [[ -z "\$json_file" ]] && continue
        
        echo "Processing JSON file: \$json_file"
        
        if [[ ! -f "\$json_file" ]]; then
            echo "WARNING: JSON file \$json_file not found. Skipping."
            continue
        fi

        json_filename=\$(basename "\$json_file")

        # Determine metric type
        if [[ "\$json_filename" == FWHM* ]]; then
            param_id="QC:1000894"
        elif [[ "\$json_filename" == Log2_Total_Area* ]]; then
            param_id="QC:1001844"
        elif [[ "\$json_filename" == Observed_RT_sec* ]]; then
            param_id="QC:1000894"
        elif [[ "\$json_filename" == dmz_ppm* ]]; then
            param_id="QC:1000014"
        else
            echo "WARNING: Unknown metric for \$json_file. Skipping."
            continue
        fi

        for entry in "\${peptides[@]}"; do
            mz=\$(echo "\$entry" | awk '{print \$1}')
            peptide=\$(echo "\$entry" | cut -d' ' -f2-)
            echo "Extracting QC summary for peptide: \$peptide from \$json_file"

            if ! extract_peptide_metrics_qcsummary "\$json_file" "\$peptide" "\$sample_id" "\$checksum" "\$param_id"; then
                echo "WARNING: Failed to extract metrics for peptide \$peptide"
            fi
        done
    done <<< "\$json_files_clean"

    echo "All peptides processed successfully."

    # Get access token
    echo "Getting access token..."
    if ! access_token=\$(source ${binfolder}/api.sh; get_api_access_token_qcloud ${url_api_qcloud_signin} ${url_api_qcloud_user} ${url_api_qcloud_pass}); then
        echo "ERROR: Failed to get access token"
        exit 1
    fi

    echo "Inserting file metadata to QCloud..."
    echo "DEBUG: Using URL: ${url_api_qcloud_insert_file}/QC:0000005/\$labsysid"

    # FIXED: Better error handling and response capture
    response=\$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST \\
        -H "Authorization: \$access_token" \\
        -H "Content-Type: application/json" \\
        "${url_api_qcloud_insert_file}/QC:0000005/\$labsysid" \\
        --data @insert_file_string)

    http_code=\$(echo \$response | tr -d '\\n' | sed -e 's/.*HTTPSTATUS://')
    body=\$(echo \$response | sed -e 's/HTTPSTATUS:.*//')

    echo "HTTP Status: \$http_code"
    echo "Response: \$body"

    if [[ \$http_code -ne 200 && \$http_code -ne 201 ]]; then
        echo "ERROR: Failed to insert file metadata (HTTP \$http_code)"
        echo "Response: \$body"
        exit 1
    fi

    # Insert peptide metrics with better error handling
    echo "Inserting peptide metrics to QCloud..."
    for param in QC_0000048 QC_1000927 QC_1000928 QC_1001844 QC_1000894 QC_1000014; do
        json_file="\${checksum}_\${param}.json"
        if [[ -f "\$json_file" ]]; then
            echo "Posting \$json_file"
            
            # DEBUGGING: Show JSON content before posting
            echo "DEBUG: Content of \$json_file:"
            head -5 "\$json_file"
            
            response=\$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST \\
                -H "Authorization: \$access_token" \\
                -H "Content-Type: application/json" \\
                "${url_api_qcloud_insert_data}" \\
                --data @\$json_file)

            http_code=\$(echo \$response | tr -d '\\n' | sed -e 's/.*HTTPSTATUS://')
            body=\$(echo \$response | sed -e 's/HTTPSTATUS:.*//')

            echo "HTTP Status: \$http_code"
            echo "Response: \$body"

            if [[ \$http_code -ne 200 && \$http_code -ne 201 ]]; then
                echo "WARNING: Failed to post \$json_file (HTTP \$http_code)"
                echo "Response: \$body"
            else
                echo "Successfully posted \$json_file"
            fi
        else
            echo "WARNING: JSON file \$json_file not found. Skipping."
        fi
    done
    echo "QCloud insertion process completed."
    """
}
