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
