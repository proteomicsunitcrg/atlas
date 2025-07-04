process EXTRACT_METADATA {
    label 'clitools'
    tag { "${mzml_file}" }
    
    input:
    tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
    
    output:
    path "metadata.json", emit: metadata_json
    tuple val(basename_mzml), path("*_QC_*.json"), emit: qc_jsons, optional: true
    
    script:
    """
    # Copy bash scripts to working directory
    cp ${params.scripts_folder}/parsing_qcloud.sh .
    
    # Make scripts executable
    chmod +x parsing_qcloud.sh
    
    # Source the bash functions
    source parsing_qcloud.sh
    
    # Use config file from params
    config_file="${params.home_dir}/mygit/atlas-config/atlas-test/conf/tools/qcloud.config"
    
    # Extract general metrics using your function with config file
    echo "Extracting general metrics using config-driven approach..."
    echo "Using config file: \$config_file"
    metrics_result=\$(extract_general_metrics ${mzml_file} \$config_file)
    
    # Parse the returned values (tic,mit_ms1,mit_ms2,checksum,uuid)
    tic=\$(echo \$metrics_result | cut -d',' -f1)
    mit_ms1=\$(echo \$metrics_result | cut -d',' -f2)
    mit_ms2=\$(echo \$metrics_result | cut -d',' -f3)
    checksum=\$(echo \$metrics_result | cut -d',' -f4)
    labsysid=\$(echo \$metrics_result | cut -d',' -f5)
    
    # Extract sample ID from filename
    sample_id=\$(extract_sample_id_from_filename ${mzml_file})
    
    # Get creation date
    creation_date=\$(stat -c %y ${mzml_file} | cut -d'.' -f1 | sed 's/ /T/')
    
    echo "Extracted values: TIC=\$tic, MIT_MS1=\$mit_ms1, MIT_MS2=\$mit_ms2"
    echo "Sample ID: \$sample_id"
    echo "Lab System ID: \$labsysid"
    echo "Checksum: \$checksum"
    echo "Creation Date: \$creation_date"
    
    # Create a summary metadata JSON
    cat > metadata.json << EOL
{
  "checksum": "\$checksum",
  "labsysid": "\$labsysid",
  "sample_id": "\$sample_id",
  "creation_date": "\$creation_date",
  "mzml_file": "${mzml_file}",
  "config_file": "\$config_file",
  "tic": "\$tic",
  "mit_ms1": "\$mit_ms1",
  "mit_ms2": "\$mit_ms2"
}
EOL
    
    echo "Metadata extraction completed for ${mzml_file}"
    echo "Generated files:"
    ls -la *.json
    """
}
