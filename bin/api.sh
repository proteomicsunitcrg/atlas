#!/bin/bash

get_api_access_token(){
 curl -s -X POST $1 -H "Content-Type: application/json" --data '{"username":"'$2'","password":"'$3'"}' | grep -Po '"accessToken": *\K"[^"]*"' | sed 's/"//g'
}

get_api_access_token_qcloud(){
 curl -s -X POST $1 -H "Content-Type: application/json" --data '{"username":"'$2'","password":"'$3'"}' | grep -Po '"token" : *\K"[^"]*"' | sed 's/"//g'
}

post_api_access_context_source(){
 curl -v -X POST -H "Authorization: Bearer $1" $2 -H "Content-Type: application/json" --data '{"file": {"checksum": "'$3'"},"data": [{"parameter": {"apiKey": "$4","id": "1"},"values": $6}]}'
}
