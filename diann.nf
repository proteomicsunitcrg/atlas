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
