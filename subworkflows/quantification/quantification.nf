//FeatureFinderMultiplex params:
algorithm_labels         = params.algorithm_labels
algorithm_charge         = params.algorithm_charge
algorithm_rt_typical     = params.algorithm_rt_typical
algorithm_rt_min         = params.algorithm_rt_min
algorithm_mz_tolerance   = params.algorithm_mz_tolerance
algorithm_rt_band        = params.algorithm_rt_band

//IDMapper params:
rt_tolerance             = params.rt_tolerance
mz_tolerance             = params.mz_tolerance

//ProteinQuantifier: 
average                  = params.average

//EICExtractor:
eic_rt_tol               = params.eic_rt_tol
eic_mz_tol               = params.eic_mz_tol
extra_assets_file        = params.extra_assets_file
assets_folder            = params.assets_folder 

process FeatureFinderMultiplex {
    label 'ffm'
    tag { "${mzML_ffm_file}" }

    input:
    tuple val(filename), val(basename), val(path), file(mzML_ffm_file)

    output:
    file("${basename}_ffm.featureXML")

    """
    FeatureFinderMultiplex -debug 1 -in ${mzML_ffm_file} -out ${basename}_ffm.featureXML -algorithm:rt_band $algorithm_rt_band -algorithm:labels $algorithm_labels -algorithm:charge $algorithm_charge -algorithm:rt_typical $algorithm_rt_typical -algorithm:rt_min $algorithm_rt_min -algorithm:mz_tolerance $algorithm_mz_tolerance
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
    ProteinQuantifier -include_all -average $average -in $idmapper_to_proteinquantifier -out ${idmapper_to_proteinquantifier.baseName}_proteinquantifier.csv
    """
}

process EICExtractor {
    label 'eic'
    tag { "${mzML_ff_file}" }

    input:
    tuple val(filename), val(basename), val(path), file(mzML_ff_file)

    output:
    file("${basename}_eic.csv")

    shell:
    '''
    assets_folder_sh=!{assets_folder}
    extra_assets_file_sh=!{extra_assets_file} 
    edta_file=$assets_folder_sh"/"$extra_assets_file_sh
    EICExtractor --helphelp
    EICExtractor -debug 1 -in !{mzML_ff_file} -pos $edta_file -out !{basename}_eic.csv -rt_tol !{eic_rt_tol} -mz_tol !{eic_mz_tol}
    '''
}
