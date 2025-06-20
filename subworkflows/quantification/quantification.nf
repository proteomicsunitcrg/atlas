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
    ProteinQuantifier -top:include_all -top:aggregate $average -in $idmapper_to_proteinquantifier -out ${idmapper_to_proteinquantifier.baseName}_proteinquantifier.csv
    """
}

process msnbasexic {

    label 'msnbase'
    tag { "${basename}" }

    input:
    tuple val(filename), val(basename), val(path), file(mzML_file)
    file(msnbasexic_script) 
    val(tsv_file)
    val(output_dir)
    val(analyte_name)
    val(rt_tol_sec)
    val(mz_tol_ppm)
    val(msLevel)
    val(plot_xic_ms1)
    val(plot_xic_ms2)
    val(plot_output_path)
    val(overwrite_tsv)

    output:
    file("*.json")

    script:
    """
    Rscript ${msnbasexic_script} \\
      --file_name ${mzML_file} \\
      --tsv_name ${tsv_file} \\
      --output_dir ${output_dir} \\
      --analyte_name ${analyte_name} \\
      --rt_tol_sec ${rt_tol_sec} \\
      --mz_tol_ppm ${mz_tol_ppm} \\
      --msLevel ${msLevel} \\
      --plot_xic_ms1 ${plot_xic_ms1} \\
      --plot_xic_ms2 ${plot_xic_ms2} \\
      --plot_output_path ${plot_output_path} \\
      --overwrite_tsv ${overwrite_tsv}
    """
}
