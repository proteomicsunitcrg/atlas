#!/usr/bin/env nextflow
nextflow.enable.dsl=2

import DiannConfigLoader

// ----------------------------
// UTILS
// ----------------------------
include { extractQCType; selectTsvFile; extractQCTypeFromFilename; getQCloudSampleType; extract_checksum_from_filename } from './modules/functions/utils'

// ----------------------------
// SUBWORKFLOWS
// ----------------------------
include { diann_qcloud as diann_pr } from './subworkflows/dia/diann_qcloud.nf'
include { diann_bruker_qcloud as diann_bruker_pr } from './subworkflows/dia/diann_qcloud.nf'
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
// Add parameter validation
if (!params.rawfile) {
    log.error "ERROR: --rawfile parameter is required"
    exit 1
}

def rawfilePath         = params.rawfile
def filename            = new File(rawfilePath).getName()

// ----------------------------
// INSTRUMENT TYPE DETECTION
// ----------------------------
def is_bruker           = rawfilePath.toLowerCase().contains('.d.')
def is_thermo           = rawfilePath.toLowerCase().endsWith('.raw') || rawfilePath.toLowerCase().contains('.raw.')

log.info "Raw file/folder: ${params.rawfile}"
log.info "Detected instrument type: ${is_bruker ? 'Bruker (.d folder)' : 'Thermo (.raw file)'}"

def qcType              = extractQCTypeFromFilename(filename)
def selected_tsv_file   = selectTsvFile(qcType, params)
def qcodeFilePath       = "${params.qcode_file}"
def qcloud_sample_type  = getQCloudSampleType(qcType, qcodeFilePath)
def checksum            = extract_checksum_from_filename(filename)
def config_file_path = "${params.qcloud_config}"

log.info "QC type: ${qcType}"
log.info "Selected TSV file: ${selected_tsv_file}"
log.info "QCloud sample type: ${qcloud_sample_type}"
log.info "Checksum: ${checksum}"
log.info "Config file: ${config_file_path}"

// ----------------------------
// CHANNEL CREATION - HANDLES BOTH FILES AND FOLDERS
// ----------------------------
def input_ch = Channel.fromPath(params.rawfile, checkIfExists: true, type: is_bruker ? 'dir' : 'file')
    .map { input -> 
        def input_name = input.getName()      
        def input_basename = input.getBaseName()  
        def input_path = input.getParent()    
        tuple(input_name, input_basename, input_path, input)
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
    // USE QCTYPE AS PATTERN FOR DIA-NN CONFIG
    // ----------------------------
    // For QCloud files, qcType is already extracted (QC01, QC02, QCD1, QCD2, etc.)
    // This was extracted earlier using extractQCTypeFromFilename()
    log.info "Using QC type as pattern for DIA-NN config: '${qcType}'"

    // ----------------------------
    // LOAD DIA-NN METHOD CONFIG
    // ----------------------------
    def diannConfigPath = params.diann_config ?: "${params.assets}/diann_methods_config.yaml"
    def diannMethodConfig = DiannConfigLoader.loadConfig(diannConfigPath, qcType)

    def diannVersion = DiannConfigLoader.getVersion(diannMethodConfig)
    def diannContainer = DiannConfigLoader.getContainer(diannMethodConfig)
    def diannConfigFile = "${params.assets}/${DiannConfigLoader.getConfigFile(diannMethodConfig)}"
    def parserVersion = DiannConfigLoader.getParserVersion(diannMethodConfig)

    log.info "DIA-NN Config loaded for pattern '${qcType}':"
    log.info "  Version: ${diannVersion}"
    log.info "  Container: ${diannContainer}"
    log.info "  Config: ${diannConfigFile}"
    log.info "  Parser: ${parserVersion}"

    if (is_thermo) {
        // ----------------------------
        // THERMO WORKFLOW: RAW → mzML → DIA-NN
        // ----------------------------
        log.info "Processing Thermo RAW file..."
        
        // Convert tuple for Thermo workflow (extract first 3 elements)
        thermo_ch = input_ch.map { name, basename, path, file -> tuple(name, basename, path) }
        
        // Convert RAW → mzML
        trfp_pr(thermo_ch)

        // Run DIA-NN on mzML
        diann_pr(trfp_pr.out, diannContainer, diannConfigFile, parserVersion

        // Extract metadata from mzML
        mzml_ch = trfp_pr.out.map { f ->
            def filename_mzml  = f.getName()
            def basename_mzml  = filename_mzml.replaceAll(/\.mzML\..*$/, "")
            def path_mzml      = f.getParent()
            tuple(filename_mzml, basename_mzml, path_mzml, f)
        }
        EXTRACT_METADATA(mzml_ch)

        // Set up channels for downstream processing
        report_tsv_ch = diann_pr.out.report_tsv
        report_stats_tsv_ch = diann_pr.out.report_stats_tsv
        metadata_ch = EXTRACT_METADATA.out
        
    } else if (is_bruker) {
        // ----------------------------
        // BRUKER WORKFLOW: .d folder → DIA-NN directly
        // ----------------------------
        log.info "Processing Bruker .d folder..."
        
        // Extract just the folder path for Bruker workflow
        bruker_ch = input_ch.map { name, basename, path, folder -> folder }
        
        // Run DIA-NN directly on .d folder
        diann_bruker_pr(bruker_ch, diannContainer, diannConfigFile, parserVersion)

        // For Bruker, we don't have mzML files, so create a mock metadata channel
        // or extract metadata from the original .d folder if needed
        mock_metadata_ch = input_ch.map { name, basename, path, folder ->
            // Create a structure similar to EXTRACT_METADATA output
            def mock_qc_jsons = []  // Empty for now, could be populated if needed
            def mock_metadata_json = null  // Could extract from .d folder if needed
            [qc_jsons: mock_qc_jsons, metadata_json: mock_metadata_json]
        }

        // Set up channels for downstream processing
        report_tsv_ch = diann_bruker_pr.out.report_tsv
        report_stats_tsv_ch = diann_bruker_pr.out.report_stats_tsv
        metadata_ch = mock_metadata_ch
        
    } else {
        error "ERROR: Unable to determine instrument type. Expected .raw file or .d folder."
    }

    // ----------------------------
    // PARSE DIA-NN REPORT.TSV → JSON QC (Common for both instruments)
    // ----------------------------
    EXTRACT_DIANN_METRICS(
        report_tsv_ch,
        report_stats_tsv_ch,
        tsv_file_ch,
        checksum_ch,
        config_ch
    )

    // ----------------------------
    // COLLECT ALL JSON FILES - UPDATED for both instrument types
    // ----------------------------
    if (is_thermo) {
        all_json_files = metadata_ch.qc_jsons
            .map { basename, jsons -> jsons }
            .mix(EXTRACT_DIANN_METRICS.out.diann_jsons.map { cs, jsons -> jsons })
            .flatten()
            .collect()

        sample_info = metadata_ch.qc_jsons.map { basename_mzml, jsons ->
            basename_mzml.replaceAll(/\.mzML\..*$/, "")
        }.first()

        // Collect all files including metadata.json
        all_files_with_metadata = all_json_files
            .mix(metadata_ch.metadata_json)
            .collect()
            
    } else if (is_bruker) {
        // For Bruker, we only have DIA-NN metrics
        all_json_files = EXTRACT_DIANN_METRICS.out.diann_jsons
            .map { cs, jsons -> jsons }
            .flatten()
            .collect()

        sample_info = input_ch.map { name, basename, path, folder ->
            basename.replaceAll(/\.d$/, "")
        }.first()

        // For Bruker, no metadata.json from mzML
        all_files_with_metadata = all_json_files.collect()
    }

    // ----------------------------
    // SUBMIT TO QCLOUD
    // ----------------------------
    SUBMIT_TO_QCLOUD(all_files_with_metadata, sample_info, sampletype_ch)

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
