#!/bin/bash

csvfile=$1
checksum=$2
output=$3
num_prots=$4
is_diann_file=$5

#Remove 3 first rows: 
sed -i '1,3d' $csvfile

#List of all prots (TODO: parse accessions without pipes '|'): 
if [ "${5}" = true ]; then
   all_prots=($(tail -n +2 $csvfile | sort -u -r -g -k 9 -t $'\t' | awk -F '\t' '{print $3}' | cut -d ";" -f1))
   all_descr=($(tail -n +2 $csvfile | sort -u -r -g -k 9 -t $'\t' | awk -F '\t' '{print $5}' | cut -d ";" -f1))
   all_abund=($(tail -n +2 $csvfile | sort -u -r -g -k 9 -t $'\t' | awk -F '\t' '{print $9}' | cut -d ";" -f1))
else
   all_prots=($(sort -r -g -k 5 -t $'\t' $csvfile | awk -F '\t' '{print $1}' | tr -d '"' | awk -F '|' '{print $2}'))
   all_descr=($(sort -r -g -k 5 -t $'\t' $csvfile | awk -F '\t' '{print $1}' | tr -d '"' | awk -F '|' '{print $3}'))
   all_abund=($(sort -r -g -k 5 -t $'\t' $csvfile | awk -F '\t' '{print $5}'))
fi

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
   if (( $(echo "${all_abund[i]} != 0" | sed 's/[eE]+*/\*10^/' | bc -l) )); then
      if [ "${count_cont}" -le $num_prots ] && [ "${bcont}" == "true" ]; then echo -n { \""accession"\": \""${all_prots[i]}"\", \""description"\": \""${all_descr[i]}"\", \""abundance"\": ${all_abund[i]}, \""contaminant"\": "true" }, >> $output; fi
      if [ "${count_prot}" -le $num_prots ] && [ "${bcont}" == "false" ]; then echo -n { \""accession"\": \""${all_prots[i]}"\", \""description"\": \""${all_descr[i]}"\", \""abundance"\": ${all_abund[i]}, \""contaminant"\": "false" }, >> $output; fi
   fi
done

#Remove last comma: 
jsonfile=$(<$output)
jsonfile=${jsonfile::-1}
cat /dev/null > $output

#JSON close: 
echo -n $jsonfile"]}" >> $output
