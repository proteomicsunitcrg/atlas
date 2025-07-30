process EXTRACT_INSTRUMENT_INFO {
    
    tag { "${basename}" }
    
    input:
    tuple val(filename), val(basename), val(path), file(mzml_file)
    
    output:
    tuple val(basename), path("instrument_accession"), emit: instrument_info
    
    script:
    """
    echo "Extracting instrument information from mzML..."
    echo "mzML file: ${mzml_file}"
    
    # Extract instrument accession using xmllint
    accession=\$(xmllint --xpath "string(//*[local-name()='referenceableParamGroup'][1]/*[local-name()='cvParam'][1]/@accession)" ${mzml_file} 2>/dev/null || echo "")
    
    if [[ -z "\$accession" ]]; then
        echo "Warning: Could not extract instrument accession from mzML"
        echo "unknown" > instrument_accession
    else
        echo "Extracted instrument accession: \$accession"
        echo "\$accession" > instrument_accession
    fi
    
    echo "Instrument extraction completed"
    """
}