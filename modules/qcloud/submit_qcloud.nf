process SUBMIT_TO_QCLOUD {

    tag { "${sample_id}" }

    input:
    path json_files
    val sample_id
    val qcloud_sample_type
    
    output:
    path "qcloud_submission_*.log"
    
    script:
    """
    # Copy the api.sh script to get the authentication function
    cp ${projectDir}/bin/api.sh .
    chmod +x api.sh
    
    echo "Submitting QCloud data for sample: ${sample_id}"
    echo "Using QCloud sample type: ${qcloud_sample_type}"
    echo "Available JSON files:"
    ls -la *.json || echo "No JSON files found"
    
    # API endpoints and credentials from config
    SIGNIN_URL="${params.url_api_qcloud_signin}"
    INSERT_DATA_URL="${params.url_api_qcloud_insert_data}"
    INSERT_FILE_URL="${params.url_api_qcloud_insert_file}"
    API_USER="${params.url_api_qcloud_user}"
    API_PASS="${params.url_api_qcloud_pass}"
    
    echo "API URLs:"
    echo "  Signin: \$SIGNIN_URL"
    echo "  Insert Data: \$INSERT_DATA_URL" 
    echo "  Insert File: \$INSERT_FILE_URL"
    
    # Get access token
    echo "Getting access token..."
    if ! access_token=\$(source ./api.sh; get_api_access_token_qcloud "\$SIGNIN_URL" "\$API_USER" "\$API_PASS"); then
        echo "ERROR: Failed to get access token"
        exit 1
    fi
    
    echo "Access token obtained successfully"
    
    # Extract file metadata from sample_id for file registration
    # Parse sample_id: 2019_QC01_ref_6583a564-93dd-4500-a101-b2fe56496b25_QC01_93d2a97b9d0b35c9668663223bdef998.raw
    reversed_sample_id=\$(echo "${sample_id}" | rev)
    checksum_reversed=\$(echo "\$reversed_sample_id" | cut -d'_' -f1)
    context_code_reversed=\$(echo "\$reversed_sample_id" | cut -d'_' -f2)
    uuid_reversed=\$(echo "\$reversed_sample_id" | cut -d'_' -f3)
    
    # Reverse them back
    checksum=\$(echo "\$checksum_reversed" | rev | sed 's/\\.raw\$//')
    context_code=\$(echo "\$context_code_reversed" | rev)
    uuid=\$(echo "\$uuid_reversed" | rev)
    labsysid="\$uuid"
    
    # Clean filename by removing timestamp, UUID, QC code, and checksum
    # Original: 20250729_C39321_001_autoQC01___20250729170452_f96990c5-5d2a-42ac-8b38-31d341be673d_QC01_e1033c0c2b8f753d87113e72577e4141.raw
    # Desired: 20250729_C39321_001_autoQC01

    echo "Original sample_id: ${sample_id}"

    # Remove .raw extension first
    filename_no_ext=\$(echo "${sample_id}" | sed 's/\\.raw\$//')
    echo "Filename without extension: \$filename_no_ext"

    # First, remove the ___timestamp pattern if it exists
    # Pattern: ___YYYYMMDDHHMMSS (e.g., ___20250729170452)
    filename_no_timestamp=\$(echo "\$filename_no_ext" | sed 's/___[0-9]\\{14\\}//')
    echo "Filename after removing timestamp: \$filename_no_timestamp"

    # Now apply the existing reverse parsing logic to remove UUID, QC code, and checksum
    # Reverse filename, split by "_", remove first 3 elements, reverse back
    reversed_filename=\$(echo "\$filename_no_timestamp" | rev)
    echo "Reversed filename: \$reversed_filename"

    # Split by underscore and convert to array
    IFS='_' read -ra parts <<< "\$reversed_filename"
    echo "Number of parts: \${#parts[@]}"

    # Check if we have enough parts to remove (need at least 4 parts)
    if [ \${#parts[@]} -gt 3 ]; then
        # Remove first 3 elements (checksum, QC code, UUID)
        cleaned_parts=("\${parts[@]:3}")
        
        # Join remaining parts and reverse back
        cleaned_reversed=\$(IFS='_'; echo "\${cleaned_parts[*]}")
        cleaned_filename=\$(echo "\$cleaned_reversed" | rev)
        
        echo "Cleaned filename: \$cleaned_filename"
    else
        # Fallback: use filename without timestamp if not enough parts
        cleaned_filename="\$filename_no_timestamp"
        echo "Warning: Not enough parts for cleaning, using filename without timestamp: \$cleaned_filename"
    fi

    # Use cleaned filename for API
    reversed_rest_of_filename="\$cleaned_filename"
        
    # Get current date in the correct format for QCloud API
    creation_date=\$(date -u +"%Y-%m-%d %H:%M:%S")

    echo "File metadata:"
    echo "  Original filename: ${sample_id}"
    echo "  Cleaned filename: \$reversed_rest_of_filename"
    echo "  Checksum: \$checksum"
    echo "  LabSysID: \$labsysid"
    echo "  Creation Date: \$creation_date"
    
    # Create file registration JSON
    insert_file_string='{"creationDate": "'\$creation_date'","filename": "'\$reversed_rest_of_filename'","checksum": "'\$checksum'"}'
    echo \$insert_file_string > insert_file_string
    
    echo "Inserting file metadata to QCloud..."
    echo "DEBUG: Using URL: \${INSERT_FILE_URL}/${qcloud_sample_type}/\$labsysid"
    echo "DEBUG: File registration JSON:"
    cat insert_file_string
    
    # Register the file first
    response=\$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST \\
        -H "Authorization: \$access_token" \\
        -H "Content-Type: application/json" \\
        "\${INSERT_FILE_URL}/${qcloud_sample_type}/\$labsysid" \\
        --data @insert_file_string)
    
    http_code=\$(echo \$response | tr -d '\\n' | sed -e 's/.*HTTPSTATUS://')
    body=\$(echo \$response | sed -e 's/HTTPSTATUS:.*//')
    
    echo "File registration - HTTP Status: \$http_code"
    echo "File registration - Response: \$body"
    
    if [[ \$http_code -ne 200 && \$http_code -ne 201 ]]; then
        echo "ERROR: Failed to insert file metadata (HTTP \$http_code)"
        echo "Response: \$body"
        exit 1
    fi
    
    echo "File metadata inserted successfully"
    
    # Now submit each QC data JSON file
    echo "Inserting QC data to QCloud..."
    for json_file in *.json; do
        if [[ -f "\$json_file" ]]; then
            echo "Submitting \$json_file..."
            
            # Show JSON content for debugging
            echo "DEBUG: Content of \$json_file:"
            head -5 "\$json_file"
            
            # API call with authentication
            response=\$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST \\
                -H "Authorization: \$access_token" \\
                -H "Content-Type: application/json" \\
                "\$INSERT_DATA_URL" \\
                --data @"\$json_file")
            
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
        fi
    done
    
    echo "QCloud submission completed for ${sample_id}" > qcloud_submission_${sample_id}.log
    """
}