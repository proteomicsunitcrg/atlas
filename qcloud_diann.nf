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
include { ThermoRawFileParserDiann as trfp_pr } from './subworkflows/conversion/conversion'

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
def config_file_path    = "${params.home_dir}/mygit/atlas-config/atlas-test/conf/tools/qcloud.config"

log.info "Raw file: ${params.rawfile}"
log.info "QC type: ${qcType}"
log.info "Selected TSV file: ${selected_tsv_file}"
log.info "QCloud sample type: ${qcloud_sample_type}"
log.info "Checksum: ${checksum}"
log.info "Config file: ${config_file_path}"

// FIX: Create proper tuple structure for ThermoRawFileParserDiann
// Use different variable names to avoid conflict
def rawfile_ch = Channel.fromPath(params.rawfile, checkIfExists: true)
    .map { file -> 
        def file_name = file.getName()      // Changed from 'filename'
        def file_basename = file.getBaseName()  // Changed from 'basename'
        def file_path = file.getParent()    // Changed from 'path'
        tuple(file_name, file_basename, file_path)
    }

def tsv_file_ch   = Channel.value(selected_tsv_file)
def checksum_ch   = Channel.value(checksum)
def sampletype_ch = Channel.value(qcloud_sample_type)
def config_ch     = Channel.fromPath(config_file_path, checkIfExists: true)

// ----------------------------
// WORKFLOW
// ----------------------------
workflow {

    // ----------------------------
    // CONVERT RAW → mzML (using ThermoRawFileParserDiann)
    // ----------------------------
    trfp_pr(rawfile_ch)

    // ----------------------------
    // Transform ThermoRawFileParserDiann output for diann_pr
    // Since ThermoRawFileParserDiann outputs file("*.mzML.*"), we need to adapt it
    // ----------------------------
    mzml_for_diann = trfp_pr.out

    // ----------------------------
    // RUN DIA-NN (uses mzML)
    // ----------------------------
    diann_pr(mzml_for_diann)

    // ----------------------------
    // PARSE DIA-NN REPORT.TSV → JSON QC
    // ----------------------------
    EXTRACT_DIANN_METRICS(
        diann_pr.out.report_tsv,
        tsv_file_ch,
        checksum_ch,
        config_ch
    )

    // ----------------------------
    // GENERAL METADATA (tic, mit, ms2 scans…)
    // ----------------------------
    mzml_ch = trfp_pr.out.map { f ->
        def filename_mzml  = f.getName()
        def basename_mzml  = filename_mzml.replaceAll(/\.mzML\..*$/, "")
        def path_mzml      = f.getParent()
        tuple(filename_mzml, basename_mzml, path_mzml, f)
    }

    EXTRACT_METADATA(mzml_ch)

    // ----------------------------
    // COLLECT ALL JSON FILES - UPDATED for new output structure
    // ----------------------------
    all_json_files = EXTRACT_METADATA.out.qc_jsons
        .map { basename, jsons -> jsons }
        .mix(EXTRACT_DIANN_METRICS.out.diann_jsons.map { cs, jsons -> jsons })
        .flatten()
        .collect()

    sample_info = EXTRACT_METADATA.out.qc_jsons.map { basename_mzml, jsons ->
        basename_mzml.replaceAll(/\.mzML\..*$/, "")
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
