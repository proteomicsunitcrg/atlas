//QCloud2 API:
qcloud2_api_signin             = params.qcloud2_api_signin
qcloud2_api_user               = params.qcloud2_api_user
qcloud2_api_pass               = params.qcloud2_api_pass
qcloud2_api_insert_file        = params.qcloud2_api_insert_file
qcloud2_api_insert_data        = params.qcloud2_api_insert_data
qcloud2_api_insert_quant       = params.qcloud2_api_insert_quant
qcloud2_api_fileinfo           = params.qcloud2_api_fileinfo
qcloud2_api_insert_modif       = params.qcloud2_api_insert_modif
qcloud2_api_insert_wetlab_file = params.qcloud2_api_insert_wetlab_file
qcloud2_api_insert_wetlab_data = params.qcloud2_api_insert_wetlab_data
num_max_prots                  = params.num_max_prots

//Bash scripts folder:
binfolder                = "$baseDir/bin"


process insertFileToQSample {
        tag { "${mzml_file}" }

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        output:
        file("${filename}.checksum")

        when:
        filename =~ /^((?!QCGL|QCDL|QCFL|QCPL|QCRL|QCHL).)*$/

        shell:
        '''
        request_code=$(echo !{filename} | awk -F'[_.]' '{print $1}')
        checksum=$(source !{binfolder}/utils.sh; get_checksum !{path} !{filename})
        echo $checksum > !{filename}.checksum
        creation_date=$(grep -Pio '.*startTimeStamp="\\K[^"]*' !{mzml_file} | sed 's/Z//g' | xargs -I{} date -d {} +"%Y-%m-%dT%T")
        echo $creation_date > creation_date
        access_token=$(source !{binfolder}/api.sh; get_api_qcloud2_access_token !{qcloud2_api_signin} !{qcloud2_api_user} !{qcloud2_api_pass})
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_file}/$request_code -H "Content-Type: application/json" --data '{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'!{basename}'"}'
        '''
}


process insertWetlabFileToQSample {
        tag { "${mzml_file}" }

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        output:
        file("${filename}.checksum")

        when:
        filename =~ /QCGL|QCDL|QCFL|QCPL|QCRL|QCHL/

        shell:
        '''
        api_key=""
        basename_sh=!{basename}
        if [[ $basename_sh == *"QCGL"* ]]; then api_key="7765746c-6162-3300-0000-000000000000"; fi
        if [[ $basename_sh == *"QCDL"* ]]; then api_key="6170694b-6579-3100-0000-000000000000"; fi
        if [[ $basename_sh == *"QCFL"* ]]; then api_key="7765746c-6162-3500-0000-000000000000"; fi
        if [[ $basename_sh == *"QCPL"* ]]; then api_key="7765746c-6162-3400-0000-000000000000"; fi
        if [[ $basename_sh == *"QCRL"* ]]; then api_key="7765746c-6162-3200-0000-000000000000"; fi
        if [[ $basename_sh == *"QCHL"* ]]; then api_key="7765746c-6162-3600-0000-000000000000"; fi
        checksum=$(md5sum !{path}/!{filename} | awk '{print $1}')
        echo $checksum > !{filename}.checksum
        creation_date=$(grep -Pio '.*startTimeStamp="\\K[^"]*' !{mzml_file} | sed 's/Z//g' | xargs -I{} date -d {} +"%Y-%m-%dT%T")
        replicate=$(echo !{filename} | cut -d"_" -f4 | cut -c2-3)
        year=$(echo !{filename} | cut -d"_" -f1 | cut -c1-4)
        week=$(echo !{filename} | cut -d"_" -f3 | cut -c2-3 | bc)
        access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_file}/$api_key -H "Content-Type: application/json" --data '{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'$basename_sh'","replicate": '$replicate',"year": '$year',"week": '$week'}'
        '''
}

process insertDataToQSample {

        tag { "${protinf_file}" }
        label 'clitools'

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)
        file(idfilter_score_file)
        file(qccalc_file)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        when:
        fileinfo_file =~ /^((?!QCGL|QCDL|QCFL|QCPL|QCRL).)*$/

        shell:
        '''
        # Parsings: 
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
 
        source !{binfolder}/parsing.sh; get_peptidoform_miscleavages_counts !{protinf_file}
        miscleavages_0=$(cat *.miscleavages.0)
        miscleavages_1=$(cat *.miscleavages.1)
        miscleavages_2=$(cat *.miscleavages.2)
        miscleavages_3=$(cat *.miscleavages.3)
        charge_2=$(source !{binfolder}/parsing.sh; get_num_charges !{protinf_file} 2)
        charge_3=$(source !{binfolder}/parsing.sh; get_num_charges !{protinf_file} 3)
        charge_4=$(source !{binfolder}/parsing.sh; get_num_charges !{protinf_file} 4)
        total_base_peak_intenisty=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000505)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
 
        # Checks: 
        echo $total_base_peak_intenisty > total_base_peak_intenisty
        echo $total_tic > total_tic
        echo $num_prots > num_prots
        echo $charge_2 > charge_2
        echo $charge_3 > charge_3 
        echo $charge_4 > charge_4

        # QCloud2 API posts:
        checksum=$(cat !{checksum})
        access_token=$(source !{binfolder}/api.sh; get_api_qcloud2_access_token !{qcloud2_api_signin} !{qcloud2_api_user} !{qcloud2_api_pass})
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "3","value": "'$charge_2'"},{"contextSource": "4","value": "'$charge_3'"},{"contextSource": "5","value": "'$charge_4'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "7","value": "'$total_base_peak_intenisty'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "19","value": "'$total_tic'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "20","value": "'$miscleavages_0'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "21","value": "'$miscleavages_1'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "22","value": "'$miscleavages_2'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "23","value": "'$miscleavages_3'"}]}]}'

        '''
}

process insertDIANNDataToQSample {

        tag { "${tsv_file}" }
        label 'clitools'

        input:
        file(checksum)
        file(tsv_file)
        file(mzml_file)

        shell:
        '''
        # Parsings:
        num_prots=$(source !{binfolder}/parsing_diann.sh; get_num_prot_groups_diann !{tsv_file})
        num_peptd=$(source !{binfolder}/parsing_diann.sh; get_num_peptidoforms_diann !{tsv_file})

        source !{binfolder}/parsing_diann.sh; get_peptidoform_miscleavages_counts_diann !{tsv_file}
        miscleavages_0=$(cat *.miscleavages.0)
        miscleavages_1=$(cat *.miscleavages.1)
        miscleavages_2=$(cat *.miscleavages.2)
        miscleavages_3=$(cat *.miscleavages.3)
        charge_2=$(source !{binfolder}/parsing_diann.sh; get_num_charges_diann !{tsv_file} 2)
        charge_3=$(source !{binfolder}/parsing_diann.sh; get_num_charges_diann !{tsv_file} 3)
        charge_4=$(source !{binfolder}/parsing_diann.sh; get_num_charges_diann !{tsv_file} 4)
        total_base_peak_intenisty=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000505)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)

        # Checks:
        echo $total_base_peak_intenisty > total_base_peak_intenisty
        echo $total_tic > total_tic
        echo $num_prots > num_prots
        echo $charge_2 > charge_2
        echo $charge_3 > charge_3
        echo $charge_4 > charge_4

        # QCloud2 API posts:
        checksum=$(cat !{checksum})
        access_token=$(source !{binfolder}/api.sh; get_api_qcloud2_access_token !{qcloud2_api_signin} !{qcloud2_api_user} !{qcloud2_api_pass})
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "3","value": "'$charge_2'"},{"contextSource": "4","value": "'$charge_3'"},{"contextSource": "5","value": "'$charge_4'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "7","value": "'$total_base_peak_intenisty'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "19","value": "'$total_tic'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "20","value": "'$miscleavages_0'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "21","value": "'$miscleavages_1'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "22","value": "'$miscleavages_2'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "23","value": "'$miscleavages_3'"}]}]}'

        '''
}


process insertQuantToQSample {
    tag { "${csvfile}" }

    input:
    file(checksum)
    file(csvfile)

    when: 
    csvfile =~ /^((?!QCGL|QCDL|QCFL|QCPL|QCRL).)*$/

    shell:
    '''
    checksum=$(cat !{checksum})
    !{binfolder}/quant2json.sh !{csvfile} $checksum output.json !{num_max_prots}
    access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
    curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_quant} -H "Content-Type: application/json" --data '@output.json'
    '''
}

process insertPhosphoModifToQSample {
    tag { "${fileinfo_file}" }

     input:
     file(checksum)
     file(fileinfo_file)
     file(protinf_file)

     when:
     fileinfo_file.name =~ /((^[^_]+)MP)|((^[^_]+)MA)|((^[^_]+)MB)/

     shell:
        '''
        checksum=$(cat !{checksum})

        num_peptides_total=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        num_mod_phospho_s=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "S(Phospho)")
        num_mod_phospho_t=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "T(Phospho)")
        num_mod_phospho_y=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "Y(Phospho)")
        num_peptides_modif=$(echo "$num_mod_phospho_s+$num_mod_phospho_t+$num_mod_phospho_y" | bc -l)

        access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_fileinfo} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"info": {"peptideHits": "'$num_peptides_total'", "peptideModified": "'$num_peptides_modif'"}}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "PHOSPHO (S)"},"value": "'$num_mod_phospho_s'"},{"modification": {"name": "PHOSPHO (T)"},"value": "'$num_mod_phospho_t'"},{"modification": {"name": "PHOSPHO (Y)"},"value": "'$num_mod_phospho_y'"}]}'
        '''
}

process insertPTMhistonesToQSample {
     tag { "${fileinfo_file}" }

     label 'clitools'

     input:
     file(checksum)
     file(fileinfo_file)
     file(idmapper_file)
     file(protinf_file)

     when:
     fileinfo_file.name =~ /((^[^_]+)MH)|((^[^_]+)MZ)|QCHL/

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
access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')

# Insert number of modified peptides:
curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_fileinfo} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"info": {"peptideHits": "'$num_peptides_total'", "peptideModified": "'$num_peptides_modif'"}}'

# Insert modifications counts:
curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Sum. area Propionyl N-term"},"value": "'$sum_area_propionyl_protein_n_terminal'"},{"modification": {"name": "Sum. area not Propionyl N-term"},"value": "'$sum_area_not_propionyl_protein_n_terminal'"},{"modification": {"name": "Sum. area PIC precursors N-term"},"value": "'$sum_area_phenylisocyanate_precursors_n_terminal'"},{"modification": {"name": "Sum. area not PIC precursors N-term"},"value": "'$sum_area_not_phenylisocyanate_precursors_n_terminal'"}]}'

# Insert percentages for HistoneQC:
if [[ !{fileinfo_file} == *"QCHL"* ]]; then
    echo "Inserting QCHL percentages..."
    curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "7765746c-6162-3400-0000-000000000000","id": "1"},"values": [{"contextSource": "8","value": "'$percentage_propionyl'"},{"contextSource": "9","value": "'$percentage_pic'"}]}]}'
fi


'''
}

process insertSilacToQSample {
     tag { "${fileinfo_file}" }

     input:
     file(checksum)
     file(fileinfo_file)
     file(protinf_file)

     when:
     fileinfo_file.name =~ /((^[^_]+)LC)|((^[^_]+)LP)|((^[^_]+)LQ)|((^[^_]+)LU)/

     shell:
        '''
        checksum=$(cat !{checksum})
        num_peptides_total=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        num_mod_label_R=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "R(Label:13C(6)15N(4))")
        num_mod_label_K=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(Label:13C(6)15N(2))")
        num_peptides_modif=$(echo "$num_mod_label_R+$num_mod_label_K" | bc -l)
       
        access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_fileinfo} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"info": {"peptideHits": "'$num_peptides_total'", "peptideModified": "'$num_peptides_modif'"}}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Label:13C(6)15N(2) (K)"},"value": "'$num_mod_label_K'"},{"modification": {"name": "Label:13C(6)15N(4) (R)"},"value": "'$num_mod_label_R'"}]}'
        '''
}

process insertTmtToQSample {
     tag { "${fileinfo_file}" }

     input:
     file(checksum)
     file(fileinfo_file)
     file(protinf_file)

     when:
     fileinfo_file.name =~ /((^[^_]+)LT)|((^[^_]+)LF)/

     shell:
        '''
        checksum=$(cat !{checksum})
        num_peptides_total=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        num_mod_tmt_K=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "K(TMT6plex)")
        num_mod_tmt_N=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} ".(TMT6plex)")       
        num_peptides_modif=$(echo "$num_mod_tmt_K+$num_mod_tmt_N" | bc -l)

        access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_fileinfo} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"info": {"peptideHits": "'$num_peptides_total'", "peptideModified": "'$num_peptides_modif'"}}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "TMT6plex (K)"},"value": "'$num_mod_tmt_K'"},{"modification": {"name": "TMT6plex (N-term)"},"value": "'$num_mod_tmt_N'"}]}'
        '''
}

process insertWetlabInSolutionDataToQSample {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCDL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        
        #echo $num_peptd > /users/pr/qsample/test/atlas-peptide/output/!{protinf_file}.num_peptd.wetlab_insolution
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd

access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}

process insertWetlabInGelDataToQSample {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCGL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        
        #echo $num_peptd > /users/pr/qsample/test/atlas-peptide/output/!{protinf_file}.num_peptd.wetlab_ingel
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd

access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "7765746c-6162-3300-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}

process insertWetlabFaspDataToQSample {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCFL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        
        #echo $num_peptd > /users/pr/qsample/test/atlas-peptide/output/!{protinf_file}.num_peptd.wetlab_fasp
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd

access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "7765746c-6162-3500-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}

process insertWetlabPhosphoDataToQSample {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCPL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})        
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        num_mod_phospho_s=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "S(Phospho)")
        num_mod_phospho_t=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "T(Phospho)")
        num_mod_phospho_y=$(source !{binfolder}/parsing.sh; get_num_peptidoform_sites !{protinf_file} "Y(Phospho)")
        num_peptides_modif=$(echo "$num_mod_phospho_s+$num_mod_phospho_t+$num_mod_phospho_y" | bc -l)


        #Check: 
        echo $num_prots > num_prots

access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "7765746c-6162-3400-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "7765746c-6162-3400-0000-000000000000","id": "1"},"values": [{"contextSource": "24","value": "'$num_peptides_modif'"}]}]}'
        '''
}

process insertWetlabAgilentDataToQSample {
        tag { "${fileinfo_file}" }

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)

        when:
        fileinfo_file.name =~ /QCRL/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        
        #Check: 
        #echo $num_peptd > /users/pr/qsample/test/atlas-peptide/output/!{protinf_file}.num_peptd.wetlab_agilent  
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd

access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "7765746c-6162-3200-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}
