//IDMapper params:
rt_tolerance             = params.rt_tolerance
mz_tolerance             = params.mz_tolerance

//PeptideIndexer params:
decoy_string             = params.decoy_string
decoy_string_position    = params.decoy_string_position
missing_decoy_action     = params.missing_decoy_action
unmatched_action         = params.unmatched_action
aaa_max                  = params.aaa_max
enzyme_specificity       = params.enzyme_specificity

//FalseDiscoveryRate params:
PSM                      = params.PSM
protein                  = params.protein
FDR_PSM                  = params.FDR_PSM
FDR_protein              = params.FDR_protein

//IDFilter:
score_pep                = params.score_pep
score_prot               = params.score_prot
aaa_pep                  = params.aaa_pep
aaa_prot                 = params.aaa_prot
black_regex              = params.black_regex


process PeptideIndexer {
    label 'openms'
    tag { "${search_engine_idxml_file}" }

    input:
    file(search_engine_idxml_file)
    file(organism)
    file(fastafile_decoy)

    output:
    file("${search_engine_idxml_file.baseName}_peptideindexer.idXML")

    """
    PeptideIndexer -aaa_max ${aaa_max} -enzyme:specificity ${enzyme_specificity} -IL_equivalent -in ${search_engine_idxml_file} -out ${search_engine_idxml_file.baseName}_peptideindexer.idXML -write_protein_sequence -fasta ${fastafile_decoy} -decoy_string ${decoy_string} -decoy_string_position ${decoy_string_position} -unmatched_action ${unmatched_action} -missing_decoy_action ${missing_decoy_action} -write_protein_sequence
    """
}


process IDFilter_aaa {
    label 'openms'
    tag { "${fdr_idxml_file}" }

    input:
    file(fdr_idxml_file)

    output:
    file("${fdr_idxml_file.baseName}_idfilter_aaa.idXML")

    """
    IDFilter -in $fdr_idxml_file -blacklist:RegEx $black_regex -out ${fdr_idxml_file.baseName}_idfilter_aaa.idXML -remove_decoys -score:pep $aaa_pep -score:prot $aaa_prot
    """

}

process FalseDiscoveryRate {
    label 'openms'
    tag { "${peptideIndexer_idxml_file}" }

    input:
    file(peptideIndexer_idxml_file)

    output:
    file("${peptideIndexer_idxml_file.baseName}_fdr.idXML")

    """
    FalseDiscoveryRate -in $peptideIndexer_idxml_file -out ${peptideIndexer_idxml_file.baseName}_fdr.idXML -PSM $PSM -protein $protein -FDR:PSM $FDR_PSM -FDR:protein $FDR_protein
    """
}

process IDFilter_score {
    label 'openms'
    tag { "${fdr_idxml_file}" }

    input:
    file(fdr_idxml_file)

    output:
    file("${fdr_idxml_file.baseName}_idfilter_score.idXML")

    """
    IDFilter -in $fdr_idxml_file -out ${fdr_idxml_file.baseName}_idfilter_score.idXML -remove_decoys -score:pep $score_pep -score:prot $score_prot
    """

}

process ProteinInference {
    label 'openms'
    tag { "${idfilter_idxml_file}" }

    input:
    file(idfilter_idxml_file)
 
    output:
    file("${idfilter_idxml_file.baseName}_proteininference.idXML")
 
    """
    ProteinInference -in $idfilter_idxml_file -out ${idfilter_idxml_file.baseName}_proteininference.idXML
    """
}

process FileInfo {
    label 'openms'
    tag  { "${idxml_file}" }

    input:
    file(idxml_file)

    output:
    file("${idxml_file.baseName}.info")


    """
    FileInfo -in $idxml_file > ${idxml_file.baseName}.info
    """
}

process QCCalculator {
    label 'openms'
    tag { "${idxml_file}" }

    input:
    file(idxml_file)
    tuple val(filename_mzml), val(basename_mzml), val(path_mzml), file(mzml_file)

    output:
    file("${idxml_file.baseName}_qccalculator.qcML")

    """
    QCCalculator -in $mzml_file -id $idxml_file -out ${idxml_file.baseName}_qccalculator.qcML
    """
}

