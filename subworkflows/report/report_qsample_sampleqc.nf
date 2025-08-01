//API:
url_api_signin             = params.url_api_signin
url_api_user               = params.url_api_user
url_api_pass               = params.url_api_pass
url_api_insert_wetlab_file = params.url_api_insert_wetlab_file
url_api_insert_wetlab_data = params.url_api_insert_wetlab_data

//Bash scripts folder:
binfolder                      = "$baseDir/bin"

process insertSampleQCFileToQSample {
        tag { "${mzml_file}" }
        label 'clitools'

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
        val sampleqc_api_key

        output:
        file("${filename}.checksum")

        shell:
        '''
        basename_sh=!{basename}
        api_key_sh=!{sampleqc_api_key}
        checksum=$(md5sum !{path}/!{filename} | awk '{print $1}')
        echo $checksum > !{filename}.checksum
        mzml_file=$(ls -l *.mzML | awk '{print $11}')
        echo $mzml_file > mzml_file
        creation_date=$(source !{binfolder}/utils.sh; get_mzml_date $mzml_file)
        replicate=$(echo !{filename} | cut -d"_" -f4 | cut -c2-3)
        year=$(echo !{filename} | cut -d"_" -f1 | cut -c1-4)
        week=$(echo !{filename} | cut -d"_" -f3 | cut -c2-3 | bc)
        data_string='{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'$basename_sh'","replicate": '$replicate',"year": '$year',"week": '$week'}'
        echo $data_string > data_string
        access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_file}/$api_key_sh -H "Content-Type: application/json" --data @data_string
        '''
}

process insertSampleQCDataToQSample {

        tag { "${protinf_file}" }
        label 'clitools'

        input:
        tuple val(filename), val(basename), val(path)
        file(checksum)
        file(protinf_file)
        val sampleqc_api_key
        
        shell:
        '''
        basename_sh=!{basename}
        checksum=$(cat !{checksum})
        api_key_sh=!{sampleqc_api_key}
        
        # Access token: 
        access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo "[INFO] Access token: "$access_token

        # Total number of protein groups and peptides: 
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        echo "[INFO] num_prots: "$num_prots
        echo "[INFO] num_peptd: "$num_peptd
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}

process insertSampleQCModificationsToQsample {
        
        tag { "${protinf_file}" }
        label 'clitools'

        input:
        tuple val(filename), val(basename), val(path)
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)
        val sites_modif
        val sampleqc_api_key
        
        when:
         sites_modif != true

        shell:
        '''
        basename_sh=!{basename}
        checksum=$(cat !{checksum})
        api_key_sh=!{sampleqc_api_key}
        sites_modif=$(echo "!{sites_modif}")    

        # Access token: 
        access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo "[INFO] Access token: "$access_token

        # Count sites modifications:
        sites_modif=$(echo "!{sites_modif}")
        IFS=',' read -r -a sites_modif_array <<< "$sites_modif"
        num_sites_total=0
        for sites_modif in "${sites_modif_array[@]}"
        do
           num_sites=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "$sites_modif")
           echo "[INFO] Number of modifications sites for $sites_modif: $num_sites"
           num_sites_total=$(echo "$num_sites_total+$num_sites" | bc -l)
        done
        echo "[INFO] Total number of modifications sites: $num_sites_total"
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"a    piKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "24","value": "'$num_sites_total'"}]}]}'

        # Total number of modified peptides:
        pattern=$(echo "!{sites_modif}" | sed 's/(/\\\\(/g; s/)/\\\\)/g' | tr ',' '\\n' | paste -sd '|')
        num_peptides_sites_modif=$(source !{binfolder}/parsing.sh; get_num_all_modified_peptidoforms !{protinf_file} "$pattern")
        echo "[INFO] num_peptides_sites_modif: $num_peptides_sites_modif"
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "25","value": "'$num_peptides_sites_modif'"}]}]}'
        '''
}
