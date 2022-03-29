#!/bin/bash

# Author : Roger Olivella
# Created: 02/03/2022

# Function: get acces token from QCloud2 API.
# Input: QCloud2 user ans password.
# Output: access token.
get_api_qcloud2_access_token(){
 curl -s -X POST $1 -H "Content-Type: application/json" --data '{"username":"'$2'","password":"'$3'"}' | grep -Po '"accessToken": *\K"[^"]*"' | sed 's/"//g'
}

# $1->$access_token, $2->!{qcloud2_api_insert_data}, $3->$checksum, $4->apikey,$5->contex_source_id, $6->values
post_api_qcloud2_access_context_source(){
 curl -v -X POST -H "Authorization: Bearer $1" $2 -H "Content-Type: application/json" --data '{"file": {"checksum": "'$3'"},"data": [{"parameter": {"apiKey": "$4","id": "1"},"values": $6}]}'
}
