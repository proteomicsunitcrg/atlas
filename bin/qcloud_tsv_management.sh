#!/bin/bash

#./qcloud_tsv_management.sh /home/proteomics/mygit/atlas-config/atlas-qcloud/conf/crg_secrets.config /tmp /home/proteomics/mysoftware/atlas qcloud_monitored_peptides.tsv

SECRETS_FILE=$1
TMP_FOLDER=$2
OUTPUT_FOLDER=$3
OUTPUT_FILENAME=$4

URL_QCLOUD=$(cat $SECRETS_FILE | grep "url_server_qcloud" | cut -d'=' -f2 | tr -d '"' | xargs)
API_USER=$(cat $SECRETS_FILE | grep "url_api_qcloud_user" | cut -d'=' -f2 | tr -d '"' | xargs)
API_PASSWORD=$(cat $SECRETS_FILE | grep "url_api_qcloud_pass" | cut -d'=' -f2 | tr -d '"' | xargs)

QCLOUD_RESPONSE=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" "$URL_QCLOUD")

if ! [ -z "$QCLOUD_RESPONSE" ]; then
    if [ "$QCLOUD_RESPONSE" -ge 200 ] && [ "$QCLOUD_RESPONSE" -le 299 ]; then
        QCLOUD_API_LOGIN_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $URL_QCLOUD"/api/auth" -H "Content-Type: application/json" --data '{"username":"'$API_USER'","password":"'$API_PASSWORD'"}')
        if ! [ "$QCLOUD_API_LOGIN_RESPONSE" -eq 401 ]; then
             
            echo "[INFO] Creating QCloud TSV..."
             TOKEN=$(curl -s -X POST $URL_QCLOUD"/api/auth" -H "Content-Type: application/json" --data '{"username":"'$API_USER'","password":"'$API_PASSWORD'"}' | jq '.[]' | sed "s/\"//g")
             #echo $TOKEN
             samplecategory=$(curl -s --url ${URL_QCLOUD}/api/samplecategory "Content-Type: application/json" -H 'Authorization: '${TOKEN}'' | jq '.[].sampleTypes[].name')
             readarray -t samplecategory_array < <(echo "${samplecategory}")
             
             for samplecategory_element in "${samplecategory_array[@]}"; do
                 curl -s --url ${URL_QCLOUD}/api/samplecomposition -H "Content-Type: application/json" -H 'Authorization: '${TOKEN}'' | jq '.[] | select(.sampleType.name == '$samplecategory_element') | .peptide.name' | sed "s/\"//g" >> ${TMP_FOLDER}/peptide_sequences.txt
                 curl -s --url ${URL_QCLOUD}/api/samplecomposition -H "Content-Type: application/json" -H 'Authorization: '${TOKEN}'' | jq '.[] | select(.sampleType.name == '$samplecategory_element') | .peptide.mz' >> ${TMP_FOLDER}/peptide_mz.txt
                 NUM_PEPTIDES=$(curl -s --url ${URL_QCLOUD}/api/samplecomposition "Content-Type: application/json" -H 'Authorization: '${TOKEN}'' | jq '.[] | select(.sampleType.name == '$samplecategory_element') | .peptide.id' | wc -l)
                 QCCODE=$(curl -s --url ${URL_QCLOUD}/api/samplecategory "Content-Type: application/json" -H 'Authorization: '${TOKEN}'' | jq '.[] | select(.sampleTypes[].name == '$samplecategory_element') | .name' | sed "s/\"//g")
                 for ((i=1; i<=$NUM_PEPTIDES; i++)); do echo $QCCODE; done >> ${TMP_FOLDER}/qccode.txt
             done
             
             rm ${TMP_FOLDER}/$OUTPUT_FILENAME
             paste -d '\t' ${TMP_FOLDER}/peptide_sequences.txt ${TMP_FOLDER}/peptide_mz.txt ${TMP_FOLDER}/qccode.txt > ${TMP_FOLDER}/$OUTPUT_FILENAME
             rm ${TMP_FOLDER}/peptide_mz.txt 
             rm ${TMP_FOLDER}/peptide_sequences.txt 
             rm ${TMP_FOLDER}/qccode.txt
             
             diffOutput=$(diff -q "${TMP_FOLDER}/$OUTPUT_FILENAME" "${OUTPUT_FOLDER}/$OUTPUT_FILENAME")

             if [ -n "$diffOutput" ]; then
                   echo "[INFO] QCloud TSVs are different so updating original...[TEMPORAL: ${TMP_FOLDER}/$OUTPUT_FILENAME ORIGINAL: ${OUTPUT_FOLDER}/$OUTPUT_FILENAME]"
                   cp ${TMP_FOLDER}/$OUTPUT_FILENAME ${OUTPUT_FOLDER} #<<-----------------ACTUAL TSV FILE UPDATE!
                   echo "[INFO] QCloud TSV file update done!"
                 else
                   echo "[INFO] QCloud TSV are identical. Resuming...[TEMPORAL: ${TMP_FOLDER}/$OUTPUT_FILENAME ORIGINAL: ${OUTPUT_FOLDER}/$OUTPUT_FILENAME]"
             fi

             echo "[INFO] EOF"
        else
            echo "[WARNING] QCloud API is not accessible due to an Unauthorized return code. Please check user and password. Resuming..."
        fi
    else
        echo "[WARNING] QCloud server $URL_QCLOUD is not accessible. Response: $QCLOUD_RESPONSE. Resuming..."
    fi
else
     echo "[WARNING] QCloud server $URL_QCLOUD timeout. Resuming..."
fi
