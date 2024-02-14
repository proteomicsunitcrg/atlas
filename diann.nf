#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParserDiann as trfp_diann_pr } from './subworkflows/conversion/conversion'
include { diann as diann_pr } from './subworkflows/dia/dia'
include { insertDIANNFileToQSample as insertDIANNFileToQSample_pr; insertDIANNDataToQSample as insertDIANNDataToQSample_pr; insertDIANNQuantToQSample as insertDIANNQuantToQSample_pr} from './subworkflows/report/report_qsample_diann'
include { output_folder_diann_test as output_folder_diann_test_pr; output_folder_diannqc as output_folder_diannqc_pr; output_folder_diann as output_folder_diann_pr} from './subworkflows/report/report_output_folder'
include { insertDiannPolymerContToQSample as insertDiannPolymerContToQSample_pr } from './subworkflows/lab/report_qsample_diann_lab'

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

params.params_file

workflow {
 
   //Conversion:
   trfp_diann_pr(rawfile_ch)

   //DIA-NN: 
   diann_pr(trfp_diann_pr.out)

   //Report to QSample database:
   insertDIANNFileToQSample_pr(rawfile_ch,trfp_diann_pr.out)
   insertDIANNDataToQSample_pr(insertDIANNFileToQSample_pr.out,diann_pr.out,trfp_diann_pr.out)
   insertDIANNQuantToQSample_pr(insertDIANNFileToQSample_pr.out,diann_pr.out)

   //Report to output folder (if the field output_folder was informed at methods CSV file):
   output_folder_diann_pr(diann_pr.out,output_folder_ch)  
   
   //Report to output folder for testing purposes (if the pipeline was triggered through test mode):
   output_folder_diannqc_pr(insertDIANNFileToQSample_pr.out,diann_pr.out,trfp_diann_pr.out)
   output_folder_diann_test_pr(diann_pr.out)
   
   //lab
   insertDiannPolymerContToQSample_pr(insertDIANNFileToQSample_pr.out,trfp_diann_pr.out)
}
