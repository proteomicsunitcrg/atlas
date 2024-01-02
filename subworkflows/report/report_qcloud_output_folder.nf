output_folder             = params.output_folder
instrument_folder         = params.instrument_folder

//Bash scripts folder:
binfolder                = "$baseDir/bin"

process output_folder_qcloud {

        tag { "${csv_file}" }
        label 'clitools'

        publishDir params.test_folder, mode: 'copy', overwrite: true

        input:
        tuple val(filename), val(basename), val(path)
        val output_folder
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)
        file (csv_file)

        when:
        output_folder != true

        shell:
        '''
        # Parsings:
        checksum=$(source !{binfolder}/utils.sh; get_checksum !{path} !{filename})
        labsysid=$(echo !{filename} | rev | cut -d'_' -f4 | rev)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
        mit_ms1=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 1 MS:1000927)
        mit_ms2=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 2 MS:1000927)
        request_code=$(echo !{mzml_file} | awk -F'[_.]' '{print $1}')
        basename_sh=$(basename !{mzml_file} | cut -f 1 -d '.')

        # QC01 monitored peptides processing:
        csv_file_sh=$(echo $PWD"/"!{csv_file}) 
        $(source !{binfolder}/parsing_qcloud.sh; set_csv_to_json $csv_file_sh $basename_sh)
      
        LVN_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '582.3' $basename_sh)
        LVN_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '582.3' $basename_sh)
        LVN_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '582.3' $basename_sh)
        
        YIC_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json '722.3' $basename_sh)
        YIC_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json '722.3' $basename_sh)
        YIC_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json '722.3' $basename_sh)

        # QCloud JSON files creation: 
        # TOTAL TIC: 
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json $checksum "QC:0000048" "QC:0000048")
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
        # RT: 
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json_monitored_peptides $checksum "QC:1010086")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $LVN_rt "QC:1010086" "LVNELTEFAK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $YIC_rt "QC:1010086" "YIC(Carbamidomethyl)DNQDTISSK")
        # MASS ACCURACY:     
        $(source !{binfolder}/parsing_qcloud.sh; create_qcloud_json_monitored_peptides $checksum "QC:1000014")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $LVN_dppm "QC:1000014" "LVNELTEFAK")
        $(source !{binfolder}/parsing_qcloud.sh; set_value_to_qcloud_json_monitored_peptides $checksum $YIC_dppm "QC:1000014" "YIC(Carbamidomethyl)DNQDTISSK")

        echo "$basename_sh\t$total_tic\t$mit_ms1\t$mit_ms2\t$LVN_area\t$LVN_rt\t$LVN_dppm" >> !{output_folder}/$labsysid.tsv

        '''
}

process output_folder_qcloud_qcn1 {

        tag { "${csv_file}" }
        label 'clitools'

        publishDir params.test_folder, mode: 'copy', overwrite: true

        input:
        tuple val(filename), val(basename), val(path)
        val output_folder
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_trfp_file)
        file (csv_file)

        when:
        output_folder != true

        shell:
        '''
        # Parsings:
        checksum=$(source !{binfolder}/utils.sh; get_checksum !{path} !{filename})
        labsysid=$(echo !{filename} | rev | cut -d'_' -f4 | rev)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_trfp_file} MS:1000285)
        mit_ms1=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_trfp_file} MS:1000511 1 MS:1000927)
        request_code=$(echo !{mzml_trfp_file} | awk -F'[_.]' '{print $1}')
        basename_sh=$(basename !{mzml_trfp_file} | cut -f 1 -d '.')

        # QC01 monitored peptides processing:
        $(source !{binfolder}/parsing_qcloud.sh; set_csv_to_json(!{csv_file} $basename_sh)

        GUANO_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json('284.0989' $basename_sh) 
        GUANO_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json('284.0989' $basename_sh)
        GUANO_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json('284.0989' $basename_sh)

        INOSINE_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json('269.088' $basename_sh)
        INOSINE_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json('269.088' $basename_sh)
        INOSINE_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json('269.088' $basename_sh)

        METHYILADENO25_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json('282.1197' $basename_sh)
        METHYILADENO25_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json('282.1197' $basename_sh)
        METHYILADENO25_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json('282.1197' $basename_sh)

        METHYL50_area=$(source !{binfolder}/parsing_qcloud.sh; get_qc_area_from_json('259.0' $basename_sh)
        METHYL50_rt=$(source !{binfolder}/parsing_qcloud.sh; get_qc_RTobs_from_json('259.0' $basename_sh)
        METHYL50_dppm=$(source !{binfolder}/parsing_qcloud.sh; get_qc_dppm_from_json('259.0' $basename_sh)

        echo "$basename_sh\t$total_tic\t$mit_ms1\t$GUANO_area\t$GUANO_rt\t$GUANO_dppm\t$INOSINE_area\t$INOSINE_rt\t$INOSINE_dppm\t$METHYILADENO25_area\t$METHYILADENO25_rt\t$METHYILADENO25_dppm\t$METHYL50_area\t$METHYL50_rt\t$METHYL50_dppm" >> !{output_folder}/$request_code.tsv

        '''
}
