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

//SHell scripts folder:
binfolder                = "$baseDir/bin"

process insertFileToQSample {
        tag { "${mzml_file}" }

        input:
        tuple val(filename), val(basename), val(path)
        tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

        output:
        file("${filename}.checksum")

        when: 
        filename =~ /^((?!QCGL|QCDL|QCFL|QCPL|QCRL).)*$/

        shell:
        '''
        request_code=$(echo !{filename} | awk -F'[_.]' '{print $1}')
        checksum=$(md5sum !{path}/!{filename} | awk '{print $1}')
        echo $checksum > !{filename}.checksum
        creation_date=$(grep -Pio '.*startTimeStamp="\\K[^"]*' !{mzml_file} | sed 's/Z//g' | xargs -I{} date -d {} +"%Y-%m-%dT%T")
        echo $creation_date > creation_date
        access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        echo 'data: ------------->{"checksum": "'$checksum'","creation_date": "'$creation_date'","filename": "'!{basename}'"}<-----------------'
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
        filename =~ /QCGL|QCDL|QCFL|QCPL|QCRL/

        shell:
        '''
        api_key=""
        basename_sh=!{basename}
        if [[ $basename_sh == *"QCGL"* ]]; then api_key="7765746c-6162-3300-0000-000000000000"; fi
        if [[ $basename_sh == *"QCDL"* ]]; then api_key="6170694b-6579-3100-0000-000000000000"; fi
        if [[ $basename_sh == *"QCFL"* ]]; then api_key="7765746c-6162-3500-0000-000000000000"; fi
        if [[ $basename_sh == *"QCPL"* ]]; then api_key="7765746c-6162-3400-0000-000000000000"; fi
        if [[ $basename_sh == *"QCRL"* ]]; then api_key="7765746c-6162-3200-0000-000000000000"; fi
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

        input:
        file(checksum)
        file(fileinfo_file)
        file(protinf_file)
        file(idfilter_score_file)
        file(qccalc_file)

        when:
        fileinfo_file =~ /^((?!QCGL|QCDL|QCFL|QCPL|QCRL).)*$/

        shell:
        '''
        checksum=$(cat !{checksum})
        num_prots=$(grep -Pio 'indistinguishable_proteins_' !{protinf_file} | wc -l)
        num_peptd=$(grep 'non-redundant peptide hits:' !{fileinfo_file} | sed 's/^.*: //')
        missed_cleavages=$(grep -Pio '.*accession="QC:0000037"[^>]*' !{qccalc_file} | grep -Pio '.*value="\\K[^"]*')
        charge_2=$(grep -Pio '.*charge="\\K[^"]*' !{idfilter_score_file} | grep 2 | wc -l)
        charge_3=$(grep -Pio '.*charge="\\K[^"]*' !{idfilter_score_file} | grep 3 | wc -l)
        charge_4=$(grep -Pio '.*charge="\\K[^"]*' !{idfilter_score_file} | grep 4 | wc -l)
        echo $num_prots > num_prots
        echo $num_peptd > num_peptd
        access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')
        echo $access_token > acces_token
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "1","value": "'$num_prots'"},{"contextSource": "2","value": "'$num_peptd'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "6","value": "'$missed_cleavages'"}]}]}'
        curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_data} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"parameter": {"apiKey": "6170694b-6579-3100-0000-000000000000","id": "1"},"values": [{"contextSource": "3","value": "'$charge_2'"},{"contextSource": "4","value": "'$charge_3'"},{"contextSource": "5","value": "'$charge_4'"}]}]}'
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

     input:
     file(checksum)
     file(fileinfo_file)
     file(protinf_file)

     when:
     fileinfo_file.name =~ /((^[^_]+)MH)|((^[^_]+)MZ)/

     shell:
'''

checksum=$(cat !{checksum})

### Extract parameters from FileInfo file:

#Totals:
num_peptides_total=$(grep -Pio '.* modified top-hits: ([^(]+)' !{fileinfo_file}  | sed 's|.*/||' | sed "s/ //g")
num_peptides_modif=$(grep -Pio '.* modified top-hits: ([^//]+)' !{fileinfo_file}  | awk '{print $NF}')

#Chemical modifications:
num_mod_phenylisocyanate_n=$(grep -Pio '.*Phenylisocyanate ([^,]+)' !{fileinfo_file} | awk '{print $NF}')
num_mod_propionyl_k=$(grep -Pio 'Propionyl ([^,]+)' !{fileinfo_file} | grep K | awk '{print $NF}')
num_mod_propionyl_n=$(grep -Pio 'Propionyl ([^,]+)' !{fileinfo_file} | grep -v K | awk '{print $NF}')

#PTMs:
num_mod_acetyl_k=$(grep -Pio 'Acetyl ([^,]+)' !{fileinfo_file} | grep K | awk '{print $NF}')
num_mod_dimethyl_k=$(grep -Pio '.*Dimethyl \\(K\\) ([^,]+)' !{fileinfo_file} | awk '{print $NF}')
num_mod_trimethyl_k=$(grep -Pio '.*Trimethyl \\(K\\) ([^,]+)' !{fileinfo_file} | awk '{print $NF}')
num_mod_propionyl_methyl=$(grep -Pio '.*Crotonaldehyde \\(K\\) ([^,]+)' !{fileinfo_file} | awk '{print $NF}') #same mass

#Additional counts:
num_precursors_with_n_terminal=$(cat !{protinf_file} | grep "<PeptideHit" | grep -e aa_before=\\"M -e aa_before=\\"\\\\[ | wc -l)
num_K_propionyl=$(cat !{protinf_file} | grep -Pio '.*sequence="\\K[^"]*' | grep K | grep -e "K(Propionyl)" -e "K(Crotonaldehyde)" | wc -l)
num_not_K_propionyl=$(cat !{protinf_file} | grep "<PeptideHit" | grep -Pio '.*sequence="\\K[^"]*' | grep K | grep -v "K(Propionyl)" | grep -v "K(Crotonaldehyde)" | wc -l)
num_phenylisocyanate_start_seq=$(cat !{protinf_file} | grep "<PeptideHit" | grep ".(Phenylisocyanate)" | wc -l)
num_not_phenylisocyanate_start_seq=$((num_peptides_total-num_phenylisocyanate_start_seq-num_precursors_with_n_terminal))
num_propionyl_k_start_protein=$(cat !{protinf_file} | grep "<PeptideHit" | grep '\"K(Propionyl)' | wc -l)
num_not_propionyl_k_start_protein=$(cat !{protinf_file} | grep "<PeptideHit" | grep -e aa_before=\\"M -e aa_before=\\"\\\\[ | grep -v ".(Propionyl)" | wc -l)

#Check:
echo $num_K_propionyl > num_K_propionyl
echo $num_not_K_propionyl > num_not_K_propionyl
echo $num_phenylisocyanate_start_seq > num_phenylisocyanate_start_seq
echo $num_not_phenylisocyanate_start_seq > num_not_phenylisocyanate_start_seq
echo $num_propionyl_k_start_protein > num_propionyl_k_start_protein
echo $num_not_propionyl_k_start_protein > num_not_propionyl_k_start_protein

#Insert to database through QSample API: 
access_token=$(curl -s -X POST !{qcloud2_api_signin} -H "Content-Type: application/json" --data '{"username":"'!{qcloud2_api_user}'","password":"'!{qcloud2_api_pass}'"}' | grep -Po '"accessToken": *\\K"[^"]*"' | sed 's/"//g')

curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_fileinfo} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"info": {"peptideHits": "'$num_peptides_total'", "peptideModified": "'$num_peptides_modif'"}}'

curl -v -X POST -H "Authorization: Bearer $access_token" !{qcloud2_api_insert_modif} -H "Content-Type: application/json" --data '{"file": {"checksum": "'$checksum'"},"data": [{"modification": {"name": "Phenylisocyanate (N-term)"},"value": "'$num_mod_phenylisocyanate_n'"},{"modification": {"name": "Propionyl (K)"},"value": "'$num_mod_propionyl_k'"},{"modification": {"name": "Propionyl (Protein N-term)"},"value": "'$num_mod_propionyl_n'"},{"modification": {"name": "Acetyl (K)"},"value": "'$num_mod_acetyl_k'"},{"modification": {"name": "Dimethyl (K)"},"value": "'$num_mod_dimethyl_k'"},{"modification": {"name": "Trimethyl (K)"},"value": "'$num_mod_trimethyl_k'"},{"modification": {"name": "Propionyl+Methyl"},"value": "'$num_mod_propionyl_methyl'"}]}'

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
        num_mod_label_K=$(grep 'Modification count (top-hits only):' !{fileinfo_file} | cut -d"," -f3 | cut -d")" -f4 | sed 's/ //g')
        num_mod_label_R=$(grep 'Modification count (top-hits only):' !{fileinfo_file} | cut -d"," -f4 | cut -d")" -f4 | sed 's/ //g')
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
