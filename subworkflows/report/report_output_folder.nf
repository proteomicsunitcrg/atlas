output_folder             = params.output_folder
instrument_folder         = params.instrument_folder

//Bash scripts folder:
binfolder                = "$baseDir/bin"

//Variables: 
//output_folder: set it up at the methods CSV for each application. 
//test_folder: set it up at the test run modes CSV.

process output_folder {
        
        tag { "${output_folder}" }

        input:
        file(protinf_file)
        tuple val(filename), val(basename), val(path), file(mzml_file)
        val output_folder

        when:
        output_folder != true

        shell:
        '''
        # Parsings:
        request_code=$(echo !{protinf_file} | awk -F'[_.]' '{print $1}')
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

        basename_sh=$(basename !{protinf_file} | cut -f 1 -d '.')
        output_tsv=!{output_folder}/$request_code.tsv
        echo "$basename_sh\t$num_prots\t$num_peptd\t$miscleavages_0\t$miscleavages_1\t$miscleavages_2\t$miscleavages_3\t$charge_2\t$charge_3\t$charge_4\t$total_base_peak_intenisty\t$total_tic" >> $output_tsv
        if ! head -n 1 "$output_tsv" | grep -q "num_prots"; then
           (printf "filename\tnum_prots\tnum_peptd\tmiscleavages_0\tmiscleavages_1\tmiscleavages_2\tmiscleavages_3\tcharge_2\tcharge_3\tcharge_4\ttotal_base_peak_intenisty\ttotal_tic\n"; cat $output_tsv) | tee $output_tsv > /dev/null
        fi

        '''
}

process output_folder_diann {

        tag { "${output_folder}" }

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

process output_folder_fragpipe {

        tag { "${output_folder}" }

        input:
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
        file("peptide.tsv")
        file("protein.tsv")
        file("ion.tsv")
        file("combined_protein.tsv")
        file("global.modsummary.tsv")
        file(checksum)
        val output_folder

        when:
        output_folder != true

        shell:
        '''
        # Parsings:
        request_code=$(echo !{checksum} | awk -F'[_.]' '{print $1}')
        num_prots=$(source !{binfolder}/parsing_fragpipe.sh; get_num_prot_groups_fragpipe ./protein.tsv)
        num_peptd=$(source !{binfolder}/parsing_fragpipe.sh; get_num_peptidoforms_fragpipe ./peptide.tsv)
        basename_sh=$(basename !{checksum} | cut -f 1 -d '.')
        charge_2=$(source !{binfolder}/parsing_fragpipe.sh; get_num_charges_fragpipe ./ion.tsv 2)
        charge_3=$(source !{binfolder}/parsing_fragpipe.sh; get_num_charges_fragpipe ./ion.tsv 3)
        charge_4=$(source !{binfolder}/parsing_fragpipe.sh; get_num_charges_fragpipe ./ion.tsv 4)
        source !{binfolder}/parsing_fragpipe.sh; get_peptidoform_miscleavages_counts_fragpipe ./peptide.tsv
        miscleavages_0=$(cat *.miscleavages.0)
        miscleavages_1=$(cat *.miscleavages.1)
        miscleavages_2=$(cat *.miscleavages.2)
        miscleavages_3=$(cat *.miscleavages.3)
        total_base_peak_intenisty=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000505)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)

        request_code=$(echo !{checksum} | awk -F'[_.]' '{print $1}')
        basename_sh=$(basename !{checksum} | cut -f 1 -d '.')
        output_tsv=!{output_folder}/$request_code.tsv
        echo "$basename_sh\t$num_prots\t$num_peptd\t$miscleavages_0\t$miscleavages_1\t$miscleavages_2\t$miscleavages_3\t$charge_2\t$charge_3\t$charge_4\t$total_base_peak_intenisty\t$total_tic" >> $output_tsv
        if ! head -n 1 "$output_tsv" | grep -q "num_prots"; then
           (printf "filename\tnum_prots\tnum_peptd\tmiscleavages_0\tmiscleavages_1\tmiscleavages_2\tmiscleavages_3\tcharge_2\tcharge_3\tcharge_4\ttotal_base_peak_intenisty\ttotal_tic\n"; cat $output_tsv) | tee $output_tsv > /dev/null
        fi

        '''
}
