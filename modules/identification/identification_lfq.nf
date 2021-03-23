//IDMapper params:
rt_tolerance             = params.rt_tolerance
mz_tolerance             = params.mz_tolerance

//PeptideIndexer params:
decoy_string             = params.decoy_string
decoy_string_position    = params.decoy_string_position
missing_decoy_action     = params.missing_decoy_action
unmatched_action         = params.unmatched_action

//FalseDiscoveryRate params:
PSM                      = params.PSM
protein                  = params.protein
FDR_PSM                  = params.FDR_PSM
FDR_protein              = params.FDR_protein

//IDFilter:
score_pep                = params.score_pep
score_prot               = params.score_prot

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
    PeptideIndexer -debug 1 -threads 4 -enzyme:specificity full -IL_equivalent -in ${search_engine_idxml_file} -out ${search_engine_idxml_file.baseName}_peptideindexer.idXML -write_protein_sequence -fasta ${fastafile_decoy} -decoy_string ${decoy_string} -decoy_string_position ${decoy_string_position} -unmatched_action ${unmatched_action} -missing_decoy_action ${missing_decoy_action} -write_protein_sequence
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

process IDFilter {
    label 'openms'
    tag { "${fdr_idxml_file}" }

    input:
    file(fdr_idxml_file)

    output:
    file("${fdr_idxml_file.baseName}_idfilter.idXML")

    """
    IDFilter -in $fdr_idxml_file -out ${fdr_idxml_file.baseName}_idfilter.idXML -remove_decoys -score:pep $score_pep -score:prot $score_prot
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
    file("file.info")

    """
    FileInfo -in $idxml_file > file.info
    """
}
