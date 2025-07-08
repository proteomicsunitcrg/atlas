//API:
url_api_signin             = params.url_api_signin
url_api_user               = params.url_api_user
url_api_pass               = params.url_api_pass
url_api_insert_file        = params.url_api_insert_file
url_api_insert_data        = params.url_api_insert_data
url_api_insert_quant       = params.url_api_insert_quant
url_api_fileinfo           = params.url_api_fileinfo
url_api_insert_modif       = params.url_api_insert_modif
num_max_prots              = params.num_max_prots

//Bash scripts folder:
binfolder                  = "$baseDir/bin"

//Tools: 
tools_folder               = params.tools_folder

//Output folder: 
output_folder              = params.output_folder

process insertPTMhistonesToQSample {
     tag { "${fileinfo_file}" }

     label 'clitools'

     input:
     file(checksum)
     file(fileinfo_file)
     file(idmapper_file)
     file(protinf_file)

     when:
     fileinfo_file.name =~ /((^[^_]+)MH)|((^[^_]+)MZ)/

     shell:
'''

checksum=$(cat !{checksum})

### Extract parameters from FileInfo file:

echo "Calculating parameters..."

## Total number of modified sites:
num_peptides_total=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
echo "[INFO] num_peptides_total: $num_peptides_total"

num_pic_n_term=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} ".(Phenylisocyanate)")
num_prop_k=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Propionyl)")
num_prop_n_term=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} ".(Propionyl)")
num_k_dim=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Dimethyl)")
num_k_trim=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Trimethyl)")
num_k_acet=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Acetyl)")
num_k_croton=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Crotonaldehyde)")
num_peptides_modif_sites=$(echo "$num_pic_n_term+$num_prop_k+$num_prop_n_term+$num_k_dim+$num_k_trim+$num_k_acet+$num_k_croton" | bc -l)
echo "[INFO] num_peptides_modif_sites: $num_peptides_modif_sites"

# Total number of modified peptides:
pattern=".(Phenylisocyanate)|K\\(Propionyl\\)|.(Propionyl)|K\\(Dimethyl\\)|K\\(Trimethyl\\)|K\\(Acetyl\\)|K\\(Crotonaldehyde\\)"
num_peptides_modif=$(source !{binfolder}/parsing.sh; get_num_all_modified_peptidoforms !{protinf_file} "$pattern")
echo "[INFO] num_peptides_modif: $num_peptides_modif"

### Extract parameters from IDMapper file:
sum_area_propionyl_protein_n_terminal=$(source !{binfolder}/parsing.sh; get_sum_area_propionyl_protein_n_terminal !{idmapper_file})
sum_area_not_propionyl_protein_n_terminal=$(source !{binfolder}/parsing.sh; get_sum_area_not_propionyl_protein_n_terminal !{idmapper_file})
percentage_propionyl=$(echo "$sum_area_propionyl_protein_n_terminal/($sum_area_propionyl_protein_n_terminal+$sum_area_not_propionyl_protein_n_terminal)" | bc -l)
sum_area_phenylisocyanate_precursors_n_terminal=$(source !{binfolder}/parsing.sh; get_sum_area_phenylisocyanate_precursors_n_terminal !{idmapper_file})
sum_area_not_phenylisocyanate_precursors_n_terminal=$(source !{binfolder}/parsing.sh; get_sum_area_not_phenylisocyanate_precursors_n_terminal !{idmapper_file})
percentage_pic=$(echo "$sum_area_phenylisocyanate_precursors_n_terminal/($sum_area_phenylisocyanate_precursors_n_terminal+$sum_area_not_phenylisocyanate_precursors_n_terminal)" | bc -l)

### Check:
echo $sum_area_propionyl_protein_n_terminal > sum_area_propionyl_protein_n_terminal
echo $sum_area_not_propionyl_protein_n_terminal > sum_area_not_propionyl_protein_n_terminal
echo $sum_area_phenylisocyanate_precursors_n_terminal > sum_area_phenylisocyanate_precursors_n_terminal
echo $sum_area_not_phenylisocyanate_precursors_n_terminal > sum_area_not_phenylisocyanate_precursors_n_terminal
echo $percentage_propionyl > percentage_propionyl
echo $percentage_pic > percentage_pic

#Insert to database through QSample API:

# Get token:
access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')

# Insert number of modified peptides:
curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_fileinfo} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"info": {"peptideHits": "'$num_peptides_total'", "peptideModified": "'$num_peptides_modif'"}}'

# Insert modifications counts:
curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Sum. area Propionyl N-term"},"value": "'$sum_area_propionyl_protein_n_terminal'"},{"modification": {"name": "Sum. area not Propionyl N-term"},"value": "'$sum_area_not_propionyl_protein_n_terminal'"},{"modification": {"name": "Sum. area PIC precursors N-term"},"value": "'$sum_area_phenylisocyanate_precursors_n_terminal'"},{"modification": {"name": "Sum. area not PIC precursors N-term"},"value": "'$sum_area_not_phenylisocyanate_precursors_n_terminal'"}]}'

'''
}
