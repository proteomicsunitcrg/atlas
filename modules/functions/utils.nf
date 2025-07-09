// modules/functions/utils.nf

/**
 * Extract QC type from filename using complex parsing logic
 * Reverses filename, splits by "_", takes second element, reverses again
 * @param filename The filename to parse
 * @return The extracted QC type (QC01, QC02) or null if not found
 */
def extractQCType(filename) {
    try {
        // Remove file extension if present
        def nameWithoutExt = filename.contains('.') ? filename.substring(0, filename.lastIndexOf('.')) : filename
        
        // Reverse the filename
        def reversed = nameWithoutExt.reverse()
        
        // Split by "_"
        def parts = reversed.split('_')
        
        // Take the second element (index 1)
        if (parts.size() >= 2) {
            def secondElement = parts[1]
            
            // Reverse again
            def qcCandidate = secondElement.reverse()
            
            //log.info "Filename parsing: '${filename}' -> reversed: '${reversed}' -> parts: ${parts} -> second element: '${secondElement}' -> final: '${qcCandidate}'"
            
            return qcCandidate
        } else {
            log.warn "Filename '${filename}' doesn't have enough underscore-separated parts after reversing"
            return null
        }
    } catch (Exception e) {
        log.error "Error parsing filename '${filename}': ${e.message}"
        return null
    }
}

/**
 * Determine TSV file path based on QC type
 * @param qcType The QC type extracted from filename
 * @param params The pipeline parameters object
 * @return Path to the appropriate TSV file
 */
def selectTsvFile(qcType, params) {
    def selected_tsv_file
    
    if (qcType == 'QC01') {
        selected_tsv_file = params.peptides_tsv_qc01
        log.info "Detected QC01 pattern - using QC01 TSV file"
    } else if (qcType == 'QC02') {
        selected_tsv_file = params.peptides_tsv_qc02
        log.info "Detected QC02 pattern - using QC02 TSV file"
    } else {
        selected_tsv_file = params.peptides_tsv_file
        log.warn "No QC01 or QC02 pattern detected (extracted: '${qcType}'), using default TSV file"
    }
    
    return selected_tsv_file
}