#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { ThermoRawFileParser as trfp_pr } from './subworkflows/conversion/conversion'
include { EICExtractor as eicextr_pr } from './subworkflows/quantification/quantification'
include { insertDataNucleosidesToQCloud as insertDataNucleosidesToQCloud_pr } from './subworkflows/report/report_qcloud'
include { FileFilter as filefilter_pr } from './subworkflows/filtering/filtering'
include { output_folder_qcloud_qcn1 as output_folder_qcloud_qcn1_pr } from './subworkflows/report/report_qcloud_output_folder'

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
  .from(params.output_folder)
  .set { output_folder_ch }

workflow {
  
   //Conversion: 
   trfp_pr(rawfile_ch)

   //Filtering
   filefilter_pr(trfp_pr.out)

   //Quantification: 
   eicextr_pr(filefilter_pr.out)
   
   //Report to QCloud database:
   insertDataNucleosidesToQCloud_pr(rawfile_ch,trfp_pr.out,eicextr_pr.out)
 
   //Report to output folder (if the field output_folder was informed at methods CSV file):
   //output_folder_qcloud_qcn1_pr(rawfile_ch,output_folder_ch,trfp_pr.out,eicextr_pr.out)

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
