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

// Function to extract QC type from filename using reverse parsing
def extractQCTypeFromFilename(filename) {
    try {
        // Remove common suffixes first
        def cleanFilename = filename
            .replaceAll(/\.raw.*$/, '')  // Remove .raw and everything after
            .replaceAll(/\.mzML.*$/, '') // Remove .mzML and everything after
        
        log.info "Cleaned filename: ${cleanFilename}"
        
        // Reverse filename, split by "_", look for QC pattern
        def reversedFilename = cleanFilename.reverse()
        def parts = reversedFilename.split('_')
        
        log.info "Reversed parts: ${parts.join(', ')}"
        
        // Look for QC pattern in the parts (should be "20CQ", "10CQ", etc.)
        for (int i = 0; i < parts.length; i++) {
            def part = parts[i].reverse()
            log.info "Checking part ${i}: '${parts[i]}' -> '${part}'"
            if (part.matches(/QC\d+/)) {
                log.info "Found QC type: ${part} from filename: ${filename}"
                return part
            }
        }
        
        log.warn "No QC pattern found in filename: ${filename}"
        log.warn "Available parts were: ${parts.collect { it.reverse() }.join(', ')}"
    } catch (Exception e) {
        log.warn "Could not extract QC type from filename ${filename}: ${e.message}"
    }
    return null
}

// Function to get QCloud sample type code from QC type and mapping file
def getQCloudSampleType(qcType, qcodeFilePath) {
    def qcloudCode = null
    
    try {
        new File(qcodeFilePath).eachLine { line ->
            if (!line.startsWith('qc_type') && !line.trim().isEmpty()) {
                def parts = line.split('\t')
                if (parts.length >= 3) {
                    if (parts[0] == qcType) {
                        qcloudCode = parts[2]
                        log.info "Found QCloud code ${qcloudCode} for QC type ${qcType}"
                        return true // break from eachLine
                    }
                }
            }
        }
        
        // If no specific match found, try default
        if (qcloudCode == null) {
            new File(qcodeFilePath).eachLine { line ->
                if (!line.startsWith('qc_type') && !line.trim().isEmpty()) {
                    def parts = line.split('\t')
                    if (parts.length >= 3 && parts[0] == 'default') {
                        qcloudCode = parts[2]
                        log.warn "Using default QCloud code ${qcloudCode} for QC type ${qcType}"
                        return true
                    }
                }
            }
        }
    } catch (Exception e) {
        log.error "Could not read qcode mapping file ${qcodeFilePath}: ${e.message}"
        throw e
    }
    
    if (qcloudCode == null) {
        throw new Exception("No QCloud sample type found for QC type ${qcType} and no default available")
    }
    
    return qcloudCode
}