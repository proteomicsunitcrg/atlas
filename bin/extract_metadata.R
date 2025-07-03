#!/usr/bin/env Rscript

# Load required libraries
suppressPackageStartupMessages({
  library(MSnbase)
  library(optparse)
  library(jsonlite)
  library(readr)
  library(digest)
})

#' Load configuration from Nextflow config-style file
#' 
#' @param config_file Path to configuration file
load_config <- function(config_file) {
  if (!file.exists(config_file)) {
    stop("Configuration file not found: ", config_file)
  }
  
  # Read the config file and parse it
  # This is a simplified parser for the Nextflow config format
  config_lines <- readLines(config_file)
  
  # Extract qcloud_terms section
  qcloud_terms <- list()
  qcloud_contexts <- list()
  json_pattern_map <- list()
  
  in_qcloud_terms <- FALSE
  in_qcloud_contexts <- FALSE
  in_json_pattern_map <- FALSE
  
  for (line in config_lines) {
    line <- trimws(line)
    
    # Skip comments and empty lines
    if (grepl("^//", line) || line == "") next
    
    # Check for section starts
    if (grepl("qcloud_terms\\s*=\\s*\\[", line)) {
      in_qcloud_terms <- TRUE
      next
    } else if (grepl("qcloud_contexts\\s*=\\s*\\[", line)) {
      in_qcloud_contexts <- TRUE
      next
    } else if (grepl("json_pattern_map\\s*=\\s*\\[", line)) {
      in_json_pattern_map <- TRUE
      next
    }
    
    # Check for section ends
    if (grepl("^\\]", line)) {
      in_qcloud_terms <- FALSE
      in_qcloud_contexts <- FALSE
      in_json_pattern_map <- FALSE
      next
    }
    
    # Parse key-value pairs
    if (in_qcloud_terms && grepl(":", line)) {
      parts <- strsplit(line, ":")[[1]]
      if (length(parts) >= 2) {
        key <- trimws(gsub("'", "", parts[1]))
        value <- trimws(gsub("[',]", "", parts[2]))
        qcloud_terms[[key]] <- value
      }
    } else if (in_qcloud_contexts && grepl(":", line)) {
      parts <- strsplit(line, ":")[[1]]
      if (length(parts) >= 2) {
        key <- trimws(gsub("'", "", parts[1]))
        value <- trimws(gsub("[',]", "", parts[2]))
        qcloud_contexts[[key]] <- value
      }
    } else if (in_json_pattern_map && grepl(":", line)) {
      parts <- strsplit(line, ":")[[1]]
      if (length(parts) >= 2) {
        key <- trimws(gsub("'", "", parts[1]))
        value <- trimws(gsub("[',]", "", parts[2]))
        json_pattern_map[[key]] <- value
      }
    }
  }
  
  return(list(
    qcloud_terms = qcloud_terms,
    qcloud_contexts = qcloud_contexts,
    json_pattern_map = json_pattern_map
  ))
}

#' Create QCloud JSON with proper header structure
#' 
#' @param checksum File checksum for header
#' @param param_id Parameter ID (e.g., "QC:1001844")
#' @param values_data Data frame with contextSource and value columns
#' @param output_file Output JSON file path
create_qcloud_json_with_header <- function(checksum, param_id, values_data, output_file) {
  
  # Ensure values_data is a data frame
  if (is.null(values_data) || nrow(values_data) == 0) {
    values_list <- list()
  } else {
    values_list <- apply(values_data, 1, function(row) {
      list(
        contextSource = as.character(row["contextSource"]),
        value = as.character(row["value"])
      )
    }, simplify = FALSE)
  }
  
  json_structure <- list(
    file = list(
      checksum = checksum
    ),
    data = list(
      list(
        parameter = list(
          qCCV = param_id
        ),
        values = values_list
      )
    )
  )
  
  # Write JSON with pretty formatting
  write_json(json_structure, output_file, pretty = TRUE, auto_unbox = TRUE)
  
  cat("Created JSON file:", output_file, "\n")
  return(invisible(TRUE))
}

#' Extract metadata from mzML file using MSnbase
#' 
#' @param mzml_file Path to mzML file
#' @param config_file Path to configuration file
#' @param output_file Output JSON file for metadata
extract_mzml_metadata <- function(mzml_file, config_file, output_file) {
  
  cat("Loading configuration from:", config_file, "\n")
  
  # Load configuration
  config <- load_config(config_file)
  
  cat("Loading mzML file:", mzml_file, "\n")
  
  # Read mzML file using MSnbase
  raw_data <- readMSData(mzml_file, mode = "onDisk")
  
  # Extract basic information
  cat("Extracting basic metadata...\n")
  
  # Calculate total TIC
  cat("Calculating total TIC...\n")
  tic_values <- tic(raw_data)
  total_tic <- sum(tic_values, na.rm = TRUE) * 1e-10  # Convert to same scale as original
  
  # Get MS levels
  ms_levels <- msLevel(raw_data)
  
  # Calculate median injection times for MS1 and MS2
  cat("Calculating median injection times...\n")
  
  # For now, we'll use placeholder values since injection time extraction 
  # depends on your specific mzML structure
  mit_ms1 <- 50.0  # Placeholder - you'll need to implement actual extraction
  mit_ms2 <- 100.0 # Placeholder - you'll need to implement actual extraction
  
  # Get creation date
  cat("Extracting creation date...\n")
  creation_date <- tryCatch({
    # Try to get from file metadata
    format(file.info(mzml_file)$mtime, "%Y-%m-%dT%H:%M:%S")
  }, error = function(e) {
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  })
  
  # Calculate checksum
  cat("Calculating file checksum...\n")
  checksum <- digest(file = mzml_file, algo = "md5")
  
  # Parse filename for labsysid and sample_id
  cat("Parsing filename information...\n")
  basename_file <- tools::file_path_sans_ext(basename(mzml_file))
  
  # Extract UUID from filename using base R
  uuid_pattern <- "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
  uuid_matches <- regmatches(basename_file, regexpr(uuid_pattern, basename_file))
  
  if (length(uuid_matches) > 0 && uuid_matches != "") {
    labsysid <- uuid_matches[1]
  } else {
    # For testing, create a dummy UUID if none found
    labsysid <- "550e8400-e29b-41d4-a716-446655440000"
    cat("WARNING: No UUID found in filename, using dummy UUID:", labsysid, "\n")
  }
  
  # Extract sample ID (remove .raw.mzML extension)
  sample_id <- gsub("\\.raw\\.mzML$", "", basename(mzml_file))
  
  # Create metadata list with configuration references
  metadata <- list(
    checksum = checksum,
    total_tic = as.character(total_tic),
    mit_ms1 = as.character(mit_ms1),
    mit_ms2 = as.character(mit_ms2),
    creation_date = creation_date,
    labsysid = labsysid,
    sample_id = sample_id,
    num_spectra = length(raw_data),
    ms1_count = sum(ms_levels == 1),
    ms2_count = sum(ms_levels == 2),
    # Add configuration references
    qcloud_terms = config$qcloud_terms,
    qcloud_contexts = config$qcloud_contexts,
    json_pattern_map = config$json_pattern_map
  )
  
  # Write metadata to JSON file
  write_json(metadata, output_file, pretty = TRUE, auto_unbox = TRUE)
  
  cat("Metadata extraction completed successfully\n")
  cat("Output written to:", output_file, "\n")
  
  return(metadata)
}

# Command line interface
if (!interactive()) {
  option_list <- list(
    make_option(c("--mzml-file"), type = "character", default = NULL,
                help = "Path to mzML file"),
    make_option(c("--config-file"), type = "character", default = NULL,
                help = "Path to configuration file"),
    make_option(c("--output"), type = "character", default = "metadata.json",
                help = "Output JSON file for metadata")
  )
  
  opt_parser <- OptionParser(option_list = option_list)
  opt <- parse_args(opt_parser)
  
  if (is.null(opt$`mzml-file`) || is.null(opt$`config-file`)) {
    print_help(opt_parser)
    stop("mzML file and config file must be specified", call. = FALSE)
  }
  
  if (!file.exists(opt$`mzml-file`)) {
    stop("mzML file does not exist: ", opt$`mzml-file`, call. = FALSE)
  }
  
  if (!file.exists(opt$`config-file`)) {
    stop("Config file does not exist: ", opt$`config-file`, call. = FALSE)
  }
  
  extract_mzml_metadata(opt$`mzml-file`, opt$`config-file`, opt$output)
}