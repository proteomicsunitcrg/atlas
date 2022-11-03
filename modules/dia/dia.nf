//DIA Umpire params:
jar_file             = params.jar_file
params_file          = params.params_file
lib_folder           = params.lib_folder

//DIA-NN params: 
databases_folder         = params.databases_folder

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

process diann {
    label 'diann'
    tag  { "${filename}" }

    input:
    tuple val(filename), val(basename), val(path)

    output:
    file("*.tsv")

    shell:
    '''

    # Copy spectra file: 
    cp !{path}/!{filename} .
    filename_sh=!{filename}
    echo "Spectra complete filename: "$filename_sh

    # Extract filename info:
    basename_sh=$(basename $filename_sh | cut -f 1 -d '.')
    extension_sh=$(basename $filename_sh | cut -f 2 -d '.')
    organism_sh=$(basename $filename_sh | cut -f 3 -d '.')

    # Load fasta file:
    fastafile=$(basename /users/pr/qsample/databases/${organism_sh}/current/*.fasta)
    fastafilename=$(echo ${fastafile%.*})
    fasta_orig_path=/users/pr/qsample/databases/${organism_sh}/current/${fastafile}
    cp $fasta_orig_path .
    echo "Fasta complete filename: "$fastafile

    # Rename spectra file for DIA-NN:
    diann_filename=$basename_sh"."$extension_sh
    mv $filename_sh $diann_filename
    echo "Spectra filename for DIA-NN: "$diann_filename

    # Output files:
    output_file=$basename_sh".report.tsv"
    output_lib=$basename_sh".lib.tsv"
    echo "Output TSV report: "$output_file
    echo "Output TSV lib: "$output_lib

    echo "Running DIA-NN command line..."
    /usr/diann/1.8/./diann-1.8  --f "$diann_filename"  --lib "" --threads 5 --verbose 10 --out "$output_file" --out-lib "$output_lib" --qvalue 0.01 --gen-spec-lib --predictor --fasta ${fastafile} --fasta-search --min-fr-mz 350 --max-fr-mz 1850 --met-excision --cut K*,R* --missed-cleavages 1 --min-pep-len 7 --max-pep-len 30 --min-pr-mz 500 --max-pr-mz 900 --min-pr-charge 1 --max-pr-charge 4 --unimod4 --var-mods 1 --var-mod UniMod:35,15.994915,M --smart-profiling --pg-level 1 --peak-center --no-ifs-removal --relaxed-prot-inf


    '''
}
