nextflow.enable.dsl=2

process EXTRACT_DIANN_MODIFICATION_METRICS {
    label 'diann'
    tag "${meta.basename}"

    input:
    tuple val(meta), path(report_parquet)
    val config_file

    output:
    tuple val(meta), path("${meta.basename}.modification_metrics.tsv"), emit: metrics_tsv

    script:
    """
    set -euo pipefail

    bash ${moduleDir}/scripts/extract_modification_metrics.sh \
        "${report_parquet}" \
        "${config_file}" \
        "${meta.basename}.modification_metrics.tsv" \
        "${params.duckdb_path}" \
        "0.01"
    """
}
