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
include { diann_qcloud as diann_pr } from './subworkflows/dia/dia.nf'
include { diann_bruker_qcloud as diann_bruker_pr } from './subworkflows/dia/dia.nf'
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

// ----------------------------
// WORKFLOW
// ----------------------------
workflow {

    // ----------------------------
    // EXTRACT QC TYPE & CONFIG
    // ----------------------------
    def qcType              = extractQCTypeFromFilename(filename)
    def selected_tsv_file   = selectTsvFile(qcType, params)
    def qcodeFilePath       = "${params.qcode_file}"
    def qcloud_sample_type  = getQCloudSampleType(qcType, qcodeFilePath)
    def checksum            = extract_checksum_from_filename(filename)
    def config_file_path    = "${params.qcloud_config}"

    log.info "QC type: ${qcType}"
    log.info "Selected TSV file: ${selected_tsv_file}"
    log.info "QCloud sample type: ${qcloud_sample_type}"
    log.info "Checksum: ${checksum}"
    log.info "Config file: ${config_file_path}"

    // ----------------------------
    // CHANNEL CREATION - HANDLES BOTH FILES AND FOLDERS
    // ----------------------------
    // <--- Channel creation - simplified since workflows now handle parsing
    def input_ch = Channel.fromPath(params.rawfile, checkIfExists: true, type: is_bruker ? 'dir' : 'file')

    def tsv_file_ch   = Channel.value(selected_tsv_file)
    def checksum_ch   = Channel.value(checksum)
    def sampletype_ch = Channel.value(qcloud_sample_type)
    def config_ch     = Channel.fromPath(config_file_path, checkIfExists: true)

    // ----------------------------
    // USE QCTYPE AS PATTERN FOR DIA-NN CONFIG
    // ----------------------------
    // For QCloud files, qcType is already extracted (QC01, QC02, QCD1, QCD2, etc.)
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
    
    def diannExecutable = DiannConfigLoader.getExecutable(diannMethodConfig)
    def requiresConversion = DiannConfigLoader.requiresConversion(diannMethodConfig)
    def spectralLibraryFilter = DiannConfigLoader.getSpectralLibraryFilter(diannMethodConfig)
    
    log.info "  Executable: ${diannExecutable}"
    
    log.info "DIA-NN Config loaded for pattern '${qcType}':"
    log.info "  Version: ${diannVersion}"
    log.info "  Container: ${diannContainer}"
    
    log.info "  Config: ${diannConfigFile}"
    log.info "  Parser: ${parserVersion}"
    log.info "  Requires RAW->mzML conversion: ${requiresConversion}"
    log.info "  Spectral library filter: ${spectralLibraryFilter}"

    // <--- Declare channels outside conditional blocks for proper scoping
    def report_tsv_ch
    def report_stats_tsv_ch
    def metadata_ch
    
    if (is_thermo) {
        // ----------------------------
        // THERMO WORKFLOW: Conditional RAW processing
        // ----------------------------
        log.info "Processing Thermo RAW file..."
        
        if (requiresConversion) {
            // ----------------------------
            // PATH 1: RAW → mzML → DIA-NN
            // ----------------------------
            log.info "RAW->mzML conversion enabled"
            
            // Convert Path to tuple for ThermoRawFileParser
            thermo_ch = input_ch.map { file ->
                tuple(file.getName(), file.getBaseName(), file.getParent())
            }
            
            // Convert RAW → mzML
            trfp_pr(thermo_ch)

            // Run DIA-NN on mzML
            diann_pr(trfp_pr.out, diannContainer, diannConfigFile, parserVersion, diannExecutable, spectralLibraryFilter)

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
            
        } else {
            // ----------------------------
            // PATH 2: RAW → DIA-NN (direct processing)
            // ----------------------------
            log.info "RAW->mzML conversion skipped (DIA-NN processes RAW directly)"
            
            // Pass RAW file directly to DIA-NN (input_ch is already Path)
            diann_pr(input_ch, diannContainer, diannConfigFile, parserVersion, diannExecutable, spectralLibraryFilter)
            
            // <--- Create mock metadata structure matching EXTRACT_METADATA output
            def mock_qc_jsons = input_ch.map { file ->
                tuple(file.getBaseName(), [])  // Empty list for qc_jsons
            }
            def mock_metadata_json = Channel.empty()  // Empty channel for metadata_json
            
            // <--- Create metadata_ch with same structure as EXTRACT_METADATA.out
            metadata_ch = [qc_jsons: mock_qc_jsons, metadata_json: mock_metadata_json]
            
            // Set up channels for downstream processing
            report_tsv_ch = diann_pr.out.report_tsv
            report_stats_tsv_ch = diann_pr.out.report_stats_tsv
        }
        
    }  else if (is_bruker) {
        // ----------------------------
        // BRUKER WORKFLOW: .d folder → DIA-NN directly
        // ----------------------------
        log.info "Processing Bruker .d folder..."
        
        // Run DIA-NN directly on .d folder (input_ch is already Path)
        diann_bruker_pr(input_ch, diannContainer, diannConfigFile, parserVersion, diannExecutable, spectralLibraryFilter)

        // <--- Create mock metadata structure matching EXTRACT_METADATA output
        def mock_qc_jsons = input_ch.map { folder ->
            tuple(folder.getBaseName().replaceAll(/\.d$/, ''), [])  // Empty list for qc_jsons
        }
        def mock_metadata_json = Channel.empty()  // Empty channel for metadata_json
        
        // <--- Create metadata_ch with same structure as EXTRACT_METADATA.out
        metadata_ch = [qc_jsons: mock_qc_jsons, metadata_json: mock_metadata_json]

        // Set up channels for downstream processing
        report_tsv_ch = diann_bruker_pr.out.report_tsv
        report_stats_tsv_ch = diann_bruker_pr.out.report_stats_tsv
        
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
        // <--- Mix metadata QC jsons (may be empty) with DIA-NN jsons
        all_json_files = metadata_ch.qc_jsons
            .map { basename, jsons -> jsons }
            .mix(EXTRACT_DIANN_METRICS.out.diann_jsons.map { cs, jsons -> jsons })
            .flatten()
            .collect()

        // <--- Extract sample_info from basename (remove .raw and .mzML extensions)
        sample_info = metadata_ch.qc_jsons.map { basename_mzml, jsons ->
            basename_mzml.replaceAll(/\.mzML\..*$/, "").replaceAll(/\.raw\..*$/, "")
        }.first()

        // <--- Collect all files including metadata.json (may be empty)
        all_files_with_metadata = all_json_files
            .mix(metadata_ch.metadata_json)
            .collect()
            
    } else if (is_bruker) {
        // For Bruker, we only have DIA-NN metrics
        all_json_files = EXTRACT_DIANN_METRICS.out.diann_jsons
            .map { cs, jsons -> jsons }
            .flatten()
            .collect()

        sample_info = input_ch.map { folder ->
            folder.getName().replaceAll(/\.d$/, "")
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
                subject: ":( ATLAS DIA-NN pipeline error",
                body: msg
            )
        } else {
            log.error msg
        }
    }
}