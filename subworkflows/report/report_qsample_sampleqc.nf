//API:
url_api_signin             = params.url_api_signin
url_api_user               = params.url_api_user
url_api_pass               = params.url_api_pass
url_api_fileinfo           = params.url_api_fileinfo
url_api_insert_wetlab_file = params.url_api_insert_wetlab_file
url_api_insert_wetlab_data = params.url_api_insert_wetlab_data

//Bash scripts folder:
binfolder                      = "$baseDir/bin"

//wetlab api-keys:
api_key_qcgl                    = params.api_key_qcgl
api_key_qcdl                    = params.api_key_qcdl
api_key_qcfl                    = params.api_key_qcfl
api_key_qcpl                    = params.api_key_qcpl
api_key_qcrl                    = params.api_key_qcrl
api_key_qchl                    = params.api_key_qchl

process insertSampleQCFileToQSample {
        tag { "${mzml_file}" }

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        output:
        file("${filename}.checksum")

        when:
        filename =~ /QCGL|QCDL|QCFL|QCPL|QCRL|QCHL/
        
        shell:
        '''
        api_key=""
        basename_sh=!{basename}
        if [[ $basename_sh == *"QCGL"* ]]; then api_key=!{api_key_qcgl}; fi
        if [[ $basename_sh == *"QCDL"* ]]; then api_key=!{api_key_qcdl}; fi
        if [[ $basename_sh == *"QCFL"* ]]; then api_key=!{api_key_qcfl}; fi
        if [[ $basename_sh == *"QCPL"* ]]; then api_key=!{api_key_qcpl}; fi
        if [[ $basename_sh == *"QCRL"* ]]; then api_key=!{api_key_qcrl}; fi
        if [[ $basename_sh == *"QCHL"* ]]; then api_key=!{api_key_qchl}; fi
        checksum=$(md5sum !{path}/!{filename} | awk '{print $1}')
        echo $checksum > !{filename}.checksum
        mzml_file=$(ls -l *.mzML | awk '{print $11}')
        echo $mzml_file > mzml_file
        creation_date=$(source !{binfolder}/utils.sh; get_mzml_date $mzml_file)
        data_string='{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'$basename_sh'"}'
        echo $data_string > data_string
        replicate=$(echo !{filename} | cut -d"_" -f4 | cut -c2-3)
        year=$(echo !{filename} | cut -d"_" -f1 | cut -c1-4)
        week=$(echo !{filename} | cut -d"_" -f3 | cut -c2-3 | bc)
        access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_file}/$api_key -H "Content-Type: application/json" --data @data_string
        '''
}

process insertSampleQCInSolutionDataToQSample {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCDL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        
access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'!{api_key_qcdl}'","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}

process insertSampleQCInGelDataToQSample {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCGL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        
access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'!{api_key_qcgl}'","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}

process insertSampleQCFaspDataToQSample {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCFL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        
access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'!{api_key_qcfl}'","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}

process insertSampleQCPhosphoDataToQSample {
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


        #Check: 
        echo $num_prots > num_prots

access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'!{api_key_qcpl}'","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'!{api_key_qcpl}'","id": "1"},"values": [{"contextSource": "24","value": "'$num_peptides_modif'"}]}]}'
        '''
}

process insertSampleQCOfflineFractionationDataToQSample {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCRL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})

access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'!{api_key_qcrl}'","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}
