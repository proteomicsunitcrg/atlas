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
