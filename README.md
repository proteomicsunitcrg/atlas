# atlas

## Introduction

**atlas** is a Nextflow-based pipeline developed for the processing and analysis of mass spectrometry data, specifically tailored to assist proteomics laboratories with daily quality assessments across various proteomics applications. It supports multiple workflows, such as regular proteomes, phosphoproteomes and independent acquisition modes, among others. 

With these diverse workflows, **atlas** extracts critical quality control parameters, greatly simplifying the evaluation of mass spectrometry experiments. The pipeline is built on **OpenMS** modules, a widely used open-source software for mass spectrometry data processing. These modules are encapsulated using **Singularity** containers, which ensure all dependencies are properly packaged. By leveraging containers, the pipeline achieves a high degree of reproducibility, allowing consistent quality control analyses over time.

The pipeline is implemented using the latest **Nextflow DSL2 syntax** and is designed to operate efficiently in **HPC (High-Performance Computing) environments**.

For more detailed information, please refer to the [documentation](link).

---

## Credits

The **atlas** pipeline was initially developed by **@rolivella**.

We would like to express our gratitude to the following individuals for their valuable contributions during the development:

- Eduard Sabidó (@edunivers)
- Cristina Chiva
- Eva Borràs
- Guadalupe Espadas
- Olga Pastor
- Enrique Alonso
- Selena Fernández

---

## Citations

A comprehensive list of references for the tools utilized in the pipeline can be found in the **CITATIONS.md** file.
