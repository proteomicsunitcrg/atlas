#!/bin/bash

get_checksum(){
  md5sum $1/$2 | awk '{print $1}'
}

get_log_base_n(){
 echo 'l('$1')/l('$2')' | bc -l
}

get_mzml_date(){
 grep -Pio '.*startTimeStamp="\K[^"]*' $1 | sed 's/Z//g' | xargs -I{} date -d {} +"%Y-%m-%d %T"
}
