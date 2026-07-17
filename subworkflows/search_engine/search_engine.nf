databases_folder         = params.databases_folder
contaminants_file        = params.contaminants_file
contaminants_prefix      = params.contaminants_prefix
tools_folder             = params.tools_folder

search_engine            = params.search_engine

//Comet engine: 
precursor_charge         = params.precursor_charge
comet_executable         = params.comet_executable

//Mascot engine:
search_title             = params.search_title
hostname                 = params.hostname
host_port                = params.host_port
server_path              = params.server_path
timeout                  = params.timeout
username                 = params.username
password                 = params.password
precursor_mass_tolerance = params.precursor_mass_tolerance
precursor_error_units    = params.precursor_error_units
fixed_modifications      = params.fixed_modifications
variable_modifications   = params.variable_modifications
enzyme                   = params.enzyme
fragment_mass_tolerance  = params.fragment_mass_tolerance
fragment_error_units     = params.fragment_error_units
charges                  = params.charges
missed_cleavages         = params.missed_cleavages
batch_size               = params.batch_size
debug_code               = params.debug_code

//FragPipe engine: 
fp_workflow              = params.fp_workflow
fp_tools                 = params.fp_tools
fp_jvm_ram_thermo        = params.fp_jvm_ram_thermo
fp_jvm_ram_bruker        = params.fp_jvm_ram_bruker

//Bash scripts folder:                                                                  
binfolder                = "$baseDir/bin"

process create_decoy {
    label 'openms'
    tag  { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path)

    output:
    file("organism")
    file("*_decoy.fasta")

    shell:
    '''
    filename_sh=!{filename}
    echo $filename_sh > filename_sh
    
    # Extract organism: for .d files, remove .d first, then extract last component
    if [[ $filename_sh == *.d ]]; then
        organism=$(echo ${filename_sh%.d} | rev | cut -d'.' -f1 | rev)
    else
        organism=$(echo ${filename_sh##*.})
    fi
    
    echo $organism > organism
    echo "[INFO] Extracted organism: $organism from $filename_sh"

    fastafile=$(basename !{databases_folder}/${organism}/current/*.fasta)
    echo $fastafile > fastafile
    fastafilename=$(echo ${fastafile%.*})
    echo $fastafilename > fastafilename
    fasta_orig_path=!{databases_folder}/${organism}/current/${fastafile}
    cp $fasta_orig_path .
    echo >> ${fastafile}
    perl !{tools_folder}/mascot/decoy.pl --append ${fastafile}
    mv ${fastafile} ${fastafile}_decoy.fasta
    '''
}

process MascotAdapterOnline {
    label 'mascot'
    tag { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path), file(mascot_mzml_file)
    file(organism)
    file(fastafile_decoy)
    val var_modif
    val frag_mass_tol
    val frag_err_uni

    output:
    file("${basename}_mascot.idXML")

    shell:
    '''
    organism_sh=$(cat organism)
    
    # Determine enzyme based on filename pattern
    # For histone patterns (MH, MZ, or QCHE), use Arg-C; otherwise use default
    filename_sh=!{filename}
    if [[ $filename_sh =~ (MH|MZ|QCHE) ]]; then
        enzyme_param='Arg-C'
        echo "[INFO] Detected histone pattern (MH/MZ/QCHE) in filename: $filename_sh - using Arg-C enzyme"
    else
        enzyme_param=!{enzyme}
        echo "[INFO] Using default enzyme: $enzyme_param"
    fi
    
    MascotAdapterOnline -debug !{debug_code} -in !{mascot_mzml_file} -out !{basename}_mascot.idXML -Mascot_parameters:search_title !{search_title} -Mascot_server:hostname !{hostname} -Mascot_server:host_port !{host_port} -Mascot_server:server_path !{server_path} -Mascot_server:batch_size !{batch_size} -Mascot_server:timeout !{timeout} -Mascot_server:login -Mascot_server:username !{username} -Mascot_server:password !{password} -Mascot_parameters:database $organism_sh -Mascot_parameters:enzyme $enzyme_param -Mascot_parameters:missed_cleavages !{missed_cleavages} -Mascot_parameters:precursor_mass_tolerance !{precursor_mass_tolerance} -Mascot_parameters:precursor_error_units !{precursor_error_units} -Mascot_parameters:fragment_mass_tolerance !{frag_mass_tol} -Mascot_parameters:fragment_error_units !{frag_err_uni} -Mascot_parameters:charges !{charges} -Mascot_parameters:fixed_modifications !{fixed_modifications} -Mascot_parameters:variable_modifications !{var_modif} -Mascot_parameters:decoy
    '''
}

process CometAdapter {
    label 'comet'
    tag { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path), file(comet_mzml_file)
    file(organism)
    file(fastafile_decoy)
    val var_modif
    val frag_mass_tol
    val frag_err_uni

    output:
    file("${basename}_comet.idXML")

    shell:
    '''
    CometAdapter -threads !{task.cpus} -debug 10 -force -in !{comet_mzml_file} -out !{basename}_comet.idXML -database !{fastafile_decoy} -missed_cleavages !{missed_cleavages} -precursor_charge !{precursor_charge} -comet_executable !{comet_executable} -precursor_mass_tolerance !{precursor_mass_tolerance} -precursor_error_units !{precursor_error_units} -fragment_mass_tolerance !{frag_mass_tol} -fragment_error_units !{frag_err_uni} -fixed_modifications !{fixed_modifications} -variable_modifications !{var_modif}
    '''
}

process fragpipe_prep {
    tag  { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path)
    file(organism)
    file(fastafile_decoy)

    output:
    file("*.workflow")
    file("*.manifest")
    file("*_formatted.fasta")

    shell:
    '''
    # Append contaminants and rename fasta file:
    filename_sh=!{filename}
    
    # Extract organism: for .d files, remove .d first, then extract last component
    if [[ $filename_sh == *.d ]]; then
        organism_sh=$(echo ${filename_sh%.d} | rev | cut -d'.' -f1 | rev)
    else
        organism_sh=$(echo ${filename_sh##*.})
    fi
    
    echo "[INFO] Extracted organism for FragPipe: $organism_sh from $filename_sh"
    rename_fasta_file=${organism_sh}"_decoy.fasta"

    fastafile_decoy_sh=!{fastafile_decoy}
    cp ${fastafile_decoy_sh} ${rename_fasta_file}
    cat !{contaminants_file} >> ${rename_fasta_file}
    cont_fasta=$(echo ${rename_fasta_file%.*})"_cont.fasta"
    cont_fasta_file=$(echo ${cont_fasta,,})
    mv $rename_fasta_file $cont_fasta_file
    fragpipe_fasta_file=$(echo ${cont_fasta_file%.*})"_formatted.fasta"
    sed 's/###REV###/DECOY_/' $cont_fasta_file > $fragpipe_fasta_file

    # Run philosopher for generating new fasta file with decoys:
    !{tools_folder}/fragpipe/philosopher version
    !{tools_folder}/fragpipe/philosopher workspace --init 
    !{tools_folder}/fragpipe/philosopher database --annotate ${fragpipe_fasta_file} --prefix !{contaminants_prefix}

    # Modify workflow file:
    cp !{fp_workflow} .
    fp_workflow_file=$(basename !{fp_workflow})
    PWD=$(pwd)
    echo "[INFO] Fragpipe fasta file: ${fragpipe_fasta_file}"
    echo "[INFO] Working folder: ${PWD}"
    echo "[INFO] FragPipe workflow file: ${PWD}/${fp_workflow_file}"
    echo "[INFO] Modifying ${fp_workflow_file}..."
    source !{binfolder}/parsing_fragpipe.sh; modify_key_value "database.db-path" ${fragpipe_fasta_file} ${PWD}/${fp_workflow_file}
    new_fasta_file=$(cat ${PWD}/${fp_workflow_file} | grep "fasta")
    echo "[INFO] New Fasta file added to workflow: "$new_fasta_file
    
    # Create manifest: 
    echo "[INFO] Creating manifest file..."
    # Remove database suffix - match what fragpipe_main does
    basename_no_db="${filename_sh%.*}"
    if [[ $filename_sh == *.d ]]; then
        manifest_basename="${basename_no_db}.d"
    else
        manifest_basename="${basename_no_db}"
    fi
    echo -e "/home/tmp/${manifest_basename}\t1\t1\tDDA" > ${PWD}/fragpipe-220.manifest

    echo "[INFO] New manifest file: (print delimiters mode)"
    cat -A ${PWD}/fragpipe-220.manifest
    '''
}

process fragpipe_main {
    label 'fragpipe'
    tag { "${filename}" }

    beforeScript "mkdir -p ${task.workDir}/fragpipe_cache"
    
    containerOptions { 
        "--bind ${task.workDir}:/home/tmp --bind ${task.workDir}/fragpipe_cache:/fragpipe_bin/fragPipe-22.0/fragpipe/cache" 
    }
    
    input:
    tuple val(filename), val(basename), val(path)
    file(fp_workflow)
    file(fp_manifest)
    file(fp_fasta)

    output: 
    path("peptide.tsv")
    path("protein.tsv")
    path("ion.tsv")
    path("combined_protein.tsv")
    path("global.modsummary.tsv")
    path("combined_ion.tsv")
    path("psm.tsv")
    tuple val(filename), val(basename), val(path), path("*_calibrated.mzML"), emit: mzml_output

    shell:
    '''
    #Prepare Fragpipe input files: 
    filename_sh=!{filename}
    basename_sh=!{basename}

    # Set RAM based on file type
    if [[ "$filename_sh" == *.d ]]; then
        FP_RAM=!{fp_jvm_ram_bruker}
    else
        FP_RAM=!{fp_jvm_ram_thermo}
    fi

    echo "[INFO] Using ${FP_RAM}GB RAM for FragPipe"

    # basename_sh already has database suffix removed by Nextflow's getBaseName()
    # For "file.raw.Database", getBaseName() returns "file.raw" - use it directly
    raw_filename="$basename_sh"

    echo "[INFO] Copying raw file..."
    echo "[INFO] Path: "!{path}
    echo "[INFO] Filename: "$filename_sh
    echo "[INFO] Basename (from Nextflow): "$basename_sh
    echo "[INFO] Target filename: "$raw_filename

    # Find the actual file (may have database suffix in original name)
    if [ -e "!{path}/$filename_sh" ]; then
        actual_file="!{path}/$filename_sh"
        echo "[INFO] Using file as specified: $actual_file"
    else
        # Try without database suffix (e.g., filename.SP_Bovine.d -> filename.d)
        original_filename=$(echo "$filename_sh" | sed 's/\\.[A-Z][A-Z]_[^.]*\\.d$/.d/')
        if [ -e "!{path}/$original_filename" ]; then
            actual_file="!{path}/$original_filename"
            echo "[INFO] Using original file: $actual_file"
        else
            echo "[ERROR] Cannot find raw file: !{path}/$filename_sh or !{path}/$original_filename"
            exit 1
        fi
    fi

    echo "[INFO] Actual file: $actual_file"
    echo "[INFO] Target filename: "$raw_filename
    echo "[INFO] Copying to working directory..."
    cp -r "$actual_file" ./$raw_filename
    echo "[INFO] Copy complete"
    echo "[INFO] Running FragPipe..."
    echo "[INFO] Tools folder: "!{fp_tools}
    echo "[INFO] Workflow file: "!{fp_workflow}
    echo "[INFO] Manifest file: "!{fp_manifest}
    echo "[INFO] FASTA file: "!{fp_fasta}
    echo "[INFO] FragPipe cache will be at: /fragpipe_bin/fragPipe-22.0/fragpipe/cache (bind-mounted)"

    # Update workflow file to use local FASTA file (resolve symlink issue)
    FASTA_FILE=$(pwd)/!{fp_fasta}
    echo "[INFO] Updating workflow file with FASTA path: $FASTA_FILE"
    sed -i "s|database.db-path=.*|database.db-path=$FASTA_FILE|g" !{fp_workflow}
    echo "[INFO] Workflow database path updated"
    grep "database.db-path" !{fp_workflow}

    # Set temp directory for Java
    FRAGPIPE_TMP=$(pwd)/tmp
    mkdir -p $FRAGPIPE_TMP
    export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$FRAGPIPE_TMP"
    echo "[INFO] Java temp directory: $FRAGPIPE_TMP"

    mkdir ./output

    #Run Fragpipe: 
    #Run Fragpipe: 
    /fragpipe_bin/fragPipe-22.0/fragpipe/bin/fragpipe --headless --ram ${FP_RAM} --config-tools-folder !{fp_tools} --workflow !{fp_workflow} --manifest !{fp_manifest} --workdir ./output
    
    #Prepare Fragpipe output: 
    find ./output -name "peptide.tsv" -exec cp {} . \\;
    find ./output -name "protein.tsv" -exec cp {} . \\;
    find ./output -name "ion.tsv" -exec cp {} . \\;
    find ./output -name "combined_protein.tsv" -exec cp {} . \\;
    find ./output -name "global.modsummary.tsv" -exec cp {} . \\;
    find ./output -name "combined_ion.tsv" -exec cp {} . \\;
    find ./output -name "psm.tsv" -exec cp {} . \\;
    # FragPipe/Percolator write the search mzML directly into the task work dir
    # (bind-mounted as /home/tmp), not into ./output. If a calibrated one is
    # already there, nothing to do; otherwise fall back to the uncalibrated
    # mzML (MSFragger skips calibration when a sample yields too few PSMs,
    # e.g. low-injection/low-ID QC runs) so the process output glob is satisfied
    if ls ./*_calibrated.mzML >/dev/null 2>&1; then
        echo "[INFO] Calibrated mzML already present in work dir"
    elif ls ./*_uncalibrated.mzML >/dev/null 2>&1; then
        echo "[WARN] No calibrated mzML found - falling back to uncalibrated (insufficient PSMs for mass calibration)"
        for f in ./*_uncalibrated.mzML; do
            cp "$f" "$(basename "$f" _uncalibrated.mzML)_calibrated.mzML"
        done
    else
        echo "[ERROR] Neither calibrated nor uncalibrated mzML found in work dir"
    fi
    '''
}

process extract_apex_rt {
    tag "update_qcloud_tsv"

    input:
    path qcloud_tsv       // The original qcloud_qc01.tsv file
    file combined_ion     // File containing experimental RT values

    output:
    path "qcloud_updated.tsv"

    script:
    """
    # Write header: same columns, overwriting rt_teoretical with updated values
    echo -e "short_name\tlong_name\tmz_M0\tmz_M1\tmz_M2\tms2_mz\trt_teoretical" > qcloud_updated.tsv

    # Process each data line, skipping the header
    tail -n +2 ${qcloud_tsv} | while IFS=\$'\\t' read -r short_name long_name mz_M0 mz_M1 mz_M2 ms2_mz rt_teoretical; do
        # Extract experimental RT (column 20 in combined_ion)
        rt_teoretical=\$(grep -P "^\${long_name}\t" ${combined_ion} | sort -k21,21nr | head -1 | cut -f20 || echo "NOT_FOUND")

        # Output the line with updated rt_teoretical value, and empty mz_M1
        echo -e "\${short_name}\t\${long_name}\t\${mz_M0}\t\t\${mz_M2}\t\${ms2_mz}\t\${rt_teoretical}"
    done >> qcloud_updated.tsv
    """

}
