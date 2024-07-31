
url_api_signin             = params.url_api_signin
url_api_user               = params.url_api_user
url_api_pass               = params.url_api_pass
url_api_insert_file        = params.url_api_insert_file
url_api_insert_data        = params.url_api_insert_data
url_api_insert_quant       = params.url_api_insert_quant
url_api_fileinfo           = params.url_api_fileinfo
url_api_insert_modif       = params.url_api_insert_modif

//Bash scripts folder:
binfolder                      = "$baseDir/bin"
  
sec_react_modif                = params.sec_react_modif     

process insertFileToQSample {
        tag { "${mzml_file}" }

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        output:
        file("${filename}.checksum")

        when:
        filename =~ /^((?!QCGL|QCDL|QCFL|QCPL|QCRL).)*$/

        shell:
        '''
        request_code=$(echo !{filename} | awk -F'[_.]' '{print $1}')
        checksum=$(source !{binfolder}/utils.sh; get_checksum !{path} !{filename})
        echo $checksum > !{filename}.checksum
        mzml_file=$(ls -l *.mzML | awk '{print $11}')
        echo $mzml_file > mzml_file
        creation_date=$(source /users/pr/qsample/test/atlas-last/bin/utils.sh; get_mzml_date $mzml_file)
        data_string='{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'!{basename}'"}'       
        access_token=$(source !{binfolder}/api.sh; get_api_access_token !{url_api_signin} !{url_api_user} !{url_api_pass})
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_file}/$request_code -H "Content-Type: application/json" --data @data_string
        '''
}


process insertSecReactDataToQSample {
        tag { "${protinf_file}" }
   
        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)
        file(idfilter_score_file)
        file(qccalc_file)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        when:
        fileinfo_file =~ /^((?!QCGL|QCDL|QCFL|QCPL|QCRL).)*$/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})

        ### Secondary reactions: 
        sec_react_carbamyl_k=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Carbamyl)")        
        sec_react_carbamyl_n=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} ".(Carbamyl)")
        sec_react_carbamyl_r=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "R(Carbamyl)")
        sec_react_deamidated_n=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "N(Deamidated)")
        sec_react_formyl_k=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Formyl)")
        sec_react_formyl_n=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} ".(Formyl)")
        sec_react_formyl_s=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "S(Formyl)")
        sec_react_formyl_t=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "T(Formyl)")
        sec_react_pyro_glu=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "pyro-Glu")

        percentage_carbamyl_k=$(echo "$sec_react_carbamyl_k/$num_peptd" | bc -l)
        percentage_carbamyl_n_term=$(echo "$sec_react_carbamyl_n/$num_peptd" | bc -l)
        percentage_carbamyl_r=$(echo "$sec_react_carbamyl_r/$num_peptd" | bc -l)
        percentage_deamidated_n=$(echo "$sec_react_deamidated_n/$num_peptd" | bc -l)
        percentage_formyl_k=$(echo "$sec_react_formyl_k/$num_peptd" | bc -l)
        percentage_formyl_n_term=$(echo "$sec_react_formyl_n/$num_peptd" | bc -l)
        percentage_formyl_s=$(echo "$sec_react_formyl_s/$num_peptd" | bc -l)
        percentage_formyl_t=$(echo "$sec_react_formyl_t/$num_peptd" | bc -l)
        percentage_pyro_glu=$(echo "$sec_react_pyro_glu/$num_peptd" | bc -l)

        #Check:
        echo $percentage_carbamyl_k > percentage_carbamyl_k
        echo $percentage_carbamyl_n_term > percentage_carbamyl_n_term
        echo $percentage_carbamyl_r > percentage_carbamyl_r
        echo $percentage_deamidated_n > percentage_deamidated_n
        echo $percentage_formyl_k > percentage_formyl_k
        echo $percentage_formyl_n_term > percentage_formyl_n_term
        echo $percentage_formyl_s > percentage_formyl_s
        echo $percentage_formyl_t > percentage_formyl_t
        echo $percentage_pyro_glu > percentage_pyro_glu
        
        ### Inserts API:
        access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        
        echo "Inserting sec. react. totals and percentages..."
        if [[ !{sec_react_modif} == "Carbamyl (K)" ]]; then
          echo "Inserting K(Carbamyl)"
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "K(Carbamyl)"},"value": "'$sec_react_carbamyl_k'"}]}'
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "10","value": "'$percentage_carbamyl_k'"}]}]}'
        fi
        if [[ !{sec_react_modif} == "Carbamyl (N-term)" ]]; then
          echo "Inserting .(Carbamyl)"
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": ".(Carbamyl)"},"value": "'$sec_react_carbamyl_n'"}]}'
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "11","value": "'$percentage_carbamyl_n_term'"}]}]}'
        fi
        if [[ !{sec_react_modif} == "Carbamyl (R)" ]]; then
          echo "Inserting R(Carbamyl)"
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "R(Carbamyl)"},"value": "'$sec_react_carbamyl_r'"}]}'  
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "12","value": "'$percentage_carbamyl_r'"}]}]}'
        fi
        if [[ !{sec_react_modif} == "Deamidated (N)" ]]; then
          echo "Inserting N(Deamidated)"
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "N(Deamidated)"},"value": "'$sec_react_deamidated_n'"}]}'
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "13","value": "'$percentage_deamidated_n'"}]}]}'
        fi
        if [[ !{sec_react_modif} == "Formyl (K)" ]]; then
          echo "Inserting  K(Formyl)"
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "K(Formyl)"},"value": "'$sec_react_formyl_k'"}]}'
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "14","value": "'$percentage_formyl_k'"}]}]}'
        fi
        if [[ !{sec_react_modif} == "Formyl (N-term)" ]]; then
          echo "Inserting  .(Formyl)"
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": ".(Formyl)"},"value": "'$sec_react_formyl_n'"}]}'
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "15","value": "'$percentage_formyl_n_term'"}]}]}'
        fi
        if [[ !{sec_react_modif} == "Formyl (S)" ]]; then
          echo "Inserting  S(Formyl)"
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "S(Formyl)"},"value": "'$sec_react_formyl_s'"}]}'
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "16","value": "'$percentage_formyl_s'"}]}]}'
        fi
        if [[ !{sec_react_modif} == "Formyl (T)" ]]; then
          echo "Inserting  T(Formyl)"
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "T(Formyl)"},"value": "'$sec_react_formyl_t'"}]}'
          curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "17","value": "'$percentage_formyl_t'"}]}]}'
        fi
        if [[ !{sec_react_modif} == "Gln->pyro-Glu (N-term Q)" ]]; then
         echo "Inserting pyro-Glu"
         curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "pyro-Glu"},"value": "'$sec_react_pyro_glu'"}]}' 
         curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "18","value": "'$percentage_pyro_glu'"}]}]}'
        fi
        echo "Sec. react. inserted!"
        '''
}

process insertFragpipeSecReactDataToQSample {
        tag { "global.summary.tsv" }
   
        input:
        file(checksum)
        file('peptide.tsv')                                                             
        file('protein.tsv')                                                             
        file('ion.tsv')                                                                 
        file('combined_protein.tsv')
        file('global.summary.tsv')    
 
        shell:
        '''
        checksum=$(cat !{checksum})
        
        ### Secondary reactions:
        echo "[INFO] Computing secondary reactions..."
        Formylation=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Formylation" global.summary.tsv) 
        Carbamyl=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Carbamyl" global.summary.tsv)
        Oxidation=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Oxidation" global.summary.tsv)
        Ammonialoss=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Ammonia loss" global.summary.tsv)
        Acetyl=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Acetyl" global.summary.tsv)
        Deamidation=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Deamidation" global.summary.tsv)
        Amidation=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Amidation" global.summary.tsv)
        Isotopic_peak_error=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Isotopic peak error" global.summary.tsv)
        Didehydrobutyrine_Water_loss=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Didehydrobutyrine/Water loss" global.summary.tsv)
        Methyl=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Methyl" global.summary.tsv)
        Carbamidomethyl_Addition_of_G=$(source /home/proteomics/mygit/atlas-test/bin/parsing_fragpipe.sh; parse_global_modsummary "Carbamidomethyl/Addition of G" global.summary.tsv)

        ### Inserts API:
        echo "[INFO] API inserts..."
        access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        
        if [[ -n "$Formylation" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Formylation"},"value": "'$Formylation'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "26","value": "'$Formylation'"}]}]}'
        fi
        
        if [[ -n "$Carbamyl" ]]; then   
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Carbamyl"},"value": "'$Carbamyl'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKiey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "27","value": "'$Carbamyl'"}]}]}'
        fi
        
        if [[ -n "$Oxidation" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Oxidation"},"value": "'$Oxidation'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "28","value": "'$Oxidation'"}]}]}'
        fi

        if [[ -n "$Ammonialoss" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Ammonia loss"},"value": "'$Ammonialoss'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "29","value": "'$Ammonialoss'"}]}]}'
        fi

        if [[ -n "$Acetyl" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Acetyl"},"value": "'$Acetyl'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "30","value": "'$Acetyl'"}]}]}'
        fi

        if [[ -n "$Deamidation" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Deamidation"},"value": "'$Deamidation'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "31","value": "'$Deamidation'"}]}]}'
        fi

        if [[ -n "$Amidation" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Amidation"},"value": "'$Amidation'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "32","value": "'$Amidation'"}]}]}'
        fi

        if [[ -n "$Isotopic_peak_error" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Isotopic peak error"},"value": "'$Isotopic_peak_error'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "33","value": "'$Isotopic_peak_error'"}]}]}'
        fi

        if [[ -n "$Didehydrobutyrine_Water_loss" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Didehydrobutyrine/Water loss"},"value": "'$Didehydrobutyrine_Water_loss'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "34","value": "'$Didehydrobutyrine_Water_loss'"}]}]}'
        fi

        if [[ -n "$Methyl" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Methyl"},"value": "'$Methyl'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "35","value": "'$Methyl'"}]}]}'
        fi

        if [[ -n "$Carbamidomethyl_Addition_of_G" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Carbamidomethyl/Addition of G"},"value": "'$Carbamidomethyl_Addition_of_G'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "36","value": "'$Carbamidomethyl_Addition_of_G'"}]}]}'
        fi
        
        echo "[INFO] EOF"
        '''
}
