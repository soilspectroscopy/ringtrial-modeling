
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("doParallel")
library("qs")
library("rules")
library("Cubist")

options(scipen = 999)
options(tidymodels.dark = TRUE)
tidymodels_prefer()

## Folders
# mnt.dir <- "~/projects/mnt-ringtrial/"
mnt.dir <- "~/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.pca <- paste0(mnt.dir, "pca/")
dir.predictions <- paste0(mnt.dir, "predictions/CT-KSSL_Cubist/")
dir.hyperparameters <- paste0(mnt.dir, "performance/cubist_hyperparameters/")

## Number of cores available
n.cores <- 15 # We are running 10-fold CV with 1 rep

## Modeling combinations
modeling.combinations <- read_csv("outputs/modeling_combinations_CT-KSSL_Cubist.csv")
modeling.combinations

## Automated calibration with 10-fold cross-validation

i=1
for(i in 1:nrow(modeling.combinations)) {
  
  # Iterators
  
  itrain <- unlist(modeling.combinations[[i,"train"]])
  iprep_spectra <- modeling.combinations[[i,"prep_spectra"]]
  isoil_property <- modeling.combinations[[i,"soil_property"]]
  iprep_transform <- modeling.combinations[[i,"prep_transform"]]
  
  cat(paste0("Running iteration ", paste0(i, "/", nrow(modeling.combinations)),
             ", ", itrain,
             ", ", isoil_property,
             ", ", iprep_spectra,
             " at ", now(),
             "\n"))
  
  # Loading train data
  
  column.ids <- c("sample_id")
  
  if(iprep_spectra == "wavelet") {
    
    train.preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_wavelet.qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(all_of(column.ids), all_of(isoil_property), starts_with("H9_"))
    
  } else if(iprep_spectra == "SST") {
    
    # SST specta is actually SNV preprocessed. Only RTs are aligned to KSSL SNV
    pca.model <-  qread(paste0(dir.pca,
                               "pca_model_normalized_cumvar99dot99_",
                               itrain, "_",
                               isoil_property, "_SNV.qs"))
    
    train.preprocessed <- juice(pca.model) %>%
      rename_at(vars(starts_with("PC")), ~paste0("PC", as.numeric(gsub("PC", "", .))))
    
  } else {
    
    pca.model <-  qread(paste0(dir.pca,
                               "pca_model_normalized_cumvar99dot99_",
                               itrain, "_",
                               isoil_property, "_",
                               iprep_spectra, ".qs"))
    
    train.preprocessed <- juice(pca.model) %>%
      rename_at(vars(starts_with("PC")), ~paste0("PC", as.numeric(gsub("PC", "", .))))
    
  }
  
  cat(paste0("Imported data at ", now(), "\n"))

  # Splitting into 10-folds
  # Setting a lower bound (less than 0.05% of the data lies lower than 0.01) for any soil property.
  # zero values must be replaced because of log transformation.
  set.seed(1993)
  modeling.folds <- train.preprocessed %>%
    mutate(!!isoil_property := ifelse(!!as.name(isoil_property) < 0.01, NA, !!as.name(isoil_property))) %>%
    filter(!is.na(!!as.name(isoil_property))) %>%
    vfold_cv(v = 10, repeats = 1)
  
  # Recipe model
  # A recipe is associated with the data set used to create the model.
  # This will typically be the training set, so data = train_data here.
  # Naming a data set doesn’t actually change the data itself;
  # it is only used to catalog the names of the variables and their types
  if(iprep_transform == "withoutTransform") {
    
    recipe.model <- train.preprocessed %>%
      recipe() %>%
      update_role(everything()) %>%
      update_role(all_of(column.ids), new_role = "id") %>%
      update_role(all_of(isoil_property), new_role = "outcome")
    
  } else if(iprep_transform == "logTransform") {
    
    recipe.model <- train.preprocessed %>%
      recipe() %>%
      update_role(everything()) %>%
      update_role(all_of(column.ids), new_role = "id") %>%
      update_role(all_of(isoil_property), new_role = "outcome") %>%
      step_log(all_outcomes(), id = "log")
    
  }
  
  cat(paste0("Recipe prepared at ", now(), "\n"))
  
  # Preparing Cubist fit
  
  cubist.model <-  cubist_rules(committees = tune(),
                                neighbors = tune()) %>% 
    set_engine("Cubist")
  
  # Preparing modelling workflow
  
  modeling.workflow <- workflow() %>%
    add_model(cubist.model) %>% 
    add_recipe(recipe.model)
  
  # Preparing hyperparameters grid
  
  committees.tune <- c(1, 10, 25, 50, 100)
  neighbors.tune <- c(1, 5, 9)
  
  hyperparameters.grid <- crossing("committees" = committees.tune,
                                   "neighbors" = neighbors.tune)
  
  # Tuning hyperparameters - parallel
  
  cl <- makeCluster(n.cores)
  registerDoParallel(cl)
  
  set.seed(1993)
  cubist.fit.tune <- modeling.workflow %>%
    tune_grid(resamples = modeling.folds, grid = hyperparameters.grid,
              control = control_grid(verbose = FALSE, # Switch TRUE if allow_par = FALSE
                                     allow_par = TRUE,
                                     parallel_over = "everything",
                                     save_pred = TRUE))
  
  try(stopCluster(cl))
  
  cat(paste0("Hyperparameters tuned ", now(), "\n"))
  
  # Tidying tuning information
  
  # autoplot(cubist.fit.tune, metric = "rmse")
  # collect_notes(cubist.fit.tune)
  # collect_predictions(cubist.fit.tune) %>% arrange(.row)
  # collect_metrics(cubist.fit.tune)
  
  # Best hyperparameters
  
  best.hyperparameters <- select_best(cubist.fit.tune, metric = "rmse") %>%
    select(-.config) %>%
    mutate(soil_property = isoil_property,
           prep_transform = iprep_transform,
           train = itrain,
           prep_spectra = iprep_spectra) %>%
    relocate(soil_property, prep_transform, train, prep_spectra, .before = committees)
  
  best.metrics <- collect_metrics(cubist.fit.tune) %>%
    select(committees, neighbors, .metric, mean) %>%
    filter(neighbors == pull(best.hyperparameters, neighbors)) %>%
    filter(committees == pull(best.hyperparameters, committees)) %>%
    pivot_wider(names_from = ".metric", values_from = "mean")
  
  best.hyperparameters <- left_join(best.hyperparameters, best.metrics,
                                    by = c("committees", "neighbors"))
  
  qsave(best.hyperparameters,
        paste0(dir.hyperparameters,
               "tab_best_hp_10CVrep1_",
               itrain, "_",
               isoil_property, "_",
               iprep_transform, "_",
               iprep_spectra, ".qs"))
  
  all.hyperparameters <- collect_metrics(cubist.fit.tune) %>%
    select(committees, neighbors, .metric, mean) %>%
    pivot_wider(names_from = ".metric", values_from = "mean") %>%
    mutate(soil_property = isoil_property,
           prep_transform = iprep_transform,
           train = itrain,
           prep_spectra = iprep_spectra) %>%
    relocate(soil_property, prep_transform, train, prep_spectra, .before = committees)
  
  qsave(all.hyperparameters,
        paste0(dir.hyperparameters,
               "tab_all_hp_10CVrep1_",
               itrain, "_",
               isoil_property, "_",
               iprep_transform, "_",
               iprep_spectra, ".qs"))
  
  # CV10rep10 predictions
  # summarize	= TRUE. Should metrics be summarized (mean) over resamples?
  
  predictions <- collect_predictions(cubist.fit.tune, summarize = TRUE) %>%
    arrange(.row) %>%
    select(-.row, -.config) %>%
    rename(predicted = .pred, observed = !!isoil_property) %>%
    relocate(observed, .before = predicted) %>%
    filter(neighbors == pull(best.hyperparameters, neighbors)) %>%
    filter(committees == pull(best.hyperparameters, committees))
  
  # Exporting results
  
  qsave(predictions, paste0(dir.predictions,
                           "tab_predictions_10CVrep1_",
                           itrain, "_",
                           isoil_property, "_",
                           iprep_transform, "_",
                           iprep_spectra, ".qs"))
  
  cat(paste0("Exported results at ", now(), "\n\n"))
  
  # Cleaning iteration and freeing memory
  
  keep.objects <- c("mnt.dir", "dir.preprocessed", "dir.predictions",
                    "dir.pca", "dir.hyperparameters",
                    "n.cores", "modeling.combinations",
                    "hyperparameters.list")
  
  remove.objects <- ls()[-grep(paste(keep.objects, collapse = "|"), ls())]
  rm(list = remove.objects)
  gc()
  
}
