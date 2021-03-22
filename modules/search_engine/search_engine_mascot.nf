
//Create decoy database: 
databases_folder         = params.databases_folder
scripts_folder           = params.scripts_folder

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
    perl !{scripts_folder}/decoy.pl --append ${fastafile}
    mv ${fastafile} ${fastafile}_decoy.fasta
    '''
}

process MascotAdapterOnline {
    label 'openms'
    tag { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path), file(mascot_mzml_file)
    file(organism)
    file(fastafile_decoy)

    output:
    file("${basename}_mascot.idXML")

    shell:
    '''
    organism_sh=$(cat organism)
    MascotAdapterOnline -debug 1 -threads 6 -in !{mascot_mzml_file} -out !{basename}_mascot.idXML -Mascot_parameters:search_title !{search_title} -Mascot_server:hostname !{hostname} -Mascot_server:host_port !{host_port} -Mascot_server:server_path !{server_path} -Mascot_server:timeout !{timeout} -Mascot_server:login -Mascot_server:username !{username} -Mascot_server:password !{password} -Mascot_parameters:database $organism_sh -Mascot_parameters:enzyme !{enzyme} -Mascot_parameters:missed_cleavages !{missed_cleavages} -Mascot_parameters:precursor_mass_tolerance !{precursor_mass_tolerance} -Mascot_parameters:precursor_error_units !{precursor_error_units} -Mascot_parameters:fragment_mass_tolerance !{fragment_mass_tolerance} -Mascot_parameters:fragment_error_units !{fragment_error_units} -Mascot_parameters:charges !{charges} -Mascot_parameters:fixed_modifications !{fixed_modifications} -Mascot_parameters:variable_modifications !{variable_modifications} -Mascot_parameters:decoy
    '''
}
