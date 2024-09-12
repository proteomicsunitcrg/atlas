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
        file("peptide.tsv")
        file("protein.tsv")
        file("ion.tsv")
        file("combined_protein.tsv")
        file("global.modsummary.tsv")
        file(checksum)
        val output_folder

        output:
        path '*num*'

        when:
        output_folder != true

        shell:
        '''
        # Parsings:
        request_code=$(echo !{checksum} | awk -F'[_.]' '{print $1}')
        num_prots=$(source !{binfolder}/parsing_fragpipe.sh; get_num_prot_groups_fragpipe ./protein.tsv)
        num_peptd=$(source !{binfolder}/parsing_fragpipe.sh; get_num_peptidoforms_fragpipe ./peptide.tsv)
        basename_sh=$(basename !{checksum} | cut -f 1 -d '.')
        echo $num_prots > $basename_sh".num_prots"
        echo $num_peptd > $basename_sh".num_peptd"

        echo "$basename_sh\t$num_prots\t$num_peptd" >> !{output_folder}/$request_code.tsv
        '''
}
