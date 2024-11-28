databases_folder        = params.databases_folder
diann_speclib_folder    = params.diann_speclib_folder
qvalue    	            = params.qvalue                        
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
min_pr_mz_bruker        = params.min_pr_mz_bruker
max_pr_mz_bruker        = params.max_pr_mz_bruker
min_pr_charge_bruker    = params.min_pr_charge_bruker
max_pr_charge_bruker    = params.max_pr_charge_bruker
var_mods                = params.var_mods        
var_mod                 = params.var_mod       
pg_level                = params.pg_level 
diann_threads           = params.diann_threads
diann_threads_bruker    = params.diann_threads_bruker
diann_exec_cmd          = params.diann_exec_cmd
diann_exec_cmd_bruker   = params.diann_exec_cmd_bruker
diann_cfg               = params.diann_cfg
diann_cfg_bruker        = params.diann_cfg_bruker

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
    diann_cfg_sh=!{diann_cfg}

    echo "CFG file: "$diann_cfg_sh
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
        !{diann_exec_cmd} --f "$diann_filename" --cfg "$diann_cfg_sh" --out "$output_file" --lib $fastafilename".lib.predicted.speclib"
    else
        echo "Running DIA-NN command line with lib prediction..."
        !{diann_exec_cmd} --f "$diann_filename" --cfg "${diann_cfg}" --out "$output_file" --fasta "$fastafile" -fasta-search --gen-spec-lib --predictor
    fi  
    '''
}

process diann_bruker {
    label 'diann_bruker'
    tag  { "${folder}" }

    input:
    tuple val(folder), val(base), val(d_folder)

    output:
    file("*report.tsv")
    path("chromatography-data.sqlite"), emit: sqlite_file    

    shell:
    '''
    bruker_folder_sh="!{d_folder}"
    echo "Bruker folder: $bruker_folder_sh"

    diann_cfg_bruker_sh=!{diann_cfg_bruker}
    echo "CFG file: "$diann_cfg_bruker_sh

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

    # Copy the SQLite file to the current working directory
    cp $bruker_folder_sh/chromatography-data.sqlite .

    # Check for existing predicted spec. libs. and send main process:
    # /diann-1.9.2/diann-linux
    diann_speclib_folder_sh=!{diann_speclib_folder}
    if ls $diann_speclib_folder_sh | grep -i "$fastafilename"; then
        cp $diann_speclib_folder_sh"/"$fastafilename".lib.predicted.speclib" .
        echo "Running DIA-NN command line with already existing $diann_speclib_folder_sh"/"$fastafilename.lib.predicted.speclib..."
        !{diann_exec_cmd_bruker} --f "$bruker_folder_sh" --cfg "$diann_cfg_bruker" --out "$output_file" --lib $fastafilename".lib.predicted.speclib"
    else
        echo "Running DIA-NN command line with lib prediction..."
        !{diann_exec_cmd_bruker} --f "$bruker_folder_sh" --cfg "${diann_cfg_bruker}" --out "$output_file" --fasta "$fastafile" -fasta-search --gen-spec-lib --predictor
    fi
    '''
}
