#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr } from './modules/conversion/conversion_trfp'
include { create_decoy as cdecoy_pr } from '/users/pr/qsample/atlas/modules/search_engine/search_engine_mascot'
include { MascotAdapterOnline as mao_pr } from '/users/pr/qsample/atlas/modules/search_engine/search_engine_mascot'
include { PeptideIndexer as pepidx_pr } from '/users/pr/qsample/atlas/modules/identification/identification_lfq'
include { FalseDiscoveryRate as fdr_pr } from '/users/pr/qsample/atlas/modules/identification/identification_lfq'
include { IDFilter as idfilter_pr } from '/users/pr/qsample/atlas/modules/identification/identification_lfq'
include { FeatureFinderMultiplex as ffm_pr } from '/users/pr/qsample/atlas/modules/quantification/quantification_lfq'
include { IDMapper as idmapper_pr } from '/users/pr/qsample/atlas/modules/quantification/quantification_lfq'
include { ProteinQuantifier as protquant_pr } from '/users/pr/qsample/atlas/modules/quantification/quantification_lfq'
include { insertFileToQSample as insertFileToQSample_pr } from '/users/pr/qsample/atlas/modules/report/report_qsample'
include { insertQuantToQSample as insertQuantToQSample_pr } from '/users/pr/qsample/atlas/modules/report/report_qsample'
include { insertDataToQSample as insertDataToQSample_pr } from '/users/pr/qsample/atlas/modules/report/report_qsample'

workflow {

   //Input raw file channel:
   rawfile_ch = Channel.watchPath(params.watch_folder).
       map {
          file = it.getName()
          base = it.getBaseName()
          path = it.getParent()
          [file, base, path]
       }

   //Conversion: 
   trfp_pr(rawfile_ch)

   //Search engine: 
   cdecoy_pr(rawfile_ch)
   mao_pr(trfp_pr.out,cdecoy_pr.out)

   //Identification: 
   pepidx_pr(mao_pr.out,cdecoy_pr.out)
   fdr_pr(pepidx_pr.out)
   idfilter_pr(fdr_pr.out)

   //Quantification: 
   ffm_pr(trfp_pr.out)
   idmapper_pr(ffm_pr.out,idfilter_pr.out)
   protquant_pr(idmapper_pr.out)

   //Report to QSample database:
   insertFileToQSample_pr(rawfile_ch,trfp_pr.out) 
   insertQuantToQSample_pr(insertFileToQSample_pr.out,protquant_pr.out)
   insertDataToQSample_pr(insertFileToQSample_pr.out,idfilter_pr.out) 
}
