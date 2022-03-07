//QCloud2 API:
qcloud2_api_signin             = params.qcloud2_api_signin
qcloud2_api_user               = params.qcloud2_api_user
qcloud2_api_pass               = params.qcloud2_api_pass
qcloud2_api_insert_file        = params.qcloud2_api_insert_file
qcloud2_api_insert_data        = params.qcloud2_api_insert_data
qcloud2_api_insert_quant       = params.qcloud2_api_insert_quant
qcloud2_api_fileinfo           = params.qcloud2_api_fileinfo
qcloud2_api_insert_modif       = params.qcloud2_api_insert_modif

//Bash scripts folder:
binfolder                = "$baseDir/bin"


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
        creation_date=$(grep -Pio '.*startTimeStamp="\\K[^"]*' !{mzml_file} | sed 's/Z//g' | xargs -I{} date -d {} +"%Y-%m-%dT%T")
        echo $creation_date > creation_date
        access_token=$(source !{binfolder}/api.sh; get_api_qcloud2_access_token !{qcloud2_api_signin} !{qcloud2_api_user} !{qcloud2_api_pass})
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_file}/$request_code -H "Content-Type: application/json" --data '{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'!{basename}'"}'
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
        num_peptd=$(grep 'non-redundant peptide hits:' !{fileinfo_file} | sed 's/^.*: //')
        echo $num_peptd > num_peptd

        ### Secondary reactions: 
        sec_react_carbamyl_k=$(cat !{protinf_file} | grep "<PeptideHit" | grep "K(Carbamyl)" | wc -l)
        sec_react_carbamyl_n_term=$(cat !{protinf_file} | grep "<PeptideHit" | grep ".(Carbamyl)" | wc -l)       
        sec_react_carbamyl_r=$(cat !{protinf_file} | grep "<PeptideHit" | grep "R(Carbamyl)" | wc -l)
        sec_react_deamidated_n=$(cat !{protinf_file} | grep "<PeptideHit" | grep "N(Deamidated)" | wc -l)      
        sec_react_formyl_k=$(cat !{protinf_file} | grep "<PeptideHit" | grep "K(Formyl)" | wc -l)
        sec_react_formyl_n_term=$(cat !{protinf_file} | grep "<PeptideHit" | grep ".(Formyl)" | wc -l)
        sec_react_formyl_s=$(cat !{protinf_file} | grep "<PeptideHit" | grep "S(Formyl)" | wc -l)
        sec_react_formyl_t=$(cat !{protinf_file} | grep "<PeptideHit" | grep "T(Formyl)" | wc -l)
        sec_react_pyro_glu=$(cat !{protinf_file} | grep "<PeptideHit" | grep "pyro-Glu" | wc -l)

        percentage_carbamyl_k=$(echo "$sec_react_carbamyl_k/$num_peptd" | bc -l)
        percentage_carbamyl_n_term=$(echo "$sec_react_carbamyl_n_term/$num_peptd" | bc -l)
        percentage_carbamyl_r=$(echo "$sec_react_carbamyl_r/$num_peptd" | bc -l)
        percentage_deamidated_n=$(echo "$sec_react_deamidated_n/$num_peptd" | bc -l)
        percentage_formyl_k=$(echo "$sec_react_formyl_k/$num_peptd" | bc -l)
        percentage_formyl_n_term=$(echo "$sec_react_formyl_n_term/$num_peptd" | bc -l)
        percentage_formyl_s=$(echo "$sec_react_formyl_s/$num_peptd" | bc -l)
        percentage_formyl_t=$(echo "$sec_react_formyl_t/$num_peptd" | bc -l)
        percentage_pyro_glu=$(echo "$sec_react_pyro_glu/$num_peptd" | bc -l)

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
        access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        
        ### Insert secondary reactions: 
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "K(Carbamyl)"},"value": "'$sec_react_carbamyl_k'"}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": ".(Carbamyl)"},"value": "'$sec_react_carbamyl_n_term'"}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "R(Carbamyl)"},"value": "'$sec_react_carbamyl_r'"}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "N(Deamidated)"},"value": "'$sec_react_deamidated_n'"}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "K(Formyl)"},"value": "'$sec_react_formyl_k'"}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": ".(Formyl)"},"value": "'$sec_react_formyl_n_term'"}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "S(Formyl)"},"value": "'$sec_react_formyl_s'"}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "T(Formyl)"},"value": "'$sec_react_formyl_t'"}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "pyro-Glu"},"value": "'$sec_react_pyro_glu'"}]}'

        ### Insert sec. react. percentages:
        echo "Inserting sec. react. percentages..."
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "10","value": "'$percentage_carbamyl_k'"},{"contextSource": "11","value": "'$percentage_carbamyl_n_term'"},{"contextSource": "12","value": "'$percentage_carbamyl_r'"},{"contextSource": "13","value": "'$percentage_deamidated_n'"},{"contextSource": "14","value": "'$percentage_formyl_k'"},{"contextSource": "15","value": "'$percentage_formyl_n_term'"},{"contextSource": "16","value": "'$percentage_formyl_s'"},{"contextSource": "17","value": "'$percentage_formyl_t'"},{"contextSource": "18","value": "'$percentage_pyro_glu'"}]}]}'

        '''
}
