//DIA-NN params: 
databases_folder        = params.databases_folder
diann_speclib_folder    = params.diann_speclib_folder
qvalue 			        = params.qvalue                        
min_fr_mz               = params.min_fr_mz       
max_fr_mz               = params.max_fr_mz      
cut                     = params.cut
missed_cleavages        = params.missed_cleavages        
min_pep_len             = params.min_pep_len        
max_pep_len             = params.max_pep_len        
min_pr_mz               = params.min_pr_mz        
max_pr_mz               = params.max_pr_mz        
min_pr_charge           = params.min_pr_charge       
max_pr_charge           = params.max_pr_charge       
var_mods                = params.var_mods        
var_mod                 = params.var_mod       
pg_level                = params.pg_level 
diann_threads           = params.diann_threads

process diann {
    label 'diann'
    tag  { "${mzml_file}" }

    input:
    file(mzml_file)

    output:
    file("*report.tsv")

    shell:
    '''

    # Copy spectra file: 
    filename_sh=!{mzml_file}
    echo "Spectra complete filename: "$filename_sh

    # Extract filename info:
    basename_sh=$(basename $filename_sh | cut -f 1 -d '.')
    if [[ !{mzml_file} == *"QCDI"* ]]; then
      extension_sh=$(basename $filename_sh | cut -f 4 -d '.')
    else 
      extension_sh=$(basename $filename_sh | cut -f 3 -d '.') 
    fi       
    organism_sh=$(echo ${filename_sh##*.})

    # Load fasta file:
    databases_folder_sh=!{databases_folder}
    fastafile=$(basename ${databases_folder_sh}/${organism_sh}/current/*.fasta)
    fastafilename=$(echo ${fastafile%.*})
    fasta_orig_path=${databases_folder_sh}/${organism_sh}/current/${fastafile}
    cp $fasta_orig_path .
    echo "Fasta complete filename: "$fastafile

    # Rename spectra file for DIA-NN:
    diann_filename=$basename_sh"."$extension_sh
    mv $filename_sh $diann_filename
    echo "Spectra filename for DIA-NN: "$diann_filename

    # Output files:
    output_file=$basename_sh".report.tsv"
    echo "Output TSV report: "$output_file

    # Check for existing predicted spec. libs. and send main process: 
    diann_speclib_folder_sh=!{diann_speclib_folder}
    if ls $diann_speclib_folder_sh | grep -i "$fastafilename"; then
        cp $diann_speclib_folder_sh"/"$fastafilename".lib.predicted.speclib" .
        echo "Running DIA-NN command line with already existing $diann_speclib_folder_sh"/"$fastafilename.lib.predicted.speclib..."
        /usr/diann/1.8.1/./diann-1.8.1 --f "$diann_filename"  --lib $fastafilename".lib.predicted.speclib" --threads !{diann_threads} --verbose 10 --out "$output_file" --qvalue 0.01 --min-fr-mz 350 --max-fr-mz 1850 --met-excision --cut K*,R* --missed-cleavages 1 --min-pep-len 7 --max-pep-len 30 --min-pr-mz 500 --max-pr-mz 900 --min-pr-charge 1 --max-pr-charge 4 --unimod4 --var-mods 1 --var-mod UniMod:35,15.994915,M --smart-profiling --pg-level 1 --peak-center --no-ifs-removal --relaxed-prot-inf
    else
        echo "Running DIA-NN command line with lib prediction..."
        /usr/diann/1.8.1/./diann-1.8.1 --f "$diann_filename"  --lib "" --threads !{diann_threads} --verbose 10 --out "$output_file" --qvalue 0.01 --gen-spec-lib --predictor --fasta ${fastafile} --fasta-search --min-fr-mz 350 --max-fr-mz 1850 --met-excision --cut K*,R* --missed-cleavages 1 --min-pep-len 7 --max-pep-len 30 --min-pr-mz 500 --max-pr-mz 900 --min-pr-charge 1 --max-pr-charge 4 --unimod4 --var-mods 1 --var-mod UniMod:35,15.994915,M --smart-profiling --pg-level 1 --peak-center --no-ifs-removal --relaxed-prot-inf
    fi  
    '''
}

process diann_bruker {
    label 'diann'
    tag  { "${folder}" }

    input:
    tuple val(folder), val(base), val(d_folder)

    output:
    file("*report.tsv")

    shell:
    '''
    bruker_folder_sh="!{d_folder}"
    echo "Bruker folder: $bruker_folder_sh"

    # Extract filename info:
    basename_sh=$(basename "$bruker_folder_sh" .d)
    extension_sh="d"

    # Extract the organism taking into account the file type:
    organism_sh=$(echo "$bruker_folder_sh" | cut -d'.' -f2)

    # Load fasta file:
    databases_folder_sh=!{params.databases_folder}
    fastafile=$(basename ${databases_folder_sh}/${organism_sh}/current/*.fasta)
    fastafilename=$(echo ${fastafile%.*})
    fasta_orig_path=${databases_folder_sh}/${organism_sh}/current/${fastafile}
    cp $fasta_orig_path .
    echo "Fasta complete filename: "$fastafile

    # Output files:
    output_file=$basename_sh".report.tsv"
    echo "Output TSV report: "$output_file

    # Check for existing predicted spec. libs. and send main process:
    diann_speclib_folder_sh=!{diann_speclib_folder}
    if ls $diann_speclib_folder_sh | grep -i "$fastafilename"; then
        cp $diann_speclib_folder_sh"/"$fastafilename".lib.predicted.speclib" .
        echo "Running DIA-NN command line with already existing $diann_speclib_folder_sh"/"$fastafilename.lib.predicted.speclib..."
        /usr/diann/1.8.1/./diann-1.8.1 --f "$bruker_folder_sh"  --lib $fastafilename".lib.predicted.speclib" --threads !{diann_threads} --verbose 10 --out "$output_file" --qvalue 0.01 --min-fr-mz 350 --max-fr-mz 1850 --met-excision --cut K*,R* --missed-cleavages 1 --min-pep-len 7 --max-pep-len 30 --min-pr-mz 500 --max-pr-mz 900 --min-pr-charge 1 --max-pr-charge 4 --unimod4 --var-mods 1 --var-mod UniMod:35,15.994915,M --smart-profiling --pg-level 1 --peak-center --no-ifs-removal --relaxed-prot-inf
    else
        echo "Running DIA-NN command line with lib prediction..."
        /usr/diann/1.8.1/./diann-1.8.1 --f "$bruker_folder_sh"  --lib "" --threads !{diann_threads} --verbose 10 --out "$output_file" --qvalue 0.01 --gen-spec-lib --predictor --fasta ${fastafile} --fasta-search --min-fr-mz 350 --max-fr-mz 1850 --met-excision --cut K*,R* --missed-cleavages 1 --min-pep-len 7 --max-pep-len 30 --min-pr-mz 500 --max-pr-mz 900 --min-pr-charge 1 --max-pr-charge 4 --unimod4 --var-mods 1 --var-mod UniMod:35,15.994915,M --smart-profiling --pg-level 1 --peak-center --no-ifs-removal --relaxed-prot-inf
    fi
    '''
}
