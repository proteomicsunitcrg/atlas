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
        num_prots=$(source !{binfolder}/parsing.sh; get_num_prots !{protinf_file})
        num_peptd=$(source !{binfolder}/parsing.sh; get_num_peptd !{fileinfo_file})      
        missed_cleavages_2=$(source !{binfolder}/parsing.sh; get_miscleavages_by_charge !{protinf_file} 2)
        missed_cleavages_3=$(source !{binfolder}/parsing.sh; get_miscleavages_by_charge !{protinf_file} 3)
        missed_cleavages_4=$(source !{binfolder}/parsing.sh; get_miscleavages_by_charge !{protinf_file} 4)
        charge_2=$(source !{binfolder}/parsing.sh; get_charges !{protinf_file} 2)
        charge_3=$(source !{binfolder}/parsing.sh; get_charges !{protinf_file} 3)
        charge_4=$(source !{binfolder}/parsing.sh; get_charges !{protinf_file} 4)
        total_base_peak_intenisty=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000505)
        total_tic=$(source !{binfolder}/parsing.sh; get_mzml_param_by_cv !{mzml_file} MS:1000285)
        log10_total_base_peak_intenisty=$(source !{binfolder}/utils.sh; get_log_base_n $total_base_peak_intenisty 10)
        log10_total_tic=$(source !{binfolder}/utils.sh; get_log_base_n $total_tic 10)
 
        # Checks: 
        echo $total_base_peak_intenisty > total_base_peak_intenisty
        echo $total_tic > total_tic
        echo $log10_total_base_peak_intenisty > log10_base_peak_intenisty
        echo $log10_total_tic > log10_total_tic
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd
        echo $missed_cleavages_2 > missed_cleavages_2
        echo $missed_cleavages_3 > missed_cleavages_3
        echo $missed_cleavages_4 > missed_cleavages_4
        echo $charge_2 > charge_2
        echo $charge_3 > charge_3 
        echo $charge_4 > charge_4

        # QCloud2 API posts:
        checksum=$(cat !{checksum})
        access_token=$(source !{binfolder}/api.sh; get_api_qcloud2_access_token !{qcloud2_api_signin} !{qcloud2_api_user} !{qcloud2_api_pass})
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'        
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "3","value": "'$charge_2'"},{"contextSource": "4","value": "'$charge_3'"},{"contextSource": "5","value": "'$charge_4'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "7","value": "'$log10_total_base_peak_intenisty'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "19","value": "'$log10_total_tic'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "20","value": "'$missed_cleavages_2'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "21","value": "'$missed_cleavages_3'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "22","value": "'$missed_cleavages_4'"}]}]}'
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

     when:
     fileinfo_file.name =~ /((^[^_]+)MP)|((^[^_]+)MA)|((^[^_]+)MB)/

     shell:
        '''
        checksum=$(cat !{checksum})
        num_peptides_total=$(grep 'modified top-hits:' !{fileinfo_file} | cut -d'/' -f2 | cut -d'(' -f1 | sed 's/ //g')
        num_peptides_modif=$(grep 'modified top-hits:' !{fileinfo_file} | cut -d':' -f2 | cut -d'/' -f1 | sed 's/ //g')
        num_mod_phospho_s=$(grep 'Modification count (top-hits only):' !{fileinfo_file} | cut -d"," -f4 | cut -d")" -f2 | sed 's/ //g')
        num_mod_phospho_t=$(grep 'Modification count (top-hits only):' !{fileinfo_file} | cut -d"," -f5 | cut -d")" -f2 | sed 's/ //g')
        num_mod_phospho_y=$(grep 'Modification count (top-hits only):' !{fileinfo_file} | cut -d"," -f6 | cut -d")" -f2 | sed 's/ //g')
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

     when:
     fileinfo_file.name =~ /((^[^_]+)MH)|((^[^_]+)MZ)|QCHL/

     shell:
'''

checksum=$(cat !{checksum})

### Extract parameters from FileInfo file:

echo "Calculating parameters..."

#Totals:
num_peptides_total=$(grep -Pio '.* modified top-hits: ([^(]+)' !{fileinfo_file}  | sed 's|.*/||' | sed "s/ //g")
num_peptides_modif=$(grep -Pio '.* modified top-hits: ([^//]+)' !{fileinfo_file}  | awk '{print $NF}')

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

     when:
     fileinfo_file.name =~ /((^[^_]+)LC)|((^[^_]+)LP)|((^[^_]+)LQ)|((^[^_]+)LU)/

     shell:
        '''
        checksum=$(cat !{checksum})
        num_peptides_total=$(grep 'modified top-hits:' !{fileinfo_file} | cut -d'/' -f2 | cut -d'(' -f1 | sed 's/ //g')
        num_peptides_modif=$(grep 'modified top-hits:' !{fileinfo_file} | cut -d':' -f2 | cut -d'/' -f1 | sed 's/ //g')
        num_mod_label_K=$(grep 'Modification count (top-hits only):' !{fileinfo_file} | cut -d"," -f5 | cut -d")" -f4 | sed 's/ //g')
        num_mod_label_R=$(grep 'Modification count (top-hits only):' !{fileinfo_file} | cut -d"," -f6 | cut -d")" -f4 | sed 's/ //g')
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

     when:
     fileinfo_file.name =~ /((^[^_]+)LT)|((^[^_]+)LF)/

     shell:
        '''
        checksum=$(cat !{checksum})
        num_peptides_total=$(grep 'modified top-hits:' !{fileinfo_file} | cut -d'/' -f2 | cut -d'(' -f1 | sed 's/ //g')
        num_peptides_modif=$(grep 'modified top-hits:' !{fileinfo_file} | cut -d':' -f2 | cut -d'/' -f1 | sed 's/ //g')
        num_mod_tmt_K=$(grep 'Modification count (top-hits only):' !{fileinfo_file} | cut -d"," -f5 | cut -d")" -f2 | sed 's/ //g')
        num_mod_tmt_N=$(grep 'Modification count (top-hits only):' !{fileinfo_file} | cut -d"," -f4 | cut -d" " -f3 | sed 's/ //g')
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
        num_prots=$(grep -Pio 'indistinguishable_proteins_' !{protinf_file} | wc -l)
        num_peptd=$(grep 'non-redundant peptide hits:' !{fileinfo_file} | sed 's/^.*: //')
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
        num_prots=$(grep -Pio 'indistinguishable_proteins_' !{protinf_file} | wc -l)
        num_peptd=$(grep 'non-redundant peptide hits:' !{fileinfo_file} | sed 's/^.*: //')
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
        num_prots=$(grep -Pio 'indistinguishable_proteins_' !{protinf_file} | wc -l)
        num_peptd=$(grep 'non-redundant peptide hits:' !{fileinfo_file} | sed 's/^.*: //')
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
        num_prots=$(grep -Pio 'indistinguishable_proteins_' !{protinf_file} | wc -l)
        num_peptd=$(grep 'non-redundant peptide hits:' !{fileinfo_file} | sed 's/^.*: //')
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd
access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "7765746c-6162-3400-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
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
        num_prots=$(grep -Pio 'indistinguishable_proteins_' !{protinf_file} | wc -l)
        num_peptd=$(grep 'non-redundant peptide hits:' !{fileinfo_file} | sed 's/^.*: //')
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd
access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_wetlab_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "7765746c-6162-3200-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        '''
}
