
## Loading packages
library("tidyverse")
library("readxl")
library("purrr")
library("prospectr")

## Folders
# mnt.dir <- "~/projects/mnt-ringtrial/"
mnt.dir <- "~/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.output <- "outputs/"

## Modeling combinations

soil.properties <- c("clay_perc", "pH_H20", "carbon_org_perc", "potassium_cmolkg")
train.spectra <- c("CT-KSSL")
prep.spectra <- c("raw", "BOC", "SG1stDer", "SNV", "SNVplusSG1stDer", "wavelet", "SST")

combinations <- tibble(soil_property = soil.properties) %>%
  crossing(train = train.spectra) %>%
  crossing(prep_spectra = prep.spectra)

combinations

combinations <- combinations %>%
  mutate(prep_transform = case_when(soil_property == "carbon_org_perc" ~ "logTransform",
                                    soil_property == "potassium_cmolkg" ~ "logTransform",
                                    TRUE ~ "withoutTransform"), .after = soil_property)

combinations

write_csv(combinations, "outputs/modeling_combinations_CT-KSSL_Cubist.csv")
