

# Function to insert a key-value pair into the file
insert_key_value() {
    local key="$1"
    local value="$2"
    local file="$3"
    
    # Append new key-value pair to the file
    echo "$key=$value" >> "$file"
}

# Function to modify the value of an existing key
modify_key_value() {
    local key="$1"
    local new_value="$2"
    local file="$3"
    
    # Use sed to find and replace the value of the key
    sed -i "s/^$key=.*/$key=$new_value/" "$file"
}

# Function to remove a key-value pair from the file
remove_key_value() {
    local key="$1"
    local file="$2"
    
    # Use sed to remove the line containing the key
    sed -i "/^$key=/d" "$file"
}

get_num_prot_groups_fragpipe(){
 cat $1 | wc -l
}

get_num_peptidoforms_fragpipe(){
 cat $1 | wc -l
}

get_num_charges_fragpipe(){
 cat $1 | awk -F'\t' '{print $9}' | grep $2 | wc -l
}

get_peptidoform_miscleavages_counts_fragpipe(){

 # Input params: 
 tsv_file=$1
 curr_dir=$(pwd)
 basename=$(basename $curr_dir/$tsv_file | cut -f 1 -d '.')

 cat $curr_dir/$tsv_file | awk -F'\t' '{print $1}' | sort -u > $curr_dir/$basename.seq

 lines=$(cat $curr_dir/$basename.seq)

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

 cat $curr_dir/$basename.miscleavages.tsv | awk '{print $2}' | grep 0 | wc -l > $curr_dir/$basename.miscleavages.0
 cat $curr_dir/$basename.miscleavages.tsv | awk '{print $2}' | grep 1 | wc -l > $curr_dir/$basename.miscleavages.1
 cat $curr_dir/$basename.miscleavages.tsv | awk '{print $2}' | grep 2 | wc -l > $curr_dir/$basename.miscleavages.2
 cat $curr_dir/$basename.miscleavages.tsv | awk '{print $2}' | grep 3 | wc -l > $curr_dir/$basename.miscleavages.3

}

parse_combined_protein_tsv() {

        input_file=$1
        curr_dir=$(pwd)

        # Process each row of the TSV file
        result=$(awk -F'\t' '
        {
          first_col = $1
          last_col = $NF
          second_last_col = $(NF-1)
          # Check if the last column is numeric
          if (last_col ~ /^[0-9]+([.][0-9]+)?$/) {
             print first_col "\t0\t0\t0\t" last_col
          } else {
             print first_col "\t0\t0\t0\t" second_last_col
         }
        }
        ' "$curr_dir/$input_file")

        echo "$result" | sed '1d' > $curr_dir/extracted_quant_data.tsv
        echo -e "foo1\\nfoo2\\nfoo3" >> $curr_dir/foo.txt
        cat $curr_dir/foo.txt $curr_dir/extracted_quant_data.tsv > $curr_dir/extracted_quant_data_final.tsv

}
