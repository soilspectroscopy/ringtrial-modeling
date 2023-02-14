
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("readxl")
library("purrr")
library("furrr")
library("pls")
library("future")
library("qs")

## Folders
mnt.dir <- "~/mnt-ringtrial/"
# mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.output <- paste0(mnt.dir, "predictions/CT-KSSL_PLSR/")

## Number of cores available
n.cores <- 10 # We are running 10-fold CV with 1 rep

## Modeling combinations
modeling.combinations <- read_csv("outputs/modeling_combinations_CT-KSSL_PLSR.csv")
modeling.combinations

## Automated prediction

i=8
for(i in 1:nrow(modeling.combinations)) {
  
  # Iterators
  
  isoil_property <- modeling.combinations[[i,"soil_property"]]
  iprep_transfom <- modeling.combinations[[i,"prep_transform"]]
  itrain <- unlist(modeling.combinations[[i,"train"]])
  iprep_spectra <- modeling.combinations[[i,"prep_spectra"]]
  
  cat(paste0("Running iteration ", paste0(i, "/", nrow(modeling.combinations)),
             ", ", itrain,
             ", ", isoil_property,
             ", ", iprep_spectra,
             " at ", now(),
             "\n"))
  
  # Loading dataset inside loop for memory management
  
  spectra.columns <- as.character(seq(650, 4000, by = 2))
  column.ids <- c("sample_id")
  
  if(iprep_spectra == "wavelet") {
    
    preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_wavelet.qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(all_of(column.ids), all_of(isoil_property), starts_with("H9_"))
    
  } else if(iprep_spectra == "SST") {
    
    # SST specta is actually SNV preprocessed. Only RTs are aligned to KSSL SNV
    preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_SNV.qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(all_of(column.ids), all_of(isoil_property), any_of(spectra.columns)) %>%
      as_tibble()
    
  } else {
    
    preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_", iprep_spectra, ".qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(all_of(column.ids), all_of(isoil_property), any_of(spectra.columns)) %>%
      as_tibble()
    
  }
  
  cat(paste0("Imported data at ", now(), "\n"))
  
  # Splitting into 10-folds
  # Setting a lower bound (less than 0.05% of the data lies lower than 0.01) for any soil property.
  # zero values must be replaced because of log transformation.
  set.seed(1993)
  modeling.folds <- preprocessed %>%
    mutate(!!isoil_property := ifelse(!!as.name(isoil_property) < 0.01, NA, !!as.name(isoil_property))) %>%
    filter(!is.na(!!as.name(isoil_property))) %>%
    vfold_cv(v = 10, repeats = 1) %>%
    mutate(idfull = id) # Adjust with repeats
  
  rm(preprocessed)
  gc()
  
  # Recipe model
  
  if(iprep_transfom == "withoutTransform") {
    
    recipe.model <- function(dataset){
      dataset %>%
        recipe() %>%
        update_role(everything()) %>%
        update_role(all_of(column.ids), new_role = "id") %>%
        update_role(all_of(isoil_property), new_role = "outcome") %>%
        prep()
    }
    
  } else if(iprep_transfom == "logTransform") {
    
    recipe.model <- function(dataset){
      dataset %>%
        recipe() %>%
        update_role(everything()) %>%
        update_role(all_of(column.ids), new_role = "id") %>%
        update_role(all_of(isoil_property), new_role = "outcome") %>%
        step_log(all_outcomes(), id = "log") %>%
        prep()
    }
    
  }
  
  cat(paste0("Recipe prepared at ", now(), "\n"))
  
  # Prediction function
  
  model.prediction.folds <- function(maxcomps = 20, split, id){
    
    # maxcomps = 20
    # split = modeling.folds[["splits"]][[1]]
    # id=1
    
    # Preparing pls matrices
    
    training.set <- analysis(split)
    
    training.outcome <- juice(recipe.model(training.set), composition = "matrix", all_outcomes())
    
    training.predictors <- juice(recipe.model(training.set), composition = "matrix", all_predictors())
    
    pls.training.data <- data.frame(target = I(training.outcome),
                                    spectra = I(training.predictors))
    
    pls.model <- plsr(target ~ spectra, data = pls.training.data, ncomp = maxcomps,
                      scale = T, center = T)
    
    # Evaluation
    
    testing.set <- assessment(split)
    
    testing.outcome <- bake(recipe.model(training.set),
                            new_data = testing.set,
                            composition = "matrix", all_outcomes())
    
    testing.predictors <- bake(recipe.model(training.set),
                               new_data = testing.set,
                               composition = "matrix", all_predictors())
    
    pls.testing.format <- data.frame(target = I(testing.outcome),
                                     spectra = I(testing.predictors))
    
    test <- predict(pls.model, newdata = pls.testing.format) %>%
      as.data.frame() %>%
      as_tibble() %>%
      rename_with(~paste0("prediction_", seq(1, maxcomps, by=1), "comp"), everything()) %>%
      bind_cols(tibble("id" = id,
                       "sample_id" = testing.set[["sample_id"]],
                       "observed" = testing.outcome[,1]), .) %>%
      mutate(soil_property = isoil_property,
             prep_transform = iprep_transfom,
             train = itrain,
             prep_spectra = iprep_spectra,
             .before = 1)
    
  }
  
  future::plan(multisession, workers = n.cores, gc = TRUE)
  
  cv.results <- future_map2_dfr(.x = modeling.folds$splits,
                                .y = modeling.folds$idfull,
                                ~model.prediction.folds(maxcomps = 30, split = .x, id = .y),
                                .options = furrr_options(seed = T))
  
  # cv.results <- map2_dfr(.x = modeling.folds$splits,
  #                               .y = modeling.folds$idfull,
  #                               ~model.prediction.folds(maxcomps = 20, split = .x, id = .y))
  
  future:::ClusterRegistry("stop")
  
  cat(paste0("CV predictions conclude at ", now(), "\n"))
  
  # Exporting results
  
  qsave(cv.results, paste0(dir.output,
                                 "tab_predictions_10CVrep1_",
                                 itrain, "_",
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

