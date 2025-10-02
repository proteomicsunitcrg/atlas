process SUBMIT_TO_QCLOUD {
    label 'clitools'
    tag { "${sample_id}" }
    
    input:
    path json_files
    val sample_id
    val sample_type
    
    output:
    path "qcloud_submission.log", emit: log
    
    shell:
    '''
    echo "Submitting QCloud data for sample: !{sample_id}"
    echo "Using QCloud sample type: !{sample_type}"
    
    echo "Available JSON files:"
    echo "DIA-NN JSON files:"
    ls -la *_QC_*.json 2>/dev/null || echo "No DIA-NN JSON files found"
    echo "Metadata JSON files:"
    ls -la *.json | grep -v "_QC_" 2>/dev/null || echo "No metadata JSON files found"
    echo "All JSON files:"
    ls -la *.json
    
    # QCloud API configuration
    QCLOUD_BASE_URL="10.102.1.26"
    QCLOUD_USERNAME="!{params.qcloud_username}"
    QCLOUD_PASSWORD="!{params.qcloud_password}"
    QCLOUD_SAMPLE_TYPE="!{sample_type}"
    
    # QCloud API URLs
    QCLOUD_AUTH_URL="${QCLOUD_BASE_URL}/api/auth"
    QCLOUD_DATA_URL="${QCLOUD_BASE_URL}/api/data/pipeline"
    QCLOUD_FILE_URL="${QCLOUD_BASE_URL}/api/file"
    
    # Validate required parameters
    if [ -z "$QCLOUD_USERNAME" ] || [ "$QCLOUD_USERNAME" = "null" ]; then
        echo "ERROR: QCLOUD_USERNAME is not set"
        exit 11
    fi
    
    if [ -z "$QCLOUD_PASSWORD" ] || [ "$QCLOUD_PASSWORD" = "null" ]; then
        echo "ERROR: QCLOUD_PASSWORD is not set"
        exit 12
    fi
    
    if [ -z "$QCLOUD_SAMPLE_TYPE" ] || [ "$QCLOUD_SAMPLE_TYPE" = "null" ]; then
        echo "ERROR: QCLOUD_SAMPLE_TYPE is not set"
        exit 13
    fi
    
    echo "API URLs:"
    echo "  Signin: ${QCLOUD_AUTH_URL}"
    echo "  Insert Data: ${QCLOUD_DATA_URL}"
    echo "  Insert File: ${QCLOUD_FILE_URL}"
    
    # Get access token with timeout and retry
    echo "Getting access token..."
    
    # Add timeout and connection settings to curl
    TOKEN_RESPONSE=$(curl -s --connect-timeout 30 --max-time 60 -X POST "${QCLOUD_AUTH_URL}" \\
        -H "Content-Type: application/json" \\
        -d "{\\"username\\": \\"${QCLOUD_USERNAME}\\", \\"password\\": \\"${QCLOUD_PASSWORD}\\"}")
    
    CURL_EXIT_CODE=$?
    
    if [ $CURL_EXIT_CODE -ne 0 ]; then
        echo "ERROR: Failed to get access token (curl exit code: $CURL_EXIT_CODE)"
        case $CURL_EXIT_CODE in
            6) echo "  - Could not resolve host" ;;
            7) echo "  - Failed to connect to host" ;;
            28) echo "  - Operation timeout" ;;
            35) echo "  - SSL connect error" ;;
            *) echo "  - Unknown curl error" ;;
        esac
        exit 1
    fi
    
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
    
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        echo "ERROR: Invalid access token received"
        echo "Token response: $TOKEN_RESPONSE"
        exit 2
    fi
    
    echo "Access token obtained successfully"
    
    # Extract metadata from sample_id
    echo "Original sample_id: !{sample_id}"
    
    # Remove file extension if present
    filename_no_ext=$(echo "!{sample_id}" | sed 's/\\.[^.]*$//')
    echo "Filename without extension: $filename_no_ext"
    
    # Remove timestamp pattern (YYYYMMDD_) from the beginning if present
    filename_no_timestamp=$(echo "$filename_no_ext" | sed 's/^[0-9]\\{8\\}_//')
    echo "Filename after removing timestamp: $filename_no_timestamp"
    
    # Reverse the filename to extract components from the end
    reversed_filename=$(echo "$filename_no_timestamp" | rev)
    echo "Reversed filename: $reversed_filename"
    
    # Split by underscore and count parts
    IFS='_' read -ra PARTS <<< "$reversed_filename"
    num_parts=${#PARTS[@]}
    echo "Number of parts: $num_parts"
    
    # Extract checksum (last part when reversed = first part originally)
    checksum_reversed=${PARTS[0]}
    checksum=$(echo "$checksum_reversed" | rev)
    
    # Extract context code (second to last part when reversed)
    if [ $num_parts -ge 2 ]; then
        context_reversed=${PARTS[1]}
        context_code=$(echo "$context_reversed" | rev)
    else
        context_code=""
    fi
    
    # Extract UUID (third to last part when reversed)
    if [ $num_parts -ge 3 ]; then
        uuid_reversed=${PARTS[2]}
        uuid=$(echo "$uuid_reversed" | rev)
    else
        uuid=""
    fi
    
    # Reconstruct the cleaned filename (everything except UUID, context, and checksum)
    if [ $num_parts -gt 3 ]; then
        # Get all parts except the last 3 (checksum, context, uuid)
        cleaned_parts=()
        for ((i=3; i<num_parts; i++)); do
            part_reversed=${PARTS[i]}
            part=$(echo "$part_reversed" | rev)
            cleaned_parts=("$part" "${cleaned_parts[@]}")
        done
        # Join with underscores
        cleaned_filename=$(IFS='_'; echo "${cleaned_parts[*]}")
    else
        cleaned_filename="$filename_no_timestamp"
    fi
    
    echo "Cleaned filename: $cleaned_filename"
    
    # Get file creation date (use current date as fallback)
    creation_date=$(date -Iseconds | cut -d'T' -f1,2 | tr 'T' ' ')
    
    echo "File metadata:"
    echo "  Original filename: !{sample_id}"
    echo "  Cleaned filename: $cleaned_filename"
    echo "  Checksum: $checksum"
    echo "  LabSysID: $uuid"
    echo "  Creation Date: $creation_date"
    
    # Insert file metadata to QCloud
    echo "Inserting file metadata to QCloud..."
    
    FILE_URL="${QCLOUD_FILE_URL}/${QCLOUD_SAMPLE_TYPE}/${uuid}"
    echo "DEBUG: Using URL: $FILE_URL"
    
    FILE_JSON="{\\"creationDate\\": \\"${creation_date}\\",\\"filename\\": \\"${cleaned_filename}\\",\\"checksum\\": \\"${checksum}\\"}"
    echo "DEBUG: File registration JSON:"
    echo "$FILE_JSON"
    
    FILE_RESPONSE=$(curl -s --connect-timeout 30 --max-time 60 -X POST "$FILE_URL" \\
        -H "Content-Type: application/json" \\
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \\
        -d "$FILE_JSON")
    
    FILE_STATUS=$?
    echo "DEBUG: File registration curl exit code: $FILE_STATUS"
    echo "DEBUG: File registration response: $FILE_RESPONSE"
    
    if [ $FILE_STATUS -ne 0 ]; then
        echo "ERROR: Failed to register file (curl error: $FILE_STATUS)"
        case $FILE_STATUS in
            6) echo "  - Could not resolve host" ;;
            7) echo "  - Failed to connect to host" ;;
            28) echo "  - Operation timeout" ;;
            35) echo "  - SSL connect error" ;;
            *) echo "  - Unknown curl error" ;;
        esac
        exit 3
    fi
    
    # Check if response indicates success
    if echo "$FILE_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        echo "ERROR: File registration failed with API error"
        echo "Response: $FILE_RESPONSE"
        exit 4
    fi
    
    echo "File registered successfully"
    
    # Submit each JSON file
    echo "Submitting QC data files..."
    
    success_count=0
    total_files=0
    
    for json_file in *.json; do
        if [ -f "$json_file" ]; then
            total_files=$((total_files + 1))
            echo "Processing: $json_file"
            
            # Read JSON content
            json_content=$(cat "$json_file")
            
            # Submit to QCloud
            DATA_URL="${QCLOUD_DATA_URL}"
            
            echo "DEBUG: Submitting to: $DATA_URL"
            echo "DEBUG: JSON content: $json_content"
            
            RESPONSE=$(curl -s --connect-timeout 30 --max-time 60 -X POST "$DATA_URL" \\
                -H "Content-Type: application/json" \\
                -H "Authorization: Bearer ${ACCESS_TOKEN}" \\
                -d "$json_content")
            
            CURL_STATUS=$?
            echo "DEBUG: Curl exit code: $CURL_STATUS"
            echo "DEBUG: Response: $RESPONSE"
            
            if [ $CURL_STATUS -eq 0 ]; then
                # Check if response indicates success
                if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
                    echo "WARNING: API returned error for $json_file: $RESPONSE"
                else
                    echo "SUCCESS: $json_file submitted successfully"
                    success_count=$((success_count + 1))
                fi
            else
                echo "ERROR: Failed to submit $json_file (curl error: $CURL_STATUS)"
                case $CURL_STATUS in
                    6) echo "  - Could not resolve host" ;;
                    7) echo "  - Failed to connect to host" ;;
                    28) echo "  - Operation timeout" ;;
                    35) echo "  - SSL connect error" ;;
                    *) echo "  - Unknown curl error" ;;
                esac
            fi
        fi
    done
    
    echo "Submission summary:"
    echo "  Total files: $total_files"
    echo "  Successful submissions: $success_count"
    echo "  Failed submissions: $((total_files - success_count))"
    
    # Create log file
    cat > qcloud_submission.log << EOF
{
  "sample_id": "!{sample_id}",
  "cleaned_filename": "$cleaned_filename",
  "checksum": "$checksum",
  "uuid": "$uuid",
  "creation_date": "$creation_date",
  "total_files": $total_files,
  "successful_submissions": $success_count,
  "failed_submissions": $((total_files - success_count)),
  "submission_status": "$([ $success_count -eq $total_files ] && echo "complete" || echo "partial")"
}
EOF
    
    # Exit with error if not all files were submitted successfully
    if [ $success_count -ne $total_files ]; then
        echo "ERROR: Not all files were submitted successfully"
        exit 5
    fi
    
    echo "All QCloud submissions completed successfully"
    '''
}
