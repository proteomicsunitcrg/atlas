#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// ----------------------------
// UTILS
// ----------------------------
include { extractQCType; selectTsvFile; extractQCTypeFromFilename; getQCloudSampleType; extract_checksum_from_filename } from './modules/functions/utils'

// ----------------------------
// SUBWORKFLOWS
// ----------------------------
include { diann_qcloud as diann_pr } from './subworkflows/dia/diann_qcloud.nf'

// ----------------------------
// QCLOUD MODULES
// ----------------------------
include { EXTRACT_METADATA } from './modules/qcloud/extract_metadata'
include { EXTRACT_DIANN_METRICS } from './modules/qcloud/extract_diann_metrics'
include { SUBMIT_TO_QCLOUD } from './modules/qcloud/submit_qcloud'

// ----------------------------
// CHANNELS & INPUT PARSING
// ----------------------------
def rawfilePath         = params.rawfile
def filename            = new File(rawfilePath).getName()

def qcType              = extractQCTypeFromFilename(filename)
def selected_tsv_file   = selectTsvFile(qcType, params)
def qcodeFilePath       = "${params.home_dir}/mygit/atlas-config/atlas-test/assets/qcode.tsv"
def qcloud_sample_type  = getQCloudSampleType(qcType, qcodeFilePath)
def checksum            = extract_checksum_from_filename(filename)

log.info "Raw file: ${params.rawfile}"
log.info "QC type: ${qcType}"
log.info "Selected TSV file: ${selected_tsv_file}"
log.info "QCloud sample type: ${qcloud_sample_type}"
log.info "Checksum: ${checksum}"

def rawfile_ch    = Channel.fromPath(params.rawfile)
def tsv_file_ch   = Channel.value(selected_tsv_file)
def checksum_ch   = Channel.value(checksum)
def sampletype_ch = Channel.value(qcloud_sample_type)

// ----------------------------
// WORKFLOW
// ----------------------------
workflow {

    // ----------------------------
    // RUN DIA-NN
    // ----------------------------
    diann_pr(rawfile_ch)

    // ----------------------------
    // PARSE DIA-NN REPORT.TSV → JSON QC
    // ----------------------------
    EXTRACT_DIANN_METRICS(
        diann_pr.out.report_tsv,
        tsv_file_ch,
        checksum_ch
    )

    // ----------------------------
    // GENERAL METADATA (tic, mit, ms2 scans…)
    // ----------------------------
    // Prepare tuple for EXTRACT_METADATA
    rawfile_ch = Channel
        .fromPath(params.rawfile)
        .map { f ->
            def filename_mzml  = f.getName()
            def basename_mzml  = filename_mzml.replaceAll(/\.mzML$/, "")
            def path_mzml      = f.getParent()
            tuple(filename_mzml, basename_mzml, path_mzml, f)
        }

    EXTRACT_METADATA(rawfile_ch)

    // ----------------------------
    // COLLECT ALL JSON FILES
    // ----------------------------
    all_json_files = EXTRACT_METADATA.out.qc_jsons
        .map { basename, jsons -> jsons }
        .mix(EXTRACT_DIANN_METRICS.out.diann_jsons.map { cs, jsons -> jsons })
        .flatten()
        .collect()

    sample_info = EXTRACT_METADATA.out.qc_jsons.map { basename_mzml, jsons ->
        basename_mzml.replaceAll(/\.mzML$/, "")
    }

    // ----------------------------
    // SUBMIT TO QCLOUD
    // ----------------------------
    SUBMIT_TO_QCLOUD(all_json_files, sample_info, sampletype_ch)

    // ----------------------------
    // ERROR HANDLER
    // ----------------------------
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
                subject: ":( ATLAS DIA-NN pipeline error",
                body: msg
            )
        } else {
            log.error msg
        }
    }
}
