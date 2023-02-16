
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("readxl")
library("pls")
library("qs")

options(scipen = 999)

## Folders
mnt.dir <- "~/mnt-ringtrial/"
# mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.output <- paste0(mnt.dir, "predictions/CT-KSSL_PLSR/")

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
modeling.combinations <- read_csv("outputs/tab_CT-KSSL_PLSR_10CVrep1_performance_metrics.csv")
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
  # zero values must be replaced because of log transformation.
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
  
  # Preparing pls matrices
  
  training.outcome <- juice(recipe.model, composition = "matrix", all_outcomes())
  
  training.predictors <- juice(recipe.model, composition = "matrix", all_predictors())
  
  pls.training.data <- data.frame(target = I(training.outcome),
                                  spectra = I(training.predictors))
  
  # Fitting model
  
  pls.model <- plsr(target ~ spectra, data = pls.training.data,
                    ncomp = icomponents, scale = TRUE, center = TRUE)
  
  cat(paste0("Model fitted at ", now(), "\n"))
  
  # Predicting
  
  testing.set <- test.preprocessed
  
  testing.outcome <- bake(recipe.model,
                          new_data = testing.set,
                          composition = "matrix", all_outcomes())
  
  testing.predictors <- bake(recipe.model,
                             new_data = testing.set,
                             composition = "matrix", all_predictors())
  
  pls.testing.format <- data.frame(spectra = I(testing.predictors))
  
  predictions <- predict(pls.model, ncomp = icomponents,
                         newdata = pls.testing.format) %>%
    as.data.frame() %>%
    as_tibble() %>%
    rename_with(~"predicted", everything()) %>%
    bind_cols({testing.set %>%
        select(any_of(column.ids),)},
        tibble("observed" = testing.outcome[,1]),
        .) %>%
    mutate(soil_property = isoil_property,
           prep_transform = iprep_transfom,
           train = itrain,
           prep_spectra = iprep_spectra,
           .before = 1)
  
  cat(paste0("Predictions concluded at ", now(), "\n"))
  
  # Exporting results
  
  qsave(predictions, paste0(dir.output,
                           "tab_predictions_",
                           itrain, "_PLSR_",
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

