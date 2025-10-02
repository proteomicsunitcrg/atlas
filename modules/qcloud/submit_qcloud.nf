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
    QCLOUD_USERNAME="!{params.url_api_qcloud_user}"
    QCLOUD_PASSWORD="!{params.url_api_qcloud_pass}"
    QCLOUD_SAMPLE_TYPE="!{sample_type}"
    
    # QCloud API URLs - using direct URLs from config
    QCLOUD_AUTH_URL="!{params.url_api_qcloud_signin}"
    QCLOUD_DATA_URL="!{params.url_api_qcloud_insert_data}"
    QCLOUD_FILE_URL="!{params.url_api_qcloud_insert_file}"
    
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
    
    # Validate API URLs are not empty
    if [ -z "$QCLOUD_AUTH_URL" ] || [ "$QCLOUD_AUTH_URL" = "null" ]; then
        echo "ERROR: QCLOUD_AUTH_URL is not set or empty"
        exit 14
    fi
    
    if [ -z "$QCLOUD_DATA_URL" ] || [ "$QCLOUD_DATA_URL" = "null" ]; then
        echo "ERROR: QCLOUD_DATA_URL is not set or empty"
        exit 15
    fi
    
    if [ -z "$QCLOUD_FILE_URL" ] || [ "$QCLOUD_FILE_URL" = "null" ]; then
        echo "ERROR: QCLOUD_FILE_URL is not set or empty"
        exit 16
    fi
    
    # Get access token with timeout and retry
    echo "========================================="
    echo "STEP 1: AUTHENTICATION"
    echo "========================================="
    echo "Attempting to authenticate with QCloud API..."
    echo "Auth URL: ${QCLOUD_AUTH_URL}"
    echo "Username: ${QCLOUD_USERNAME}"
    echo "Password: [HIDDEN]"
    
    # Prepare authentication payload
    AUTH_PAYLOAD="{\\"username\\": \\"${QCLOUD_USERNAME}\\", \\"password\\": \\"${QCLOUD_PASSWORD}\\"}"
    echo "Auth payload: {\\"username\\": \\"${QCLOUD_USERNAME}\\", \\"password\\": \\"[HIDDEN]\\"}"
    
    # Add timeout and connection settings to curl
    echo "Sending authentication request..."
    TOKEN_RESPONSE=$(curl -s --connect-timeout 30 --max-time 60 -X POST "${QCLOUD_AUTH_URL}" \\
        -H "Content-Type: application/json" \\
        -d "$AUTH_PAYLOAD")
    
    CURL_EXIT_CODE=$?
    echo "Authentication curl exit code: $CURL_EXIT_CODE"
    
    if [ $CURL_EXIT_CODE -ne 0 ]; then
        echo "ERROR: Failed to get access token (curl exit code: $CURL_EXIT_CODE)"
        case $CURL_EXIT_CODE in
            6) echo "  - Could not resolve host: ${QCLOUD_AUTH_URL}" ;;
            7) echo "  - Failed to connect to host: ${QCLOUD_AUTH_URL}" ;;
            28) echo "  - Operation timeout (30s connect, 60s total)" ;;
            35) echo "  - SSL connect error" ;;
            52) echo "  - Empty reply from server" ;;
            56) echo "  - Failure in receiving network data" ;;
            *) echo "  - Unknown curl error: $CURL_EXIT_CODE" ;;
        esac
        echo "Raw response: $TOKEN_RESPONSE"
        exit 1
    fi
    
    echo "Authentication response received successfully"
    echo "Raw token response: $TOKEN_RESPONSE"
    
    # FIXED: Use the same token extraction method as working template (grep/sed instead of jq)
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -Po '"token" : *\\K"[^"]*"' | sed 's/"//g')
    
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        echo "ERROR: Invalid access token received"
        echo "Token response: $TOKEN_RESPONSE"
        
        # Try to extract error message if present
        ERROR_MSG=$(echo "$TOKEN_RESPONSE" | jq -r '.error // .message // empty')
        if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
            echo "API Error: $ERROR_MSG"
        fi
        exit 2
    fi
    
    echo "SUCCESS: Access token obtained successfully"
    echo "Token length: ${#ACCESS_TOKEN} characters"
    echo "Token preview: ${ACCESS_TOKEN:0:20}..."
    
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
    echo ""
    echo "========================================="
    echo "STEP 2: FILE REGISTRATION"
    echo "========================================="
    echo "Registering file metadata with QCloud..."
    
    FILE_URL="${QCLOUD_FILE_URL}/${QCLOUD_SAMPLE_TYPE}/${uuid}"
    echo "File registration URL: $FILE_URL"
    echo "Sample type: ${QCLOUD_SAMPLE_TYPE}"
    echo "UUID: ${uuid}"
    
    FILE_JSON="{\\"creationDate\\": \\"${creation_date}\\",\\"filename\\": \\"${cleaned_filename}\\",\\"checksum\\": \\"${checksum}\\"}"
    echo "File registration payload:"
    echo "$FILE_JSON"
    
    echo "Sending file registration request..."
    # FIXED: Use same authorization format and HTTP status capture as working template
    FILE_RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" --connect-timeout 30 --max-time 60 -X POST "$FILE_URL" \\
        -H "Content-Type: application/json" \\
        -H "Authorization: ${ACCESS_TOKEN}" \\
        -d "$FILE_JSON")
    
    FILE_STATUS=$?
    FILE_HTTP_CODE=$(echo $FILE_RESPONSE | tr -d '\\n' | sed -e 's/.*HTTPSTATUS://')
    FILE_BODY=$(echo $FILE_RESPONSE | sed -e 's/HTTPSTATUS:.*//')
    echo "File registration curl exit code: $FILE_STATUS"
    echo "File registration HTTP status: $FILE_HTTP_CODE"
    
    if [ $FILE_STATUS -ne 0 ]; then
        echo "ERROR: Failed to register file (curl error: $FILE_STATUS)"
        case $FILE_STATUS in
            6) echo "  - Could not resolve host: $FILE_URL" ;;
            7) echo "  - Failed to connect to host: $FILE_URL" ;;
            28) echo "  - Operation timeout (30s connect, 60s total)" ;;
            35) echo "  - SSL connect error" ;;
            52) echo "  - Empty reply from server" ;;
            56) echo "  - Failure in receiving network data" ;;
            *) echo "  - Unknown curl error: $FILE_STATUS" ;;
        esac
        echo "Raw response: $FILE_BODY"
        exit 3
    fi
    
    echo "File registration response received successfully"
    echo "Raw file registration response: $FILE_BODY"
    
    # FIXED: Use HTTP status code for success/failure determination like working template
    if [[ $FILE_HTTP_CODE -ne 200 && $FILE_HTTP_CODE -ne 201 ]]; then
        echo "ERROR: Failed to register file (HTTP $FILE_HTTP_CODE)"
        echo "Response: $FILE_BODY"
        exit 4
    fi
    
    echo "SUCCESS: File registered successfully (HTTP $FILE_HTTP_CODE)"
    
    # Submit each JSON file
    echo ""
    echo "========================================="
    echo "STEP 3: QC DATA SUBMISSION"
    echo "========================================="
    echo "Submitting QC data files to QCloud..."
    
    success_count=0
    total_files=0
    
    # Count total JSON files first
    for json_file in *.json; do
        if [ -f "$json_file" ]; then
            total_files=$((total_files + 1))
        fi
    done
    
    echo "Found $total_files JSON files to submit"
    echo "Data submission URL: ${QCLOUD_DATA_URL}"
    echo ""
    
    for json_file in *.json; do
        if [ -f "$json_file" ]; then
            echo "----------------------------------------"
            echo "Processing file: $json_file"
            echo "File size: $(wc -c < "$json_file") bytes"
            
            # Read JSON content
            json_content=$(cat "$json_file")
            
            # Validate JSON content
            if ! echo "$json_content" | jq . > /dev/null 2>&1; then
                echo "WARNING: $json_file contains invalid JSON"
                echo "Content preview: ${json_content:0:200}..."
            else
                echo "JSON validation: PASSED"
                # Show a preview of the JSON structure
                echo "JSON structure preview:"
                echo "$json_content" | jq -r 'keys[]' 2>/dev/null | head -5 | sed 's/^/  - /'
            fi
            
            echo "Submitting to: $DATA_URL"
            echo "Payload size: ${#json_content} characters"
            
            # FIXED: Use same authorization format and HTTP status capture as working template
            RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" --connect-timeout 30 --max-time 60 -X POST "$DATA_URL" \\
                -H "Content-Type: application/json" \\
                -H "Authorization: ${ACCESS_TOKEN}" \\
                -d "$json_content")
            
            CURL_STATUS=$?
            HTTP_CODE=$(echo $RESPONSE | tr -d '\\n' | sed -e 's/.*HTTPSTATUS://')
            BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//')
            
            echo "Curl exit code: $CURL_STATUS"
            echo "HTTP status: $HTTP_CODE"
            
            if [ $CURL_STATUS -eq 0 ]; then
                echo "HTTP request completed successfully"
                echo "Response received: ${#BODY} characters"
                echo "Raw response: $BODY"
                
                # FIXED: Use HTTP status code for success/failure determination like working template
                if [[ $HTTP_CODE -eq 200 || $HTTP_CODE -eq 201 ]]; then
                    echo "RESULT: SUCCESS (HTTP $HTTP_CODE)"
                    success_count=$((success_count + 1))
                else
                    echo "RESULT: API ERROR (HTTP $HTTP_CODE)"
                    echo "Error response: $BODY"
                fi
            else
                echo "RESULT: CURL ERROR"
                case $CURL_STATUS in
                    6) echo "  - Could not resolve host: $DATA_URL" ;;
                    7) echo "  - Failed to connect to host: $DATA_URL" ;;
                    28) echo "  - Operation timeout (30s connect, 60s total)" ;;
                    35) echo "  - SSL connect error" ;;
                    52) echo "  - Empty reply from server" ;;
                    56) echo "  - Failure in receiving network data" ;;
                    *) echo "  - Unknown curl error: $CURL_STATUS" ;;
                esac
                echo "Raw response: $BODY"
            fi
            
            echo "File $json_file processing completed"
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
