#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr } from './modules/conversion/conversion_trfp'
include { create_decoy as cdecoy_pr; MascotAdapterOnline as mao_pr } from './modules/search_engine/search_engine_mascot'
include { PeptideIndexer as pepidx_pr; FalseDiscoveryRate as fdr_pr; IDFilter_aaa as idfilter_aaa_pr; IDFilter_score as idfilter_score_pr; FileInfo as fileinfo_pr; ProteinInference as protinf_pr } from './modules/identification/identification_lfq'
include { FeatureFinderMultiplex as ffm_pr; IDMapper as idmapper_pr; ProteinQuantifier as protquant_pr } from './modules/quantification/quantification_lfq'
include { insertFileToQSample as insertFileToQSample_pr; insertQuantToQSample as insertQuantToQSample_pr; insertDataToQSample as insertDataToQSample_pr; insertPhosphoModifToQSample as insertPhosphoModifToQSample_pr; insertPTMhistonesToQSample as insertPTMhistonesToQSample_pr; insertWetlabFileToQSample as insertWetlabFileToQSample_pr; insertWetlabDataToQSample as insertWetlabDataToQSample_pr; insertSilacToQSample as insertSilacToQSample_pr; insertTmtToQSample as insertTmtToQSample_pr} from './modules/report/report_qsample'

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

   //Identification: 
   idfilter_aaa_pr(mao_pr.out)
   pepidx_pr(idfilter_aaa_pr.out,cdecoy_pr.out)
   fdr_pr(pepidx_pr.out)
   idfilter_score_pr(fdr_pr.out)
   fileinfo_pr(idfilter_score_pr.out)
   protinf_pr(idfilter_score_pr.out)

   //Quantification: 
   ffm_pr(trfp_pr.out)
   idmapper_pr(ffm_pr.out,idfilter_score_pr.out)
   protquant_pr(idmapper_pr.out)

   //Report to QSample database:
   insertFileToQSample_pr(rawfile_ch,trfp_pr.out)
   insertWetlabFileToQSample_pr(rawfile_ch,trfp_pr.out)
   insertDataToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out,protinf_pr.out)
   insertWetlabDataToQSample_pr(insertWetlabFileToQSample_pr.out,fileinfo_pr.out,protinf_pr.out)
   insertQuantToQSample_pr(insertFileToQSample_pr.out,protquant_pr.out)
   insertPhosphoModifToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out)
   insertPTMhistonesToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out)
   insertSilacToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out)
   insertTmtToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out)
}
