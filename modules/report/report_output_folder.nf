output_folder             = params.output_folder
instrument_folder         = params.instrument_folder

process output_folder_diaqc {

        tag { "${protinf_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)
        file(idfilter_score_file)
        file(qccalc_file)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        when:
        fileinfo_file =~ /QCDI/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(grep -Pio 'indistinguishable_proteins_' !{protinf_file} | wc -l)
        num_peptd=$(grep 'non-redundant peptide hits:' !{fileinfo_file} | sed 's/^.*: //')
        missed_cleavages=$(grep -Pio '.*accession="QC:0000037"[^>]*' !{qccalc_file} | grep -Pio '.*value="\\K[^"]*')
        charge_2=$(grep -Pio '.*charge="\\K[^"]*' !{idfilter_score_file} | grep 2 | wc -l)
        charge_3=$(grep -Pio '.*charge="\\K[^"]*' !{idfilter_score_file} | grep 3 | wc -l)
        charge_4=$(grep -Pio '.*charge="\\K[^"]*' !{idfilter_score_file} | grep 4 | wc -l)
        log_total_tic=$(cat !{mzml_file} | grep -Pio '.*accession="MS:1000505" value="\\K[^"]*' | paste -sd+ - | bc -l)    
        log10_total_tic=$(echo "l($log_total_tic)/l(10)" | bc -l)

        mkdir -p !{output_folder}/!{instrument_folder}
        echo $num_prots > !{output_folder}/!{instrument_folder}/!{protinf_file}.num_prots
        echo $num_peptd > !{output_folder}/!{instrument_folder}/!{protinf_file}.num_peptd
        echo $missed_cleavages > !{output_folder}/!{instrument_folder}/!{protinf_file}.missed_cleavages
        echo $charge_2 > !{output_folder}/!{instrument_folder}/!{protinf_file}.charge_2
        echo $charge_3 > !{output_folder}/!{instrument_folder}/!{protinf_file}.charge_3
        echo $charge_4 > !{output_folder}/!{instrument_folder}/!{protinf_file}.charge_4
        echo $log10_total_tic > !{output_folder}/!{instrument_folder}/!{protinf_file}.log10_total_tic
        '''
}
