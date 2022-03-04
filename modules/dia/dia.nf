//DIA Umpire params:
jar_file             = params.jar_file
params_file          = params.params_file
lib_folder           = params.lib_folder

process dia_umpire {
    label 'diaumpire'
    tag  { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path), file(fileconverter_mzxml)

    output: 
    tuple val(filename), val(basename), val(path), file("*_Q1.mgf")

    shell:
    '''
    java -Djava.library.path=!{lib_folder} -jar -Xmx8G !{jar_file} !{fileconverter_mzxml} !{params_file}
    '''
}
