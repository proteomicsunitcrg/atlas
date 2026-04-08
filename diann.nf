#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParserDiann as trfp_diann_pr } from './subworkflows/conversion/conversion'
include { diann as diann_pr } from './subworkflows/dia/dia'
include { insertDIANNFileToQSample as insertDIANNFileToQSample_pr; insertDIANNDataToQSample as insertDIANNDataToQSample_pr; insertDIANNQuantToQSample as insertDIANNQuantToQSample_pr; insertDiannPolymerContToQSample as insertDiannPolymerContToQSample_pr} from './subworkflows/report/report_qsample_diann'
include { output_folder_diann as output_folder_diann_pr} from './subworkflows/report/report_output_folder'
include { DiannConfigLoader } from './lib/DiannConfigLoader'

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

// ----------------------------
// LOAD DIA-NN METHOD CONFIG
// ----------------------------
def diannConfigPath = "${params.assets}/diann_methods_config.yaml"
def diannMethodConfig = DiannConfigLoader.loadConfig(diannConfigPath, params.pattern)

def diannVersion = DiannConfigLoader.getVersion(diannMethodConfig)
def diannContainer = DiannConfigLoader.getContainer(diannMethodConfig)
def diannConfigFile = DiannConfigLoader.getConfigFile(diannMethodConfig)
def parserVersion = DiannConfigLoader.getParserVersion(diannMethodConfig)

log.info "DIA-NN Config loaded for pattern '${params.pattern}':"
log.info "  Version: ${diannVersion}"
log.info "  Container: ${diannContainer}"
log.info "  Config: ${diannConfigFile}"
log.info "  Parser: ${parserVersion}"

workflow {
 
   //Conversion:
   trfp_diann_pr(rawfile_ch)

   //DIA-NN: 
   diann_pr(trfp_diann_pr.out, diannContainer, diannConfigFile, parserVersion)

   //Report to QSample database:
   insertDIANNFileToQSample_pr(rawfile_ch,trfp_diann_pr.out)
   insertDIANNDataToQSample_pr(insertDIANNFileToQSample_pr.out,diann_pr.out,trfp_diann_pr.out)
   insertDIANNQuantToQSample_pr(insertDIANNFileToQSample_pr.out,diann_pr.out)
   //Report to output folder (if the field output_folder was informed at methods CSV file):
   output_folder_diann_pr(diann_pr.out,trfp_diann_pr.out,output_folder_ch)  
   
   //lab
   insertDiannPolymerContToQSample_pr(insertDIANNFileToQSample_pr.out,trfp_diann_pr.out)
}
