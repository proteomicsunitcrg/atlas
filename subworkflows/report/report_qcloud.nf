//API:
url_api_qcloud_signin             = params.url_api_qcloud_signin
url_api_qcloud_user               = params.url_api_qcloud_user
url_api_qcloud_pass               = params.url_api_qcloud_pass
url_api_qcloud_insert_data        = params.url_api_qcloud_insert_data
url_api_qcloud_insert_file        = params.url_api_qcloud_insert_file

//Bash scripts folder:
binfolder                  = "$baseDir/bin"
instrument_folder          = params.instrument_folder

process insertDataToQCloud {

        tag { "${csv_file}" }
        label 'clitools'

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
        file (csv_file)

        shell:
        '''
        # Parsings:
        checksum=$(source !{binfolder}/utils.sh; get_checksum !{path} !{filename})
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
        total_tic=$(echo "$total_tic * 0.0000000001" | bc -l)
        mit_ms1=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 1 MS:1000927)
        mit_ms2=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 2 MS:1000927)
        request_code=$(echo !{mzml_file} | awk -F'[_.]' '{print $1}')
        basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')
        reversed_filename=$(echo $basename_sh | rev)
        first_3_underscores=$(echo $reversed_filename | cut -d'_' -f1-3)
        reversed_first_3_underscores=$(echo $first_3_underscores | rev)
        rest_of_filename=$(echo $reversed_filename | cut -d'_' -f4-)
        reversed_rest_of_filename=$(echo $rest_of_filename | rev)
        labsysid=$(echo $reversed_first_3_underscores | cut -d'_' -f1) 
        creation_date=$(source !{binfolder}/utils.sh; get_mzml_date !{mzml_file})
        insert_file_string='{"creationDate": "'$creation_date'","filename": "'$reversed_rest_of_filename'","checksum": "'$checksum'"}'
        echo $insert_file_string > insert_file_string
 
        # QC01 XIC: 
        csv_file_sh=$(echo $PWD"/"!{csv_file})
        $(source !{binfolder}/parsing_qcloud.sh; set_csv_to_json $csv_file_sh $basename_sh)
  
        LVN_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '582.3' $basename_sh)
        LVN_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '582.8' $basename_sh)
        LVN_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '583.3' $basename_sh)
        LVN_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $LVN_area_isotope_1)
        LVN_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $LVN_area_isotope_2)
        LVN_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $LVN_area_isotope_3)
        LVN_area=$(echo "$LVN_area_isotope_1+$LVN_area_isotope_2+$LVN_area_isotope_3" | bc -l)
        LVN_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '582.3' $basename_sh)
        LVN_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '582.3' $basename_sh)

        YIC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '722.3' $basename_sh)
        YIC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '722.8' $basename_sh)
        YIC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '723.3' $basename_sh)
        YIC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $YIC_area_isotope_1)
        YIC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $YIC_area_isotope_2)
        YIC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $YIC_area_isotope_3)
        YIC_area=$(echo "$YIC_area_isotope_1+$YIC_area_isotope_2+$YIC_area_isotope_3" | bc -l)
        YIC_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '722.3' $basename_sh)
        YIC_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '722.3' $basename_sh)

        HLV_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '653.3' $basename_sh)
        HLV_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '653.8' $basename_sh)
        HLV_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '654.3' $basename_sh)
        HLV_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $HLV_area_isotope_1)
        HLV_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $HLV_area_isotope_2)    
        HLV_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $HLV_area_isotope_3)
        HLV_area=$(echo "$HLV_area_isotope_1+$HLV_area_isotope_2+$HLV_area_isotope_3" | bc -l)
        HLV_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '653.3' $basename_sh)
        HLV_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '653.3' $basename_sh)

        VPQ_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '756.4' $basename_sh)
        VPQ_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '756.9' $basename_sh)
        VPQ_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '757.4' $basename_sh)
        VPQ_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $VPQ_area_isotope_1)
        VPQ_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $VPQ_area_isotope_2)    
        VPQ_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $VPQ_area_isotope_3) 
        VPQ_area=$(echo "$VPQ_area_isotope_1+$VPQ_area_isotope_2+$VPQ_area_isotope_3" | bc -l)
        VPQ_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '756.4' $basename_sh)    
        VPQ_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '756.4' $basename_sh)

        EAC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '554.2' $basename_sh)
        EAC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '554.7' $basename_sh)
        EAC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '555.2' $basename_sh)
        EAC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $EAC_area_isotope_1)
        EAC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $EAC_area_isotope_2)    
        EAC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $EAC_area_isotope_3)
        EAC_area=$(echo "$EAC_area_isotope_1+$EAC_area_isotope_2+$EAC_area_isotope_3" | bc -l)
        EAC_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '554.2' $basename_sh)    
        EAC_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '554.2' $basename_sh)

        EYE_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '751.8' $basename_sh)
        EYE_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '752.3' $basename_sh)
        EYE_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '752.8' $basename_sh)
        EYE_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $EYE_area_isotope_1)
        EYE_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $EYE_area_isotope_2)    
        EYE_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $EYE_area_isotope_3)
        EYE_area=$(echo "$EYE_area_isotope_1+$EYE_area_isotope_2+$EYE_area_isotope_3" | bc -l)
        EYE_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '751.8' $basename_sh)    
        EYE_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '751.8' $basename_sh)  
  
        ECC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '583.8' $basename_sh)
        ECC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '584.2' $basename_sh)
        ECC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '584.5' $basename_sh)
        ECC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $ECC_area_isotope_1)
        ECC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $ECC_area_isotope_2)    
        ECC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $ECC_area_isotope_3)         
        ECC_area=$(echo "$ECC_area_isotope_1+$ECC_area_isotope_2+$ECC_area_isotope_3" | bc -l)
        ECC_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '583.8' $basename_sh)    
        ECC_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '583.8' $basename_sh)  

        SLH_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '710.3' $basename_sh)
        SLH_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '710.8' $basename_sh)
        SLH_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '711.3' $basename_sh)
        SLH_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $SLH_area_isotope_1)
        SLH_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $SLH_area_isotope_2)    
        SLH_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $SLH_area_isotope_3)
        SLH_area=$(echo "$SLH_area_isotope_1+$SLH_area_isotope_2+$SLH_area_isotope_3" | bc -l)
        SLH_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '710.3' $basename_sh)    
        SLH_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '710.3' $basename_sh)  

        TCC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '488.5' $basename_sh)
        TCC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '488.8' $basename_sh)
        TCC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '489.2' $basename_sh)
        TCC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $TCC_area_isotope_1)
        TCC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $TCC_area_isotope_2)    
        TCC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $TCC_area_isotope_3) 
        TCC_area=$(echo "$TCC_area_isotope_1+$TCC_area_isotope_2+$TCC_area_isotope_3" | bc -l)
        TCC_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '488.5' $basename_sh)    
        TCC_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '488.5' $basename_sh)  

        NEC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '517.7' $basename_sh)
        NEC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '518.2' $basename_sh)
        NEC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '518.7' $basename_sh)
        NEC_area_isotope_1=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $NEC_area_isotope_1)
        NEC_area_isotope_2=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $NEC_area_isotope_2)    
        NEC_area_isotope_3=$(source !{binfolder}/parsing_qcloud.sh; convert_scientific_notation $NEC_area_isotope_3)
        NEC_area=$(echo "$NEC_area_isotope_1+$NEC_area_isotope_2+$NEC_area_isotope_3" | bc -l)
        NEC_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '517.7' $basename_sh)    
        NEC_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '517.7' $basename_sh)

        # QC01 JSON files:
        # TOTAL TIC:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json $checksum "QC:9000005" "QC:0000048")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json $checksum $total_tic "QC:0000048" "QC:0000048")
        # MIT MS1:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json $checksum "QC:9000002" "QC:1000927")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json $checksum $mit_ms1 "QC:9000002" "QC:1000927")
        # MIT MS2:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json $checksum "QC:9000002" "QC:1000928")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json $checksum $mit_ms2 "QC:9000002" "QC:1000928")
        # PEAK AREA:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json_monitored_peptides $checksum "QC:1001844")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $LVN_area "QC:1001844" "LVNELTEFAK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $YIC_area "QC:1001844" "YIC(Carbamidomethyl)DNQDTISSK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $HLV_area "QC:1001844" "HLVDEPQNLIK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $VPQ_area "QC:1001844" "VPQVSTPTLVEVSR")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $EAC_area "QC:1001844" "EAC(Carbamidomethyl)FAVEGPK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $EYE_area "QC:1001844" "EYEATLEEC(Carbamidomethyl)C(Carbamidomethyl)AK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $ECC_area "QC:1001844" "EC(Carbamidomethyl)C(Carbamidomethyl)HGDLLEC(Carbamidomethyl)ADDR")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $SLH_area "QC:1001844" "SLHTLFGDELC(Carbamidomethyl)K")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $TCC_area "QC:1001844" "TC(Carbamidomethyl)VADESHAGC(Carbamidomethyl)EK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $NEC_area "QC:1001844" "NEC(Carbamidomethyl)FLSHK")
        # RT:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json_monitored_peptides $checksum "QC:1000894")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $LVN_rt "QC:1000894" "LVNELTEFAK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $YIC_rt "QC:1000894" "YIC(Carbamidomethyl)DNQDTISSK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $HLV_rt "QC:1000894" "HLVDEPQNLIK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $VPQ_rt "QC:1000894" "VPQVSTPTLVEVSR")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $EAC_rt "QC:1000894" "EAC(Carbamidomethyl)FAVEGPK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $EYE_rt "QC:1000894" "EYEATLEEC(Carbamidomethyl)C(Carbamidomethyl)AK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $ECC_rt "QC:1000894" "EC(Carbamidomethyl)C(Carbamidomethyl)HGDLLEC(Carbamidomethyl)ADDR")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $SLH_rt "QC:1000894" "SLHTLFGDELC(Carbamidomethyl)K")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $TCC_rt "QC:1000894" "TC(Carbamidomethyl)VADESHAGC(Carbamidomethyl)EK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $NEC_rt "QC:1000894" "NEC(Carbamidomethyl)FLSHK")
        # MASS ACCURACY:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json_monitored_peptides $checksum "QC:1000014")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $LVN_dppm "QC:1000014" "LVNELTEFAK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $YIC_dppm "QC:1000014" "YIC(Carbamidomethyl)DNQDTISSK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $HLV_dppm "QC:1000014" "HLVDEPQNLIK") 
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $VPQ_dppm "QC:1000014" "VPQVSTPTLVEVSR")    
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $EAC_dppm "QC:1000014" "EAC(Carbamidomethyl)FAVEGPK")    
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $EYE_dppm "QC:1000014" "EYEATLEEC(Carbamidomethyl)C(Carbamidomethyl)AK")    
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $ECC_dppm "QC:1000014" "EC(Carbamidomethyl)C(Carbamidomethyl)HGDLLEC(Carbamidomethyl)ADDR")    
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $SLH_dppm "QC:1000014" "SLHTLFGDELC(Carbamidomethyl)K")    
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $TCC_dppm "QC:1000014" "TC(Carbamidomethyl)VADESHAGC(Carbamidomethyl)EK")    
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $NEC_dppm "QC:1000014" "NEC(Carbamidomethyl)FLSHK")
        
        # Insert to QCloud database: 
        echo "[INFO] Get acces token......"
        access_token=$(source !{binfolder}/api.sh; get_api_access_token_qcloud !{url_api_qcloud_signin} !{url_api_qcloud_user} !{url_api_qcloud_pass})
        # Insert file:
        echo "[INFO] Insert file......"
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_file}/QC:0000005/$labsysid -H "Content-Type: application/json" --data @insert_file_string
        # Insert data: 
        echo "[INFO] Insert data......"
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_0000048.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1000927.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1000928.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1001844.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1000894.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1000014.json
        '''
}

process insertDataNucleosidesToQCloud {

        tag { "${csv_file}" }
        label 'clitools'

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
        file (csv_file)

        shell:
        '''
        # Parsings:
        checksum=$(source !{binfolder}/utils.sh; get_checksum !{path} !{filename})
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
        total_tic=$(echo "$total_tic * 0.0000000001" | bc -l)
        mit_ms1=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 1 MS:1000927)
        mit_ms2=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 2 MS:1000927)
        request_code=$(echo !{mzml_file} | awk -F'[_.]' '{print $1}')
        basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')
        reversed_filename=$(echo $basename_sh | rev)
        first_3_underscores=$(echo $reversed_filename | cut -d'_' -f1-3)
        reversed_first_3_underscores=$(echo $first_3_underscores | rev)
        rest_of_filename=$(echo $reversed_filename | cut -d'_' -f4-)
        reversed_rest_of_filename=$(echo $rest_of_filename | rev)
        labsysid=$(echo $reversed_first_3_underscores | cut -d'_' -f1) 
        creation_date=$(source !{binfolder}/utils.sh; get_mzml_date !{mzml_file})
        insert_file_string='{"creationDate": "'$creation_date'","filename": "'$reversed_rest_of_filename'","checksum": "'$checksum'"}'
        echo $insert_file_string > insert_file_string
 
        # QCN1 XIC: 
        csv_file_sh=$(echo $PWD"/"!{csv_file})
        $(source !{binfolder}/parsing_qcloud.sh; set_csv_to_json $csv_file_sh $basename_sh)

        GUANO_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '284.0989' $basename_sh) 
        GUANO_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '284.0989' $basename_sh)
        GUANO_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '284.0989' $basename_sh)

        INOSINE_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '269.088' $basename_sh) 
        INOSINE_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '269.088' $basename_sh)
        INOSINE_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '269.088' $basename_sh)

        METHYILADENO25_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '282.1197' $basename_sh)
        METHYILADENO25_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '282.1197' $basename_sh) 
        METHYILADENO25_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '282.1197' $basename_sh)

        METHYL50_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '259.0' $basename_sh) 
        METHYL50_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '259.0' $basename_sh)
        METHYL50_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '259.0' $basename_sh)

        CYTIDINE50_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '244.0' $basename_sh)
        CYTIDINE50_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '244.0' $basename_sh)
        CYTIDINE50_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '244.0' $basename_sh)

        URIDINE25_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '245.0' $basename_sh)
        URIDINE25_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '245.0' $basename_sh)
        URIDINE25_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '245.0' $basename_sh)


        # QCN1 JSON files:
        # TOTAL TIC:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json $checksum "QC:9000005" "QC:0000048")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json $checksum $total_tic "QC:0000048" "QC:0000048")
        # MIT MS1:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json $checksum "QC:9000002" "QC:1000927")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json $checksum $mit_ms1 "QC:9000002" "QC:1000927")
        # MIT MS2:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json $checksum "QC:9000002" "QC:1000928")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json $checksum $mit_ms2 "QC:9000002" "QC:1000928")
        # PEAK AREA:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json_monitored_peptides $checksum "QC:1001844")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $GUANO_area "QC:1001844" "GUANOSINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $INOSINE_area "QC:1001844" "INOSINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $METHYILADENO25_area "QC:1001844" "METHYILADENOSINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $METHYL50_area "QC:1001844" "METHYLURIDINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $CYTIDINE50_area "QC:1001844" "CYTIDINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $URIDINE25_area "QC:1001844" "URIDINE")

        # RT:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json_monitored_peptides $checksum "QC:1000894")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $GUANO_rt "QC:1000894" "GUANOSINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $INOSINE_rt "QC:1000894" "INOSINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $METHYILADENO25_rt "QC:1000894" "METHYILADENOSINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $METHYL50_rt "QC:1000894" "METHYLURIDINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $CYTIDINE50_rt "QC:1000894" "CYTIDINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $URIDINE25_rt "QC:1000894" "URIDINE")

        # MASS ACCURACY:
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json_monitored_peptides $checksum "QC:1000014")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $GUANO_dppm "QC:1000014" "GUANOSINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $INOSINE_dppm "QC:1000014" "INOSINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $METHYILADENO25_dppm "QC:1000014" "METHYILADENOSINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $METHYL50_dppm "QC:1000014" "METHYLURIDINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $CYTIDINE50_dppm "QC:1000014" "CYTIDINE")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $URIDINE25_dppm "QC:1000014" "URIDINE")

        # Insert to QCloud database: 
        echo "[INFO] Get acces token......"
        access_token=$(source !{binfolder}/api.sh; get_api_access_token_qcloud !{url_api_qcloud_signin} !{url_api_qcloud_user} !{url_api_qcloud_pass})
        # Insert file:
        echo "[INFO] Insert file......"
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_file}/QC:0000012/$labsysid -H "Content-Type: application/json" --data @insert_file_string
        # Insert data: 
        echo "[INFO] Insert data......"
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_0000048.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1000927.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1000928.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1001844.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1000894.json
        curl -v -X POST -H "Authorization: $access_token" !{url_api_qcloud_insert_data} -H "Content-Type: application/json" --data @${checksum}_QC_1000014.json
        '''
}
