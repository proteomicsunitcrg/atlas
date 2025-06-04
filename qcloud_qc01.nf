#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr }       from 'subworkflows/conversion/conversion'
include { msnbasexic as msnbasexic_pr }          from 'subworkflows/quantification/quantification'
include { insertDataToQCloud as insertDataToQCloud_pr } from 'subworkflows/report/report_qcloud'

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
    def xic_params = params.msnbasexic_params

    def tsv_file_ch         = Channel.value(xic_params.tsv_file)
    def output_dir_ch       = Channel.value(xic_params.output_dir)
    def analyte_name_ch     = Channel.value(xic_params.analyte_name)
    def rt_tol_sec_ch       = Channel.value(xic_params.rt_tol_sec)
    def mz_tol_ppm_ch       = Channel.value(xic_params.mz_tol_ppm)
    def ms_level_ch         = Channel.value(xic_params.ms_level)
    def plot_xic_ms1_ch     = Channel.value(xic_params.plot_xic_ms1)
    def plot_xic_ms2_ch     = Channel.value(xic_params.plot_xic_ms2)
    def plot_output_path_ch = Channel.value(xic_params.plot_output_path)
    def overwrite_tsv_ch    = Channel.value(xic_params.overwrite_tsv)

    // File conversion
    trfp_pr(rawfile_ch)

    // Quantification using MSnbaseXIC
    msnbasexic_pr(
        trfp_pr.out,
        tsv_file_ch,
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

    // Report to QCloud database
    insertDataToQCloud_pr(rawfile_ch, trfp_pr.out, msnbasexic_pr.out)

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
