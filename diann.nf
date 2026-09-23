#!/usr/bin/env nextflow

nextflow.enable.dsl=2

import DiannConfigLoader

include { ThermoRawFileParserDiann as trfp_diann_pr } from './subworkflows/conversion/conversion'
include { diann as diann_pr } from './subworkflows/dia/dia'
include { insertDIANNFileToQSample as insertDIANNFileToQSample_pr; insertDIANNDataToQSample as insertDIANNDataToQSample_pr; insertDIANNQuantToQSample as insertDIANNQuantToQSample_pr; insertDiannPolymerContToQSample as insertDiannPolymerContToQSample_pr; insertDIANNModificationsToQSample as insertDIANNModificationsToQSample_pr } from './subworkflows/report/report_qsample_diann'
include { output_folder_diann as output_folder_diann_pr} from './subworkflows/report/report_output_folder'

Channel
  .fromPath(params.rawfile)
  .map {
      file = it.getName()
      base = it.getBaseName()
      path = it.getParent()
      [file, base, path]
  }
  .set { rawfile_ch }

Channel
  .from(params.var_modif)
  .set { var_modif_ch }

Channel
  .from(params.fragment_mass_tolerance)
  .set { fragment_mass_tolerance_ch }

Channel
  .from(params.fragment_error_units)
  .set { fragment_error_units_ch }

Channel
  .from(params.precursor_mass_tolerance)
  .set { precursor_mass_tolerance }

Channel
  .from(params.missed_cleavages)
  .set { missed_cleavages }

Channel
  .from(params.instrument_folder)
  .set { instrument_folder }

Channel
  .from(params.output_folder)
  .set { output_folder }

Channel
  .from(params.output_folder)
  .set { output_folder_ch }

Channel
  .fromPath(params.atlas_ptm_list)
  .set { atlas_ptm_list_ch }

workflow {

   // Fire-and-forget "received" notification for the Request plots processing
   // icon (proteomicsunitcrg/qsample-server#192) - fires immediately as plain script code in
   // the same driver process running this workflow, not a separate Nextflow
   // process. Mirrors the same notifier in main.nf/qcloud.nf.
    try {
        def startScript = """
            cd '${projectDir}/bin'
            source api.sh
            checksum=\$(md5sum '${params.rawfile}' 2>/dev/null | awk '{print \$1}')
            [ -z "\$checksum" ] && exit 0
            access_token=\$(get_api_access_token '${params.url_api_signin}' '${params.url_api_user}' '${params.url_api_pass}')
            [ -z "\$access_token" ] && exit 0
            api_base='${params.url_api_insert_file}'
            api_base=\${api_base%/api/file/insertFromPipelineRequest}
            fname=\$(basename '${params.rawfile}')
            request_code=\$(echo "\$fname" | awk -F'[_.]' '{print \$1}')
            fbase=\${fname%.*}
            [ "\$fbase" = "\$fname" ] && fbase=\$fname
            curl -s --max-time 10 -X POST -H "Authorization: Bearer \$access_token" \\
                "\${api_base}/api/file/insertFromPipelineRequest/\$request_code" \\
                -H "Content-Type: application/json" \\
                --data '{\"checksum\": \"'\$checksum'\", \"filename\": \"'\$fbase'\"}' -o /dev/null
            curl -s --max-time 10 -X POST -H "Authorization: Bearer \$access_token" \\
                "\${api_base}/api/requestFileStatus/received/\$checksum" -o /dev/null
        """
        ['bash', '-c', startScript].execute()
    } catch (Exception e) {
        log.warn "Could not notify QSample of processing start (non-fatal): ${e.message}"
    }

   // ----------------------------
   // EXTRACT PATTERN FROM FILENAME
   // ----------------------------
   // Example: 2024MK888_DIA_min_test.mzML.SP_Human → REQUEST=2024MK888 → pattern=MK
   def rawfilePath = params.rawfile
   def filename = new File(rawfilePath).getName()
   def request = filename.tokenize('_')[0]  // Extract first part before underscore
   def pattern = request.find(/[A-Z]{2,3}/)  // Extract 2-3 uppercase letters (MK, NK, LA, etc.)
   
   log.info "Pattern extraction: filename='${filename}' → request='${request}' → pattern='${pattern}'"

   // ----------------------------
   // LOAD DIA-NN METHOD CONFIG
   // ----------------------------
   def diannMethodConfig = DiannConfigLoader.loadConfig(params.diann_config, pattern)
   def diannVersion = DiannConfigLoader.getVersion(diannMethodConfig)
   def diannContainer = DiannConfigLoader.getContainer(diannMethodConfig)
   def diannConfigFile = "${params.assets}/${DiannConfigLoader.getConfigFile(diannMethodConfig)}"
   def parserVersion = DiannConfigLoader.getParserVersion(diannMethodConfig)
   def diannExecutable = DiannConfigLoader.getExecutable(diannMethodConfig)
   def requiresConversion = DiannConfigLoader.requiresConversion(diannMethodConfig)
   def spectralLibraryFilter = DiannConfigLoader.getSpectralLibraryFilter(diannMethodConfig) 

   log.info "  Executable: ${diannExecutable}"
   log.info "  DIA-NN Config loaded for pattern '${pattern}':"
   log.info "  Version: ${diannVersion}"
   log.info "  Container: ${diannContainer}"
   log.info "  Config: ${diannConfigFile}"
   log.info "  Parser: ${parserVersion}"
   log.info "  Requires RAW->mzML conversion: ${requiresConversion}"    
   log.info "  Spectral Library Filter: ${spectralLibraryFilter} (derived from version)" 

   def converted_files_ch
   def diann_input_ch

   if (requiresConversion) {
       // Mode LEGACY: DIA-NN espera conversió (seqüencial)
       log.info "RAW->mzML conversion REQUIRED (sequential mode)"
       trfp_diann_pr(rawfile_ch)
       converted_files_ch = trfp_diann_pr.out
       diann_pr(converted_files_ch, diannContainer, diannConfigFile, parserVersion, diannExecutable, spectralLibraryFilter)
   } else {
       // Mode PARAL·LEL: DIA-NN processa RAW directament, conversió en background
       log.info "RAW->mzML conversion NOT REQUIRED (parallel mode)"
       log.info "  - DIA-NN processes .raw directly"
       log.info "  - TRFP conversion runs in parallel for compatibility"
       
       // DIA-NN processa fitxer RAW original
       diann_input_ch = rawfile_ch.map { fname, bname, fpath -> 
           file("${fpath}/${fname}")
       }
       diann_pr(diann_input_ch, diannContainer, diannConfigFile, parserVersion, diannExecutable, spectralLibraryFilter)
       
       // Conversió en paral·lel per altres eines downstream
       trfp_diann_pr(rawfile_ch)
       converted_files_ch = trfp_diann_pr.out
   }                                                                          

  //Report to QSample database:
  insertDIANNFileToQSample_pr(rawfile_ch, converted_files_ch)                   
  insertDIANNDataToQSample_pr(insertDIANNFileToQSample_pr.out, diann_pr.out.report_tsv, converted_files_ch)  
  insertDIANNQuantToQSample_pr(insertDIANNFileToQSample_pr.out, diann_pr.out.report_tsv)
  insertDIANNModificationsToQSample_pr(insertDIANNFileToQSample_pr.out, diann_pr.out.modification_metrics_tsv, atlas_ptm_list_ch)
  //Report to output folder (if the field output_folder was informed at methods CSV file):
  output_folder_diann_pr(diann_pr.out.report_tsv, converted_files_ch, output_folder_ch)        
  
  //lab
  insertDiannPolymerContToQSample_pr(insertDIANNFileToQSample_pr.out, converted_files_ch)

}

// Capture workflow metadata and params now: resolving the implicit `workflow`/
// `params` bindings from inside the onError closure can return null when
// Nextflow's Task monitor thread invokes this handler after a session abort.
def wf = workflow
def enableNotifEmail = params.enable_notif_email
def notifEmail = params.notif_email
def errRawfile = params.rawfile
def errBinDir = "${projectDir}/bin"
def errSigninUrl = params.url_api_signin
def errUser = params.url_api_user
def errPass = params.url_api_pass
def errInsertFileUrl = params.url_api_insert_file
workflow.onError {

    def msg = """\
        Pipeline execution summary
        --------------------------
        Run name      : ${wf.runName}
        Working dir   : ${wf.workDir}
        Command line  : ${wf.commandLine}
        """
        .stripIndent()

    if (enableNotifEmail) {
        sendMail(to: notifEmail, subject: ':( atlas pipeline error', body: msg)
    } else {
        log.error msg
    }

    // Best-effort, fires the moment the whole run fails (any process, any
    // reason) so the Request plots icon gets an accurate ERROR timestamp
    // right away, instead of waiting for atlas_checker.sh's cron to notice
    // later. atlas_checker.sh still runs afterwards and enriches the
    // reason/diagnostic fields (see RequestFileStatusService.markError - it
    // only stamps updatedDate on the *first* transition into ERROR, so this
    // later enrichment doesn't corrupt the duration shown in the UI).
    try {
        def errScript = """
            cd '${errBinDir}'
            source api.sh
            checksum=\$(md5sum '${errRawfile}' 2>/dev/null | awk '{print \$1}')
            [ -z "\$checksum" ] && exit 0
            access_token=\$(get_api_access_token '${errSigninUrl}' '${errUser}' '${errPass}')
            [ -z "\$access_token" ] && exit 0
            api_base='${errInsertFileUrl}'
            api_base=\${api_base%/api/file/insertFromPipelineRequest}
            size_bytes=\$(stat -c '%s' '${errRawfile}' 2>/dev/null)
            size_mb_json="null"
            [[ "\$size_bytes" =~ ^[0-9]+\$ ]] && size_mb_json=\$(awk "BEGIN { printf \\"%.0f\\", \$size_bytes/1024/1024 }")
            payload=\$(printf '{"errorReason":"Pipeline failed - detailed reason pending automatic classification.","sizeMb":%s}' "\$size_mb_json")
            curl -s --max-time 10 -X POST -H "Authorization: Bearer \$access_token" -H "Content-Type: application/json" \\
                --data "\$payload" "\${api_base}/api/requestFileStatus/error/\$checksum" -o /dev/null
        """
        def proc = ['bash', '-c', errScript].execute()
        proc.waitForOrKill(15000)
    } catch (Exception e) {
        log.warn "onError: could not notify QSample requestFileStatus (non-fatal): ${e.message}"
    }
}
