//DIA-NN params: 
databases_folder        = params.databases_folder
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

    echo "Running DIA-NN command line..."
    /usr/diann/1.8.1/./diann-1.8.1 --f "$diann_filename"  --lib "" --threads 5 --verbose 10 --out "$output_file" --qvalue !{qvalue} --gen-spec-lib --predictor --fasta ${fastafile} --fasta-search --min-fr-mz !{min_fr_mz} --max-fr-mz !{max_fr_mz} --met-excision --cut !{cut} --missed-cleavages !{missed_cleavages} --min-pep-len !{min_pep_len} --max-pep-len !{max_pep_len} --min-pr-mz !{min_pr_mz} --max-pr-mz !{max_pr_mz} --min-pr-charge !{min_pr_charge} --max-pr-charge !{max_pr_charge} --unimod4 --var-mods !{var_mods} --var-mod !{var_mod} --smart-profiling --pg-level !{pg_level} --peak-center --no-ifs-removal --relaxed-prot-inf

    '''
}
