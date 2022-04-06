#!/bin/bash

# Author : Roger Olivella
# Created: 02/03/2022

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

get_miscleavages_by_charge(){
 xmllint --xpath '//*[local-name()="PeptideIdentification"]/*[local-name()="PeptideHit"][contains(@charge,"'$2'") and (starts-with(@sequence,"R") and not(contains(@sequence,"RP"))) or (starts-with(@sequence,"K") and not(contains(@sequence,"KP"))) or (not(starts-with(@aa_before,"K")) and not(starts-with(@aa_before,"R"))) or (not(substring(@sequence, string-length(@sequence)) = "K") and not(substring(@sequence, string-length(@sequence)) = "R"))]' $1 | grep "<PeptideHit" | wc -l
}

get_num_prots(){
 grep -Pio 'indistinguishable_proteins_' $1 | wc -l
}

get_miscleavages_counts(){

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
     if [[ $pair = "K"* && ${#pair} == 2 && $pair != "KP" ]] || [[ $pair = "R"* && ${#pair} == 2 && $pair != "RP" ]]
     then
      ((missed+=1))
     fi
    done
    echo $line$'\t'$missed >> $curr_dir/$basename.miscleavages.tsv
 done
 echo "EOF"

 grep -o '0' $curr_dir/$basename.miscleavages.tsv | wc -l > $curr_dir/$basename.miscleavages.0
 grep -o '1' $curr_dir/$basename.miscleavages.tsv | wc -l > $curr_dir/$basename.miscleavages.1
 grep -o '2' $curr_dir/$basename.miscleavages.tsv | wc -l > $curr_dir/$basename.miscleavages.2
 grep -o '3' $curr_dir/$basename.miscleavages.tsv | wc -l > $curr_dir/$basename.miscleavages.3

}

get_num_peptd(){
 grep 'non-redundant peptide hits:' $1 | sed 's/^.*: //'
}

get_charges(){
 grep -Pio '.*charge="\K[^"]*' $1 | grep $2 | wc -l
}

get_mzml_param_by_cv(){
 cat $1 | grep -Pio '.*accession="'$2'" value="\K[^"]*' | paste -sd+ - | bc -l
}
