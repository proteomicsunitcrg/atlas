process EXTRACT_INSTRUMENT_INFO {
    
    label 'rawrr'
    tag { "${basename}" }
    
    input:
    tuple val(filename), val(basename), val(path), file(mzml_file)
    
    output:
    tuple val(basename), path("instrument_accession"), emit: instrument_info
    
    script:
    def raw_file = "${path}/${filename}"
    """
    echo "=== Instrument Information Extraction ==="
    echo "Basename: ${basename}"
    echo "RAW file path: ${raw_file}"
    echo "mzML file: ${mzml_file}"
    echo ""
    
    # Initialize variables
    accession=""
    extraction_method=""
    
    # Debug: Check file existence
    echo ""
    echo "=== File Existence Check ==="
    echo "Original RAW file path: ${raw_file}"
    if [[ -f "${raw_file}" ]]; then
        echo "✓ Original file exists"
        ls -lh "${raw_file}"
    else
        echo "✗ Original file NOT found"
        echo "Directory listing:"
        ls -la "\$(dirname "${raw_file}")" 2>/dev/null | head -20
    fi
    echo ""
    
    # Method 1: Try extracting from RAW file using rawrr (if RAW file exists and container is available)
    # Note: Use the original file path as-is, rawrr can handle .raw.SP_Bovine extensions
    if [[ -f "${raw_file}" ]]; then
        echo "=== RAW File Extraction (Primary Method) ==="
        echo "Attempting to extract instrument model from RAW file using rawrr..."
        echo "Using RAW file: ${raw_file}"
        
        # Extract instrument model using rawrr (container is automatically bound via label)
        instrument_model=\$(Rscript -e "library(rawrr); cat(rawrr::readFileHeader('${raw_file}')\\\$'Instrument model')" 2>&1)
        rscript_exit=\$?
        
        echo "Rscript exit code: \$rscript_exit"
        echo "Extracted value: '\$instrument_model'"
        
        # Check if extraction was successful (non-empty and doesn't contain error messages)
        if [[ \$rscript_exit -eq 0 && -n "\$instrument_model" && ! "\$instrument_model" =~ "Error" ]]; then
            echo "✓ Successfully extracted instrument model from RAW: \$instrument_model"
            # Store the instrument model as the accession (will be looked up later in MODIFY_FRAGPIPE_WORKFLOW)
            accession="\$instrument_model"
            extraction_method="rawrr"
        else
            echo "✗ Could not extract instrument model from RAW file"
            if [[ \$rscript_exit -ne 0 ]]; then
                echo "Reason: Rscript command failed (exit code: \$rscript_exit)"
            fi
            echo "Will fall back to mzML extraction..."
        fi
    else
        echo "RAW file not found, using mzML extraction..."
    fi
    
    # Method 2: Fall back to mzML extraction if RAW extraction failed
    if [[ -z "\$accession" ]]; then
        echo ""
        echo "=== mzML Extraction (Fallback) ==="
        echo "Attempting to extract instrument accession from mzML..."
        echo "mzML file: ${mzml_file}"
        
        # Check if mzML file exists and is readable
        if [[ -f "${mzml_file}" ]]; then
            echo "✓ mzML file exists"
            ls -lh "${mzml_file}"
            
            # Try extraction with detailed error reporting
            echo "Running xmllint extraction..."
            accession=\$(xmllint --xpath "string(//*[local-name()='referenceableParamGroup'][1]/*[local-name()='cvParam'][1]/@accession)" ${mzml_file} 2>&1)
            extraction_exit=\$?
            
            echo "xmllint exit code: \$extraction_exit"
            echo "Extracted value: '\$accession'"
            
            # Check if we got a valid MS accession
            if [[ -n "\$accession" && "\$accession" == MS:* ]]; then
                echo "✓ Successfully extracted MS accession from mzML: \$accession"
                extraction_method="mzML"
            else
                echo "✗ No valid MS accession found"
                echo "Trying alternative extraction method..."
                
                # Try extracting the first cvParam in the file
                alt_accession=\$(xmllint --xpath "string(//*[local-name()='cvParam'][1]/@accession)" ${mzml_file} 2>/dev/null || echo "")
                if [[ -n "\$alt_accession" ]]; then
                    echo "Found alternative accession: \$alt_accession"
                    accession="\$alt_accession"
                    extraction_method="mzML"
                else
                    echo "✗ Alternative extraction also failed"
                    accession="unknown"
                    extraction_method="failed"
                fi
            fi
        else
            echo "✗ mzML file NOT found: ${mzml_file}"
            accession="unknown"
            extraction_method="failed"
        fi
    fi
    
    # Write results
    echo ""
    echo "=== Extraction Results ==="
    echo "Method: \$extraction_method"
    echo "Accession/Model: \$accession"
    echo "\$accession" > instrument_accession
    echo ""
    echo "Instrument extraction completed"
    """
}