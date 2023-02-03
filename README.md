# atlas

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A522.04.4.5706-23aa62.svg)](https://www.nextflow.io/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Nextflow Tower](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Nextflow%20Tower-%234256e7)](https://tower.nf/launch?pipeline=https://github.com/proteomicsunitcrg/atlas)

## Introduction

**atlas** is a new [Nextflow-based](https://www.nextflow.io) pipeline for processing and analysis of mass spectrometry data. Specifically, atlas is designed to support proteomics laboratories in the daily quality assessment of different proteomics applications. It can work for many kinds of workflows, including the analysis of regular proteomes, phosphoproteomes, quantification of histones and it can process data on independent acquisition mode, among others. For this plethora of workflows, **atlas** is capable of extracting several key quality control parameters that substantially simplify the assessment of the experiments performed on mass spectrometers. **atlas** is based on [OpenMS](https://github.com/OpenMS/OpenMS) modules, an open source processing software for mass spectrometry data which is containerized using [Singularity](https://sylabs.io/docs), a software used to encapsulate all required dependencies. By using containers we are able to freeze the scripts and libraries of this analysis software so in this way we ensure a high reproducibility of our quality control analysis. The pipeline is implemented using the new [Nextflow DSL2](https://www.nextflow.io/docs/latest/dsl2.html) syntax and it is designed to work in HPC environments.

## Pipeline summary

Schematically, 

1. Convert RAW to mzML ([`ThermoRawFileParser`](https://github.com/compomics/ThermoRawFileParser)).
2. Search for PSM ([`Comet`](https://uwpr.github.io/Comet/) or [`Mascot`](http://www.matrixscience.com/)).
3. Protein and peptide identification ([`OpenMS`](https://github.com/OpenMS/OpenMS), [`DIA-NN`](https://github.com/vdemichev/DiaNN) or [DIA Umpire](https://diaumpire.nesvilab.org/)).
4. Protein and peptide quantification ([`OpenMS`](https://github.com/OpenMS/OpenMS) or [`DIA-NN`](https://github.com/vdemichev/DiaNN) or [DIA Umpire](https://diaumpire.nesvilab.org/)).
5. Report to a database.

More detailed, 

![atlas_schema](https://user-images.githubusercontent.com/1679820/213675154-a104ea4d-e466-4aa6-95f7-43782dfccb0e.png)


## Quick Start

1. Install [`Nextflow`](https://www.nextflow.io/docs/latest/getstarted.html#installation) (`>=22.04.4.5706`)

2. Install [`Singularity`](https://www.sylabs.io/guides/3.0/user-guide/) (you can follow [this tutorial](https://singularity-tutorial.github.io/01-installation/)).

3. Clone the pipeline: 

```bash
git clone https://github.com/proteomicsunitcrg/atlas.git
```

4. Edit configuration files: 

* Edit `assets/defaultlab_run_modes.csv` taking as an example `assets/crg_run_modes.csv`: 
   * Set `incoming_folder` where you'll put the RAW files to analyze.
   * `main_nf_folder` where the `main.nf` is. 
   * `runs_folder` where all temporary files will be created (should be cleaned up regularly).  
   * `logs_folder` where the logs will be saved. 
   * For the moment set `enable_notification_email` and `enable_nf_tower` to `false`.
* Edit `conf/defaultlab.config`: 
   * `folder_to_store_singularity_imgs` where you'll put the images that the pipeline is going to pull the first time you run it. 
   * `folder_to_store_databases` with the FASTA for each organism you need to analyze. For adding a FASTA, you must create a foler with the organism name, followed by a `current` folder and the FASTA file, for instance, `folder_to_store_databases/SP_Human/current/sp_human.fasta`. 
   * Change, if needed, the `localhost:8099`, that is, where the `qsample-server` is listening. If you didn't configure it, don't worry, you can test the pipeline without doing this step now. 
* Create an empty (for the moment) file `conf/default_secrets.config`. 
       
   
5. Test it on a minimal dataset with a single command:

   ```bash
   path_to/bin/trigger.sh crg test path_to/assets BSA
   ```


## Credits

**atlas** was originally written by @rolivella.

We thank the following people for their assistance in the development of this pipeline:

Eduard Sabidó (@edunivers), Cristina Chiva, Eva Borràs, Guadalupe Espadas, Olga Pastor, Enrique Alonso, Selena Fernández.

## Citations

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.
