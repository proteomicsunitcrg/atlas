#!/bin/bash

get_mit(){
  # Input params: 
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

get_param_eic(){
  # Input params: 
  csv_file=$1
  mz_ref=$2 
  curr_dir=$(pwd)
  basename=$(basename $curr_dir/$csv_file | cut -f 1 -d '.')
  
  
  
}
