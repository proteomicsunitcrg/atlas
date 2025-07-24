#!/usr/bin/env nextflow

nextflow.enable.dsl=2

// Import utility functions
include { extractQCType; selectTsvFile; extractQCTypeFromFilename; getQCloudSampleType } from './modules/functions/utils'

include { ThermoRawFileParser as trfp_pr } from './subworkflows/conversion/conversion'
include { msnbasexic as msnbasexic_pr } from './subworkflows/quantification/quantification'
include { insertDataToQCloud as insertDataToQCloud_pr } from './subworkflows/report/report_qcloud'
include { create_decoy as cdecoy_pr; fragpipe_prep as fragpipe_prep_pr; fragpipe_main as fragpipe_main_pr; extract_apex_rt as extract_apex_rt_pr } from './subworkflows/search_engine/search_engine.nf'
include { PROCESS_PEPTIDES } from './modules/qcloud/process_peptides'
include { EXTRACT_METADATA } from './modules/qcloud/extract_metadata'
include { EXTRACT_FRAGPIPE_METRICS } from './modules/qcloud/extract_fragpipe_metrics'
include { SUBMIT_TO_QCLOUD } from './modules/qcloud/submit_qcloud' 

workflow {
    // Extract filename from the full path for parsing
    def rawfilePath = params.rawfile
    def filename = new File(rawfilePath).getName()
    
    // Extract QC type using proper reverse parsing
    def qcType = extractQCTypeFromFilename(filename)
    def selected_tsv_file = selectTsvFile(qcType, params)
    
    // Get QCloud sample type code from mapping file
    def qcodeFilePath = "${params.home_dir}/mygit/atlas-config/atlas-test/assets/qcode.tsv"
    def qcloud_sample_type = getQCloudSampleType(qcType, qcodeFilePath)

    log.info "Raw file: ${params.rawfile}"
    log.info "Filename: ${filename}"
    log.info "Extracted QC type: ${qcType}"
    log.info "Selected TSV file: ${selected_tsv_file}"
    log.info "QCloud sample type code: ${qcloud_sample_type}"

    Channel
    .fromPath(params.rawfile)
    .map {
        def file = it.getName()
        def base = it.getBaseName()
        def path = it.getParent()
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

    // File conversion
    trfp_pr(rawfile_ch)
    cdecoy_pr(rawfile_ch)

    // Search engine preparation and execution
    fragpipe_prep_pr(rawfile_ch, cdecoy_pr.out)
    fragpipe_main_pr(rawfile_ch, fragpipe_prep_pr.out)

    combined_ion_ch = fragpipe_main_pr.out[5]

    extract_apex_rt_pr(
        Channel.fromPath(selected_tsv_file),  // Use the selected TSV file
        combined_ion_ch
    )

    // Quantification using MSnbaseXIC
    msnbasexic_script_ch = Channel.fromPath("${baseDir}/tools/msnbase/msnbasexic.R")
    msnbasexic_pr(
        trfp_pr.out,
        msnbasexic_script_ch,
        extract_apex_rt_pr.out,
        output_dir_ch, 
        analyte_name_ch,
        rt_tol_sec_ch,
        mz_tol_ppm_ch,
        ms_level_ch,
        plot_xic_ms1_ch,
        plot_xic_ms2_ch,
        plot_output_path_ch,
        overwrite_tsv_ch
    )

    //Extract area, rt, dppm, and fwhm
    PROCESS_PEPTIDES(
        trfp_pr.out,
        msnbasexic_pr.out,
        Channel.value(selected_tsv_file)
    )

    //Extract mit ms1 and ms2, tic, ms2 scan count
    EXTRACT_METADATA(trfp_pr.out)

    // Extract FragPipe metrics using actual TSV files
    EXTRACT_FRAGPIPE_METRICS(
        rawfile_ch.map { file, base, path -> 
            // Fix: Remove .raw from the end (not .raw.SOMETHING)
            def sample_id = base.replaceAll(/\.raw$/, '')
            [sample_id, file, base, path]
        }
        .combine(fragpipe_main_pr.out[1])  // protein.tsv (index 1)
        .combine(fragpipe_main_pr.out[0])  // peptide.tsv (index 0)  
        .combine(fragpipe_main_pr.out[6])  // psm.tsv (index 6)
        .map { sample_id, file, base, path, protein_tsv, peptide_tsv, psm_tsv ->
            [sample_id, protein_tsv, peptide_tsv, psm_tsv]
        }
    )

    all_json_files = EXTRACT_METADATA.out.qc_jsons
        .map { basename, jsons -> jsons }
        .mix(PROCESS_PEPTIDES.out.peptide_jsons.map { basename, jsons -> jsons })
        .mix(EXTRACT_FRAGPIPE_METRICS.out.fragpipe_jsons.map { sample_id, jsons -> jsons })
        .flatten()
        .collect()

    sample_info = EXTRACT_METADATA.out.qc_jsons.map { basename_mzml, jsons -> 
        // Remove .mzML extension to get the base sample name
        basename_mzml.replaceAll(/\.mzML$/, '')
    }

    // Submit to QCloud API with correct sample info
    SUBMIT_TO_QCLOUD(
        all_json_files,
        sample_info,
        Channel.value(qcloud_sample_type)
    )

    // Error handler
    workflow.onError {
        def msg = """
        Pipeline FAILED!
        Run name     : ${workflow.runName}
        Work dir     : ${workflow.workDir}
        Exit status  : ${workflow.exitStatus}
        Command line : ${workflow.commandLine}
        """.stripIndent()

        if (params.enable_notif_email) {
            sendMail(
                to: params.notif_email,
                subject: ":( ATLAS pipeline error",
                body: msg
            )
        } else {
            log.error msg
        }
    }
}