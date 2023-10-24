output_folder             = params.output_folder
instrument_folder         = params.instrument_folder

//Bash scripts folder:
binfolder                = "$baseDir/bin"

process output_folder_qcloud {

        tag { "qcloud" }
        label 'clitools'

        publishDir params.test_folder, mode: 'copy', overwrite: true

        input:
        tuple val(filename), val(basename), val(path)
        file(protinf_file)
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
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prot_groups !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptidoforms !{protinf_file})
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
        mit_ms1=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 1 MS:1000927)
        mit_ms2=$(source !{binfolder}/parsing_qcloud.sh; get_mit !{mzml_file} MS:1000511 2 MS:1000927)
        request_code=$(echo !{protinf_file} | awk -F'[_.]' '{print $1}')
        basename_sh=$(basename !{protinf_file} | cut -f 1 -d '.')

        # QC01 monitored peptides processing: 
        jq --slurp --raw-input --raw-output 'split("\n") | .[3:] | map(split(",")) | map({"RT": .[0],"mz": .[1],"RTobs": .[2],"dRT": .[3],"mzobs": .[4],"dppm": .[5],"intensity": .[5],"area": .[6]}) | del(..|nulls)' !{csv_file} > $basename_sh".json"
        LVN_area=$(jq -r '.[] | select(.mz | tostring | startswith("582.3")) | .area' $basename_sh".json")
        LVN_rt=$(jq -r '.[] | select(.mz | tostring | startswith("582.3")) | .RTobs' $basename_sh".json")
        LVN_dppm=$(jq -r '.[] | select(.mz | tostring | startswith("582.3")) | .dppm' $basename_sh".json")
        EAC_area=$(jq -r '.[] | select(.mz | tostring | startswith("554.2")) | .area' $basename_sh".json")
        EAC_rt=$(jq -r '.[] | select(.mz | tostring | startswith("554.2")) | .RTobs' $basename_sh".json")
        EAC_dppm=$(jq -r '.[] | select(.mz | tostring | startswith("554.2")) | .dppm' $basename_sh".json")
        NEC_area=$(jq -r '.[] | select(.mz | tostring | startswith("554.2")) | .area' $basename_sh".json")
        NEC_rt=$(jq -r '.[] | select(.mz | tostring | startswith("554.2")) | .RTobs' $basename_sh".json")
        NEC_dppm=$(jq -r '.[] | select(.mz | tostring | startswith("554.2")) | .dppm' $basename_sh".json")

        echo "$basename_sh\t$num_prots\t$num_peptd\t$total_tic\t$mit_ms1\t$mit_ms2\t$LVN_area\t$LVN_rt\t$LVN_dppm\t$EAC_area\t$EAC_rt\t$EAC_dppm\t$NEC_area\t$NEC_rt\t$NEC_dppm" >> !{output_folder}/$labsysid.tsv

        '''
}
