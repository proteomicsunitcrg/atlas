#!/bin/bash

# Author : Roger Olivella
# Created: 02/03/2022

get_num_prot_groups(){
 grep -Pio 'indistinguishable_proteins_' $1 | wc -l
}

# "peptidoform" as defined as https://arxiv.org/pdf/2109.11352.pdf

get_num_peptidoforms(){
 xmllint --xpath '//*[local-name()="PeptideIdentification"]/*[local-name()="PeptideHit"]' $1 | grep -Pio '.*sequence="\K[^"]*' | uniq -u | wc -l
}

get_num_peptidoform_sites(){
 xmllint --xpath '//*[local-name()="PeptideIdentification"]/*[local-name()="PeptideHit"]' $1 | grep -Pio '.*sequence="\K[^"]*' | uniq -u | grep -o $2 | wc -l
}

get_num_charges(){
 xmllint --xpath '//*[local-name()="PeptideIdentification"]/*[local-name()="PeptideHit"][contains(@charge,"'$2'")]' $1 | grep -Pio '.*sequence="\K[^"]*' | uniq -u | wc -l
}

get_mzml_param_by_cv(){
 cat $1 | grep -Pio '.*accession="'$2'" value="\K[^"]*' | paste -sd+ - | bc -l
}

get_peptidoform_miscleavages_counts(){

 # Input params: 
 idxml_file=$1
 curr_dir=$(pwd)
 basename=$(basename $curr_dir/$idxml_file | cut -f 1 -d '.')

 xmllint --xpath '//*[local-name()="PeptideIdentification"]/*[local-name()="PeptideHit"]' $curr_dir/$idxml_file | grep -Pio '.*sequence="\K[^"]*' | uniq -u > $curr_dir/$basename.seq

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

get_sum_area_propionyl_protein_n_terminal(){
 xmllint --xpath '//*[local-name()="PeptideIdentification"]/*[local-name()="PeptideHit"][(starts-with(@aa_before,"M") or starts-with(@aa_before,"[")) and (contains(@sequence,".(Propionyl)") or contains(@sequence,".(Acetyl)"))]/../../intensity/text()' $1 | xargs printf "%1.0f\n" | paste -sd+ - | bc -l
}

get_sum_area_not_propionyl_protein_n_terminal(){
 xmllint --xpath '//*[local-name()="PeptideIdentification"]/*[local-name()="PeptideHit"][((starts-with(@aa_before,"M") or starts-with(@aa_before,"[")) and not(contains(@sequence,".(Propionyl)"))) and not(contains(@sequence,".(Acetyl)"))]/../../intensity/text()' $1 | xargs printf "%1.0f\n" | paste -sd+ - | bc -l
}

get_sum_area_phenylisocyanate_precursors_n_terminal(){
 xmllint --xpath '//*[local-name()="PeptideIdentification"]/*[local-name()="PeptideHit"][contains (@sequence,".(Phenylisocyanate)")]/../../intensity/text()' $1 | xargs printf "%1.0f\n" | paste -sd+ - | bc -l
}

get_sum_area_not_phenylisocyanate_precursors_n_terminal(){
 xmllint --xpath '//*[local-name()="PeptideIdentification"]/*[local-name()="PeptideHit"][not(contains (@sequence,".(Phenylisocyanate)"))]/../../intensity/text()' $1 | xargs printf "%1.0f\n" | paste -sd+ - | bc -l
}
