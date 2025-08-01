//API:
url_api_signin             = params.url_api_signin
url_api_user               = params.url_api_user
url_api_pass               = params.url_api_pass
url_api_insert_file        = params.url_api_insert_file
url_api_insert_data        = params.url_api_insert_data
url_api_insert_quant       = params.url_api_insert_quant
url_api_fileinfo           = params.url_api_fileinfo
url_api_insert_modif       = params.url_api_insert_modif
num_max_prots              = params.num_max_prots
api_key_qc_params          = params.api_key_qc_params

//Bash scripts folder:
binfolder                      = "$baseDir/bin"

//Tools: 
tools_folder               = params.tools_folder

process insertFileToQSample {
        tag { "${mzml_file}" }
        label 'clitools' 

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        output:
        file("${filename}.checksum")

        shell:
        '''
        request_code=$(echo !{filename} | awk -F'[_.]' '{print $1}')
        checksum=$(source !{binfolder}/utils.sh; get_checksum !{path} !{filename})
        echo $checksum > !{filename}.checksum
        mzml_file=$(ls -l *.mzML | awk '{print $11}')
        echo $mzml_file > mzml_file
        creation_date=$(source !{binfolder}/utils.sh; get_mzml_date $mzml_file)
        data_string='{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'!{basename}'"}'
        echo $data_string > data_string
        access_token=$(source !{binfolder}/api.sh; get_api_access_token !{url_api_signin} !{url_api_user} !{url_api_pass})
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_file}/$request_code -H "Content-Type: application/json" --data @data_string 
        '''
}

process insertDataToQSample {

        tag { "${protinf_file}" }
        label 'clitools'

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)
        file(idfilter_score_file)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

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
 
        # Checks: 
        echo $total_base_peak_intenisty > total_base_peak_intenisty
        echo $total_tic > total_tic
        echo $num_prots > num_prots
        echo $charge_2 > charge_2
        echo $charge_3 > charge_3 
        echo $charge_4 > charge_4

        # API posts:
        checksum=$(cat !{checksum})
        api_key_sh=!{api_key_qc_params}
        access_token=$(source !{binfolder}/api.sh; get_api_access_token !{url_api_signin} !{url_api_user} !{url_api_pass})
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "3","value": "'$charge_2'"},{"contextSource": "4","value": "'$charge_3'"},{"contextSource": "5","value": "'$charge_4'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "7","value": "'$total_base_peak_intenisty'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "19","value": "'$total_tic'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "20","value": "'$miscleavages_0'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "21","value": "'$miscleavages_1'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "22","value": "'$miscleavages_2'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "23","value": "'$miscleavages_3'"}]}]}'

        '''
}

process insertQuantToQSample {
    tag { "${csvfile}" }

    input:
    file(checksum)
    file(csvfile)

    shell:
    '''
    checksum=$(cat !{checksum})
    !{binfolder}/quant2json.sh !{csvfile} $checksum output.json !{num_max_prots}
    access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
    curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_quant} -H "Content-Type: application/json" --data '@output.json'
    '''
}

process insertModificationsToQsample {
   tag { "${fileinfo_file}" }
   
   input:
    file(checksum)
    file(fileinfo_file)
    file(protinf_file)
    val sites_modif

   when: 
    sites_modif != true

   shell: 
    '''
       checksum=$(cat !{checksum})

       access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')

       # Count sites modifications: 
       sites_modif=$(echo "!{sites_modif}")
       IFS=',' read -r -a sites_modif_array <<< "$sites_modif"
       for sites_modif in "${sites_modif_array[@]}"
       do
         num_mod=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "$sites_modif")
         echo "[INFO] Number of modifications sites for $sites_modif: $num_mod"
         curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "'$sites_modif'"},"value": "'$num_mod'"}]}'
       done

       # Total number of peptides:
       num_peptides_total=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
       echo "[INFO] num_peptides_total: $num_peptides_total"

       # Total number of modified peptides: 
       pattern=$(echo "!{sites_modif}" | sed 's/(/\\\\(/g; s/)/\\\\)/g' | tr ',' '\\n' | paste -sd '|')
       num_peptides_modif=$(source !{binfolder}/parsing.sh; get_num_all_modified_peptidoforms !{protinf_file} "$pattern")
       echo "[INFO] num_peptides_modif: $num_peptides_modif"

       curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_fileinfo} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"info": {"peptideHits": "'$num_peptides_total'", "peptideModified": "'$num_peptides_modif'"}}'
 
    '''

}

process insertPolymerContToQSample {
     tag { "${mzml_file}" }

     label 'clitools'

     input:
     file(checksum)
     tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

     shell:
     '''
     checksum=$(cat !{checksum})
     request_code=$(echo !{mzml_file} | awk -F'[_.]' '{print $1}')
     basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')
     !{tools_folder}/mzsniffer/mzsniffer !{mzml_file} -f json > output.json
     
     total_tic=$(jq '.[] | .total' output.json)
     total_tic_PEG_1H=$(jq '.[] | .polymers[].total' ./output.json | sed -n '1p')
     total_tic_PEG_2H=$(jq '.[] | .polymers[].total' ./output.json | sed -n '2p')
     total_tic_PEG_3H=$(jq '.[] | .polymers[].total' ./output.json | sed -n '3p')
     total_tic_PPG=$(jq '.[] | .polymers[].total' ./output.json | sed -n '4p')
     total_tic_Triton_X_100=$(jq '.[] | .polymers[].total' ./output.json | sed -n '5p')
     total_tic_Triton_X_100_reduced=$(jq '.[] | .polymers[].total' ./output.json | sed -n '6p') 
     total_tic_Triton_X_100_na=$(jq '.[] | .polymers[].total' ./output.json | sed -n '7p')
     total_tic_Triton_X_100_reduced_na=$(jq '.[] | .polymers[].total' ./output.json | sed -n '8p')
     total_tic_Triton_X_101=$(jq '.[] | .polymers[].total' ./output.json | sed -n '9p')
     total_tic_Triton_X_101_reduced=$(jq '.[] | .polymers[].total' ./output.json | sed -n '10p')     
     total_tic_Polysiloxane=$(jq '.[] | .polymers[].total' ./output.json | sed -n '11p')
     total_tic_Tween_20=$(jq '.[] | .polymers[].total' ./output.json | sed -n '12p')
     total_tic_Tween_40=$(jq '.[] | .polymers[].total' ./output.json | sed -n '13p')
     total_tic_Tween_60=$(jq '.[] | .polymers[].total' ./output.json | sed -n '14p')
     total_tic_Tween_80=$(jq '.[] | .polymers[].total' ./output.json | sed -n '15p')
     total_tic_IGEPAL=$(jq '.[] | .polymers[].total' ./output.json | sed -n '16p')

     percent_tic_PEG_1H=$(printf %.4f $(echo "$total_tic_PEG_1H*100/$total_tic" | bc -l))
     percent_tic_PEG_2H=$(printf %.4f $(echo "$total_tic_PEG_2H*100/$total_tic" | bc -l))
     percent_tic_PEG_3H=$(printf %.4f $(echo "$total_tic_PEG_3H*100/$total_tic" | bc -l))
     percent_tic_PPG=$(printf %.4f $(echo "$total_tic_PPG*100/$total_tic" | bc -l))
     percent_tic_Triton_X_100=$(printf %.4f $(echo "$total_tic_Triton_X_100*100/$total_tic" | bc -l))
     percent_tic_Triton_X_100_reduced=$(printf %.4f $(echo "$total_tic_Triton_X_100_reduced*100/$total_tic" | bc -l))
     percent_tic_Triton_X_100_na=$(printf %.4f $(echo "$total_tic_Triton_X_100_na*100/$total_tic" | bc -l))
     percent_tic_Triton_X_100_reduced_na=$(printf %.4f $(echo "$total_tic_Triton_X_100_reduced_na*100/$total_tic" | bc -l))
     percent_tic_Triton_X_101=$(printf %.4f $(echo "$total_tic_Triton_X_101*100/$total_tic" | bc -l))
     percent_tic_Triton_X_101_reduced=$(printf %.4f $(echo "$total_tic_Triton_X_101_reduced*100/$total_tic" | bc -l))
     percent_tic_Polysiloxane=$(printf %.4f $(echo "$total_tic_Polysiloxane*100/$total_tic" | bc -l))
     percent_tic_Tween_20=$(printf %.4f $(echo "$total_tic_Tween_20*100/$total_tic" | bc -l))
     percent_tic_Tween_40=$(printf %.4f $(echo "$total_tic_Tween_40*100/$total_tic" | bc -l))
     percent_tic_Tween_60=$(printf %.4f $(echo "$total_tic_Tween_60*100/$total_tic" | bc -l))
     percent_tic_Tween_80=$(printf %.4f $(echo "$total_tic_Tween_80*100/$total_tic" | bc -l))
     percent_tic_IGEPAL=$(printf %.4f $(echo "$total_tic_IGEPAL*100/$total_tic" | bc -l))

     echo $percent_tic_PEG_1H
     echo $percent_tic_PEG_2H
     echo $percent_tic_PEG_3H
     echo $percent_tic_PPG
     echo $percent_tic_Triton_X_100
     echo $percent_tic_Triton_X_100_reduced
     echo $percent_tic_Triton_X_100_na
     echo $percent_tic_Triton_X_100_reduced_na
     echo $percent_tic_Triton_X_101
     echo $percent_tic_Triton_X_101_reduced
     echo $percent_tic_Polysiloxane
     echo $percent_tic_Tween_20
     echo $percent_tic_Tween_40
     echo $percent_tic_Tween_60
     echo $percent_tic_Tween_80
     echo $percent_tic_IGEPAL

     # Insert to database through QSample API:

     # Get token:
     access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')

     # Insert modifications counts:
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "PEG+1H"},"value": '$percent_tic_PEG_1H'}]}'    
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "PEG+2H"},"value": '$percent_tic_PEG_2H'}]}' 
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "PEG+3H"},"value": '$percent_tic_PEG_3H'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "PPG"},"value": '$percent_tic_PPG'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-100"},"value": '$percent_tic_Triton_X_100'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-100 (Reduced)"},"value": '$percent_tic_Triton_X_100_reduced'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-100 (Na)"},"value": '$percent_tic_Triton_X_100_na'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-100 (Reduced, Na)"},"value": '$percent_tic_Triton_X_100_reduced_na'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-101"},"value": '$percent_tic_Triton_X_101'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-101 (Reduced)"},"value": '$percent_tic_Triton_X_101_reduced'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Polysiloxane"},"value": '$percent_tic_Polysiloxane'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Tween-20"},"value": '$percent_tic_Tween_20'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Tween-40"},"value": '$percent_tic_Tween_40'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Tween-60"},"value": '$percent_tic_Tween_60'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Tween-80"},"value": '$percent_tic_Tween_80'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "IGEPAL CA-630 (NP-40)"},"value": '$percent_tic_IGEPAL'}]}'
	
     '''
}
