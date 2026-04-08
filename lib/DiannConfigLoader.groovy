import org.yaml.snakeyaml.Yaml

class DiannConfigLoader {
    
    static def loadConfig(String yamlPath, String pattern) {
        def yaml = new Yaml()
        def configFile = new File(yamlPath)
        
        if (!configFile.exists()) {
            throw new FileNotFoundException("DIA-NN config YAML not found: ${yamlPath}")
        }
        
        def config = yaml.load(configFile.text)
        
        if (!config.containsKey(pattern)) {
            throw new IllegalArgumentException("Pattern '${pattern}' not found in DIA-NN config YAML")
        }
        
        return config[pattern]
    }
    
    static def getVersion(Map methodConfig) {
        return methodConfig.diann_version ?: 'unknown'
    }
    
    static def getContainer(Map methodConfig) {
        return methodConfig.container ?: 'proteomicsunitcrg/diann:latest'
    }
    
    static def getConfigFile(Map methodConfig) {
        return methodConfig.config_file ?: 'diann.cfg'
    }
    
    static def getParserVersion(Map methodConfig) {
        return methodConfig.parser_version ?: 'tsv'
    }
}