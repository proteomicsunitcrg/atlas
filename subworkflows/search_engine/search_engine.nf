databases_folder         = params.databases_folder
contaminants_file        = params.contaminants_file
contaminants_prefix      = params.contaminants_prefix
tools_folder             = params.tools_folder

search_engine            = params.search_engine
sec_react_modif          = params.sec_react_modif

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
//fp_manifest              = params.fp_manifest
fp_tools                 = params.fp_tools

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
    organism=$(echo ${filename_sh##*.})
    echo $organism > organism
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
    MascotAdapterOnline -debug !{debug_code} -in !{mascot_mzml_file} -out !{basename}_mascot.idXML -Mascot_parameters:search_title !{search_title} -Mascot_server:hostname !{hostname} -Mascot_server:host_port !{host_port} -Mascot_server:server_path !{server_path} -Mascot_server:batch_size !{batch_size} -Mascot_server:timeout !{timeout} -Mascot_server:login -Mascot_server:username !{username} -Mascot_server:password !{password} -Mascot_parameters:database $organism_sh -Mascot_parameters:enzyme !{enzyme} -Mascot_parameters:missed_cleavages !{missed_cleavages} -Mascot_parameters:precursor_mass_tolerance !{precursor_mass_tolerance} -Mascot_parameters:precursor_error_units !{precursor_error_units} -Mascot_parameters:fragment_mass_tolerance !{frag_mass_tol} -Mascot_parameters:fragment_error_units !{frag_err_uni} -Mascot_parameters:charges !{charges} -Mascot_parameters:fixed_modifications !{fixed_modifications} -Mascot_parameters:variable_modifications !{var_modif} -Mascot_parameters:decoy
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
    if [[ !{sec_react_modif} == "" ]]; then
       CometAdapter -threads !{task.cpus} -debug 10 -force -in !{comet_mzml_file} -out !{basename}_comet.idXML -database !{fastafile_decoy} -missed_cleavages !{missed_cleavages} -precursor_charge !{precursor_charge} -comet_executable !{comet_executable} -precursor_mass_tolerance !{precursor_mass_tolerance} -precursor_error_units !{precursor_error_units} -fragment_mass_tolerance !{frag_mass_tol} -fragment_error_units !{frag_err_uni} -fixed_modifications !{fixed_modifications} -variable_modifications !{var_modif}
    else 
       CometAdapter -threads !{task.cpus} -debug 10 -force -in !{comet_mzml_file} -out !{basename}_comet.idXML -database !{fastafile_decoy} -missed_cleavages !{missed_cleavages} -precursor_charge !{precursor_charge} -comet_executable !{comet_executable} -precursor_mass_tolerance !{precursor_mass_tolerance} -precursor_error_units !{precursor_error_units} -fragment_mass_tolerance !{frag_mass_tol} -fragment_error_units !{frag_err_uni} -fixed_modifications !{fixed_modifications} -variable_modifications !{var_modif} !{sec_react_modif} 
    fi
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
    file("*.fasta")

    shell:
    '''
    # Append contaminants and rename fasta file:
    filename_sh=!{filename}
    organism_sh=$(echo ${filename_sh##*.})
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
    raw_filename=$(echo ${filename_sh%.*})
    echo -e "/home/tmp/${raw_filename}\t1\t1\tDDA" > ${PWD}/fragpipe-220.manifest
    echo "[INFO] New manifest file: (print delimiters mode)"
    cat -A ${PWD}/fragpipe-220.manifest
   '''
}

process fragpipe_main {
    label 'fragpipe'
    tag { "${filename}" }

    containerOptions { 
        "--bind ${task.workDir}:/home/tmp" 
    }

    input:
    tuple val(filename), val(basename), val(path)
    file(fp_workflow)
    file(fp_manifest)
    file(fp_fasta)

    output: 
    file("peptide.tsv")
    file("protein.tsv")
    file("ion.tsv")
    file("combined_protein.tsv")
    file("global.modsummary.tsv")

    shell:
    '''
    #Prepare Fragpipe input files: 
    filename_sh=!{filename}
    raw_filename=$(echo ${filename_sh%.*})
    echo "[INFO] Copying raw file..."
    echo "[INFO] Path: "!{path}
    echo "[INFO] Filename: "$filename_sh
    echo "[INFO] Target filename: "$raw_filename
    cp !{path}/$filename_sh ./$raw_filename
    echo "[INFO] Running FragPipe..."
    echo "[INFO] Tools folder: "!{fp_tools}
    echo "[INFO] Workflow file: "!{fp_workflow}
    echo "[INFO] Manifest file: "!{fp_manifest}
    mkdir ./output

    #Run Fragpipe: 
    /fragpipe_bin/fragPipe-22.0/fragpipe/bin/fragpipe --headless --config-tools-folder !{fp_tools} --workflow !{fp_workflow} --manifest !{fp_manifest} --workdir ./output
    
    #Prepare Fragpipe output: 
    find . -name "peptide.tsv" -exec cp {} . \\;
    find . -name "protein.tsv" -exec cp {} . \\;
    find . -name "ion.tsv" -exec cp {} . \\;
    find . -name "combined_protein.tsv" -exec cp {} . \\;
    find . -name "global.modsummary.tsv" -exec cp {} . \\;
    '''
}
