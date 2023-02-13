
## Loading packages
library("tidyverse")
library("readxl")
library("purrr")
library("prospectr")

## Folders
mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")

dir.output <- "outputs/"

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

soil.properties <- c("clay_perc", "pH_H20", "carbon_org_perc", "potassium_cmolkg")
train.spectra <- c("int10CVrep10")
prep.spectra <- c("raw", "BOC", "SG1stDer", "SNV", "SNVplusSG1stDer", "wavelet")

combinations <- tibble(instrument = codes) %>%
  crossing(soil_property = soil.properties) %>%
  crossing(train = train.spectra) %>%
  crossing(prep_spectra = prep.spectra)

combinations

combinations <- combinations %>%
  mutate(prep_transform = case_when(soil_property == "carbon_org_perc" ~ "logTransform",
                                    soil_property == "potassium_cmolkg" ~ "logTransform",
                                    TRUE ~ "withoutTransform"), .after = soil_property)

combinations

write_csv(combinations, "outputs/modeling_combinations_int10CVrep10_PLSR.csv")
