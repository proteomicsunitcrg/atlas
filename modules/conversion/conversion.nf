process ThermoRawFileParser {
    label 'thermoconvert'
    tag  { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path)

    output:
    tuple val(filename), val(basename), val(path), file("${basename}.mzML")

    """
    ThermoRawFileParser.sh -i=${path}/${filename} -f=2 -o ./
    """
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

