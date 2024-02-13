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

#Totals:
num_peptides_total=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
num_pic_n_term=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} ".(Phenylisocyanate)")
num_prop_k=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Propionyl)")
num_prop_n_term=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} ".(Propionyl)")
num_k_dim=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Dimethyl)")
num_k_trim=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Trimethyl)")
num_k_acet=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Acetyl)")
num_k_croton=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Crotonaldehyde)")
num_peptides_modif=$(echo "$num_pic_n_term+$num_prop_k+$num_prop_n_term+$num_k_dim+$num_k_trim+$num_k_acet+$num_k_croton" | bc -l)

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

process insertPolymerContToQSample {
     tag { "${mzml_file}" }

     label 'clitools'

     input:
     file(checksum)
     tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

     shell:
     '''
     checksum=$(cat !{checksum})
     request_code=$(echo !{mzml_file} | awk -F'[_.]' '{print $1}')
     basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')
     !{tools_folder}/mzsniffer/mzsniffer !{mzml_file} -f json > output.json
     
     total_tic=$(jq '.[] | .total' output.json)
     total_tic_PEG_1H=$(jq '.[] | .polymers[].total' ./output.json | sed -n '1p')
     total_tic_PEG_2H=$(jq '.[] | .polymers[].total' ./output.json | sed -n '2p')
     total_tic_PEG_3H=$(jq '.[] | .polymers[].total' ./output.json | sed -n '3p')
     total_tic_PPG=$(jq '.[] | .polymers[].total' ./output.json | sed -n '4p')
     total_tic_Triton_X_100=$(jq '.[] | .polymers[].total' ./output.json | sed -n '5p')
     total_tic_Triton_X_100_reduced=$(jq '.[] | .polymers[].total' ./output.json | sed -n '6p') 
     total_tic_Triton_X_100_na=$(jq '.[] | .polymers[].total' ./output.json | sed -n '7p')
     total_tic_Triton_X_100_reduced_na=$(jq '.[] | .polymers[].total' ./output.json | sed -n '8p')
     total_tic_Triton_X_101=$(jq '.[] | .polymers[].total' ./output.json | sed -n '9p')
     total_tic_Triton_X_101_reduced=$(jq '.[] | .polymers[].total' ./output.json | sed -n '10p')     
     total_tic_Polysiloxane=$(jq '.[] | .polymers[].total' ./output.json | sed -n '11p')
     total_tic_Tween_20=$(jq '.[] | .polymers[].total' ./output.json | sed -n '12p')
     total_tic_Tween_40=$(jq '.[] | .polymers[].total' ./output.json | sed -n '13p')
     total_tic_Tween_60=$(jq '.[] | .polymers[].total' ./output.json | sed -n '14p')
     total_tic_Tween_80=$(jq '.[] | .polymers[].total' ./output.json | sed -n '15p')
     total_tic_IGEPAL=$(jq '.[] | .polymers[].total' ./output.json | sed -n '16p')

     percent_tic_PEG_1H=$(printf %.4f $(echo "$total_tic_PEG_1H*100/$total_tic" | bc -l))
     percent_tic_PEG_2H=$(printf %.4f $(echo "$total_tic_PEG_2H*100/$total_tic" | bc -l))
     percent_tic_PEG_3H=$(printf %.4f $(echo "$total_tic_PEG_3H*100/$total_tic" | bc -l))
     percent_tic_PPG=$(printf %.4f $(echo "$total_tic_PPG*100/$total_tic" | bc -l))
     percent_tic_Triton_X_100=$(printf %.4f $(echo "$total_tic_Triton_X_100*100/$total_tic" | bc -l))
     percent_tic_Triton_X_100_reduced=$(printf %.4f $(echo "$total_tic_Triton_X_100_reduced*100/$total_tic" | bc -l))
     percent_tic_Triton_X_100_na=$(printf %.4f $(echo "$total_tic_Triton_X_100_na*100/$total_tic" | bc -l))
     percent_tic_Triton_X_100_reduced_na=$(printf %.4f $(echo "$total_tic_Triton_X_100_reduced_na*100/$total_tic" | bc -l))
     percent_tic_Triton_X_101=$(printf %.4f $(echo "$total_tic_Triton_X_101*100/$total_tic" | bc -l))
     percent_tic_Triton_X_101_reduced=$(printf %.4f $(echo "$total_tic_Triton_X_101_reduced*100/$total_tic" | bc -l))
     percent_tic_Polysiloxane=$(printf %.4f $(echo "$total_tic_Polysiloxane*100/$total_tic" | bc -l))
     percent_tic_Tween_20=$(printf %.4f $(echo "$total_tic_Tween_20*100/$total_tic" | bc -l))
     percent_tic_Tween_40=$(printf %.4f $(echo "$total_tic_Tween_40*100/$total_tic" | bc -l))
     percent_tic_Tween_60=$(printf %.4f $(echo "$total_tic_Tween_60*100/$total_tic" | bc -l))
     percent_tic_Tween_80=$(printf %.4f $(echo "$total_tic_Tween_80*100/$total_tic" | bc -l))
     percent_tic_IGEPAL=$(printf %.4f $(echo "$total_tic_IGEPAL*100/$total_tic" | bc -l))

     echo $percent_tic_PEG_1H
     echo $percent_tic_PEG_2H
     echo $percent_tic_PEG_3H
     echo $percent_tic_PPG
     echo $percent_tic_Triton_X_100
     echo $percent_tic_Triton_X_100_reduced
     echo $percent_tic_Triton_X_100_na
     echo $percent_tic_Triton_X_100_reduced_na
     echo $percent_tic_Triton_X_101
     echo $percent_tic_Triton_X_101_reduced
     echo $percent_tic_Polysiloxane
     echo $percent_tic_Tween_20
     echo $percent_tic_Tween_40
     echo $percent_tic_Tween_60
     echo $percent_tic_Tween_80
     echo $percent_tic_IGEPAL

     # Insert to database through QSample API:

     # Get token:
     access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')

     # Insert modifications counts:
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "PEG+1H"},"value": '$percent_tic_PEG_1H'}]}'    
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "PEG+2H"},"value": '$percent_tic_PEG_2H'}]}' 
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "PEG+3H"},"value": '$percent_tic_PEG_3H'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "PPG"},"value": '$percent_tic_PPG'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-100"},"value": '$percent_tic_Triton_X_100'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-100 (Reduced)"},"value": '$percent_tic_Triton_X_100_reduced'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-100 (Na)"},"value": '$percent_tic_Triton_X_100_na'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-100 (Reduced, Na)"},"value": '$percent_tic_Triton_X_100_reduced_na'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-101"},"value": '$percent_tic_Triton_X_101'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Triton X-101 (Reduced)"},"value": '$percent_tic_Triton_X_101_reduced'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Polysiloxane"},"value": '$percent_tic_Polysiloxane'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Tween-20"},"value": '$percent_tic_Tween_20'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Tween-40"},"value": '$percent_tic_Tween_40'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Tween-60"},"value": '$percent_tic_Tween_60'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Tween-80"},"value": '$percent_tic_Tween_80'}]}'
     curl -v -X POST -H "Authorization: Bearer $access_token" 10.102.1.54/api/modification/pipeline -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "IGEPAL CA-630 (NP-40)"},"value": '$percent_tic_IGEPAL'}]}'
	
     # Output folder: 
     #echo "Polymer contaminants for $basename_sh: \n\nPEG+1H\t$percent_tic_PEG_1H\nPEG+2H\t$percent_tic_PEG_2H\nPEG+3H\t$percent_tic_PEG_3H\nPPG\t$percent_tic_PPG\nTriton X-100\t$percent_tic_Triton_X_100\nTriton X-100 (Reduced)\t$percent_tic_Triton_X_100_reduced\nTriton X-100 (Na)\t$percent_tic_Triton_X_100_na\nTriton X-100 (Reduced, Na)\t$percent_tic_Triton_X_100_reduced_na\nTriton X-101\t$percent_tic_Triton_X_101\nTriton X-101 (Reduced)\t$percent_tic_Triton_X_101_reduced\nPolysiloxane\t$percent_tic_Polysiloxane\nTween-20\t$percent_tic_Tween_20\nTween-40\t$percent_tic_Tween_40\nTween-60\t$percent_tic_Tween_60\nTween-80\t$percent_tic_Tween_80\nIGEPAL CA-630 (NP-40)\t$percent_tic_IGEPAL\n\n" >> /users/pr/proteomics/mygit/atlas-output/$request_code.polymer_cont.tsv
     

     '''
}
