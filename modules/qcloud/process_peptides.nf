process PROCESS_PEPTIDES {
    label 'clitools'
    tag "${mzml_file}"
    
    input:
    tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
    path(msnbasexic_output)
    val(selected_tsv_file)  
    
    output:
    tuple val(basename_mzml), path("*_QC_*.json"), emit: peptide_jsons, optional: true
    path "peptides_summary.json", emit: summary_json
    
    script:
    """
    # Copy bash scripts to working directory
    cp ${params.scripts_folder}/parsing_qcloud.sh .
    
    # Make scripts executable
    chmod +x parsing_qcloud.sh
    
    # Source the bash functions
    source parsing_qcloud.sh
    
    echo "Processing peptides from msnbasexic outputs..."
    echo "mzML file: ${mzml_file}"
    echo "msnbasexic output files: ${msnbasexic_output}"
    
    # Pass the config and dynamically selected TSV file paths from Nextflow to bash function
    process_peptides_from_msnbasexic ${mzml_file} "${params.home_dir}/mygit/atlas-config/atlas-test/conf/tools/qcloud.config" "${selected_tsv_file}" ${msnbasexic_output}
    
    # Create summary
    echo "Peptide processing completed for ${mzml_file}" > peptides_summary.json
    
    echo "Generated peptide JSON files:"
    ls -la *_QC_*.json || echo "No peptide JSON files generated"
    """
}