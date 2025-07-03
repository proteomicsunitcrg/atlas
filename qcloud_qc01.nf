#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr } from './subworkflows/conversion/conversion'
include { msnbasexic as msnbasexic_pr } from './subworkflows/quantification/quantification'
include { insertDataToQCloud as insertDataToQCloud_pr } from './subworkflows/report/report_qcloud'
include { create_decoy as cdecoy_pr; fragpipe_prep as fragpipe_prep_pr; fragpipe_main as fragpipe_main_pr; extract_apex_rt as extract_apex_rt_pr } from './subworkflows/search_engine/search_engine.nf'
include { EXTRACT_METADATA } from './modules/qcloud/extract_metadata'

workflow {

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

    tsv_file_ch         = Channel.value(xic_params.tsv_file)
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
    .fromPath(xic_params.tsv_file)
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
    fragpipe_prep_pr(rawfile_ch,cdecoy_pr.out)
    fragpipe_main_pr(rawfile_ch, fragpipe_prep_pr.out)

    combined_ion_ch = fragpipe_main_pr.out[5]

    extract_apex_rt_pr(
        Channel.fromPath(xic_params.tsv_file),  // Pass the TSV file directly
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

    EXTRACT_METADATA(trfp_pr.out)

    // Report to QCloud database
    //insertDataToQCloud_pr(rawfile_ch, trfp_pr.out, msnbasexic_pr.out)

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
