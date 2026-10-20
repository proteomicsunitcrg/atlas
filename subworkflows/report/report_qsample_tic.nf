//API:
url_api_signin             = params.url_api_signin
url_api_user               = params.url_api_user
url_api_pass               = params.url_api_pass
url_api_insert_file        = params.url_api_insert_file

//Bash scripts folder:
binfolder                      = "$baseDir/bin"

/**
 * Extracts the full TIC series (one point per spectrum) from the mzML and
 * stores it in the QSample tic table, for the "Total Ion Current view" on the
 * request view. One blob per file: "gz1:" + base64(gzip(compact JSON
 * [[rt_ms, msLevel, tic], ...])) - the same blob format as the QCloud2 tic
 * table.
 *
 * The series sum is cross-checked against the legacy Sum TIC (MS:1000285, the
 * same value reported by insertDataToQSample under context source 19): on
 * mismatch (0.1% tolerance) or an empty series the PUT is skipped, so a
 * format surprise can never ship a corrupt curve. The file row must already
 * exist (the "received" notifier at workflow start, or the insert*FileToQSample
 * process, registers it), so this is wired right after the file insertion.
 * Best-effort, like the data POSTs: a failure here only loses the curve view,
 * never the QC data.
 */
process insertTicToQSample {
    tag { "${mzml_file}" }
    label 'clitools'

    input:
    file(checksum_file)
    file(mzml_file)

    shell:
    '''
    cp !{binfolder}/extract_tic_series.awk .
    chmod +x extract_tic_series.awk

    checksum=$(cat !{checksum_file})
    if [ -z "$checksum" ]; then
        echo "WARNING: empty checksum file - skipping TIC PUT"
        exit 0
    fi

    # Cross-check reference: sum of all per-spectrum TIC values (MS:1000285),
    # scaled by 1e10 like the reported Sum TIC. Full precision on purpose:
    # the reported Sum TIC is quantized to 2 decimals ("%.2f"), and for weak
    # runs (scaled sum < ~5) the 0.1% tolerance is smaller than that rounding
    # quantum - comparing at full precision keeps the guard (an awk regression
    # dropping spectra still shifts the sum well beyond 0.1%) without false
    # negatives on small runs.
    legacy_tic=$(grep 'MS:1000285' "!{mzml_file}" | grep -o 'value="[^"]*"' | sed 's/value="//g; s/"//g' | awk '{sum+=$1} END{printf "%.10g", sum/10000000000}')

    echo "Extracting TIC series (all points)..."
    awk -f extract_tic_series.awk -v sumfile=tic_series.sum -v no_rts_file=tic_series.nort "!{mzml_file}" > tic_series.json
    series_sum=$(cat tic_series.sum)
    series_no_rts=$(cat tic_series.nort)
    series_points=$(jq "length" tic_series.json)
    echo "TIC series: $series_points points, points_without_RT: $series_no_rts"
    if [ "$series_no_rts" != "0" ]; then
        echo "WARNING: $series_no_rts TIC points have no retention time (rt stored as 0)"
    fi

    if [ "$series_points" = "0" ]; then
        echo "WARNING: empty TIC series - skipping TIC PUT (Sum TIC unaffected)"
        exit 0
    fi
    series_ok=$(awk -v a="$series_sum" -v b="$legacy_tic" 'BEGIN{ d=a/10000000000-b; if (d<0) d=-d; lim=0.001*b; if (lim<0) lim=-lim; if (b==0) ok=(a==0); else ok=(d<=lim); print (ok?1:0) }')
    if [ "$series_ok" != "1" ]; then
        echo "WARNING: TIC series sum ($series_sum) does not match legacy Sum TIC ($legacy_tic) - skipping TIC PUT (Sum TIC unaffected)"
        exit 0
    fi

    gzip -9 -c tic_series.json | base64 -w0 > tic_payload.b64
    b64_size=$(stat -c %s tic_payload.b64)
    echo "Storing TIC series: $b64_size bytes compressed"
    if [ "$b64_size" -gt 2097152 ]; then
        echo "WARNING: compressed TIC series too large ($b64_size bytes) - skipping TIC PUT (Sum TIC unaffected)"
        exit 0
    fi

    access_token=$(source !{binfolder}/api.sh; get_api_access_token !{url_api_signin} !{url_api_user} !{url_api_pass})
    if [ -z "$access_token" ]; then
        echo "WARNING: could not obtain QSample access token - skipping TIC PUT"
        exit 0
    fi

    jq -n --rawfile b tic_payload.b64 '{tic: ("gz1:" + $b)}' > tic_payload.json
    api_base='!{url_api_insert_file}'
    api_base=${api_base%/api/file/insertFromPipelineRequest}
    tic_response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X PUT \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        "${api_base}/api/file/tic/$checksum" \
        --data @tic_payload.json)
    tic_http_code=$(echo $tic_response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    tic_body=$(echo $tic_response | sed -e 's/HTTPSTATUS:.*//')
    echo "TIC series PUT to QSample - HTTP Status: $tic_http_code"
    echo "TIC series PUT to QSample - Response: $tic_body"
    if [ "$tic_http_code" != "200" ] && [ "$tic_http_code" != "201" ]; then
        echo "WARNING: Failed to store TIC series in QSample (HTTP $tic_http_code) - QC data unaffected"
    else
        echo "TIC series stored in QSample"
    fi
    '''
}
