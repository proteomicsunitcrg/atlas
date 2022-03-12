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

        basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')

        echo "$basename_sh\t!{instrument_folder}\t$num_prots\t$num_peptd\t$missed_cleavages\t$charge_2\t$charge_3\t$log10_total_tic" >> !{output_folder}/qcdi_data.tsv

        '''
}
