#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr } from './modules/conversion/conversion'
include { create_decoy as cdecoy_pr; MascotAdapterOnline as mao_pr; CometAdapter as comet_adapter_pr } from './modules/search_engine/search_engine'
include { PeptideIndexer as pepidx_pr; FalseDiscoveryRate as fdr_pr; IDFilter_aaa as idfilter_aaa_pr; IDFilter_score as idfilter_score_pr; FileInfo as fileinfo_pr; ProteinInference as protinf_pr; QCCalculator as qccalc_pr } from './modules/identification/identification_lfq'
include { insertFileToQSample as insertFileToQSample_pr; insertSecReactDataToQSample as insertSecReactDataToQSample_pr} from './modules/report/report_qsample_sec_react'

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

workflow {
  
   //Conversion: 
   trfp_pr(rawfile_ch)

   //Search engine: 
   cdecoy_pr(rawfile_ch)
   mao_pr(trfp_pr.out,cdecoy_pr.out,var_modif_ch,fragment_mass_tolerance_ch,fragment_error_units_ch)
   comet_adapter_pr(trfp_pr.out,cdecoy_pr.out,var_modif_ch,fragment_mass_tolerance_ch,fragment_error_units_ch)

   //Identification: 
   idfilter_aaa_pr(mao_pr.out.mix(comet_adapter_pr.out))
   pepidx_pr(idfilter_aaa_pr.out,cdecoy_pr.out)
   fdr_pr(pepidx_pr.out)
   idfilter_score_pr(fdr_pr.out)
   fileinfo_pr(idfilter_score_pr.out)
   protinf_pr(idfilter_score_pr.out)
   qccalc_pr(protinf_pr.out,trfp_pr.out)

   //Report to QSample database:
   insertFileToQSample_pr(rawfile_ch,trfp_pr.out)
   insertSecReactDataToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out,protinf_pr.out,idfilter_score_pr.out,qccalc_pr.out,trfp_pr.out)
   
}

