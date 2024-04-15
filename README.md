# atlas

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A522.04.4.5706-23aa62.svg)](https://www.nextflow.io/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Nextflow Tower](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Nextflow%20Tower-%234256e7)](https://tower.nf/launch?pipeline=https://github.com/proteomicsunitcrg/atlas)

## Introduction

**atlas** is a new [Nextflow-based](https://www.nextflow.io) pipeline for processing and analysis of mass spectrometry data. Specifically, atlas is designed to support proteomics laboratories in the daily quality assessment of different proteomics applications. It can work for many kinds of workflows, including the analysis of regular proteomes, phosphoproteomes, quantification of histones and it can process data on independent acquisition mode, among others. For this plethora of workflows, **atlas** is capable of extracting several key quality control parameters that substantially simplify the assessment of the experiments performed on mass spectrometers. **atlas** is based on [OpenMS](https://github.com/OpenMS/OpenMS) modules, an open source processing software for mass spectrometry data which is containerized using [Singularity](https://sylabs.io/docs), a software used to encapsulate all required dependencies. By using containers we are able to freeze the scripts and libraries of this analysis software so in this way we ensure a high reproducibility of our quality control analysis. The pipeline is implemented using the new [Nextflow DSL2](https://www.nextflow.io/docs/latest/dsl2.html) syntax and it is designed to work in HPC environments.

### More detailed documentation can be found [here](https://github.com/proteomicsunitcrg/atlas/wiki).

## Credits

**atlas** was originally written by @rolivella.

We thank the following people for their assistance in the development of this pipeline:

Eduard Sabidó (@edunivers), Cristina Chiva, Eva Borràs, Guadalupe Espadas, Olga Pastor, Enrique Alonso, Selena Fernández.

## Citations

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.
