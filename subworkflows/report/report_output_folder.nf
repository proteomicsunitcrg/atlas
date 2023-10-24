output_folder             = params.output_folder
instrument_folder         = params.instrument_folder

//Bash scripts folder:
binfolder                = "$baseDir/bin"

process output_folder_test {

        tag { "test" }

        publishDir params.test_folder, mode: 'copy', overwrite: true
 
        input:
        file(protinf_file)
    
        output: 
        path '*num*'
 
        when:
        params.test_mode == true

        shell:
        '''
        # Parsings:
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        basename_sh=$(basename !{protinf_file} | cut -f 1 -d '.')
        echo $num_prots > $basename_sh".num_prots"
        echo $num_peptd > $basename_sh".num_peptd"
        ''' 
}

process output_folder_diann_test {

        tag { "test" }

        publishDir params.test_folder, mode: 'copy', overwrite: true

        input:
        file(tsv_file)

        output:
        path '*num*'

        when:
        params.test_mode == true

        shell:
        '''
        # Parsings:
        num_prots=$(source !{binfolder}/parsing_diann.sh; get_num_prot_groups_diann !{tsv_file})
        num_peptd=$(source !{binfolder}/parsing_diann.sh; get_num_peptidoforms_diann !{tsv_file})
        basename_sh=$(basename !{tsv_file} | cut -f 1 -d '.')
        echo $num_prots > $basename_sh".num_prots"
        echo $num_peptd > $basename_sh".num_peptd"
        '''
}

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

process output_folder_diannqc {

        tag { "${tsv_file}" }
        label 'clitools'

        input:
        file(checksum)
        file(tsv_file)
        file(mzml_file)

        when: 
        mzml_file =~ /QCDI/

        shell:
        '''
        # Parsings:
        num_prots=$(source !{binfolder}/parsing_diann.sh; get_num_prot_groups_diann !{tsv_file})
        num_peptd=$(source !{binfolder}/parsing_diann.sh; get_num_peptidoforms_diann !{tsv_file})
        source !{binfolder}/parsing_diann.sh; get_peptidoform_miscleavages_counts_diann !{tsv_file}
        miscleavages_0=$(cat *.miscleavages.0)
        miscleavages_1=$(cat *.miscleavages.1)
        miscleavages_2=$(cat *.miscleavages.2)
        miscleavages_3=$(cat *.miscleavages.3)
        charge_2=$(source !{binfolder}/parsing_diann.sh; get_num_charges_diann !{tsv_file} 2)
        charge_3=$(source !{binfolder}/parsing_diann.sh; get_num_charges_diann !{tsv_file} 3)
        charge_4=$(source !{binfolder}/parsing_diann.sh; get_num_charges_diann !{tsv_file} 4)
        total_base_peak_intenisty=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000505)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
        checksum=$(cat !{checksum})
        basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')
        echo "$basename_sh\t!{instrument_folder}\t$num_prots\t$num_peptd\t$miscleavages_0\t$miscleavages_1\t$miscleavages_2\t$miscleavages_3\t$charge_2\t$charge_3\t$charge_4\t$total_base_peak_intenisty\t$total_tic" >> !{output_folder}/qcdi_data_last_version.tsv
        '''
}

process output_folder {
        
        tag { "${protinf_file}" }

        input:
        file(protinf_file)
        val output_folder

        output:
        path '*num*'

        when:
        output_folder != true

        shell:
        '''
        # Parsings:
        request_code=$(echo !{protinf_file} | awk -F'[_.]' '{print $1}')
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        basename_sh=$(basename !{protinf_file} | cut -f 1 -d '.')
        echo $num_prots > $basename_sh".num_prots"
        echo $num_peptd > $basename_sh".num_peptd"
        
        echo "$basename_sh\t$num_prots\t$num_peptd" >> !{output_folder}/$request_code.tsv
        '''
}

process output_folder_diann {

        tag { "${tsv_file}" }

        input:
        file(tsv_file)
        val output_folder

        output:
        path '*num*'

        when:
        output_folder != true

        shell:
        '''
        # Parsings:
        request_code=$(echo !{tsv_file} | awk -F'[_.]' '{print $1}')
        num_prots=$(source !{binfolder}/parsing_diann.sh; get_num_prot_groups_diann !{tsv_file})
        num_peptd=$(source !{binfolder}/parsing_diann.sh; get_num_peptidoforms_diann !{tsv_file})
        basename_sh=$(basename !{tsv_file} | cut -f 1 -d '.')
        echo $num_prots > $basename_sh".num_prots"
        echo $num_peptd > $basename_sh".num_peptd"

        echo "$basename_sh\t$num_prots\t$num_peptd" >> !{output_folder}/$request_code.tsv
        '''
}




process output_folder_sampleqc_phospho {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCPL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        num_mod_phospho_s=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "S(Phospho)")
        num_mod_phospho_t=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "T(Phospho)")
        num_mod_phospho_y=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "Y(Phospho)")
        num_peptides_modif=$(echo "$num_mod_phospho_s+$num_mod_phospho_t+$num_mod_phospho_y" | bc -l)

        checksum=$(cat !{checksum})
        basename_sh=$(basename !{fileinfo_file} | cut -f 1 -d '.')

        echo "$basename_sh\t$num_prots\t$num_peptd\t$num_peptides_modif" >> !{output_folder}/QCPL_data_last_version.tsv
        '''
}


process output_folder_qchl {

	tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)
        file(idmapper_file)

        when:
        fileinfo_file.name =~ /QCHL/

        shell:
        '''
        checksum=$(cat !{checksum})
	num_peptides_total=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
	num_peptides_modif=$(source !{binfolder}/parsing.sh; get_num_peptidoform_modif_histones !{protinf_file})
	sum_area_propionyl_protein_n_terminal=$(source !{binfolder}/parsing.sh; get_sum_area_propionyl_protein_n_terminal !{idmapper_file})
	sum_area_not_propionyl_protein_n_terminal=$(source !{binfolder}/parsing.sh; get_sum_area_not_propionyl_protein_n_terminal !{idmapper_file})
	percentage_propionyl=$(echo "$sum_area_propionyl_protein_n_terminal/($sum_area_propionyl_protein_n_terminal+$sum_area_not_propionyl_protein_n_terminal)" | bc -l)
	sum_area_phenylisocyanate_precursors_n_terminal=$(source !{binfolder}/parsing.sh; get_sum_area_phenylisocyanate_precursors_n_terminal !{idmapper_file})
	sum_area_not_phenylisocyanate_precursors_n_terminal=$(source !{binfolder}/parsing.sh; get_sum_area_not_phenylisocyanate_precursors_n_terminal !{idmapper_file})
	percentage_pic=$(echo "$sum_area_phenylisocyanate_precursors_n_terminal/($sum_area_phenylisocyanate_precursors_n_terminal+$sum_area_not_phenylisocyanate_precursors_n_terminal)" | bc -l)

        checksum=$(cat !{checksum})
        basename_sh=$(basename !{fileinfo_file} | cut -f 1 -d '.')

        echo "$basename_sh\t$num_peptides_total\t$num_peptides_modif\t$percentage_propionyl\t$percentage_pic" >> !{output_folder}/QCHL_data_last_version.tsv
        '''
}
