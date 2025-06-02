#!/bin/bash

get_mit(){

  mzml_file=$1
  cv_ms_level=$2
  ms_level=$3
  cv_it=$4
  curr_dir=$(pwd)
  basename=$(basename $curr_dir/$mzml_file | cut -f 1 -d '.')

  xmllint --xpath '//*[local-name()="spectrum"]/*[@accession="'$cv_ms_level'"][@value="'$ms_level'"]/../*[local-name()="scanList"]/*[local-name()="scan"]/*[local-name()="cvParam"][@accession="'$cv_it'"]/@value' $mzml_file > $curr_dir/$basename.it.str

  grep -o '\".*\"' $curr_dir/$basename.it.str | sed 's/"//g' > $curr_dir/$basename.it.num

  datamash median 1 < $curr_dir/$basename.it.num

}

set_csv_to_json(){

 csv_file=$1
 basename_sh=$2
 jq --slurp --raw-input --raw-output 'split("\n") | .[3:] | map(split(",")) | map({"RT": .[0],"mz": .[1],"RTobs": .[2],"dRT": .[3],"mzobs": .[4],"dppm": .[5],"intensity": .[6],"area": .[7]}) | del(..|nulls)' $csv_file > $basename_sh".json"
        
}

get_qc_area_from_json(){

 mass=$1
 basename_sh=$2 
 jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | .area' $basename_sh".json"

}

get_qc_area_from_json_by_mass_and_rt(){

 mass=$1
 rt=$2
 basename_sh=$3 
 jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | select(.RT | tostring | startswith("'$rt'")) | .area' $basename_sh".json"

}


get_qc_dppm_from_json(){

 mass=$1
 basename_sh=$2
 jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | .dppm' $basename_sh".json"

}

get_qc_dppm_from_json_by_mass_and_rt(){

 mass=$1
 rt=$2
 basename_sh=$3 
 jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | select(.RT | tostring | startswith("'$rt'")) | .dppm' $basename_sh".json"

}

get_qc_RTobs_from_json(){

 mass=$1
 basename_sh=$2
 jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | .RTobs' $basename_sh".json"

}

get_qc_RTobs_from_json_by_mass_and_rt(){

 mass=$1
 rt=$2
 basename_sh=$3 
 jq -r '.[] | select(.mz | tostring | startswith("'$mass'")) | select(.RT | tostring | startswith("'$rt'")) | .RTobs' $basename_sh".json"

}

create_qcloud_json(){

 checksum=$1
 qccv=$2
 contextsource=$3
 
 contextsource_underscore=$(echo $contextsource | tr : _)
 json_basename=$checksum"_"$contextsource_underscore
 echo '{"file":{"checksum":"'$checksum'"},"data":[{"parameter":{"qCCV":"'$qccv'"},"values" : [{}]}]}' > $json_basename".txt"
 jq . $json_basename".txt" > $json_basename".json" 

}

create_qcloud_json_monitored_peptides(){

 checksum=$1
 qccv=$2
 qccv_underscore=$(echo $qccv | tr : _)
 json_basename=$checksum"_"$qccv_underscore
 echo '{"file":{"checksum":"'$checksum'"},"data":[{"parameter":{"qCCV":"'$qccv'"},"values" : []}]}' > $json_basename".txt"
 jq . $json_basename".txt" > $json_basename".json"

}


set_value_to_qcloud_json(){

 checksum=$1
 value=$2
 qccv=$3
 contextsource=$4
 
 contextsource_underscore=$(echo $contextsource | tr : _)
 json_basename=$checksum"_"$contextsource_underscore
 
 jq '.data[].values[] += {"value":"'$value'","contextSource":"'$contextsource'"}' $json_basename".json" | sponge $json_basename".json"

}

set_value_to_qcloud_json_monitored_peptides(){

 checksum=$1
 value=$2
 qccv=$3
 contextsource=$4

 qccv_underscore=$(echo $qccv | tr : _)
 json_basename=$checksum"_"$qccv_underscore

 jq '.data[].values += [{"value":"'$value'","contextSource":"'$contextsource'"}]' $json_basename".json" | sponge $json_basename".json"

}

convert_scientific_notation(){

 value=$1
 echo $value | sed 's/[eE]+*/\*10\^/'

}
