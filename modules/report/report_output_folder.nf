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
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        source !{binfolder}/parsing.sh; get_peptidoform_miscleavages_counts !{protinf_file}
        miscleavages_0=$(cat *.miscleavages.0)
        miscleavages_1=$(cat *.miscleavages.1)
        miscleavages_2=$(cat *.miscleavages.2)
        miscleavages_3=$(cat *.miscleavages.3)
        charge_2=$(source !{binfolder}/parsing.sh; get_num_charges !{protinf_file} 2)
        charge_3=$(source !{binfolder}/parsing.sh; get_num_charges !{protinf_file} 3)
        charge_4=$(source !{binfolder}/parsing.sh; get_num_charges !{protinf_file} 4)
        total_base_peak_intenisty=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000505)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)

        #Check: 
        #echo $num_peptd > /users/pr/qsample/test/atlas-peptide/output/!{protinf_file}.num_peptd.qcdi

        checksum=$(cat !{checksum})
        basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')

        echo "$basename_sh\t!{instrument_folder}\t$num_prots\t$num_peptd\t$miscleavages_0\t$miscleavages_1\t$miscleavages_2\t$miscleavages_3\t$charge_2\t$charge_3\t$charge_4\t$total_base_peak_intenisty\t$total_tic" >> !{output_folder}/qcdi_data_last_version.tsv
        '''
}
