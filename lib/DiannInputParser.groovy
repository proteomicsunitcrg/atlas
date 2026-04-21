class DiannInputParser {
    
    /**
     * Parse filename and extract metadata based on instrument type
     * @param filename The input filename (e.g., "sample.mzML.SP_Human" or "sample.d.SP_Human")
     * @param inputType Either 'thermo' or 'bruker'
     * @return Map with keys: basename, organism, fileType
     */
    static Map parseFilename(String filename, String inputType) {
        def result = [:]
        
        if (inputType == 'bruker') {
            // <--- Pattern: sample.d.SP_Human
            def match = filename =~ /^(.+)\.d\.(.+)$/
            if (!match) {
                throw new IllegalArgumentException("Invalid Bruker filename format: ${filename}. Expected: sample.d.Organism")
            }
            result.basename = match[0][1]
            result.organism = match[0][2]
            result.fileType = 'bruker'
            
        } else if (inputType == 'thermo') {
            // <--- Pattern: sample.mzML.SP_Human or sample.raw.SP_Human
            def match = filename =~ /^(.+)\.(mzML|raw)\.(.+)$/
            if (!match) {
                throw new IllegalArgumentException("Invalid Thermo filename format: ${filename}. Expected: sample.[mzML|raw].Organism")
            }
            result.basename = match[0][1]
            result.fileType = match[0][2]  // <--- 'mzML' or 'raw'
            result.organism = match[0][3]
            
        } else {
            throw new IllegalArgumentException("Unknown inputType: ${inputType}. Use 'thermo' or 'bruker'")
        }
        
        return result
    }
    
    /**
     * Extract pattern from basename (e.g., "2024MK888" -> "MK")
     * Used for matching against diann_methods_config.yaml
     */
    static String extractPattern(String basename) {
        def match = basename =~ /([A-Z]{2,3})\d/  // <--- MK, NK, LA, QCD, etc.
        return match ? match[0][1] : null
    }
}