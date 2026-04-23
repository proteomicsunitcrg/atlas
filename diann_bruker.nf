#!/usr/bin/env nextflow
nextflow.enable.dsl=2

import DiannConfigLoader

// ----------------------------
// SUBWORKFLOWS
// ----------------------------
include { diann_bruker_qcloud as diann_bruker_pr } from './subworkflows/dia/diann_qcloud.nf'
include { insertDIANNBrukerFileToQSample as insertDIANNBrukerFileToQSample_pr; insertDIANNBrukerDataToQSample as insertDIANNBrukerDataToQSample_pr; insertDIANNBrukerQuantToQSample as insertDIANNBrukerQuantToQSample_pr } from './subworkflows/report/report_qsample_diann'

// ----------------------------
// VALIDATION
// ----------------------------
if (!params.rawfile) {
    error "Parameter 'rawfile' is required. Please provide it using --rawfile"
}

// ----------------------------
// INPUT CHANNEL
// ----------------------------
// Create input channel as Path (same as qcloud_diann.nf)
def input_ch = channel.fromPath(params.rawfile, checkIfExists: true, type: 'dir')
    .ifEmpty { error "No .d directories found in ${params.rawfile}" }

// ----------------------------
// PATTERN EXTRACTION
// ----------------------------
// Extract pattern from filename for DIA-NN config (BK in this case)
def filename = new File(params.rawfile).getName()
def afterDigits = filename.replaceAll(/^\d+/, '')
def pattern = (afterDigits =~ /^([A-Z]{2,3})/)[0][1]

log.info "Detected pattern for DIA-NN config: '${pattern}'"

// ----------------------------
// DIA-NN CONFIG LOADING
// ----------------------------
// Load DIA-NN method config using pattern (same as qcloud_diann.nf)
def diannConfigPath = params.diann_config ?: "${params.assets}/diann_methods_config.yaml"
def diannMethodConfig = DiannConfigLoader.loadConfig(diannConfigPath, pattern)

def diannVersion = DiannConfigLoader.getVersion(diannMethodConfig)
def diannContainer = DiannConfigLoader.getContainer(diannMethodConfig)
def diannConfigFile = "${params.assets}/${DiannConfigLoader.getConfigFile(diannMethodConfig)}"
def parserVersion = DiannConfigLoader.getParserVersion(diannMethodConfig)
def diannExecutable = DiannConfigLoader.getExecutable(diannMethodConfig)
def spectralLibraryFilter = DiannConfigLoader.getSpectralLibraryFilter(diannMethodConfig)

log.info "DIA-NN Config loaded for pattern '${pattern}':"
log.info "  Version: ${diannVersion}"
log.info "  Container: ${diannContainer}"
log.info "  Config: ${diannConfigFile}"
log.info "  Executable: ${diannExecutable}"
log.info "  Spectral library filter: ${spectralLibraryFilter}"

// ----------------------------
// WORKFLOW
// ----------------------------
workflow {

   // Call Bruker workflow with same signature as qcloud_diann.nf
   diann_bruker_pr(
       input_ch,
       diannContainer,
       diannConfigFile,
       parserVersion,
       diannExecutable,
       spectralLibraryFilter
   )

   // Insert results into QSample database
   insertDIANNBrukerFileToQSample_pr(
        diann_bruker_pr.out.report_tsv,
        diann_bruker_pr.out.sqlite_file
    )   

   insertDIANNBrukerDataToQSample_pr(
        insertDIANNBrukerFileToQSample_pr.out.checksum,
        insertDIANNBrukerFileToQSample_pr.out.tsv
   )

   insertDIANNBrukerQuantToQSample_pr(
        insertDIANNBrukerFileToQSample_pr.out.checksum,
        insertDIANNBrukerFileToQSample_pr.out.tsv
   )

}