output_folder             = params.output_folder
instrument_folder         = params.instrument_folder

//Bash scripts folder:
binfolder                = "$baseDir/bin"

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
        # Parsings:
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prots !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptd !{fileinfo_file})
        missed_cleavages_2=$(source !{binfolder}/parsing.sh; get_miscleavages_by_charge !{protinf_file} 2)
        missed_cleavages_3=$(source !{binfolder}/parsing.sh; get_miscleavages_by_charge !{protinf_file} 3)
        missed_cleavages_4=$(source !{binfolder}/parsing.sh; get_miscleavages_by_charge !{protinf_file} 4)
        charge_2=$(source !{binfolder}/parsing.sh; get_charges !{protinf_file} 2)
        charge_3=$(source !{binfolder}/parsing.sh; get_charges !{protinf_file} 3)
        charge_4=$(source !{binfolder}/parsing.sh; get_charges !{protinf_file} 4)
        total_base_peak_intenisty=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000505)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
        #log10_total_base_peak_intenisty=$(source !{binfolder}/utils.sh; get_log_base_n $total_base_peak_intenisty 10)
        #log10_total_tic=$(source !{binfolder}/utils.sh; get_log_base_n $total_tic 10)

        checksum=$(cat !{checksum})
        basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')

        echo "$basename_sh\t!{instrument_folder}\t$num_prots\t$num_peptd\t$missed_cleavages_2\t$missed_cleavages_3\t$missed_cleavages_4\t$charge_2\t$charge_3\t$charge_4\t$total_base_peak_intenisty\t$total_tic" >> !{output_folder}/qcdi_data_last_version.tsv
        '''
}
