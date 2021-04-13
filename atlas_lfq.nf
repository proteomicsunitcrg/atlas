#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr } from './modules/conversion/conversion_trfp'
include { create_decoy as cdecoy_pr; MascotAdapterOnline as mao_pr } from '/users/pr/qsample/atlas/modules/search_engine/search_engine_mascot'
include { PeptideIndexer as pepidx_pr; FalseDiscoveryRate as fdr_pr; IDFilter as idfilter_pr; FileInfo as fileinfo_pr; ProteinInference as protinf_pr } from '/users/pr/qsample/atlas/modules/identification/identification_lfq'
include { FeatureFinderMultiplex as ffm_pr; IDMapper as idmapper_pr; ProteinQuantifier as protquant_pr } from '/users/pr/qsample/atlas/modules/quantification/quantification_lfq'
include { insertFileToQSample as insertFileToQSample_pr; insertQuantToQSample as insertQuantToQSample_pr; insertDataToQSample as insertDataToQSample_pr } from '/users/pr/qsample/atlas/modules/report/report_qsample'

Channel
  .fromPath(params.rawfile)
  .map {
      file = it.getName()
      base = it.getBaseName()
      path = it.getParent()
      [file, base, path]
  }
  .set { rawfile_ch }

workflow {
  
   //Conversion: 
   trfp_pr(rawfile_ch)

   //Search engine: 
   cdecoy_pr(rawfile_ch)
   mao_pr(trfp_pr.out,cdecoy_pr.out)

   //Identification: 
   pepidx_pr(mao_pr.out,cdecoy_pr.out)
   fdr_pr(pepidx_pr.out)
   idfilter_pr(fdr_pr.out)
   fileinfo_pr(idfilter_pr.out)
   protinf_pr(idfilter_pr.out)

   //Quantification: 
   ffm_pr(trfp_pr.out)
   idmapper_pr(ffm_pr.out,idfilter_pr.out)
   protquant_pr(idmapper_pr.out)

   //Report to QSample database:
   insertFileToQSample_pr(rawfile_ch,trfp_pr.out) 
   insertDataToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out,protinf_pr.out)
   insertQuantToQSample_pr(insertFileToQSample_pr.out,protquant_pr.out)

}
