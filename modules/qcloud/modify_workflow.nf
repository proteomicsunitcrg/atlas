process MODIFY_FRAGPIPE_WORKFLOW {
    
    tag { "${sample_id}" }
    
    input:
    tuple val(sample_id), path(instrument_accession_file)
    path original_workflow
    path instruments_table
    
    output:
    tuple val(sample_id), path("fragpipe_modified.workflow"), emit: modified_workflow
    
    script:
    """
    echo "Processing instrument info for sample: ${sample_id}"
    echo "Original workflow: ${original_workflow}"
    echo "Instruments table: ${instruments_table}"
    
    # Read the instrument identifier from the file (could be model name or MS accession)
    identifier=\$(cat ${instrument_accession_file})
    echo "Instrument identifier from file: \$identifier"
    
    # Look up the fragment tolerance in the instruments table
    if [[ "\$identifier" != "unknown" && -f "${instruments_table}" ]]; then
        # Try to find by instrument model name (column 1) first
        fragment_tolerance=\$(awk -F'\t' -v id="\$identifier" 'NR>1 && \$1==id {print \$3}' ${instruments_table})
        
        if [[ -n "\$fragment_tolerance" ]]; then
            echo "Found instrument by model name in table: fragment_tolerance=\$fragment_tolerance"
        else
            # If not found, try to find by MS accession (column 2)
            fragment_tolerance=\$(awk -F'\t' -v id="\$identifier" 'NR>1 && \$2==id {print \$3}' ${instruments_table})
            
            if [[ -n "\$fragment_tolerance" ]]; then
                echo "Found instrument by MS accession in table: fragment_tolerance=\$fragment_tolerance"
            else
                # Not found in table - check if it matches high-resolution pattern
                identifier_lower=\$(echo "\$identifier" | tr '[:upper:]' '[:lower:]')
                if [[ "\$identifier_lower" == *"exactive"* || "\$identifier_lower" == *"exploris"* ]]; then
                    fragment_tolerance="0.02"
                    echo "Instrument identifier '\$identifier' not found in table"
                    echo "Pattern matched (exactive/exploris) - using fragment_tolerance=0.02"
                else
                    echo "Instrument identifier '\$identifier' not found in table, using default 0.5"
                    fragment_tolerance="0.5"
                fi
            fi
        fi
    else
        echo "Unknown instrument or missing table, using default fragment_tolerance=0.5"
        fragment_tolerance="0.5"
    fi
    
    echo "Using fragment_tolerance: \$fragment_tolerance"
    
    # Copy original workflow and modify the fragment mass tolerance
    cp ${original_workflow} fragpipe_modified.workflow
    
    # Replace the fragment mass tolerance with the determined value
    if grep -q "msfragger.fragment_mass_tolerance" fragpipe_modified.workflow; then
        # Replace existing line
        sed -i "s/msfragger.fragment_mass_tolerance=.*/msfragger.fragment_mass_tolerance=\$fragment_tolerance/" fragpipe_modified.workflow
        echo "Updated existing parameter: msfragger.fragment_mass_tolerance=\$fragment_tolerance"
    else
        # Add new line if it doesn't exist
        echo "msfragger.fragment_mass_tolerance=\$fragment_tolerance" >> fragpipe_modified.workflow
        echo "Added new parameter: msfragger.fragment_mass_tolerance=\$fragment_tolerance"
    fi
    
    # Fix the FASTA database path to match the actual FASTA file provided
    echo "Updating FASTA database path..."
    if grep -q "database.db-path=" fragpipe_modified.workflow; then
        # Replace with the correct FASTA filename
        sed -i "s|database.db-path=.*|database.db-path=sp_bovine_decoy_cont_formatted.fasta|" fragpipe_modified.workflow
        echo "Updated FASTA path to: sp_bovine_decoy_cont_formatted.fasta"
    else
        echo "database.db-path=sp_bovine_decoy_cont_formatted.fasta" >> fragpipe_modified.workflow
        echo "Added FASTA path: sp_bovine_decoy_cont_formatted.fasta"
    fi
    
    # Show the final configuration for verification
    echo "Final configuration:"
    grep "msfragger.fragment_mass_tolerance" fragpipe_modified.workflow
    grep "database.db-path" fragpipe_modified.workflow
    
    echo "Workflow modification completed successfully for ${sample_id}"
    """
}
