process INSERT_FILE_METADATA_QCLOUD {
    label 'clitools'
    tag { filename }

    input:
    tuple val(filename), val(basename), val(path)
    file mzml_file
    val url_api_qcloud_signin
    val url_api_qcloud_user
    val url_api_qcloud_pass
    val url_api_qcloud_insert_file
    val binfolder

    output:
    path "${filename}.checksum", emit: checksum
    val(true), emit: metadata_inserted
    val(labsysid), emit: labsysid
    val(checksum), emit: checksum_val

    script:
    """
    set -euo pipefail

    echo "Insert file metadata to QCloud"
    echo "Input file: ${mzml_file}"

    # Get checksum
    checksum=\$(source ${binfolder}/utils.sh; get_checksum ${path} ${filename})
    echo \$checksum > ${filename}.checksum

    # Get creation date
    creation_date=\$(source ${binfolder}/utils.sh; get_mzml_date ${mzml_file})

    # Extract labsysid from filename (UUID format)
    basename_sh=\$(basename ${mzml_file} | cut -f 1 -d '.')
    labsysid=\$(echo \$basename_sh | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -1)

    if [[ -z "\$labsysid" ]]; then
        echo "ERROR: No valid UUID (labsysid) found in filename"
        exit 1
    fi

    # Prepare JSON body
    data_string='{"creationDate": "'\$creation_date'","filename": "'\$basename_sh'","checksum": "'\$checksum'"}'
    echo \$data_string > insert_file_string.json

    # Get token
    access_token=\$(source ${binfolder}/api.sh; get_api_access_token_qcloud ${url_api_qcloud_signin} ${url_api_qcloud_user} ${url_api_qcloud_pass})

    # POST to API
    response=\$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST \\
        -H "Authorization: \$access_token" \\
        -H "Content-Type: application/json" \\
        "${url_api_qcloud_insert_file}/QC:0000005/\$labsysid" \\
        --data @insert_file_string.json)

    http_code=\$(echo \$response | tr -d '\\n' | sed -e 's/.*HTTPSTATUS://')
    body=\$(echo \$response | sed -e 's/HTTPSTATUS:.*//')

    echo "HTTP Status: \$http_code"
    echo "Response: \$body"

    if [[ \$http_code -ne 200 && \$http_code -ne 201 ]]; then
        echo "ERROR: Failed to insert file metadata"
        exit 1
    fi

    echo "Metadata inserted successfully"

    echo \$labsysid > labsysid.txt
    echo \$checksum > checksum_val.txt
    """
}
