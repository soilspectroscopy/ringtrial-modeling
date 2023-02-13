
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("readxl")
library("purrr")
library("furrr")
library("pls")
library("future")

## Folders
mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.output <- paste0(mnt.dir, "predictions/int10CVrep10/")
if(!dir.exists(dir.output)){dir.create(dir.output)}

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

modeling.combinations <- read_csv("outputs/modeling_combinations_int10CVrep10_PLSR.csv")
modeling.combinations

## Automated prediction

i=1

for(i in 1:nrow(modeling.combinations)) {
  
  # Iterators
  
  iinstrument <- modeling.combinations[[i,"instrument"]]
  isoil_property <- modeling.combinations[[i,"soil_property"]]
  iprep_transfom <- modeling.combinations[[i,"prep_transform"]]
  itrain <- unlist(modeling.combinations[[i,"train"]])
  iprep_spectra <- modeling.combinations[[i,"prep_spectra"]]
  
  cat(paste0("Run ", i, "/", nrow(modeling.combinations), " - ", now(), "\n"))
  
  # Modeling data
  
  soil.data <- read_csv(paste0(dir.preprocessed, "RT_wetchem_soildata.csv"), show_col_types = FALSE)
  
  spectra.columns <- as.character(seq(650, 4000, by = 2))
  column.ids <- c("organization", "sample_id")
  
  # modeling.combinations %>%
  #   distinct(spectra_prep) %>%
  #   pull(spectra_prep)
  
  if(iprep_spectra == "wavelet") {
    
    preprocessed <- read_csv(paste0(dir.preprocessed, "RT_STD_allMIRspectra_wavelet.csv"), show_col_types = F) %>%
      left_join(soil.data, by = "sample_id") %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(all_of(column.ids), all_of(isoil_property), starts_with("H9_")) %>%
      mutate(organization = recode(organization, !!!new_codes)) %>%
      mutate(organization = factor(organization, levels = as.character(new_codes))) %>%
      filter(organization == iinstrument)
    
  } else {
    
    preprocessed <- read_csv(paste0(dir.preprocessed, "RT_STD_allMIRspectra_", iprep_spectra, ".csv"), show_col_types = F) %>%
      left_join(soil.data, by = "sample_id") %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(all_of(column.ids), all_of(isoil_property), any_of(spectra.columns)) %>%
      mutate(organization = recode(organization, !!!new_codes)) %>%
      mutate(organization = factor(organization, levels = as.character(new_codes))) %>%
      filter(organization == iinstrument)
    
  }
  
  gc()
  cat(paste0("Modeling data imported in ", now(), "\n"))
  
  # Splitting into 10-folds repeated 10 times
  
  set.seed(1993)
  modeling.folds <- preprocessed %>%
    vfold_cv(v = 10, repeats = 10) %>%
    mutate(idfull = paste(id, id2, sep = "_"))
  
  rm(preprocessed)
  gc()
  
  # Recipe model
  
  if(iprep_transfom == "withoutTransform") {
    
    recipe.model <- function(dataset){
      dataset %>%
        recipe() %>%
        update_role(everything()) %>%
        update_role(all_of(all_of(column.ids)), new_role = "id") %>%
        update_role(all_of(isoil_property), new_role = "outcome") %>%
        prep()
    }
    
  } else if(iprep_transfom == "logTransform") {
    
    recipe.model <- function(dataset){
      dataset %>%
        recipe() %>%
        update_role(everything()) %>%
        update_role(all_of(all_of(column.ids)), new_role = "id") %>%
        update_role(all_of(isoil_property), new_role = "outcome") %>%
        step_log(all_outcomes()) %>%
        prep()
    }
    
  }
  
  # Prediction function
  
  model.prediction.folds <- function(maxcomps = 20, split, id){
    
    # maxcomps = 20
    # split = modeling.folds[["splits"]][[1]]
    
    # Preparing pls matrices
    
    training.set <- analysis(split)
    
    training.outcome <- juice(recipe.model(training.set), composition = "matrix", all_outcomes())
    
    training.predictors <- juice(recipe.model(training.set), composition = "matrix", all_predictors())
    
    pls.training.data <- data.frame(target = I(training.outcome),
                                    spectra = I(training.predictors))
    
    pls.model <- plsr(target ~ spectra, data = pls.training.data, ncomp = maxcomps,
                      scale = FALSE, center = FALSE)
    
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
    
    predict(pls.model, newdata = pls.testing.format) %>%
      as.data.frame() %>%
      as_tibble() %>%
      rename_with(~paste0("prediction_", seq(1, maxcomps, by=1), "comp"), everything()) %>%
      bind_cols(tibble("id" = id,
                       "sample_id" = testing.set[["sample_id"]],
                       "observed" = testing.outcome[,1]), .) %>%
      mutate(organization = iinstrument,
             soil_property = isoil_property,
             prep_transform = iprep_transfom,
             train = itrain,
             prep_spectra = iprep_spectra,
             .before = 1)
  }
  
  future::plan(multisession, workers = 5, gc = TRUE)
  
  cv.results <- future_map2_dfr(.x = modeling.folds$splits,
                                .y = modeling.folds$idfull,
                                ~model.prediction.folds(maxcomps = 30, split = .x, id = .y),
                                .options = furrr_options(seed = T))
  
  # cv.results <- map2_dfr(.x = modeling.folds$splits,
  #                               .y = modeling.folds$idfull,
  #                               ~model.prediction.folds(maxcomps = 20, split = .x, id = .y))
  
  future:::ClusterRegistry("stop")
  
  cat(paste0("CV predictions conclude in ", now(), "\n"))
  
  # Exporting results
  
  write.table(cv.results, paste0(dir.output,
                                 "tab_plsr_inst",
                                 iinstrument, "_",
                                 itrain, "_",
                                 isoil_property, "_",
                                 iprep_transfom, "_",
                                 iprep_spectra, ".csv"),
              row.names = F, col.names = T, sep = ",", dec = ".")
  
  cat(paste0("Exported results  - ", now(), "\n\n"))
  
  # Cleaning iteration and freeing memory
  
  keep.objects <- c("mnt.dir", "dir.preprocessed", "dir.output",
                    "metadata", "organization", "code", "new_codes",
                    "modeling.combinations")
  
  remove.objects <- ls()[-grep(paste(keep.objects, collapse = "|"), ls())]
  rm(list = remove.objects)
  gc()
  
}

