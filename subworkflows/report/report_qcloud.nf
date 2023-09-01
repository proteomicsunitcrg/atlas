//API:
url_api_signin             = params.url_api_signin
url_api_user               = params.url_api_user
url_api_pass               = params.url_api_pass

//Bash scripts folder:
binfolder                  = "$baseDir/bin"

process insertDataToQCloud {

        tag { "${protinf_file}" }
        label 'clitools'

        input:
        file(protinf_file)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        shell:
        '''
        # Parsings: 
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
        mit_ms1=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 1 MS:1000927)
        mit_ms2=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 2 MS:1000927)
 
        # Checks: 
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd
        echo $total_tic > total_tic
        echo $mit_ms1 > mit_ms1
        echo $mit_ms2 > mit_ms2

        # API posts:
        #
        '''
}
