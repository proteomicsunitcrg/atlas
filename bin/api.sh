#!/bin/bash

# Author : Roger Olivella
# Created: 02/03/2022

# Function: get acces token from QCloud2 API.
# Input: QCloud2 user ans password.
# Output: access token.
get_api_qcloud2_access_token(){
 curl -s -X POST $1 -H "Content-Type: application/json" --data '{"username":"'$2'","password":"'$3'"}' | grep -Po '"accessToken": *\K"[^"]*"' | sed 's/"//g'
}
