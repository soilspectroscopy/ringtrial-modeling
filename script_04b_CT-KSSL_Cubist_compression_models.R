
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("readxl")
library("qs")

## Folders
# mnt.dir <- "~/projects/mnt-ringtrial/"
mnt.dir <- "~/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.pca <- paste0(mnt.dir, "pca/")

## Modeling combinations
modeling.combinations <- read_csv("outputs/modeling_combinations_CT-KSSL_Cubist.csv")
modeling.combinations

# Wavelet is already compressed
# SST specta is actually SNV preprocessed
modeling.combinations <- modeling.combinations %>%
  filter(!(prep_spectra %in% c("wavelet", "SST")))

## Automation

i=1
for(i in 1:nrow(modeling.combinations)) {
  
  # Iterators
  
  itrain <- unlist(modeling.combinations[[i,"train"]])
  iprep_spectra <- modeling.combinations[[i,"prep_spectra"]]
  isoil_property <- modeling.combinations[[i,"soil_property"]]
  
  # We need to use soil property because each soil property has it own spectra
  cat(paste0("Running iteration ", paste0(i, "/", nrow(modeling.combinations)),
             ", ", itrain,
             ", ", iprep_spectra,
             ", ", isoil_property,
             " at ", now(),
             "\n"))
  
  # Loading dataset inside loop for memory management
  
  spectra.columns <- as.character(seq(650, 4000, by = 2))
  column.ids <- c("sample_id")
  
  if(iprep_spectra == "SST") {
    
    # SST specta is actually SNV preprocessed. Only RTs are aligned to KSSL SNV
    preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_SNV.qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(all_of(column.ids), all_of(isoil_property), any_of(spectra.columns))
    
  } else {
    
    preprocessed <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_", iprep_spectra, ".qs")) %>%
      filter(!is.na(!!as.name(isoil_property))) %>%
      select(all_of(column.ids), all_of(isoil_property), any_of(spectra.columns))
    
  }
  
  cat(paste0("Imported data at ", now(), "\n"))
  
  # Reference PC space
  
  pca.model <- preprocessed %>%
    recipe() %>%
    update_role(everything()) %>%
    update_role(any_of(column.ids), new_role = "id") %>%
    update_role(any_of(isoil_property), new_role = "outcome") %>%
    step_normalize(all_predictors(), id = "normalization") %>% # Center and scale spectra
    step_pca(all_predictors(), threshold = 0.9999, id = "pca") %>% # 99.99% of cumvar
    prep()
  
  # Exporting model
  
  qsave(pca.model, paste0(dir.pca,
                          "pca_model_normalized_cumvar99dot99_",
                          itrain, "_",
                          isoil_property, "_",
                          iprep_spectra, ".qs"))
  
  cat(paste0("Exported results at ", now(), "\n\n"))
  
  # Cleaning iteration and freeing memory
  
  keep.objects <- c("mnt.dir", "dir.preprocessed", "dir.pca",
                    "modeling.combinations")
  
  remove.objects <- ls()[-grep(paste(keep.objects, collapse = "|"), ls())]
  rm(list = remove.objects)
  gc()
  
}
