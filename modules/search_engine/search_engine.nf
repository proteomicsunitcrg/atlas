//Create decoy database: 
databases_folder         = params.databases_folder
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
threads                  = params.threads
batch_size               = params.batch_size
debug_code               = params.debug_code


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


    when: 
    search_engine =~ /mascot/

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
    MascotAdapterOnline -debug !{debug_code} -threads !{threads} -in !{mascot_mzml_file} -out !{basename}_mascot.idXML -Mascot_parameters:search_title !{search_title} -Mascot_server:hostname !{hostname} -Mascot_server:host_port !{host_port} -Mascot_server:server_path !{server_path} -Mascot_server:batch_size !{batch_size} -Mascot_server:timeout !{timeout} -Mascot_server:login -Mascot_server:username !{username} -Mascot_server:password !{password} -Mascot_parameters:database $organism_sh -Mascot_parameters:enzyme !{enzyme} -Mascot_parameters:missed_cleavages !{missed_cleavages} -Mascot_parameters:precursor_mass_tolerance !{precursor_mass_tolerance} -Mascot_parameters:precursor_error_units !{precursor_error_units} -Mascot_parameters:fragment_mass_tolerance !{frag_mass_tol} -Mascot_parameters:fragment_error_units !{frag_err_uni} -Mascot_parameters:charges !{charges} -Mascot_parameters:fixed_modifications !{fixed_modifications} -Mascot_parameters:variable_modifications !{var_modif} -Mascot_parameters:decoy
    '''
}

process CometAdapter {
    label 'comet'
    tag { "${filename}" }

    when:
    search_engine =~ /comet/

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
       CometAdapter -force -in !{comet_mzml_file} -out !{basename}_comet.idXML -database !{fastafile_decoy} -precursor_charge !{precursor_charge} -comet_executable !{comet_executable} -precursor_mass_tolerance !{precursor_mass_tolerance} -precursor_error_units !{precursor_error_units} -fragment_mass_tolerance !{frag_mass_tol} -fragment_error_units !{frag_err_uni} -fixed_modifications !{fixed_modifications} -variable_modifications !{var_modif}
    else 
       CometAdapter -force -in !{comet_mzml_file} -out !{basename}_comet.idXML -database !{fastafile_decoy} -precursor_charge !{precursor_charge} -comet_executable !{comet_executable} -precursor_mass_tolerance !{precursor_mass_tolerance} -precursor_error_units !{precursor_error_units} -fragment_mass_tolerance !{frag_mass_tol} -fragment_error_units !{frag_err_uni} -fixed_modifications !{fixed_modifications} -variable_modifications !{var_modif} !{sec_react_modif} 
    fi
    '''
}
