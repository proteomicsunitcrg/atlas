// Fires as early as possible in the pipeline (in parallel with the real
// conversion/search-engine work, no dependency on their output) so the
// dashboard's "Time to process" can measure pure compute duration, excluding
// any Slurm queue wait between trigger.sh registering the file as received
// and the pipeline actually starting to run it. Best-effort: never fails
// the real pipeline run over this.
process MARK_PROCESSING_STARTED {
    label 'clitools'
    tag { "${basename}" }

    input:
    tuple val(filename), val(basename), val(path)

    output:
    val true, emit: done

    script:
    """
    cp ${projectDir}/bin/api.sh .
    chmod +x api.sh

    checksum=\$(md5sum "${path}/${filename}" 2>/dev/null | awk '{print \$1}')
    if [[ -z "\$checksum" ]]; then
        echo "WARNING: MARK_PROCESSING_STARTED could not checksum ${filename}, skipping."
        exit 0
    fi

    if ! access_token=\$(source api.sh; get_api_access_token_qcloud ${params.url_api_qcloud_signin} ${params.url_api_qcloud_user} ${params.url_api_qcloud_pass}); then
        echo "WARNING: MARK_PROCESSING_STARTED could not authenticate against QCloud2, skipping."
        exit 0
    fi

    insert_file_url="${params.url_api_qcloud_insert_file}"
    # -k: this is CRG-internal Atlas -> QCloud2 traffic (never external
    # clients); qcloudtest.crg.eu has no valid cert of its own (shares
    # *.qcloud2.crg.eu's, wrong SAN).
    http_code=\$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 \\
        -X POST -H "Authorization: \$access_token" \\
        "\${insert_file_url%/api/file}/api/pipelineFile/processingStarted/\$checksum" \\
        || echo "000")

    echo "MARK_PROCESSING_STARTED: HTTP \$http_code for checksum=\$checksum"
    """
}
