#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { diann_bruker as diann_bruker_pr } from './subworkflows/dia/dia'
include { insertDIANNBrukerFileToQSample as insertDIANNBrukerFileToQSample_pr; insertDIANNBrukerDataToQSample as insertDIANNBrukerDataToQSample_pr; insertDIANNBrukerQuantToQSample as insertDIANNBrukerQuantToQSample_pr } from './subworkflows/report/report_qsample_diann'

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
  .from(params.instrument_folder)
  .set { instrument_folder }

Channel
  .from(params.output_folder)
  .set { output_folder }

Channel
  .from(params.output_folder)
  .set { output_folder_ch }

workflow {

   diann_bruker_pr(rawfile_ch) 

   insertDIANNBrukerFileToQSample_pr(
        diann_bruker_pr.out[0],
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
