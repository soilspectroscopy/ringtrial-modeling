
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("readxl")
library("qs")
library("resemble")
library("doParallel")

options(scipen = 999)

## Folders
mnt.dir <- "~/mnt-ringtrial/"
# mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.output <- paste0(mnt.dir, "predictions/CT-KSSL_MBL/")

## Number of cores available
n.cores <- 30

## Reading organization codes
metadata <- read_xlsx(paste0(mnt.dir, "Spectrometers_Metadata.xlsx"), 1)

metadata <- metadata %>%
  filter(!is.na(code)) %>%
  select(code, folder_name, unique_name, country_iso)

new_codes <- metadata %>%
  pull(code)

names(new_codes) <- pull(metadata, folder_name)

organizations <- metadata %>%
  pull(folder_name)

codes <- metadata %>%
  pull(code)

## Modeling combinations
modeling.combinations <- read_csv("outputs/modeling_combinations_CT-KSSL_MBL.csv")
modeling.combinations

## Automated prediction

i=1
for(i in 1:nrow(modeling.combinations)) {
  
  # Iterators
  
  isoil_property <- modeling.combinations[[i,"soil_property"]]
  iprep_transfom <- modeling.combinations[[i,"prep_transform"]]
  itrain <- unlist(modeling.combinations[[i,"train"]])
  iprep_spectra <- modeling.combinations[[i,"prep_spectra"]]
  icomponents <- modeling.combinations[[i,"components"]]
  
  cat(paste0("Running iteration ", paste0(i, "/", nrow(modeling.combinations)),
             ", ", itrain,
             ", ", isoil_property,
             ", ", iprep_spectra,
             " at ", now(),
             "\n"))
  
  # Loading dataset inside loop for memory management
  
  spectra.columns <- as.character(seq(650, 4000, by = 2))
  column.ids <- c("organization", "sample_id", "ct_subset")
  
  if(iprep_spectra == "wavelet") {
    
    train.preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_wavelet.qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(any_of(column.ids), all_of(isoil_property), starts_with("H9_"))
    
  } else if(iprep_spectra == "SST") {
    
    # SST specta is actually SNV preprocessed. Only RTs are aligned to KSSL SNV
    train.preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_SNV.qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(any_of(column.ids), all_of(isoil_property), any_of(spectra.columns)) %>%
      as_tibble()
    
  } else {
    
    train.preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_", iprep_spectra, ".qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(any_of(column.ids), all_of(isoil_property), any_of(spectra.columns)) %>%
      as_tibble()
    
  }
  
  cat(paste0("Imported train data at ", now(), "\n"))
  
  # Test data
  
  soil.data <- read_csv(paste0(dir.preprocessed, "RT_wetchem_soildata.csv"), show_col_types = FALSE)
  
  if(iprep_spectra == "wavelet") {
    
    test.preprocessed <- read_csv(paste0(dir.preprocessed, "RT_STD_allMIRspectra_wavelet.csv"), show_col_types = F) %>%
      left_join(soil.data, by = "sample_id") %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(any_of(column.ids), all_of(isoil_property), starts_with("H9_")) %>%
      mutate(organization = recode(organization, !!!new_codes)) %>%
      mutate(organization = factor(organization, levels = as.character(new_codes)))
    
  } else {
    
    test.preprocessed <- read_csv(paste0(dir.preprocessed, "RT_STD_allMIRspectra_", iprep_spectra, ".csv"), show_col_types = F) %>%
      left_join(soil.data, by = "sample_id") %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(any_of(column.ids), all_of(isoil_property), any_of(spectra.columns)) %>%
      mutate(organization = recode(organization, !!!new_codes)) %>%
      mutate(organization = factor(organization, levels = as.character(new_codes)))
    
  }
  
  cat(paste0("Imported test data at ", now(), "\n"))
  
  # Setting a lower bound (less than 0.05% of the data lies lower than 0.01) for any soil property.
  # Zero values must be replaced because of the log transformation.
  train.preprocessed <- train.preprocessed %>%
    mutate(!!isoil_property := ifelse(!!as.name(isoil_property) <= 0.01, NA, !!as.name(isoil_property))) %>%
    filter(!is.na(!!as.name(isoil_property)))
  
  # Recipe model 
  if(iprep_transfom == "withoutTransform") {
    
    recipe.model <- train.preprocessed %>%
      recipe() %>%
      update_role(everything()) %>%
      update_role(any_of(column.ids), new_role = "id") %>%
      update_role(all_of(isoil_property), new_role = "outcome") %>%
      prep()
    
  } else if(iprep_transfom == "logTransform") {
    
    recipe.model <- train.preprocessed %>%
      recipe() %>%
      update_role(everything()) %>%
      update_role(any_of(column.ids), new_role = "id") %>%
      update_role(all_of(isoil_property), new_role = "outcome") %>%
      step_log(all_outcomes(), id = "log") %>%
      prep()
    
  }
  
  cat(paste0("Recipe prepared at ", now(), "\n"))
  
  # Preparing calibration data
  
  training.outcome <- juice(recipe.model, composition = "matrix", all_outcomes())
  
  training.predictors <- juice(recipe.model, composition = "matrix", all_predictors())
  
  testing.outcome <- bake(recipe.model,
                          new_data = test.preprocessed,
                          composition = "matrix", all_outcomes())
  
  testing.predictors <- bake(recipe.model,
                             new_data = test.preprocessed,
                             composition = "matrix", all_predictors())
  
  cat(paste0("MBL prepared ", now(), "\n"))
  
  # Model predictions diss pca
  
  clust <- makeCluster(n.cores)
  registerDoParallel(clust)
  
  mbl.model.pca <- resemble::mbl(
    Xr = training.predictors,
    Yr = training.outcome,
    Xu = testing.predictors,
    Yu = testing.outcome,
    k_diss = seq(0.5, 3.0, by=0.5),
    k_range = c(50, 200),
    method = resemble::local_fit_wapls(min_pls_c = 5, max_pls_c = 20),
    diss_method = "pca",
    diss_usage = "none",
    control = resemble::mbl_control(validation_type = "NNv"),
    center = TRUE, scale = TRUE, verbose = FALSE, seed = 1993
  )
  
  registerDoSEQ()
  try(stopCluster(clust))
  
  predictions.pca <- Reduce(bind_rows, mbl.model.pca$results) %>%
    as_tibble() %>%
    rename("observed" = "yu_obs", "predicted" = "pred") %>%
    mutate(diss_method = "pca")
  
  cat(paste0("MBL (wapls-pca) fitted at ", now(), "\n"))
  gc()
  
  # Model predictions diss pls
  
  clust <- makeCluster(n.cores)
  registerDoParallel(clust)
  
  mbl.model.pls <- resemble::mbl(
    Xr = training.predictors,
    Yr = training.outcome,
    Xu = testing.predictors,
    Yu = testing.outcome,
    k_diss = seq(0.5, 3.0, by=0.5),
    k_range = c(50, 200),
    method = resemble::local_fit_wapls(min_pls_c = 5, max_pls_c = 20),
    diss_method = "pls",
    diss_usage = "none",
    control = resemble::mbl_control(validation_type = "NNv"),
    center = TRUE, scale = TRUE, verbose = FALSE, seed = 1993
  )
  
  registerDoSEQ()
  try(stopCluster(clust))
  
  predictions.pls <- Reduce(bind_rows, mbl.model.pls$results) %>%
    as_tibble() %>%
    rename("observed" = "yu_obs", "predicted" = "pred") %>%
    mutate(diss_method = "pls")
  
  cat(paste0("MBL (wapls-pls) fitted at ", now(), "\n"))
  gc()
  
  # Model predictions diss cor
  
  clust <- makeCluster(n.cores)
  registerDoParallel(clust)
  
  mbl.model.cor <- resemble::mbl(
    Xr = training.predictors,
    Yr = training.outcome,
    Xu = testing.predictors,
    Yu = testing.outcome,
    k_diss = seq(0.5, 3.0, by=0.5),
    k_range = c(50, 200),
    method = resemble::local_fit_wapls(min_pls_c = 5, max_pls_c = 20),
    diss_method = "cor",
    diss_usage = "none",
    control = resemble::mbl_control(validation_type = "NNv"),
    center = TRUE, scale = TRUE, verbose = FALSE, seed = 1993
  )
  
  registerDoSEQ()
  try(stopCluster(clust))
  
  predictions.cor <- Reduce(bind_rows, mbl.model.cor$results) %>%
    as_tibble() %>%
    rename("observed" = "yu_obs", "predicted" = "pred") %>%
    mutate(diss_method = "cor")
  
  cat(paste0("MBL (wapls-cor) fitted at ", now(), "\n"))
  gc()
  
  predictions <- bind_rows(predictions.pca, predictions.pls, predictions.cor)
  
  # Tidying prediction results
  
  test.metadata <- test.preprocessed %>%
      select(any_of(column.ids)) %>%
      mutate(o_index = row_number())
    
  mbl.model.predictions <- predictions %>%
    left_join(test.metadata, by = "o_index") %>%
    relocate(any_of(column.ids), .before = o_index)
  
  # Exporting results
  
  qsave(mbl.model.predictions, paste0(dir.output,
                                      "tab_predictions_",
                                      itrain, "_MBL_",
                                      isoil_property, "_",
                                      iprep_transfom, "_",
                                      iprep_spectra, ".qs"))
  
  cat(paste0("Exported results at ", now(), "\n\n"))
  
  # Cleaning iteration and freeing memory
  
  keep.objects <- c("mnt.dir", "dir.preprocessed", "dir.output",
                    "metadata", "organization", "code", "new_codes",
                    "modeling.combinations", "n.cores")
  
  remove.objects <- ls()[-grep(paste(keep.objects, collapse = "|"), ls())]
  rm(list = remove.objects)
  gc()
  
}
