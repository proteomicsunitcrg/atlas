#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr } from './subworkflows/conversion/conversion'
include { create_decoy as cdecoy_pr; CometAdapter as comet_adapter_pr } from './subworkflows/search_engine/search_engine'
include { PeptideIndexer as pepidx_pr; FalseDiscoveryRate as fdr_pr; IDFilter_aaa as idfilter_aaa_pr; IDFilter_score as idfilter_score_pr; FileInfo as fileinfo_pr; ProteinInference as protinf_pr; QCCalculator as qccalc_pr } from './subworkflows/identification/identification'
include { FeatureFinderMultiplex as ffm_pr; IDMapper as idmapper_pr; ProteinQuantifier as protquant_pr } from './subworkflows/quantification/quantification'
include { insertSampleQCFileToQSample as insertSampleQCFileToQSample_pr; insertSampleQCDataToQSample as insertSampleQCDataToQSample_pr; insertSampleQCModificationsToQsample as insertSampleQCModificationsToQsample_pr } from './subworkflows/report/report_qsample_sampleqc'
include { insertSampleQCHistonesToQSample as insertSampleQCHistonesToQSample_pr } from './subworkflows/lab/report_qsample_sampleqc_lab'

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
  .from(params.sites_modif)
  .set { sites_modif_ch }

Channel
  .from(params.sampleqc_api_key)
  .set { sampleqc_api_key_ch }

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
 }

 if (params.search_engine == "comet" || params.search_engine == "mascot") {
   //Annotation:
   pepidx_pr(idfilter_aaa_pr.out,cdecoy_pr.out)
   fdr_pr(pepidx_pr.out)
   idfilter_score_pr(fdr_pr.out)
   fileinfo_pr(idfilter_score_pr.out)
   protinf_pr(idfilter_score_pr.out)
   qccalc_pr(protinf_pr.out,trfp_pr.out)

   //Quantification:
   ffm_pr(trfp_pr.out)
   idmapper_pr(ffm_pr.out,idfilter_score_pr.out)
   protquant_pr(idmapper_pr.out)

   //Report SampleQC to QSample:
   insertSampleQCFileToQSample_pr(rawfile_ch,trfp_pr.out,sampleqc_api_key_ch)
   insertSampleQCDataToQSample_pr(rawfile_ch,insertSampleQCFileToQSample_pr.out,protinf_pr.out,sampleqc_api_key_ch)
   insertSampleQCModificationsToQsample_pr(rawfile_ch,insertSampleQCFileToQSample_pr.out,fileinfo_pr.out,protinf_pr.out,sites_modif_ch,sampleqc_api_key_ch)

   //Lab:
   insertSampleQCHistonesToQSample_pr(insertSampleQCFileToQSample_pr.out,fileinfo_pr.out,idmapper_pr.out,protinf_pr.out)
 
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
