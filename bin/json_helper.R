#!/usr/bin/env Rscript

# Load required libraries
suppressPackageStartupMessages({
  library(jsonlite)
  library(optparse)
  library(readr)
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

#' Add a value to existing JSON structure
#' 
#' @param json_file Path to existing JSON file
#' @param context_source Context source for the value
#' @param value Value to add
add_value_to_json <- function(json_file, context_source, value) {
  
  # Read existing JSON
  data <- fromJSON(json_file, simplifyVector = FALSE)
  
  # Create new value entry
  new_value <- list(
    contextSource = as.character(context_source),
    value = as.character(value)
  )
  
  # Add to values array
  data$data[[1]]$values <- append(data$data[[1]]$values, list(new_value))
  
  # Write back to file
  write_json(data, json_file, pretty = TRUE, auto_unbox = TRUE)
  
  cat("Added value to JSON file:", json_file, "\n")
  return(invisible(TRUE))
}

# Command line interface
if (!interactive()) {
  option_list <- list(
    make_option(c("--action"), type = "character", default = NULL,
                help = "Action to perform: create or add"),
    make_option(c("--checksum"), type = "character", default = NULL,
                help = "File checksum"),
    make_option(c("--param-id"), type = "character", default = NULL,
                help = "Parameter ID"),
    make_option(c("--output"), type = "character", default = NULL,
                help = "Output JSON file"),
    make_option(c("--context-source"), type = "character", default = NULL,
                help = "Context source for value"),
    make_option(c("--value"), type = "character", default = NULL,
                help = "Value to add"),
    make_option(c("--values-csv"), type = "character", default = NULL,
                help = "CSV file with values data for bulk creation")
  )
  
  opt_parser <- OptionParser(option_list = option_list)
  opt <- parse_args(opt_parser)
  
  if (is.null(opt$action)) {
    print_help(opt_parser)
    stop("Action must be specified", call. = FALSE)
  }
  
  if (opt$action == "create") {
    if (is.null(opt$checksum) || is.null(opt$`param-id`) || is.null(opt$output)) {
      stop("For create action, checksum, param-id, and output are required", call. = FALSE)
    }
    
    # Load values data if provided
    if (!is.null(opt$`values-csv`) && file.exists(opt$`values-csv`)) {
      values_data <- read.csv(opt$`values-csv`, stringsAsFactors = FALSE)
    } else {
      values_data <- data.frame(contextSource = character(0), value = character(0))
    }
    
    create_qcloud_json_with_header(
      opt$checksum,
      opt$`param-id`,
      values_data,
      opt$output
    )
    
  } else if (opt$action == "add") {
    if (is.null(opt$output) || is.null(opt$`context-source`) || is.null(opt$value)) {
      stop("For add action, output, context-source, and value are required", call. = FALSE)
    }
    
    add_value_to_json(
      opt$output,
      opt$`context-source`,
      opt$value
    )
  }
}