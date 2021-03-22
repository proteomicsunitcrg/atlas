//QCloud2 API:
qcloud2_api_signin       = params.qcloud2_api_signin
qcloud2_api_user         = params.qcloud2_api_user
qcloud2_api_pass         = params.qcloud2_api_pass
qcloud2_api_insert_file  = params.qcloud2_api_insert_file
qcloud2_api_insert_data  = params.qcloud2_api_insert_data
qcloud2_api_insert_quant = params.qcloud2_api_insert_quant

//SHell scripts folder:
binfolder                = "$baseDir/bin"

process insertFileToQSample {
        tag { "${filename}" }

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        output:
        file("checksum.txt")

        shell:
        '''
        request_code=$(echo !{filename} | awk -F'[_.]' '{print $1}')
        checksum=$(md5sum !{path}/!{filename} | awk '{print $1}')
        echo $checksum > checksum.txt
        creation_date=$(grep -Pio '.*startTimeStamp="\\K[^"]*' !{mzml_file} | sed 's/Z//g' | xargs -I{} date -d {} +"%Y-%m-%dT%T")
        access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_file}/$request_code -H "Content-Type: application/json" --data '{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'!{basename}'"}'
        '''
}

process insertQuantToQSample {
    tag { "${csvfile}" }

    input:
    file(checksum)
    file(csvfile)

    shell:
    '''
    checksum=$(cat checksum.txt)
    !{binfolder}/quant2json.sh !{csvfile} $checksum output.json
    access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
    curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_quant} -H "Content-Type: application/json" --data '@output.json'
    '''
}

process insertDataToQSample {
        tag { "${idfilter_file}" }

        input:
        file(checksum)
        file(idfilter_file)

        shell:
        '''
        checksum=$(cat checksum.txt)
        num_prots=$(cat !{idfilter_file} | grep "<ProteinHit" | wc -l)
        num_peptd=$(cat !{idfilter_file} | grep "<PeptideHit" | wc -l)
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd
        access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''

}
