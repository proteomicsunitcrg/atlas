//FeatureFinderMultiplex params:
algorithm_labels         = params.algorithm_labels
algorithm_charge         = params.algorithm_charge
algorithm_rt_typical     = params.algorithm_rt_typical
algorithm_rt_min         = params.algorithm_rt_min
algorithm_mz_tolerance   = params.algorithm_mz_tolerance

//IDMapper params:
rt_tolerance             = params.rt_tolerance
mz_tolerance             = params.mz_tolerance

process FeatureFinderMultiplex {
    label 'ffm'
    tag { "${mzML_ffm_file}" }

    input:
    tuple val(filename), val(basename), val(path), file(mzML_ffm_file)

    output:
    file("${basename}_ffm.featureXML")

    """
    FeatureFinderMultiplex -debug 1 -in ${mzML_ffm_file} -out ${basename}_ffm.featureXML -algorithm:rt_band '1' -algorithm:labels $algorithm_labels -algorithm:charge $algorithm_charge -algorithm:rt_typical $algorithm_rt_typical -algorithm:rt_min $algorithm_rt_min -algorithm:mz_tolerance $algorithm_mz_tolerance
    """
}


process IDMapper {
    label 'openms'
    tag { "${ffm_featureXML_file}" }

    input:
    file(ffm_featureXML_file)
    file(idxml_file)

    output:
    file("${ffm_featureXML_file.baseName}_idmapper.featureXML")

    """
    IDMapper -id $idxml_file -in $ffm_featureXML_file -out ${ffm_featureXML_file.baseName}_idmapper.featureXML -rt_tolerance $rt_tolerance -mz_tolerance $mz_tolerance
    """
}

// Protein Quantification branch:

process ProteinQuantifier {
    label 'openms'
    tag { "${idmapper_to_proteinquantifier}" }

    input:
    file(idmapper_to_proteinquantifier)

    output:
    file("${idmapper_to_proteinquantifier.baseName}_proteinquantifier.csv")

    """
    ProteinQuantifier -include_all -average 'mean' -in $idmapper_to_proteinquantifier -out ${idmapper_to_proteinquantifier.baseName}_proteinquantifier.csv
    """
}
