# extract_tic_series.awk - single streaming pass over an mzML file.
# Emits a compact JSON array of [rt_ms, msLevel, tic] with one entry per
# spectrum carrying a TIC (MS:1000285) value, in document (time) order.
#
# Design notes:
# - Order-independent: Thermo (TRF) mzML places msLevel before the TIC and
#   the retention time (MS:1000016) AFTER it (inside scanList/scan), while
#   Bruker (FragPipe-calibrated) mzML places msLevel after the TIC. All three
#   attributes are therefore collected per spectrum block (delimited by
#   "<spectrum ...>" / "</spectrum>") and emitted together at the block end.
# - RT unit is normalized to milliseconds using the unitAccession of the
#   MS:1000016 cvParam (UO:0000031=minute, UO:0000034=second,
#   UO:0000036=millisecond, UO:0000018=microsecond). When no unit is present
#   the value is assumed to be in seconds (assumption counted in the sidecar
#   warning file).
# - The raw (unscaled) sum of all TIC values is written to the file named by
#   -v sumfile= for cross-checking against the legacy grep-based Sum TIC.
# - The number of spectra with a TIC but no retention time is written to
#   -v no_rts_file= (0 expected for well-formed files).
# - Header cvParameter/cvParam dictionary lines (no value=) and file-level
#   cvParams are ignored: capture only happens inside a spectrum block, and
#   TIC capture additionally requires a value attribute.
#
# Usage:
#   awk -f extract_tic_series.awk -v sumfile=X.sum -v no_rts_file=X.nort input.mzML > X_TIC.json
BEGIN {
    printf "["
    n = 0; sum = 0; no_rts = 0
    in_spec = 0; rt = ""; unit = ""; lvl = ""; tic = ""
}
function rt_to_ms(v, u,    f) {
    if (v == "")
        return "0"
    if (u == "UO:0000031")      f = 60000
    else if (u == "UO:0000034") f = 1000
    else if (u == "UO:0000036") f = 1
    else if (u == "UO:0000018") f = 0.001
    else                        f = 1000
    return sprintf("%.6f", v * f)
}
function flush(    rt_ms) {
    if (tic != "") {
        if (rt == "")
            no_rts++
        rt_ms = rt_to_ms(rt, unit)
        if (n++)
            printf ","
        printf "[%s,%s,%s]", rt_ms, (lvl == "" ? "0" : lvl), tic
        sum += tic + 0
    }
    rt = ""; unit = ""; lvl = ""; tic = ""
}
/<spectrum[ \t]/ { in_spec = 1; rt = ""; unit = ""; lvl = ""; tic = ""; next }
/<\/spectrum>/ { if (in_spec) flush(); in_spec = 0; next }
in_spec && /accession="MS:1000511"/ {
    if (match($0, /value="[0-9]+"/))
        lvl = substr($0, RSTART + 7, RLENGTH - 8)
    next
}
in_spec && /accession="MS:1000016"/ {
    if (rt == "" && match($0, /value="[^"]*"/))
        rt = substr($0, RSTART + 7, RLENGTH - 8)
    if (unit == "" && match($0, /unitAccession="[^"]*"/))
        unit = substr($0, RSTART + 15, RLENGTH - 16)
    next
}
in_spec && /accession="MS:1000285"/ && /value="/ {
    if (match($0, /value="[^"]*"/))
        tic = substr($0, RSTART + 7, RLENGTH - 8)
    next
}
END {
    if (in_spec)
        flush()
    printf "]\n"
    printf "%.10g\n", sum > sumfile
    printf "%d\n", no_rts > no_rts_file
}
