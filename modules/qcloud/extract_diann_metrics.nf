process EXTRACT_DIANN_METRICS {

    input:
    path report_tsv
    path qcloud_tsv
    val checksum

    output:
    tuple val(checksum), path("*_QC_*.json"), emit: diann_jsons

    script:
    """
    echo "Extracting DIA-NN metrics (QCloud format)..."
    echo "Report file: ${report_tsv}"
    echo "QCloud peptides TSV: ${qcloud_tsv}"
    echo "Checksum: ${checksum}"

    # QC terms (fixed IDs used by QCloud)
    qc_area="QC:1001844"
    qc_rt="QC:1000894"

    # Escape for filenames
    qc_area_file=\$(echo \$qc_area | tr ':' '_')
    qc_rt_file=\$(echo \$qc_rt | tr ':' '_')

    area_json="\${checksum}_\${qc_area_file}.json"
    rt_json="\${checksum}_\${qc_rt_file}.json"

    # Init JSON files
    echo "{}" > \$area_json
    echo "{}" > \$rt_json

    # Process peptides TSV (skip header)
    awk -F'\\t' 'NR==1 {next} {
        short=\$1; long=\$2;

        # Extract area (col 27) from DIA-NN report
        cmd="grep -P \"\\t" long "\\t\" ${report_tsv} | cut -f27 | head -1"
        cmd | getline area; close(cmd);

        # Extract RT observed (col 29) from DIA-NN report
        cmd="grep -P \"\\t" long "\\t\" ${report_tsv} | cut -f29 | head -1"
        cmd | getline rt_obs; close(cmd);

        if (area=="") area=0;
        if (rt_obs=="") rt_obs=0;

        # Print updates for jq
        printf "jq --arg k %s --arg v %s \\".[$k] = (\$v|tonumber)\\" %s > tmp.json && mv tmp.json %s\\n", short, area, ENVIRON["area_json"], ENVIRON["area_json"];
        printf "jq --arg k %s --arg v %s \\".[$k] = (\$v|tonumber)\\" %s > tmp.json && mv tmp.json %s\\n", short, rt_obs, ENVIRON["rt_json"], ENVIRON["rt_json"];
    }' ${qcloud_tsv} | bash

    echo "Generated QCloud JSONs:"
    ls -l *_QC_*.json | cat
    head -20 *_QC_*.json
    """
}
