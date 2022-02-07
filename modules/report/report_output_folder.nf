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

        when:
        fileinfo_file =~ /^((?!QCGL|QCDL|QCFL|QCPL|QCRL).)*$/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(grep -Pio 'indistinguishable_proteins_' !{protinf_file} | wc -l)
        num_peptd=$(grep 'non-redundant peptide hits:' !{fileinfo_file} | sed 's/^.*: //')
        missed_cleavages=$(grep -Pio '.*accession="QC:0000037"[^>]*' !{qccalc_file} | grep -Pio '.*value="\\K[^"]*')
        charge_2=$(grep -Pio '.*charge="\\K[^"]*' !{idfilter_score_file} | grep 2 | wc -l)
        charge_3=$(grep -Pio '.*charge="\\K[^"]*' !{idfilter_score_file} | grep 3 | wc -l)
        charge_4=$(grep -Pio '.*charge="\\K[^"]*' !{idfilter_score_file} | grep 4 | wc -l)
    
        mkdir -p !{output_folder}/!{instrument_folder}
        echo $num_prots > !{output_folder}/!{instrument_folder}/!{protinf_file}.num_prots

        '''
}
