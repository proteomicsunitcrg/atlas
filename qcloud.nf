#!/usr/bin/env nextflow

nextflow.enable.dsl=2

// Import utility functions
include { extractQCType; selectTsvFile; extractQCTypeFromFilename; getQCloudSampleType; getDatabaseName } from './modules/functions/utils'
include { ThermoRawFileParser as trfp_pr } from './subworkflows/conversion/conversion'
include { insertDataToQCloud as insertDataToQCloud_pr } from './subworkflows/report/report_qcloud'
include { create_decoy as cdecoy_pr; fragpipe_prep as fragpipe_prep_pr; fragpipe_main as fragpipe_main_pr; extract_apex_rt as extract_apex_rt_pr } from './subworkflows/search_engine/search_engine.nf'
include { msnbasexic as msnbasexic_pr } from './subworkflows/quantification/quantification'
include { PROCESS_PEPTIDES } from './modules/qcloud/process_peptides'
include { EXTRACT_METADATA } from './modules/qcloud/extract_metadata'
include { EXTRACT_FRAGPIPE_METRICS } from './modules/qcloud/extract_fragpipe_metrics'
include { SUBMIT_TO_QCLOUD } from './modules/qcloud/submit_qcloud' 
include { MODIFY_FRAGPIPE_WORKFLOW } from './modules/qcloud/modify_workflow'
include { EXTRACT_INSTRUMENT_INFO } from './modules/qcloud/extract_instrument'
include { PROCESS_FRAGPIPE_PEPTIDES } from './modules/qcloud/process_fragpipe_peptides'

workflow {
    // Extract filename from the full path for parsing
    def rawfilePath = params.rawfile
    def filename = new File(rawfilePath).getName()
    
    // Instrument type detection - handles both .d and .d.checksum patterns
    def is_bruker = rawfilePath.toLowerCase().endsWith('.d') || rawfilePath.toLowerCase().contains('.d.')
    def is_thermo = rawfilePath.toLowerCase().endsWith('.raw') || rawfilePath.toLowerCase().contains('.raw.')
    
    // Extract QC type using proper reverse parsing
    def qcType = extractQCTypeFromFilename(filename)
    def selected_tsv_file = selectTsvFile(qcType, params)
    
    // Get QCloud sample type code from mapping file
    def qcodeFilePath = "${params.qcode_file}"
    def qcloud_sample_type = getQCloudSampleType(qcType, qcodeFilePath)

    // Get database name from mapping file
    def database_name = getDatabaseName(qcType, qcodeFilePath)

    log.info "Raw file/folder: ${params.rawfile}"
    log.info "Detected instrument type: ${is_bruker ? 'Bruker (.d folder)' : 'Thermo (.raw file)'}"
    log.info "Filename: ${filename}"
    log.info "Extracted QC type: ${qcType}"
    log.info "Selected TSV file: ${selected_tsv_file}"
    log.info "QCloud sample type code: ${qcloud_sample_type}"

    // Channel creation - handles both files and folders
    Channel
    .fromPath(params.rawfile, checkIfExists: true, type: is_bruker ? 'dir' : 'file')
    .map {
        def file = it.getName()
        def base = it.getBaseName()
        def path = it.getParent()
        
        // For Bruker files, append database name if not already in filename
        if (is_bruker && database_name && !file.contains(".${database_name}.")) {
            // Rename the file/folder to include database
            def newName = file.replaceAll(/\.d$/, ".${database_name}.d")
            log.info "Renaming ${file} to ${newName} for database detection"
            file = newName
            base = base + ".${database_name}"
        }
        
        [file, base, path]
    }
    .set { rawfile_ch }

    // Channels for msnbasexic_pr grouped params
    xic_params = params.msnbasexic_params

    tsv_file_ch         = Channel.value(selected_tsv_file)
    output_dir_ch       = Channel.value(xic_params.output_dir)
    analyte_name_ch     = Channel.value(xic_params.analyte_name)
    rt_tol_sec_ch       = Channel.value(xic_params.rt_tol_sec)
    mz_tol_ppm_ch       = Channel.value(xic_params.mz_tol_ppm)
    ms_level_ch         = Channel.value(xic_params.ms_level)
    plot_xic_ms1_ch     = Channel.value(xic_params.plot_xic_ms1)
    plot_xic_ms2_ch     = Channel.value(xic_params.plot_xic_ms2)
    plot_output_path_ch = Channel.value(xic_params.plot_output_path)
    overwrite_tsv_ch    = Channel.value(xic_params.overwrite_tsv)

    // Parse TSV file of peptides into tuples (meta, data)
    peptide_seqs = Channel
    .fromPath(selected_tsv_file)
    .splitCsv(header: true, sep: '\t')
    .map { row ->
        def meta = [ id: row.short_name ]
        def data = [
            long_name     : row.long_name,
            rt_teoretical : row.rt_teoretical
        ]
        tuple(meta, data)
    }

    if (is_thermo) {
        // THERMO WORKFLOW: RAW → mzML → FragPipe
        log.info "Processing Thermo RAW file..."
        
        // File conversion
        trfp_pr(rawfile_ch)
        cdecoy_pr(rawfile_ch)

        // Extract instrument information from mzML files
        EXTRACT_INSTRUMENT_INFO(trfp_pr.out)

        // Extract instrument info and modify FragPipe workflow based on instrument type
        MODIFY_FRAGPIPE_WORKFLOW(
            EXTRACT_INSTRUMENT_INFO.out.instrument_info,  // [basename, instrument_accession]
            Channel.fromPath(params.fp_workflow.replaceAll("'", "")),            
            Channel.fromPath("${params.qcloud_instruments_file}")
        )

        // Search engine preparation and execution
        fragpipe_prep_pr(rawfile_ch, cdecoy_pr.out)

        // Combine channels: use modified workflow + manifest and fasta from fragpipe_prep
        fragpipe_main_pr(
            rawfile_ch,
            MODIFY_FRAGPIPE_WORKFLOW.out.modified_workflow.map { sample_id, workflow -> workflow },
            fragpipe_prep_pr.out[1],
            fragpipe_prep_pr.out[2]
        )

        // Set channels for downstream processing
        conversion_output_ch = trfp_pr.out
        
    } else if (is_bruker) {
        // BRUKER WORKFLOW: .d folder → FragPipe directly
        log.info "Processing Bruker .d folder..."
        
        // Create decoy database (still needed for FragPipe)
        cdecoy_pr(rawfile_ch)

        // For Bruker, we'll use a default workflow since we can't extract instrument info from .d folders
        // without conversion. We'll use the original workflow file directly.
        default_workflow_ch = Channel.fromPath(params.fp_workflow.replaceAll("'", ""))

        // Search engine preparation and execution (using .d folder directly)
        fragpipe_prep_pr(rawfile_ch, cdecoy_pr.out)

        // Run FragPipe with .d folder input (FragPipe can handle .d folders natively)
        fragpipe_main_pr(
            rawfile_ch,
            default_workflow_ch,
            fragpipe_prep_pr.out[1],
            fragpipe_prep_pr.out[2]
        )

        // FragPipe outputs calibrated mzML - use it for metadata extraction
        conversion_output_ch = fragpipe_main_pr.out[7]  // mzML files from FragPipe
            .flatten()
            .filter { it.toString().endsWith('_calibrated.mzML') }
            .map { mzml -> 
                def mzml_filename = mzml.getName()
                def mzml_basename = mzml.getName().replaceAll(/_calibrated\.mzML$/, '')
                def mzml_path = mzml.getParent()
                [mzml_filename, mzml_basename, mzml_path, mzml]
            }
        
        // Extract metadata from calibrated mzML
        EXTRACT_METADATA(conversion_output_ch)
        
    } else {
        error "ERROR: Unable to determine instrument type. Expected .raw file or .d folder."
    }

    // Extract apex RT from FragPipe output - MUST run before msnbasexic
    combined_ion_ch = fragpipe_main_pr.out[5]
    extract_apex_rt_pr(
        Channel.fromPath(selected_tsv_file),
        combined_ion_ch
    )

    if (is_thermo) {
        // Quantification using MSnbaseXIC (only for Thermo files with mzML conversion)
        msnbasexic_script_ch = Channel.fromPath("${baseDir}/tools/msnbase/msnbasexic.R")
        msnbasexic_pr(
            conversion_output_ch,
            msnbasexic_script_ch,
            extract_apex_rt_pr.out
        )

        // Extract area, rt, dppm, and fwhm from MSnbaseXIC output
        PROCESS_PEPTIDES(
            conversion_output_ch,
            msnbasexic_pr.out,
            Channel.value(selected_tsv_file)
        )

        // Extract mit ms1 and ms2, tic, ms2 scan count
        EXTRACT_METADATA(conversion_output_ch)
        
    } else if (is_bruker) {
        // For Bruker .d folders, extract peptide metrics from FragPipe output instead of MSnbaseXIC
        log.info "Extracting peptide metrics from FragPipe combined_ion.tsv and psm.tsv for Bruker .d folder"
        
        // Combine sample_id with combined_ion and psm outputs
        fragpipe_peptide_input = conversion_output_ch
            .map { mzml_filename, mzml_basename, mzml_path, mzml -> mzml_basename }
            .combine(fragpipe_main_pr.out[5])  // combined_ion.tsv
            .combine(fragpipe_main_pr.out[6])  // psm.tsv
        
        PROCESS_FRAGPIPE_PEPTIDES(
            fragpipe_peptide_input,
            Channel.value(selected_tsv_file)
        )
    }

    // Extract FragPipe metrics using actual TSV files
    // For Bruker, we need to get the sample_id from the mzML basename (which has UUID+checksum)
    // For Thermo, we can use the rawfile basename
    if (is_bruker) {
        fragpipe_sample_id_ch = conversion_output_ch.map { mzml_filename, mzml_basename, mzml_path, mzml -> 
            [mzml_basename]  // Use mzML basename which has full UUID+context+checksum
        }
    } else {
        fragpipe_sample_id_ch = rawfile_ch.map { file, base, path -> 
            [base.replaceAll(/\.raw$/, '')]
        }
    }
    
    EXTRACT_FRAGPIPE_METRICS(
        fragpipe_sample_id_ch
        .combine(fragpipe_main_pr.out[1])  // protein.tsv (index 1)
        .combine(fragpipe_main_pr.out[0])  // peptide.tsv (index 0)  
        .combine(fragpipe_main_pr.out[6])  // psm.tsv (index 6)
        .map { sample_id, protein_tsv, peptide_tsv, psm_tsv ->
            [sample_id, protein_tsv, peptide_tsv, psm_tsv]
        }
    )
    
    // Collect JSON files based on instrument type
    if (is_thermo) {
        // Collect JSON files from all sources (Thermo workflow)
        // CRITICAL: Must include metadata.json for SUBMIT_TO_QCLOUD to extract creation date
        all_json_files = EXTRACT_METADATA.out.metadata_json
            .mix(EXTRACT_METADATA.out.qc_jsons.map { basename, jsons -> jsons })
            .mix(PROCESS_PEPTIDES.out.peptide_jsons.map { basename, jsons -> jsons })
            .mix(EXTRACT_FRAGPIPE_METRICS.out.fragpipe_jsons.map { sample_id, jsons -> jsons })
            .flatten()
            .collect()

        sample_info = EXTRACT_METADATA.out.qc_jsons.map { basename_mzml, jsons -> 
            // Remove .mzML extension to get the base sample name
            basename_mzml.replaceAll(/\.mzML$/, '')
        }
        
    } else if (is_bruker) {
        // For Bruker, collect FragPipe metrics + metadata from mzML + peptide metrics from FragPipe
        // CRITICAL: Must include metadata.json for SUBMIT_TO_QCLOUD to extract creation date
        all_json_files = EXTRACT_METADATA.out.metadata_json
            .mix(EXTRACT_METADATA.out.qc_jsons.map { basename, jsons -> jsons })
            .mix(EXTRACT_FRAGPIPE_METRICS.out.fragpipe_jsons.map { sample_id, jsons -> jsons })
            .mix(PROCESS_FRAGPIPE_PEPTIDES.out.peptide_jsons.map { sample_id, jsons -> jsons })
            .flatten()
            .collect()

        sample_info = EXTRACT_METADATA.out.qc_jsons.map { basename_mzml, jsons -> 
            // Remove .mzML extension to get the base sample name
            basename_mzml.toString().replaceAll(/_calibrated\.mzML$/, '')
        }
    }

    // Submit to QCloud API with correct sample info
    SUBMIT_TO_QCLOUD(
        all_json_files,
        sample_info,
        Channel.value(qcloud_sample_type)
    )

    // Error handler
    // Capture workflow metadata and params now: resolving the implicit `workflow`/
    // `params` bindings from inside the onError closure can return null when
    // Nextflow's Task monitor thread invokes this handler after a session abort
    // ("Cannot get property 'runName'/'enable_notif_email' on null object")
    def wf = workflow
    def enableNotifEmail = params.enable_notif_email
    def notifEmail = params.notif_email
    workflow.onError {
        def msg = """
        Pipeline FAILED!
        Run name     : ${wf.runName}
        Work dir     : ${wf.workDir}
        Exit status  : ${wf.exitStatus}
        Command line : ${wf.commandLine}
        """.stripIndent()

        if (enableNotifEmail) {
            sendMail(
                to: notifEmail,
                subject: ":( ATLAS pipeline error",
                body: msg
            )
        } else {
            log.error msg
        }
    }
}
