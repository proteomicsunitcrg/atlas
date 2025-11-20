process PROCESS_FRAGPIPE_PEPTIDES {
    
    input:
    tuple val(sample_id), path(combined_ion_tsv), path(psm_tsv)
    path(peptides_tsv)
    
    output:
    tuple val(sample_id), path("*_QC_*.json"), emit: peptide_jsons
    
    script:
    """
    # Copy the parsing script
    cp ${baseDir}/bin/parsing_qcloud.sh .
    
    # Source the parsing functions
    source parsing_qcloud.sh
    
    # Construct config file path
    config_file="${params.home_dir}/mygit/atlas-config/atlas-test/conf/tools/qcloud.config"
    
    echo "Extracting peptide metrics from FragPipe outputs for sample: ${sample_id}"
    echo "Using combined_ion.tsv: ${combined_ion_tsv}"
    echo "Using psm.tsv: ${psm_tsv}"
    echo "Using peptides file: ${peptides_tsv}"
    echo "Using config file: \$config_file"
    
    # Call the extraction function with both files
    extract_peptide_metrics_from_fragpipe "${combined_ion_tsv}" "${psm_tsv}" "${peptides_tsv}" "\$config_file" "${sample_id}"
    
    echo "Generated peptide JSON files:"
    ls -la *_QC_*.json
    """
}