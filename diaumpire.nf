#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr; FileConverter_mzml2mzxml as fileconverter_mzml2mzxml_pr; FileConverter_mgf2mzml as fileconverter_mgf2mzml_pr } from './modules/conversion/conversion'
include { dia_umpire as dia_umpire_pr } from './modules/dia/dia'
include { create_decoy as cdecoy_pr; MascotAdapterOnline as mao_pr; CometAdapter as comet_adapter_pr } from './modules/search_engine/search_engine'
include { PeptideIndexer as pepidx_pr; FalseDiscoveryRate as fdr_pr; IDFilter_aaa as idfilter_aaa_pr; IDFilter_score as idfilter_score_pr; FileInfo as fileinfo_pr; ProteinInference as protinf_pr; QCCalculator as qccalc_pr } from './modules/identification/identification_lfq'
include { FeatureFinderMultiplex as ffm_pr; IDMapper as idmapper_pr; ProteinQuantifier as protquant_pr } from './modules/quantification/quantification_lfq'
include { insertFileToQSample as insertFileToQSample_pr; insertQuantToQSample as insertQuantToQSample_pr; insertDataToQSample as insertDataToQSample_pr} from './modules/report/report_qsample'
include { output_folder_diaqc as output_folder_diaqc_pr; output_folder_test as output_folder_test_pr} from './modules/report/report_output_folder'


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

params.params_file

workflow {
  
   //Conversion: raw to mzML
   trfp_pr(rawfile_ch)

   //DIA: 
   //Conversion: mzML to mzXML
   fileconverter_mzml2mzxml_pr(trfp_pr.out)
   //DIA analysis: 
   dia_umpire_pr(fileconverter_mzml2mzxml_pr.out)

   //SEARCH ENGINE: 
   //Conversion: mgf to mzML
   fileconverter_mgf2mzml_pr(dia_umpire_pr.out)
   //Search engine: 
   cdecoy_pr(rawfile_ch)
   mao_pr(fileconverter_mgf2mzml_pr.out,cdecoy_pr.out,var_modif_ch,fragment_mass_tolerance_ch,fragment_error_units_ch)
   comet_adapter_pr(fileconverter_mgf2mzml_pr.out,cdecoy_pr.out,var_modif_ch,fragment_mass_tolerance_ch,fragment_error_units_ch)
 
   //Identification: 
   idfilter_aaa_pr(mao_pr.out.mix(comet_adapter_pr.out))
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

   //Report to QSample database:
   insertFileToQSample_pr(rawfile_ch,trfp_pr.out)
   insertDataToQSample_pr(insertFileToQSample_pr.out,fileinfo_pr.out,protinf_pr.out,idfilter_score_pr.out,qccalc_pr.out,trfp_pr.out)
   insertQuantToQSample_pr(insertFileToQSample_pr.out,protquant_pr.out)
  
   //Report to output folder: 
   output_folder_diaqc_pr(insertFileToQSample_pr.out,fileinfo_pr.out,protinf_pr.out,idfilter_score_pr.out,qccalc_pr.out,trfp_pr.out)   
   output_folder_test_pr(protinf_pr.out)
}
