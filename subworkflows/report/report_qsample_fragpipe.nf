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
api_key_qc_params          = params.api_key_qc_params

//Bash scripts folder:
binfolder                      = "$baseDir/bin"

process insertFragpipeFileToQSample {
        tag { "${mzml_file}" }
        label 'insertQSampleWithoutClitools' 

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        output:
        file("${filename}.checksum")

        shell:
        '''
        request_code=$(echo !{filename} | awk -F'[_.]' '{print $1}')
        checksum=$(source !{binfolder}/utils.sh; get_checksum !{path} !{filename})
        echo $checksum > !{filename}.checksum
        mzml_file=$(ls -l *.mzML | awk '{print $11}')
        echo $mzml_file > mzml_file
        creation_date=$(source !{binfolder}/utils.sh; get_mzml_date $mzml_file)
        data_string='{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'!{basename}'"}'
        echo $data_string > data_string
        access_token=$(source !{binfolder}/api.sh; get_api_access_token !{url_api_signin} !{url_api_user} !{url_api_pass})
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_file}/$request_code -H "Content-Type: application/json" --data @data_string 
        '''
}

process insertFragpipeDataToQSample {

        tag { "${mzml_file}" }
        label 'insertQSampleClitools'

        input:
        file(checksum)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
        file('peptide.tsv')
        file('protein.tsv')
        file('ion.tsv')
        file('combined_protein.tsv')
        file('global.summary.tsv')

        shell:
        '''
        
        # QC metrics:
        echo "[INFO] Computing general QC metrics..."
        checksum=$(cat !{checksum})
        num_prots=$(source !{binfolder}/parsing_fragpipe.sh; get_num_prot_groups_fragpipe ./protein.tsv)
        num_peptd=$(source !{binfolder}/parsing_fragpipe.sh; get_num_peptidoforms_fragpipe ./peptide.tsv)
        charge_2=$(source !{binfolder}/parsing_fragpipe.sh; get_num_charges_fragpipe ./ion.tsv 2)   
        charge_3=$(source !{binfolder}/parsing_fragpipe.sh; get_num_charges_fragpipe ./ion.tsv 3)   
        charge_4=$(source !{binfolder}/parsing_fragpipe.sh; get_num_charges_fragpipe ./ion.tsv 4)
        source !{binfolder}/parsing_fragpipe.sh; get_peptidoform_miscleavages_counts_fragpipe ./peptide.tsv
        miscleavages_0=$(cat *.miscleavages.0)
        miscleavages_1=$(cat *.miscleavages.1)
        miscleavages_2=$(cat *.miscleavages.2)
        miscleavages_3=$(cat *.miscleavages.3)
        total_base_peak_intenisty=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000505)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
        
        ## Extract quantification data: 
        echo "[INFO] Extracting quantification data..."
        source !{binfolder}/parsing_fragpipe.sh; parse_combined_protein_tsv ./combined_protein.tsv
        !{binfolder}/quant2json.sh extracted_quant_data_final.tsv $checksum output.json !{num_max_prots} 

        # Checks: 
        echo $total_base_peak_intenisty > total_base_peak_intenisty
        echo $total_tic > total_tic
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd
        echo $charge_2 > charge_2                                                       
        echo $charge_3 > charge_3                                                       
        echo $charge_4 > charge_4

        # API calls: 
        echo "[INFO] API calls..."
        api_key_sh=!{api_key_qc_params}
        access_token=$(source !{binfolder}/api.sh; get_api_access_token !{url_api_signin} !{url_api_user} !{url_api_pass})
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "3","value": "'$charge_2'"},{"contextSource": "4","value": "'$charge_3'"},{"contextSource": "5","value": "'$charge_4'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "7","value": "'$total_base_peak_intenisty'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "19","value": "'$total_tic'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "20","value": "'$miscleavages_0'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "21","value": "'$miscleavages_1'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "22","value": "'$miscleavages_2'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "'$api_key_sh'","id": "1"},"values": [{"contextSource": "23","value": "'$miscleavages_3'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_quant} -H "Content-Type: application/json" --data '@output.json'
        echo "[INFO] EOF"
        '''
}

process insertFragpipeSecReactDataToQSample {
        tag { "global.summary.tsv" }
   
        input:
        file(checksum)
        file('peptide.tsv')                                                             
        file('protein.tsv')                                                             
        file('ion.tsv')                                                                 
        file('combined_protein.tsv')
        file('global.summary.tsv')    
 
        shell:
        '''
        checksum=$(cat !{checksum})
        
        ### Secondary reactions:
        echo "[INFO] Computing secondary reactions..."
        Formylation=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Formylation" global.summary.tsv) 
        Carbamyl=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Carbamyl" global.summary.tsv)
        Oxidation=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Oxidation" global.summary.tsv)
        Ammonialoss=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Ammonia loss" global.summary.tsv)
        Acetyl=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Acetyl" global.summary.tsv)
        Deamidation=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Deamidation" global.summary.tsv)
        Amidation=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Amidation" global.summary.tsv)
        Isotopic_peak_error=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Isotopic peak error" global.summary.tsv)
        Didehydrobutyrine_Water_loss=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Didehydrobutyrine/Water loss" global.summary.tsv)
        Methyl=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Methyl" global.summary.tsv)
        Carbamidomethyl_Addition_of_G=$(source !{binfolder}/parsing_fragpipe.sh; parse_global_modsummary "Carbamidomethyl/Addition of G" global.summary.tsv)

        ### Inserts API:
        echo "[INFO] API inserts..."
        access_token=$(curl -s -X POST !{url_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{url_api_user}'","password":"'!{url_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        
        if [[ -n "$Formylation" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Formylation"},"value": "'$Formylation'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "26","value": "'$Formylation'"}]}]}'
        fi
        
        if [[ -n "$Carbamyl" ]]; then   
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Carbamyl"},"value": "'$Carbamyl'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKiey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "27","value": "'$Carbamyl'"}]}]}'
        fi
        
        if [[ -n "$Oxidation" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Oxidation"},"value": "'$Oxidation'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "28","value": "'$Oxidation'"}]}]}'
        fi

        if [[ -n "$Ammonialoss" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Ammonia loss"},"value": "'$Ammonialoss'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "29","value": "'$Ammonialoss'"}]}]}'
        fi

        if [[ -n "$Acetyl" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Acetyl"},"value": "'$Acetyl'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "30","value": "'$Acetyl'"}]}]}'
        fi

        if [[ -n "$Deamidation" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Deamidation"},"value": "'$Deamidation'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "31","value": "'$Deamidation'"}]}]}'
        fi

        if [[ -n "$Amidation" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Amidation"},"value": "'$Amidation'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "32","value": "'$Amidation'"}]}]}'
        fi

        if [[ -n "$Isotopic_peak_error" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Isotopic peak error"},"value": "'$Isotopic_peak_error'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "33","value": "'$Isotopic_peak_error'"}]}]}'
        fi

        if [[ -n "$Didehydrobutyrine_Water_loss" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Didehydrobutyrine/Water loss"},"value": "'$Didehydrobutyrine_Water_loss'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "34","value": "'$Didehydrobutyrine_Water_loss'"}]}]}'
        fi

        if [[ -n "$Methyl" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Methyl"},"value": "'$Methyl'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "35","value": "'$Methyl'"}]}]}'
        fi

        if [[ -n "$Carbamidomethyl_Addition_of_G" ]]; then
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Carbamidomethyl/Addition of G"},"value": "'$Carbamidomethyl_Addition_of_G'"}]}'
           curl -v -X POST -H "Authorization: Bearer $access_token" !{url_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "36","value": "'$Carbamidomethyl_Addition_of_G'"}]}]}'
        fi
        
        echo "[INFO] EOF"
        '''
}
