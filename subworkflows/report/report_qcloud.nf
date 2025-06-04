// Process for uploading TIC and MIT (MS1) data to QCloud
process insertIdentDataToQCloud {

    tag { "${csv_file}" }
    label 'clitools'

    input:
    tuple val(filename), val(basename), val(path)
    tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
    file (csv_file)

    shell:
    """
    # Load reusable bash helpers
    binfolder="!{binfolder}"
    source \${binfolder}/qcloud_helpers.sh
    source \${binfolder}/parsing_qcloud.sh

    # Set constants from params
    context_tic="!{params.qcloud_contexts.tic}"
    context_mit="!{params.qcloud_contexts.mit}"
    term_tic="!{params.qcloud_terms.tic}"
    term_mit_ms1="!{params.qcloud_terms.mit_ms1}"
    ms_total="!{params.ms_params.total_tic}"
    ms_type="!{params.ms_params.ms_type}"

    # Extract metadata
    IFS="|" read -r sample_id labsysid <<< \$(get_sample_info !{mzml_file})
    checksum=\$(source \$binfolder/utils.sh; get_checksum !{path} !{filename})
    creation_date=\$(source \$binfolder/utils.sh; get_mzml_date !{mzml_file})

    # Generate insert and data JSONs
    generate_insert_file_json "\$creation_date" "\$sample_id" "\$checksum"
    create_qcloud_json "\$checksum" "\$context_tic" "\$term_tic"
    create_qcloud_json "\$checksum" "\$context_mit" "\$term_mit_ms1"

    # Extract values
    total_tic=\$(source \$binfolder/parsing.sh; get_mzml_param_by_cv !{mzml_file} \$ms_total)
    total_tic=\$(echo "\$total_tic * 0.0000000001" | bc -l)
    mit_ms1=\$(get_mit !{mzml_file} \$ms_type 1 \$term_mit_ms1)

    # Set values in JSON
    set_value_to_qcloud_json "\$checksum" "\$total_tic" "\$context_tic" "\$term_tic"
    set_value_to_qcloud_json "\$checksum" "\$mit_ms1" "\$context_mit" "\$term_mit_ms1"

    # Authenticate and upload
    access_token=\$(source \$binfolder/api.sh; get_api_access_token_qcloud !{params.url_api_qcloud_signin} !{params.url_api_qcloud_user} !{params.url_api_qcloud_pass})
    curl -s -X POST -H "Authorization: \$access_token" \
         !{params.url_api_qcloud_insert_file}/\$context_mit/\$labsysid \
         -H "Content-Type: application/json" \
         --data @insert_file_string

    upload_qc_jsons "\$checksum" "\$access_token" "!{params.url_api_qcloud_insert_data}" \
        \${term_tic//:/_} \${term_mit_ms1//:/_}
    """
}


process insertDataToQCloud {

    tag { "${csv_file}" }
    label 'clitools'

    input:
    tuple val(filename), val(basename), val(path)
    tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
    file (csv_file)

    shell:
    """
    binfolder="!{binfolder}"
    source \${binfolder}/qcloud_helpers.sh
    source \${binfolder}/parsing_qcloud.sh

    # Constants from config
    context_tic="!{params.qcloud_contexts.tic}"
    context_mit="!{params.qcloud_contexts.mit}"
    context_peptides="!{params.qcloud_contexts.monitored_peptides}"
    term_tic="!{params.qcloud_terms.tic}"
    term_mit_ms1="!{params.qcloud_terms.mit_ms1}"
    term_mit_ms2="!{params.qcloud_terms.mit_ms2}"
    term_area="!{params.qcloud_terms.area}"
    term_rt="!{params.qcloud_terms.rt}"
    term_dppm="!{params.qcloud_terms.dppm}"
    ms_total="!{params.ms_params.total_tic}"
    ms_type="!{params.ms_params.ms_type}"
    declare -A peptides=(${params.peptides.collect { k,v -> "[$k]=\"$v\"" }.join(" ")})

    # Metadata
    IFS="|" read -r sample_id labsysid <<< \$(get_sample_info !{mzml_file})
    checksum=\$(source \$binfolder/utils.sh; get_checksum !{path} !{filename})
    creation_date=\$(source \$binfolder/utils.sh; get_mzml_date !{mzml_file})

    # Create JSONs
    generate_insert_file_json "\$creation_date" "\$sample_id" "\$checksum"
    create_qcloud_json "\$checksum" "\$context_tic" "\$term_tic"
    create_qcloud_json "\$checksum" "\$context_mit" "\$term_mit_ms1"
    create_qcloud_json "\$checksum" "\$context_mit" "\$term_mit_ms2"
    create_qcloud_json_monitored_peptides "\$checksum" "\$term_area"
    create_qcloud_json_monitored_peptides "\$checksum" "\$term_rt"
    create_qcloud_json_monitored_peptides "\$checksum" "\$term_dppm"

    # Values
    total_tic=\$(source \$binfolder/parsing.sh; get_mzml_param_by_cv !{mzml_file} \$ms_total)
    total_tic=\$(echo "\$total_tic * 0.0000000001" | bc -l)
    mit_ms1=\$(get_mit !{mzml_file} \$ms_type 1 \$term_mit_ms1)
    mit_ms2=\$(get_mit !{mzml_file} \$ms_type 2 \$term_mit_ms2)

    set_value_to_qcloud_json "\$checksum" "\$total_tic" "\$context_tic" "\$term_tic"
    set_value_to_qcloud_json "\$checksum" "\$mit_ms1" "\$context_mit" "\$term_mit_ms1"
    set_value_to_qcloud_json "\$checksum" "\$mit_ms2" "\$context_mit" "\$term_mit_ms2"

    for pep in "\${!peptides[@]}"; do
        fullname=\${peptides[\$pep]}
        area=\$(get_value_from_qcloud_json Log2_Total_Area_\${sample_id}_mqc.json "\$pep" "\$sample_id")
        rt=\$(get_value_from_qcloud_json Observed_RT_sec_\${sample_id}_mqc.json "\$pep" "\$sample_id")
        dppm=\$(get_value_from_qcloud_json dmz_ppm_\${sample_id}_mqc.json "\$pep" "\$sample_id")

        set_value_to_qcloud_json_monitored_peptides "\$checksum" "\$area" "\$term_area" "\$fullname"
        set_value_to_qcloud_json_monitored_peptides "\$checksum" "\$rt" "\$term_rt" "\$fullname"
        set_value_to_qcloud_json_monitored_peptides "\$checksum" "\$dppm" "\$term_dppm" "\$fullname"
    done

    access_token=\$(source \$binfolder/api.sh; get_api_access_token_qcloud !{params.url_api_qcloud_signin} !{params.url_api_qcloud_user} !{params.url_api_qcloud_pass})
    curl -s -X POST -H "Authorization: \$access_token" \
         !{params.url_api_qcloud_insert_file}/\$context_peptides/\$labsysid \
         -H "Content-Type: application/json" --data @insert_file_string

    upload_qc_jsons "\$checksum" "\$access_token" "!{params.url_api_qcloud_insert_data}" \
        \${term_tic//:/_} \${term_mit_ms1//:/_} \${term_mit_ms2//:/_} \
        \${term_area//:/_} \${term_rt//:/_} \${term_dppm//:/_}
    """
}
