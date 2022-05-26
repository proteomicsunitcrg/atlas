#!/bin/bash

# Author : Roger Olivella
# Created: 03/03/2021
# Modif. : 21/09/2021, added number of output proteins

# Usage: ./quantjson.sh 2021MQ001_MEGI_009_01_2ug.raw_ffm_idmapper_proteinquantifier.csv 21312ed1dfwfqfv test.json 100

csvfile=$1
checksum=$2
output=$3
num_prots=$4

#Remove 3 first rows: 
sed -i '1,3d' $csvfile

#List of all prots (TODO: parse accessions without pipes '|'): 
all_prots=($(sort -r -g -k 5 -t $'\t' $csvfile | awk -F '\t' '{print $1}' | tr -d '"' | awk -F '|' '{print $2}'))
all_descr=($(sort -r -g -k 5 -t $'\t' $csvfile | awk -F '\t' '{print $1}' | tr -d '"' | awk -F '|' '{print $3}'))
all_abund=($(sort -r -g -k 5 -t $'\t' $csvfile | awk -F '\t' '{print $5}'))

#Initialize counters: 
count_prot=0
count_cont=0

#Clean output file: 
cat /dev/null > $output

#JSON head: 
echo -n {\""file"\": {\""checksum"\": \""$checksum"\"},\""quant"\": [ >> $output

#JSON body: 
for i in "${!all_prots[@]}"; do
   if [[ ${all_prots[i]} == *"CON_"* ]]; then bcont="true"; (( count_cont++ )); else bcont="false"; (( count_prot++ )); fi
   if [ "${count_cont}" -le $num_prots ] && [ "${bcont}" == "true" ]; then echo -n { \""accession"\": \""${all_prots[i]}"\", \""description"\": \""${all_descr[i]}"\", \""abundance"\": ${all_abund[i]}, \""contaminant"\": "true" }, >> $output; fi
   if [ "${count_prot}" -le $num_prots ] && [ "${bcont}" == "false" ]; then echo -n { \""accession"\": \""${all_prots[i]}"\", \""description"\": \""${all_descr[i]}"\", \""abundance"\": ${all_abund[i]}, \""contaminant"\": "false" }, >> $output; fi
done

#Remove last comma: 
jsonfile=$(<$output)
jsonfile=${jsonfile::-1}
cat /dev/null > $output

#JSON close: 
echo -n $jsonfile"]}" >> $output
