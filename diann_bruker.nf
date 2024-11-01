#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { diann_bruker as diann_bruker_pr } from './subworkflows/dia/dia'
include { insertDIANNFileToQSample as insertDIANNFileToQSample_pr; insertDIANNDataToQSample as insertDIANNDataToQSample_pr; insertDIANNQuantToQSample as insertDIANNQuantToQSample_pr; insertDiannPolymerContToQSample as insertDiannPolymerContToQSample_pr} from './subworkflows/report/report_qsample_diann'
include { output_folder_diann as output_folder_diann_pr} from './subworkflows/report/report_output_folder'

// Check if params.rawfile is defined
if (!params.rawfile) {
    error "Parameter 'rawfile' is required. Please provide it using --rawfile"
}

Channel
  .fromPath(params.rawfile, type: 'dir')
  .ifEmpty { error "No .d directories found in ${params.rawfile}" }
  .map { file ->
       def folder = file.name
       def base = file.baseName
       tuple(folder, base, file)
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
  .from(params.params_file)
  .set { params_file }

Channel
  .from(params.instrument_folder)
  .set { instrument_folder }

Channel
  .from(params.output_folder)
  .set { output_folder }

Channel
  .from(params.output_folder)
  .set { output_folder_ch }

workflow {

   // DIA-NN:
   diann_bruker_pr(rawfile_ch) 

   // Report to QSample database:
   //insertDIANNFileToQSample_pr(brukerfile_ch,trfp_diann_pr.out)
   //insertDIANNDataToQSample_pr(insertDIANNFileToQSample_pr.out,diann_pr.out,trfp_diann_pr.out)
   //insertDIANNQuantToQSample_pr(insertDIANNFileToQSample_pr.out,diann_pr.out)
   // Report to output folder (if the field output_folder was informed at methods CSV file):
   //output_folder_diann_pr(diann_pr.out,trfp_diann_pr.out,output_folder_ch)

   // Lab
   //insertDiannPolymerContToQSample_pr(insertDIANNFileToQSample_pr.out,trfp_diann_pr.out)
}
