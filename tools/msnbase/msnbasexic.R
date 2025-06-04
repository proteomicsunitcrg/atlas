#!/usr/bin/env Rscript

# Load required libraries
suppressPackageStartupMessages(library(optparse))
suppressPackageStartupMessages(library(MSnbase))
suppressPackageStartupMessages(library(pracma))
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(readr))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(glue))

# Define metrics to be exported to JSON
json_metrics <- c("Log2_Total_Area", "dmz_ppm", "Observed_RT_sec", "FWHM")
json_titles <- list(
  Log2_Total_Area = "Log₂ Area",
  dmz_ppm = "Δm/z (ppm)",
  Observed_RT_sec = "Observed Retention Time (s)",
  FWHM = "Full Width at Half Max (s)"
)
# Optional Y axis window for metrics in the MultiQC JSON
json_yaxis_window <- list(
  dmz_ppm = c(-3, 3)
 # ,Log2_Total_Area = c(5, 30)
)

# PPP constant (OPTIONAL):  
PPP_THRESHOLD_RATIO <- 0.05

# Define command-line options
option_list <- list(
  make_option(c("--file_name"), type = "character", help = "Input mzML file path"),
  make_option(c("--tsv_name"), type = "character", help = "Input TSV file with analyte info"),
  make_option(c("--output_dir"), type = "character", help = "Directory to write output files"),
  make_option(c("--analyte_name"), type = "character", help = "Name of analyte to process"),
  make_option(c("--rt_tol_sec"), type = "numeric", help = "Retention time tolerance in seconds"),
  make_option(c("--mz_tol_ppm"), type = "numeric", help = "m/z tolerance in ppm"),
  make_option(c("--msLevel"), type = "numeric", help = "MS level to use"),
  make_option(c("--plot_xic_ms1"), type = "logical", default = FALSE, help = "Plot XIC for MS1"),
  make_option(c("--plot_xic_ms2"), type = "logical", default = FALSE, help = "Plot XIC for MS2"),
  make_option(c("--plot_output_path"), type = "character", help = "Path to save XIC plot"),
  make_option(c("--overwrite_tsv"), type = "logical", default = FALSE, help = "Overwrite existing TSV")
)

# Parse command-line arguments
opt <- parse_args(OptionParser(option_list = option_list))
opt$plot_xic_ms1 <- as.logical(opt$plot_xic_ms1)
opt$plot_xic_ms2 <- as.logical(opt$plot_xic_ms2)
opt$overwrite_tsv <- as.logical(opt$overwrite_tsv)

# Create output directory if it does not exist
if (!is.null(opt$output_dir) && !dir.exists(opt$output_dir)) {
  dir.create(opt$output_dir, recursive = TRUE)
  message(glue("Created output directory: {opt$output_dir}"))
}

# Read analyte data
df <- read.delim(opt$tsv_name, sep = "\t", header = TRUE, stringsAsFactors = FALSE)
message(glue("Read {nrow(df)} analytes from TSV: {opt$tsv_name}"))

# Determine analytes to process
analyte_names <- if (opt$analyte_name == "all") df$short_name else c(opt$analyte_name)
message(glue("Analytes to process: {paste(analyte_names, collapse = ', ')}"))

# Load mzML data
message(glue("Loading mzML file: {opt$file_name}"))
ms_data <- readMSData(opt$file_name, mode = "onDisk")
message("MS data loaded.")

# Define function to extract analyte-specific parameters
get_analyte_data <- function(df, analyte) {
  analyte_data <- subset(df, short_name == analyte)
  if (nrow(analyte_data) == 0) stop(paste("Error: Analyte not found:", analyte))
  list(mz1 = analyte_data$mz_M0, ms2_mz = analyte_data$ms2_mz, rt_target = analyte_data$rt_teoretical)
}

# Assign m/z value based on MS level
assign_mz1 <- function(analyte_data, msLevel) {
  if (msLevel == 1) {
    as.numeric(analyte_data$mz1)
  } else {
    as.numeric(analyte_data$mz1)  # Use precursor m/z for MS2 as well
  }
}

# Compute XIC for given m/z and retention time
compute_xic <- function(ms_data, mz1, rt_target, rt_tol_sec, mz_tol, msLevel, ppm_tol, ms2_target_mz = NULL){ 
  # Check if rt_tol_sec and ppm_tol are provided
  if (missing(rt_tol_sec) || missing(ppm_tol)) {
    stop("Error: Both 'rt_tol_sec' and 'ppm_tol' are mandatory parameters.")
  }

  # Define RT and m/z windows
  rt_window <- c(rt_target - rt_tol_sec, rt_target + rt_tol_sec)
  mz_window <- c(mz1 - mz_tol, mz1 + mz_tol)

  if (msLevel == 1) {
    # MS1: Manual extraction without using chromatogram
    message("Manual MS1 XIC extraction")

    # Filter for MS1 level and RT window
    ms1_data <- ms_data |>
      filterMsLevel(1) |>
      filterRt(rt_window)

    # Check if any spectra are found after filtering
    if (length(ms1_data) == 0) {
      warning("No MS1 data found within the specified RT window")
      return(list(NULL))
    }

    # Build XIC by averaging intensities per spectrum within the m/z window
    rt_vals <- rtime(ms1_data)
    int_vals <- sapply(seq_along(spectra(ms1_data)), function(i) {
      spec <- spectra(ms1_data)[[i]]
      mz_values <- mz(spec)
      intensity_values <- intensity(spec)
      scan_num <- acquisitionNum(spec)  # Use acquisitionNum to get scan number

      # Filter intensities within m/z window
      valid_idx <- which(mz_values >= mz_window[1] & mz_values <= mz_window[2])

      # Log for debugging with scan number and ppm difference
      if (length(valid_idx) == 0) {
        mz_diff <- abs(mz_values - mz1)
        min_diff <- min(mz_diff, na.rm = TRUE)
        closest_mz <- mz_values[which.min(mz_diff)]
        ppm_difference <- (min_diff / mz1) * 1e6
        message(glue("MS1 Spectrum {i} (RT: {rt_vals[i]}, Scan: {scan_num}) discarded: Closest m/z {round(closest_mz, 5)} differs by {round(ppm_difference, 2)} ppm from {mz1}"))
      }

      if (length(valid_idx) > 0) {
        mean_int <- mean(intensity_values[valid_idx], na.rm = TRUE)
        mz_selected <- mz_values[valid_idx]
        closest_mz <- mz_selected[which.min(abs(mz_selected - mz1))]
        ppm_difference <- ((closest_mz - mz1) / mz1) * 1e6
        message(glue("MS1 Spectrum {i} (RT: {rt_vals[i]}, Scan: {scan_num}) used: Closest m/z {round(closest_mz, 5)} is {round(ppm_difference, 2)} ppm from {mz1}. Mean intensity = {round(mean_int, 2)}"))
        mean_int
      } else {
        NA
      }
    })

    # Clean up NA intensities
    valid <- which(!is.na(int_vals))
    if (length(valid) == 0) {
      warning("No valid XIC signal found.")
      return(list(NULL))
    }

    rt_vals <- rt_vals[valid]
    int_vals <- int_vals[valid]

    # Create chromatogram object manually
    chrom <- new("Chromatogram", rtime = rt_vals, intensity = int_vals)
    list(chrom)
    
  } else if (msLevel == 2) {
    # MS2: XIC dels fragments dins espectres MS2 associats a un precursor
    message("Manual MS2 XIC extraction (targeting fragment ion)")

    # Filter for MS2 level and RT window
    ms2_data <- ms_data |>
      filterMsLevel(2) |>
      filterRt(rt_window)

    # Filter MS2 by precursor m/z ≈ mz1 (mz_M0)
    prec_mz <- precursorMz(ms2_data)
    valid_idx <- which(!is.na(prec_mz) & prec_mz >= mz_window[1] & prec_mz <= mz_window[2])

    message(glue("Found {length(valid_idx)} MS2 spectra with precursor m/z within ±{round(ppm_tol, 1)} ppm of {mz1}"))

    if (length(valid_idx) == 0) {
      warning("No MS2 spectra matched precursor m/z within the specified ppm.")
      return(list(NULL))
    }

    # Most relevant spectra
    ms2_data <- ms2_data[valid_idx]

    # Search window for fragment
    mz_window_fragment <- c(ms2_target_mz - mz_tol, ms2_target_mz + mz_tol)

    # Intensity for the fragment
    rt_vals <- rtime(ms2_data)
    int_vals <- sapply(seq_along(spectra(ms2_data)), function(i) {
      result <- tryCatch({
        spec <- spectra(ms2_data)[[i]]
        scan_num <- acquisitionNum(spec)
        rt_val <- rtime(spec)

        mz_values <- mz(spec)
        intensity_values <- intensity(spec)

        if (length(mz_values) == 0 || length(intensity_values) == 0) {
          message(glue("MS2 Spectrum {i} (RT: {rt_val}, Scan: {scan_num}) skipped: Empty spectrum"))
          return(NA)
        }

        # Search fragment
        valid_idx <- which(mz_values >= mz_window_fragment[1] & mz_values <= mz_window_fragment[2])

        if (length(valid_idx) == 0) {
          mz_diff <- abs(mz_values - ms2_target_mz)
          min_diff <- min(mz_diff, na.rm = TRUE)
          closest_mz <- mz_values[which.min(mz_diff)]
          ppm_difference <- (min_diff / ms2_target_mz) * 1e6
          message(glue("MS2 Spectrum {i} (RT: {rt_val}, Scan: {scan_num}) discarded: Closest m/z {round(closest_mz, 5)} differs by {round(ppm_difference, 2)} ppm from fragment {ms2_target_mz}"))
          return(NA)
        } else {
          sum_int <- sum(intensity_values[valid_idx], na.rm = TRUE)
          closest_mz <- mz_values[valid_idx][which.min(abs(mz_values[valid_idx] - ms2_target_mz))]
          ppm_difference <- ((closest_mz - ms2_target_mz) / ms2_target_mz) * 1e6
          message(glue("MS2 Spectrum {i} (RT: {rt_val}, Scan: {scan_num}) used: Fragment m/z {round(closest_mz, 5)} is {round(ppm_difference, 2)} ppm from {ms2_target_mz}. Sum intensity = {round(sum_int, 2)}"))
          return(sum_int)
        }
      }, error = function(e) {
        warning(glue("Error in MS2 Spectrum {i}: {e$message}"))
        return(NA)
      })

      return(result)
    })

    # Filter valid values
    valid <- which(!is.na(int_vals))
    if (length(valid) == 0) {
      warning("No valid XIC signal found.")
      return(list(NULL))
    }

    rt_vals <- rt_vals[valid]
    int_vals <- int_vals[valid]

    chrom <- new("Chromatogram", rtime = rt_vals, intensity = int_vals)
    list(chrom)
  }

}

# Extract max intensity m/z at observed retention time
find_mz_for_intensity_obs <- function(ms_data, mz, rt_obs, intensity_mz1, msLevel) {
  data_filtered <- ms_data |>
    filterMsLevel(msLevel) |>
    filterRt(rt = c(rt_obs - 1, rt_obs + 1))

  if (length(data_filtered) == 0) stop("No spectra found near RT")

  all_mz_exp <- all_intensities <- c()

  for (spec in spectra(data_filtered)) {
    valid_idx <- mz(spec) >= mz[1] & mz(spec) <= mz[2]
    all_mz_exp <- c(all_mz_exp, mz(spec)[valid_idx])
    all_intensities <- c(all_intensities, intensity(spec)[valid_idx])
  }

  if (length(all_mz_exp) == 0) stop("No m/z values in range")

  df <- data.frame(mz_exp = all_mz_exp, intensity = all_intensities)
  df[which.min(abs(df$intensity - intensity_mz1)), "mz_exp"]
}

# Format numeric values for consistency
format_custom <- function(x) {
  if (is.na(x)) return("NA")
  if (abs(x) >= 1e4) format(x, scientific = TRUE, digits = 3) else format(x, scientific = FALSE, digits = 3)
}

# Construct results row for one analyte
function_create_output_df <- function(sample_name, analyte, rt_target, rt_obs, mz1, mz_exp_result, intensity_mz1, area_mz1, fwhm, ppp) {
  data.frame(
    Sample = sample_name,
    short_name = analyte,
    Expected_RT_sec = rt_target,
    Observed_RT_sec = rt_obs,
    dRT_sec = rt_obs - rt_target,
    Expected_MZ = mz1,
    Observed_MZ = mz_exp_result,
    dmz_ppm = ((mz_exp_result - mz1) / mz1) * 1e6,
    dmz_Da = mz_exp_result - mz1,
    Max_Intensity = format_custom(intensity_mz1),
    Area = format_custom(area_mz1),
    Log2_Total_Area = format_custom(ifelse(!is.na(area_mz1) & area_mz1 > 0, log2(area_mz1), NA)),
    FWHM = format_custom(fwhm),
    PPP = format_custom(ppp)
  )
}

# Additional metric calculations
calculate_ppp_custom <- function(rt_values, intensities, threshold_ratio = 0.5) {
  max_int <- max(intensities, na.rm = TRUE)
  sum(!is.na(intensities) & intensities >= max_int * threshold_ratio)
}

calculate_fwhm <- function(rt_values, intensities) {
  if (length(rt_values) < 2 || all(is.na(intensities))) {
    return(list(fwhm = NA, left_rt = NA, right_rt = NA))
  }

  max_idx <- which.max(intensities)
  half_max <- max(intensities, na.rm = TRUE) / 2

  left_rt <- NA
  right_rt <- NA

  # Left side crossing
  if (max_idx > 1) {
    for (i in 2:max_idx) {
      if (i <= length(rt_values) && !is.na(intensities[i - 1]) && !is.na(intensities[i])) {
        if (intensities[i - 1] < half_max && intensities[i] >= half_max) {
          left_rt <- approx(
            x = intensities[(i - 1):i],
            y = rt_values[(i - 1):i],
            xout = half_max,
            ties = mean
          )$y
          break
        }
      }
    }
  }

  # Right side crossing
  if (max_idx < length(rt_values)) {
    for (i in (max_idx + 1):length(rt_values)) {
      if (i <= length(rt_values) && !is.na(intensities[i - 1]) && !is.na(intensities[i])) {
        if (intensities[i - 1] >= half_max && intensities[i] < half_max) {
          right_rt <- approx(
            x = intensities[(i - 1):i],
            y = rt_values[(i - 1):i],
            xout = half_max,
            ties = mean
          )$y
          break
        }
      }
    }
  }

  if (is.na(left_rt) || is.na(right_rt)) {
    return(list(fwhm = NA, left_rt = left_rt, right_rt = right_rt))
  }

  fwhm <- right_rt - left_rt
  list(fwhm = fwhm, left_rt = left_rt, right_rt = right_rt)
}

# Trapezoidal area calculation
compute_xic_area <- function(rt_values, intensities) {
  valid <- which(!is.na(rt_values) & !is.na(intensities))
  if (length(valid) > 1) {
    trapz(rt_values[valid], intensities[valid])
  } else {
    NA
  }
}

plot_xic <- function(rt_values, intensities, output_file, analyte_name = NULL, ms_level = NULL,
                     mz_tol = NULL, rt_tol_sec = NULL, sample_name = NULL, mz_tol_ppm = NULL,
                     plot_ppp = TRUE, rt_target = NULL, mz_theoretical = NULL, fragment_mz = NULL) {

  if (length(rt_values) == 0 || length(intensities) == 0) return(NULL)

  xic_df <- data.frame(RT = rt_values, Intensity = intensities)
  xic_df <- xic_df[complete.cases(xic_df), ]
  xic_df <- xic_df[order(xic_df$RT), ]

  max_idx <- which.max(xic_df$Intensity)
  max_rt <- xic_df$RT[max_idx]
  max_intensity <- xic_df$Intensity[max_idx]
  half_max <- max_intensity / 2

  ppp <- if (plot_ppp) calculate_ppp_custom(xic_df$RT, xic_df$Intensity, threshold_ratio = PPP_THRESHOLD_RATIO) else NA
  fwhm_data <- calculate_fwhm(xic_df$RT, xic_df$Intensity)
  fwhm <- fwhm_data$fwhm
  left_rt <- fwhm_data$left_rt
  right_rt <- fwhm_data$right_rt

  fwhm_line <- NULL
  if (!is.na(left_rt) && !is.na(right_rt) && !is.na(half_max)) {
    fwhm_line <- data.frame(
      RT = seq(left_rt, right_rt, length.out = 100),
      Intensity = rep(half_max, 100)
    )
  }

  ppp_threshold <- max_intensity * PPP_THRESHOLD_RATIO

  rt_range_text <- if (!is.null(rt_target) && !is.null(rt_tol_sec)) {
    rt_min_theo <- rt_target - rt_tol_sec
    rt_max_theo <- rt_target + rt_tol_sec
    glue("RT range: {round(rt_min_theo, 2)} - {round(rt_max_theo, 2)} s")
  } else {
    ""
  }

  mz_info <- if (ms_level == 1 && !is.null(mz_theoretical)) {
    glue("{round(mz_theoretical, 4)}")
  } else if (ms_level == 2 && !is.null(fragment_mz)) {
    glue("{round(fragment_mz, 4)}")
  } else {
    ""
  }
  plot_title <- glue("XIC for {analyte_name} {mz_info} (MS{ms_level})")
  plot_subtitle <- glue("Sample: {sample_name} | mz tol: ±{mz_tol_ppm} ppm | rt tol: ±{round(rt_tol_sec, 1)}s")

  p <- ggplot(xic_df, aes(x = RT, y = Intensity)) +
    geom_line(color = "blue", linewidth = 0.8) +
    geom_point(size = 1.6) +
    geom_vline(xintercept = max_rt, linetype = "dashed", color = "red") +
    annotate("text", x = max_rt, y = max_intensity,
             label = "Max", color = "red", size = 3,
             vjust = -1, hjust = 1) +
    { if (!is.null(fwhm_line)) geom_line(data = fwhm_line, aes(x = RT, y = Intensity),
                                         inherit.aes = FALSE,
                                         color = "darkgreen",
                                         linetype = "dotted",
                                         linewidth = 1) } +
    { if (plot_ppp) geom_hline(yintercept = ppp_threshold,
                               color = "gray40",
                               linetype = "dotdash") } +
    
    annotate("text", x = Inf, y = Inf,
             label = glue("FWHM: {round(fwhm, 2)} s"),
             hjust = 1, vjust = 1, size = 3.5) +
    { if (plot_ppp) annotate("text", x = Inf, y = Inf,
                             label = glue("PPP: {ppp}"),
                             hjust = 1, vjust = 2, size = 3.5) } +
    annotate("text", x = Inf, y = Inf,
             label = rt_range_text,
             hjust = 1, vjust = 3, size = 3.5) +
    ggtitle(plot_title, subtitle = plot_subtitle) +
    xlab("Retention Time (s)") + ylab("Intensity") +
    coord_cartesian(clip = "off") +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 1),
      plot.subtitle = element_text(hjust = 1),
      plot.margin = margin(t = 20, r = 20, b = 20, l = 20)
    )

  ggsave(output_file, plot = p, width = 8, height = 6, dpi = 300, bg = "white")
}


# Write metric to JSON file
update_metric_json <- function(metric_name, analyte, sample_name, value, ms_level) {
  ms_label <- paste0("MS", ms_level)

  metric_title <- if (!is.null(json_titles[[metric_name]])) json_titles[[metric_name]] else metric_name

  section_label <- paste(metric_title, ms_label)

  json_file <- file.path(getwd(), paste0(metric_name, "_", sample_name, "_mqc.json"))

  if (file.exists(json_file)) {
    json_data <- fromJSON(json_file)
  } else {
    yaxis_config <- if (!is.null(json_yaxis_window[[metric_name]])) {
      list(
        ymin = json_yaxis_window[[metric_name]][1],
        ymax = json_yaxis_window[[metric_name]][2]
      )
    } else {
      list()
    }

    json_data <- list(
      id = metric_name,
      section_name = section_label,
      description = "",
      plot_type = "linegraph",
      pconfig = c(list(
        id = paste0(metric_name, "_plot"),
        title = section_label,
        xlab = "Sample",
        ylab = metric_title,
        xlab_format = "category",
        showlegend = TRUE,
        style = "lines+markers"
      ), yaxis_config),
      data = list()
    )
  }

  json_data$section_name <- section_label
  json_data$pconfig$title <- section_label
  json_data$pconfig$ylab  <- metric_title

  if (is.character(value) && value == "NA") {
    value <- NA
  }

  if (!is.null(value) && !(is.list(value) && length(value) == 0) && !(is.na(value))) {
    if (is.null(json_data$data[[analyte]])) {
      json_data$data[[analyte]] <- list()
    }
    json_data$data[[analyte]][[sample_name]] <- value
  }

  write_json(
    json_data,
    path       = json_file,
    auto_unbox = TRUE,
    pretty     = TRUE,
    na         = "null"
  )
}

# Main processing loop
all_results <- list()
for (analyte in analyte_names) {
  message(glue("Processing analyte: {analyte}"))
  analyte_data <- get_analyte_data(df, analyte)
  mz1 <- assign_mz1(analyte_data, opt$msLevel)
  mz_tol <- (opt$mz_tol_ppm * mz1) / 1e6
  rt_target <- analyte_data$rt_target
  message(glue("  MS{opt$msLevel} parameters:"))
  message(glue("    Precursor m/z (mz1): {mz1}, RT target: {rt_target}, m/z tol: {mz_tol}"))
  if (opt$msLevel == 2) {
    message(glue("    Fragment target m/z (ms2_mz): {analyte_data$ms2_mz}"))
  }
  xic <- compute_xic(ms_data, mz1, rt_target, opt$rt_tol_sec, mz_tol, opt$msLevel, opt$mz_tol_ppm, ms2_target_mz = if (opt$msLevel == 2) as.numeric(analyte_data$ms2_mz) else NULL)
  if (length(xic) == 0 || is.null(xic[[1]])) {
    message(glue("  No XIC signal found for analyte {analyte}. Skipping."))
    next
  }
  rt_values <- rtime(xic[[1]])
  int <- intensity(xic[[1]])

  if (length(rt_values) == 0 || length(int) == 0 || all(is.na(int))) {
    warning(glue("No valid XIC signal for analyte {analyte}. Skipping."))
    next
  }

  max_idx <- which.max(int)
  rt_obs <- rt_values[max_idx]
  intensity_mz1 <- int[max_idx]
  ppp_value <- calculate_ppp_custom(rt_values, int, threshold_ratio = PPP_THRESHOLD_RATIO)
  fwhm_data <- calculate_fwhm(rt_values, int)
  fwhm_value <- fwhm_data$fwhm
  area_mz1 <- compute_xic_area(rt_values, int)
  
  mz_exp_result <- tryCatch({
    find_mz_for_intensity_obs(ms_data, c(mz1 - mz_tol, mz1 + mz_tol), rt_obs, intensity_mz1, opt$msLevel)
  }, error = function(e) {
    warning(glue("Could not determine observed m/z for {analyte}: {e$message}"))
    NA
  })

  sample_base <- tools::file_path_sans_ext(basename(opt$file_name))
  sample_name <- sub("\\.raw$", "", sample_base)
  result_row <- function_create_output_df(sample_name, analyte, rt_target, rt_obs, mz1, mz_exp_result, intensity_mz1, area_mz1, fwhm_value, ppp_value)
  all_results[[analyte]] <- result_row
  message(glue("  Calculated metrics for {analyte}:"))
  message(glue("    Observed RT: {rt_obs}"))
  if (opt$msLevel == 1) {
    message(glue("    Observed precursor m/z: {mz_exp_result} (expected: {mz1})"))
  } else {
    message(glue("    Observed fragment m/z: {mz_exp_result} (target: {analyte_data$ms2_mz})"))
  }
  message(glue("    Max Intensity: {intensity_mz1}"))
  message(glue("    Area: {area_mz1}"))
  message(glue("    Log2 Area: {ifelse(!is.na(area_mz1) & area_mz1 > 0, log2(area_mz1), NA)}"))
  message(glue("    FWHM: {fwhm_value}"))
  message(glue("    PPP: {ppp_value}"))

  if (!is.null(opt$plot_output_path)) {
    should_plot_ms1 <- opt$plot_xic_ms1 && opt$msLevel == 1
    should_plot_ms2 <- opt$plot_xic_ms2 && opt$msLevel == 2
    if (should_plot_ms1 || should_plot_ms2) {
      dir.create(dirname(opt$plot_output_path), recursive = TRUE, showWarnings = FALSE)
      message(glue("  Saving XIC plot to: {opt$plot_output_path}"))
      plot_xic(rt_values, int, opt$plot_output_path,
         analyte_name = analyte,
         ms_level = opt$msLevel,
         mz_tol = mz_tol,
         rt_tol_sec = opt$rt_tol_sec,
         sample_name = sample_name,
         mz_tol_ppm = opt$mz_tol_ppm,
         plot_ppp = FALSE,
         rt_target = analyte_data$rt_target,
         mz_theoretical = mz1,
         fragment_mz = if (opt$msLevel == 2) as.numeric(analyte_data$ms2_mz) else NULL)
    }
  }

  for (metric in json_metrics) {
    if (metric %in% colnames(result_row)) {
      update_metric_json(metric, analyte, sample_name, result_row[[metric]], opt$msLevel)
      message(glue("    Updated JSON metric: {metric}"))
    }
  }
}

# Combine all results into final dataframe
output_df <- do.call(rbind, all_results)

# Save version information
version_info <- list(
  msnbasexic_script = "msnbasexic.R",
  generated_at = as.character(Sys.time()),
  R_version = paste(R.version$major, R.version$minor, sep = "."),
  MSnbase_version = as.character(packageVersion("MSnbase")),
  ggplot2_version = as.character(packageVersion("ggplot2")),
  pracma_version = as.character(packageVersion("pracma"))
)
lines <- unlist(lapply(names(version_info), function(k) paste0(k, ": ", version_info[[k]])))
writeLines(lines, "versions.yml")

print("versions.yml generated.")
