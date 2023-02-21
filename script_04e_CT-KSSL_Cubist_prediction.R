
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("doParallel")
library("readxl")
library("qs")
library("rules")
library("Cubist")

options(scipen = 999)

## Folders
# mnt.dir <- "~/projects/mnt-ringtrial/"
mnt.dir <- "~/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.pca <- paste0(mnt.dir, "pca/")
dir.predictions <- paste0(mnt.dir, "predictions/CT-KSSL_Cubist/")

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
modeling.combinations <- read_csv("outputs/tab_CT-KSSL_Cubist_10CVrep1_performance_metrics.csv")
modeling.combinations

## Automated prediction

i=1
for(i in 1:nrow(modeling.combinations)) {
  
  # Iterators
  
  isoil_property <- modeling.combinations[[i,"soil_property"]]
  iprep_transform <- modeling.combinations[[i,"prep_transform"]]
  itrain <- unlist(modeling.combinations[[i,"train"]])
  iprep_spectra <- modeling.combinations[[i,"prep_spectra"]]
  icommittees <- modeling.combinations[[i,"committees"]]
  ineighbors <- modeling.combinations[[i,"neighbors"]]
  
  cat(paste0("Running iteration ", paste0(i, "/", nrow(modeling.combinations)),
             ", ", itrain,
             ", ", isoil_property,
             ", ", iprep_spectra,
             " at ", now(),
             "\n"))
  
  # Loading train data
  
  column.ids <- c("organization", "sample_id", "ct_subset")
  
  if(iprep_spectra == "wavelet") {
    
    train.preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_wavelet.qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(any_of(column.ids), all_of(isoil_property), starts_with("H9_")) %>%
      mutate(!!isoil_property := ifelse(!!as.name(isoil_property) < 0.01, NA, !!as.name(isoil_property))) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      mutate(across(any_of(column.ids), as.character))
    
  } else if(iprep_spectra == "SST") {
    
    # SST specta is actually SNV preprocessed. Only RTs are aligned to KSSL SNV
    pca.model <-  qread(paste0(dir.pca,
                               "pca_model_normalized_cumvar99dot99_",
                               itrain, "_",
                               isoil_property, "_SNV.qs"))
    
    train.preprocessed <- juice(pca.model) %>%
      rename_at(vars(starts_with("PC")), ~paste0("PC", as.numeric(gsub("PC", "", .)))) %>%
      mutate(!!isoil_property := ifelse(!!as.name(isoil_property) < 0.01, NA, !!as.name(isoil_property))) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      mutate(across(any_of(column.ids), as.character))
    
  } else {
    
    pca.model <-  qread(paste0(dir.pca,
                               "pca_model_normalized_cumvar99dot99_",
                               itrain, "_",
                               isoil_property, "_",
                               iprep_spectra, ".qs"))
    
    train.preprocessed <- juice(pca.model) %>%
      rename_at(vars(starts_with("PC")), ~paste0("PC", as.numeric(gsub("PC", "", .)))) %>%
      mutate(!!isoil_property := ifelse(!!as.name(isoil_property) < 0.01, NA, !!as.name(isoil_property))) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      mutate(across(any_of(column.ids), as.character))
    
  }
  
  cat(paste0("Imported data at ", now(), "\n"))
  
  # Test data
  
  soil.data <- read_csv(paste0(dir.preprocessed, "RT_wetchem_soildata.csv"), show_col_types = FALSE)
  
  spectra.columns <- as.character(seq(650, 4000, by = 2))
  
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
  
  # Test predictors
  
  if(iprep_spectra == "wavelet") {
    
    testing.columns <- test.preprocessed %>%
      select(any_of(column.ids), all_of(isoil_property)) %>%
      rename_with(~"observed", all_of(isoil_property))
    
    testing.predictors <- test.preprocessed %>%
      select(any_of(column.ids), all_of(isoil_property), starts_with("H9_"))
    
  } else {
    
    testing.columns <- test.preprocessed %>%
      select(any_of(column.ids), all_of(isoil_property)) %>%
      rename_with(~"observed", all_of(isoil_property))
    
    testing.predictors <- bake(pca.model,
                               new_data = test.preprocessed, everything()) %>%
      rename_at(vars(starts_with("PC")), ~paste0("PC", as.numeric(gsub("PC", "", .))))
    
  }
  
  if(iprep_transform == "logTransform") {
    
    testing.columns <- testing.columns %>%
      mutate(observed = log(observed))
    
  } else {
    
    testing.columns <- testing.columns
    
  }
    
  cat(paste0("Imported test data at ", now(), "\n"))
    
  # Recipe
  
  if(iprep_transform == "withoutTransform") {
    
    recipe.model <- train.preprocessed %>%
      recipe() %>%
      update_role(everything()) %>%
      update_role(any_of(column.ids), new_role = "id") %>%
      update_role(all_of(isoil_property), new_role = "outcome")
    
  } else if(iprep_transform == "logTransform") {
    
    recipe.model <- train.preprocessed %>%
      recipe() %>%
      update_role(everything()) %>%
      update_role(any_of(column.ids), new_role = "id") %>%
      update_role(all_of(isoil_property), new_role = "outcome") %>%
      step_log(all_outcomes(), id = "log", skip = T)
    
  }
  
  # Preparing Cubist engine and hyperparameters
  
  cubist.model <-  cubist_rules(committees = !!icommittees,
                                neighbors = !!ineighbors) %>% 
    set_engine("Cubist")
  
  # Preparing modeling workflow
  
  modeling.workflow <- workflow() %>%
    add_model(cubist.model) %>% 
    add_recipe(recipe.model)
  
  cat(paste0("Workflow prepared at ", now(), "\n"))
  
  # Model fit
  
  cubist.fit <- modeling.workflow %>%
    fit(data = train.preprocessed)
  
  cat(paste0("Model fitted at ", now(), "\n"))
  
  # Predictions
  
  predictions <- cubist.fit %>%
    predict(new_data = testing.predictors) %>%
    rename("predicted" = .pred) %>%
    bind_cols(testing.columns, .)

  cat(paste0("Predictions made at ", now(), "\n"))
  
  # Exporting results
  
  qsave(predictions, paste0(dir.predictions,
                            "tab_predictions_",
                            itrain, "_",
                            isoil_property, "_",
                            iprep_transform, "_",
                            iprep_spectra, ".qs"))
  
  cat(paste0("Exported results at ", now(), "\n\n"))
  
  # Cleaning iteration and freeing memory
  
  keep.objects <- c("mnt.dir", "dir.preprocessed", "dir.predictions", "dir.pca",
                    "modeling.combinations", "metadata", "organizations",
                    "new_codes", "codes")
  
  remove.objects <- ls()[-grep(paste(keep.objects, collapse = "|"), ls())]
  rm(list = remove.objects)
  gc()
  
}
