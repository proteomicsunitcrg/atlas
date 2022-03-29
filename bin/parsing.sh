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

get_num_peptd(){
 grep 'non-redundant peptide hits:' $1 | sed 's/^.*: //'
}

get_charges(){
 grep -Pio '.*charge="\K[^"]*' $1 | grep $2 | wc -l
}

get_mzml_param_by_cv(){
 cat $1 | grep -Pio '.*accession="'$2'" value="\K[^"]*' | paste -sd+ - | bc -l
}


