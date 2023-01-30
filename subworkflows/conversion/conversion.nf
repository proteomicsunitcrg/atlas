process ThermoRawFileParser {
    label 'thermoconvert'
    tag  { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path)

    output:
    tuple val(filename), val(basename), val(path), file("*.mzML")

    shell:
    '''
    if [[ !{filename} == *"mzML"* ]]; then
        path_sh=!{path}
        filename_sh=!{filename}
        organism_sh=$(echo ${filename_sh##*.})
        basename_sh=!{basename}
        basename_wo_ext=${basename_sh%.*}
        cp $path_sh/$filename_sh $basename_wo_ext".mzML"    
    else
        ThermoRawFileParser.sh -i=!{path}/!{filename} -f=2 -o ./
    fi
    '''
}

process ThermoRawFileParserDiann {
    label 'thermoconvert'
    tag  { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path)

    output:
    file("*.mzML.*")

    shell:
    '''
    path_sh=!{path}
    filename_sh=!{filename}
    organism_sh=$(echo ${filename_sh##*.})
    ThermoRawFileParser.sh -i=$path_sh/$filename_sh -f=2 -o ./
    basename_sh=!{basename}
    mv $basename_sh.mzML $basename_sh.mzML.$organism_sh  
    '''
}

process FileConverter_mzml2mzxml {
    label 'openms'
    tag  { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path), file(mzml_file)

    output:
    tuple val(filename), val(basename), val(path), file("*.mzXML")

    shell: 
    '''
    basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')
    FileConverter -in !{mzml_file} -out ${basename_sh}.mzXML
    '''
}


process FileConverter_mgf2mzml {
    label 'openms'
    tag  { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path), file(mgf_file)

    output:
    tuple val(filename), val(basename), val(path), file("*_Q1.mzML")

    shell:
    '''
    basename_sh=$(basename !{mgf_file} | cut -f 1 -d '.')
    FileConverter -in !{mgf_file} -out ${basename_sh}.mzML
    '''
}
