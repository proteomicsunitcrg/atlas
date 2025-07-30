#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr } from './subworkflows/conversion/conversion'
include { create_decoy as cdecoy_pr; MascotAdapterOnline as mao_pr; CometAdapter as comet_adapter_pr; fragpipe_prep as fragpipe_prep_pr; fragpipe_main as fragpipe_main_pr } from './subworkflows/search_engine/search_engine'
include { PeptideIndexer as pepidx_pr; FalseDiscoveryRate as fdr_pr; IDFilter_aaa as idfilter_aaa_pr; IDFilter_score as idfilter_score_pr; FileInfo as fileinfo_pr; ProteinInference as protinf_pr; QCCalculator as qccalc_pr } from './subworkflows/identification/identification'
include { FeatureFinderMultiplex as ffm_pr; IDMapper as idmapper_pr; ProteinQuantifier as protquant_pr } from './subworkflows/quantification/quantification'
include { insertFileToQSample as insertFileToQSample_pr; insertQuantToQSample as insertQuantToQSample_pr; insertDataToQSample as insertDataToQSample_pr; insertModificationsToQsample as insertModificationsToQsample_pr; insertPolymerContToQSample as insertPolymerContToQSample_pr } from './subworkflows/report/report_qsample_applications'
include { insertFragpipeFileToQSample as insertFragpipeFileToQSample_pr; insertFragpipeDataToQSample as insertFragpipeDataToQSample_pr; insertFragpipeSecReactDataToQSample as insertFragpipeSecReactDataToQSample_pr } from './subworkflows/report/report_qsample_fragpipe'
include { insertPTMhistonesToQSample as insertPTMhistonesToQSample_pr } from './subworkflows/lab/report_qsample_applications_lab'
include { output_folder as output_folder_pr; output_folder_fragpipe as output_folder_fragpipe_pr } from './subworkflows/report/report_output_folder'

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

Channel.from(params.sites_modif)
  .set { sites_modif_ch }

Channel
  .from(params.fragment_mass_tolerance)
  .set { fragment_mass_tolerance_ch }

Channel
  .from(params.fragment_error_units)
  .set { fragment_error_units_ch }

Channel
  .from(params.output_folder)
  .set { output_folder_ch }

workflow {
  
   //Conversion: 
   trfp_pr(rawfile_ch)
   cdecoy_pr(rawfile_ch)

   //Search engine: 
   if (params.search_engine == "comet") {
      //Search engine: 
      comet_adapter_pr(trfp_pr.out,cdecoy_pr.out,var_modif_ch,fragment_mass_tolerance_ch,fragment_error_units_ch)
      //Identification: 
      idfilter_aaa_pr(comet_adapter_pr.out)
   } else if (params.search_engine == "mascot") {
      //Search engine:
      mao_pr(trfp_pr.out,cdecoy_pr.out,var_modif_ch,fragment_mass_tolerance_ch,fragment_error_units_ch)
      //Identification: 
      idfilter_aaa_pr(mao_pr.out.mix(mao_pr.out))
   } else if (params.search_engine == "fragpipe") {
      fragpipe_prep_pr(rawfile_ch,cdecoy_pr.out)
      fragpipe_main_pr(rawfile_ch, fragpipe_prep_pr.out[0], fragpipe_prep_pr.out[1], fragpipe_prep_pr.out[2])
      insertFragpipeFileToQSample_pr(rawfile_ch,trfp_pr.out)
      insertFragpipeDataToQSample_pr(
          insertFragpipeFileToQSample_pr.out,
          trfp_pr.out,
          fragpipe_main_pr.out[0],  // peptide.tsv
          fragpipe_main_pr.out[1],  // protein.tsv
          fragpipe_main_pr.out[2],  // ion.tsv
          fragpipe_main_pr.out[3],  // combined_protein.tsv
          fragpipe_main_pr.out[4],  // global.modsummary.tsv (maps to global.summary.tsv)
          fragpipe_main_pr.out[5]   // combined_ion.tsv
      )
      insertPolymerContToQSample_pr(insertFragpipeFileToQSample_pr.out,trfp_pr.out)
      insertFragpipeSecReactDataToQSample_pr(
          insertFragpipeFileToQSample_pr.out,
          fragpipe_main_pr.out[0],  // peptide.tsv
          fragpipe_main_pr.out[1],  // protein.tsv
          fragpipe_main_pr.out[2],  // ion.tsv
          fragpipe_main_pr.out[3],  // combined_protein.tsv
          fragpipe_main_pr.out[4],  // global.modsummary.tsv (maps to global.summary.tsv)
          fragpipe_main_pr.out[5]   // combined_ion.tsv
      )
      //Report to output folder (if the field output_folder was informed at methods CSV file):
      output_folder_fragpipe_pr(
          trfp_pr.out,                          // tuple (filename_mzml, basename_mzml, path_mzml, mzml_file)
          fragpipe_main_pr.out[0],              // peptide.tsv
          fragpipe_main_pr.out[1],              // protein.tsv
          fragpipe_main_pr.out[2],              // ion.tsv
          fragpipe_main_pr.out[3],              // combined_protein.tsv
          fragpipe_main_pr.out[4],              // global.modsummary.tsv
          fragpipe_main_pr.out[5],              // combined_ion.tsv
          insertFragpipeFileToQSample_pr.out,   // checksum
          output_folder_ch                      // output_folder
      )
   }

   if (params.search_engine == "comet" || params.search_engine == "mascot") {
      //Annotation: 
      pepidx_pr(idfilter_aaa_pr.out,cdecoy_pr.out)
      fdr_pr(pepidx_pr.out)
      idfilter_score_pr(fdr_pr.out)
      fileinfo_pr(idfilter_score_pr.out)
      protinf_pr(idfilter_score_pr.out)
            
      //Quantification: 
      ffm_pr(trfp_pr.out)
      idmapper_pr(ffm_pr.out,idfilter_score_pr.out)
      protquant_pr(idmapper_pr.out)

      //Output TSV and mzQC:   
      output_folder_pr(protinf_pr.out,trfp_pr.out,output_folder_ch)
      qccalc_pr(protinf_pr.out,ffm_pr.out,output_folder_ch,trfp_pr.out)

      //Report to QSample database:
      insertFileToQSample_pr(rawfile_ch,trfp_pr.out)
      insertDataToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out,protinf_pr.out,idfilter_score_pr.out,trfp_pr.out)
      insertQuantToQSample_pr(insertFileToQSample_pr.out,protquant_pr.out)
      //Report additional applications to QSample:
      insertModificationsToQsample_pr(insertFileToQSample_pr.out,fileinfo_pr.out,protinf_pr.out,sites_modif_ch) 

      //Lab
      insertPTMhistonesToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out,idmapper_pr.out,protinf_pr.out)
      insertPolymerContToQSample_pr(insertFileToQSample_pr.out,trfp_pr.out) 
   }

}


workflow.onError {

    def msg = """\
        Pipeline execution summary
        --------------------------
        Run name      : ${workflow.runName}
        Working dir   : ${workflow.workDir}
        Command line  : ${workflow.commandLine}
        """
        .stripIndent()

    if(params.enable_notif_email){
      sendMail(to: params.notif_email, subject: ':( atlas pipeline error', body: msg)
    }

}
