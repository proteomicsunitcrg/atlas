#!/bin/bash

# Author : Roger Olivella
# Created: 02/03/2022

get_num_prot_groups_diann(){
 cat $1 | tail -n +2 | awk -F'\t' '{print $3}' | sed 's|;|\n|g' | sort -u | wc -l
}

get_num_peptidoforms_diann(){
 cat $1 | tail -n +2 | awk -F'\t' '{print $14}' | sort -u | wc -l
}

get_num_charges_diann(){
 cat $1 | tail -n +2 | awk -F'\t' '{print $17}' | grep $2 | wc -l
}

get_peptidoform_miscleavages_counts_diann(){

 # Input params: 
 tsv_file=$1
 curr_dir=$(pwd)
 basename=$(basename $curr_dir/$tsv_file | cut -f 1 -d '.')

 cat $curr_dir/$tsv_file | awk -F'\t' '{print $15}' | sort -u > $curr_dir/$basename.seq

 lines=$(cat $curr_dir/$basename.seq)

 echo "Start computing miscleavages..."
 for line in $lines
 do
    missed=0
    for (( i=0; i<${#line}; i++ )); do
     pair=${line:$i:2}
     if [[ $pair = "K"* && ${#pair} == 2 && $pair != "KP" && $pair != "K(" ]] || [[ $pair = "R"* && ${#pair} == 2 && $pair != "RP"  && $pair != "R(" ]]
     then
      ((missed+=1))
     fi
    done
    echo $line$'\t'$missed >> $curr_dir/$basename.miscleavages.tsv
 done
 echo "EOF"

 cat $curr_dir/$basename.miscleavages.tsv | awk '{print $2}' | grep 0 | wc -l > $curr_dir/$basename.miscleavages.0
 cat $curr_dir/$basename.miscleavages.tsv | awk '{print $2}' | grep 1 | wc -l > $curr_dir/$basename.miscleavages.1
 cat $curr_dir/$basename.miscleavages.tsv | awk '{print $2}' | grep 2 | wc -l > $curr_dir/$basename.miscleavages.2
 cat $curr_dir/$basename.miscleavages.tsv | awk '{print $2}' | grep 3 | wc -l > $curr_dir/$basename.miscleavages.3

}
