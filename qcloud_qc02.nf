#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr } from './subworkflows/conversion/conversion'
include { create_decoy as cdecoy_pr;  create_decoy as cdecoy_pr; MascotAdapterOnline as mao_pr; CometAdapter as comet_adapter_pr; fragpipe_prep as fragpipe_prep_pr; fragpipe_main as fragpipe_main_pr } from './subworkflows/search_engine/search_engine'
include { EICExtractor as eicextr_pr } from './subworkflows/quantification/quantification'
include { FileFilter as filefilter_pr } from './subworkflows/filtering/filtering'
include { PeptideIndexer as pepidx_pr; FalseDiscoveryRate as fdr_pr; IDFilter_aaa as idfilter_aaa_pr; IDFilter_score as idfilter_score_pr; FileInfo as fileinfo_pr; ProteinInference as protinf_pr; QCCalculator as qccalc_pr } from './subworkflows/identification/identification'

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
  .from(params.eic_rt_tol_qc02)
  .set { eic_rt_tol_qc02_ch }

workflow {
  
   //Conversion: 
   trfp_pr(rawfile_ch)

   //Filtering
   //filefilter_pr(trfp_pr.out)

   //Quantification: 
   //eicextr_pr(trfp_pr.out,eic_rt_tol_qc02_ch)

   //Search engine: 
   if (params.search_engine == "comet") {
      cdecoy_pr(rawfile_ch)
      comet_adapter_pr(trfp_pr.out,cdecoy_pr.out,var_modif_ch,fragment_mass_tolerance_ch,fragment_error_units_ch)
   } else if (params.search_engine == "mascot") {
      cdecoy_pr(rawfile_ch)
      mao_pr(trfp_pr.out,cdecoy_pr.out,var_modif_ch,fragment_mass_tolerance_ch,fragment_error_units_ch)
   } else if (params.search_engine == "fragpipe") {
      fragpipe_prep_pr(rawfile_ch)
      fragpipe_main_pr(trfp_pr.out)
   }

   //Identification: 
   //idfilter_aaa_pr(mao_pr.out.mix(comet_adapter_pr.out))
   //pepidx_pr(idfilter_aaa_pr.out,cdecoy_pr.out)
   //fdr_pr(pepidx_pr.out)
   //idfilter_score_pr(fdr_pr.out)
   //fileinfo_pr(idfilter_score_pr.out)
   //protinf_pr(idfilter_score_pr.out)
   //qccalc_pr(protinf_pr.out,trfp_pr.out)

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
