nextflow.enable.dsl=2

// <--- Import del process unificat
include { DIANN_RUN } from '../../modules/diann/diann_core'

// <--- Import del parser
import DiannInputParser

// =========================================
// WORKFLOW: DIA-NN per Thermo (.raw/.mzML)
// =========================================
workflow diann {
    take:
    input_ch                  // <--- Path to .mzML or .raw file
    container_img
    config_file
    parser_version            // <--- DEPRECATED but kept for compatibility
    diann_executable
    diann_version_filter

    main:
    // <--- Convert input to meta tuple
    meta_ch = input_ch.map { file ->
        def filename = file.getName()
        def parsed = DiannInputParser.parseFilename(filename, 'thermo')
        
        def meta = [
            basename: parsed.basename,
            organism: parsed.organism,
            fileType: parsed.fileType
        ]
        
        tuple(meta, file)
    }
    
    // <--- Call unified process
    DIANN_RUN(
        meta_ch,
        container_img,
        config_file,
        diann_executable,
        diann_version_filter,
        params.diann_name_speclib_filter,           // <--- legacy filter (NK, MK, etc.)
        params.databases_folder,
        params.diann_speclib_folder
    )

    emit:
    report_tsv = DIANN_RUN.out.report_tsv.map { meta, file -> file }         // <--- Remove meta
    report_stats_tsv = DIANN_RUN.out.report_stats_tsv.map { meta, file -> file }
}

// =========================================
// WORKFLOW: DIA-NN per Bruker (.d folder)
// =========================================
workflow diann_bruker {
    take:
    input_ch                  // <--- Tuple: (folder_name, base_name, path)
    container_img
    config_file
    parser_version            // <--- DEPRECATED but kept for compatibility
    diann_executable
    diann_version_filter

    main:
    // <--- Convert Bruker input to meta tuple
    meta_ch = input_ch.map { folder_name, base_name, folder_path ->
        def parsed = DiannInputParser.parseFilename(folder_name, 'bruker')
        
        def meta = [
            basename: parsed.basename,
            organism: parsed.organism,
            fileType: 'bruker'
        ]
        
        def folder_file = file("${folder_path}/${folder_name}")
        tuple(meta, folder_file)
    }
    
    // <--- Call unified process
    DIANN_RUN(
        meta_ch,
        container_img,
        config_file,
        diann_executable,
        diann_version_filter,
        params.diann_name_speclib_filter,
        params.databases_folder,
        params.diann_speclib_folder
    )

    emit:
    report_tsv = DIANN_RUN.out.report_tsv.map { meta, file -> file }
    report_stats_tsv = DIANN_RUN.out.report_stats_tsv.map { meta, file -> file }
    sqlite_file = DIANN_RUN.out.sqlite_file.map { meta, file -> file }
    tuple_output = DIANN_RUN.out.report_tsv.map { meta, file -> tuple(meta.basename, file) }  // <--- For QSample compatibility
}

// =========================================
// WRAPPER WORKFLOWS per QCloud
// =========================================
workflow diann_qcloud {
    take:
    rawfile_ch
    container_img
    config_file
    parser_version
    diann_executable
    diann_version_filter

    main:
    diann(
        rawfile_ch,
        container_img,
        config_file,
        parser_version,
        diann_executable,
        diann_version_filter
    )

    emit:
    report_tsv = diann.out.report_tsv
    report_stats_tsv = diann.out.report_stats_tsv
}

workflow diann_bruker_qcloud {
    take:
    bruker_folder_ch          // <--- Path to .d folder
    container_img
    config_file
    parser_version
    diann_executable
    diann_version_filter

    main:
    // <--- Convert single path to expected tuple format
    bruker_tuple_ch = bruker_folder_ch.map { folder ->
        def folder_name = folder.getName()
        def folder_path = folder.getParent()
        tuple(folder_name, folder.getBaseName(), folder_path)
    }
    
    diann_bruker(
        bruker_tuple_ch,
        container_img,
        config_file,
        parser_version,
        diann_executable,
        diann_version_filter
    )

    emit:
    report_tsv = diann_bruker.out.report_tsv
    report_stats_tsv = diann_bruker.out.report_stats_tsv
    sqlite_file = diann_bruker.out.sqlite_file
}