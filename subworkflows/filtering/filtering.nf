process FileFilter {
    label 'openms'
    tag { "${mzML_trfp_file}" }

    input:
    tuple val(filename), val(basename), val(path), file(mzML_trfp_file)

    output:
    tuple val(filename), val(basename), val(path), file("${basename}_ff.mzML")
    
    """
    FileFilter -debug 1 -in $mzML_trfp_file -out ${basename}_ff.mzML -spectra:select_mode 'MS1Spectrum'
    """
}
