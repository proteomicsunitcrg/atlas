process EXTRACT_FRAGPIPE_METRICS {
    
    input:
    tuple val(sample_id), path(protein_tsv), path(peptide_tsv), path(psm_tsv)
    
    output:
    tuple val(sample_id), path("*_QC_*.json"), emit: fragpipe_jsons
    path "fragpipe_metadata.json", emit: metadata
    
    script:
    """
    # Copy the parsing script
    cp ${baseDir}/bin/parsing_qcloud.sh .
    
    # Source the parsing functions
    source parsing_qcloud.sh
    
    # Construct config file path the same way as your other scripts
    config_file="${params.home_dir}/mygit/atlas-config/atlas-test/conf/tools/qcloud.config"
    
    echo "Extracting FragPipe metrics for sample: ${sample_id}"
    echo "Processing files: ${protein_tsv}, ${peptide_tsv}, ${psm_tsv}"
    echo "Using config file: \$config_file"
    
    # Show file sizes for debugging
    echo "File sizes:"
    wc -l ${protein_tsv} ${peptide_tsv} ${psm_tsv}
    
    # Use the constructed config_file path instead of params.qcloud_config
    extract_fragpipe_metrics "${protein_tsv}" "${peptide_tsv}" "${psm_tsv}" "\$config_file" "${sample_id}"
    
    # Create metadata file
    echo '{"fragpipe_metrics_extracted": true, "sample_id": "${sample_id}"}' > fragpipe_metadata.json
    
    echo "Generated FragPipe JSON files:"
    ls -la *_QC_*.json
    """
}
