#!/bin/bash

# Author : Roger Olivella
# Created: 02/03/2022

# Function: get file checksum. 
# Input: ABSOLUTE PATH and FILENAME. 
# Output: file checksum. 
get_checksum(){
  md5sum $1/$2 | awk '{print $1}'
}
