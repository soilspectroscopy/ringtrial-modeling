
## Loading packages
library("tidyverse")
library("lubridate")
library("readxl")

options(scipen = 999)

## Mounted disk for storing big files
mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.predictions <- paste0(mnt.dir, "predictions/int10CVrep10/")

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

# ## Files
# list.files("outputs")
# 
# perf.plsr <- read_csv("outputs/tab_CT-KSSL_PLSR_test_performance.csv") %>%
#   mutate(model_type = "plsr", .before = 1)
# 
# perf.mbl <- read_csv("outputs/tab_CT-KSSL_MBL_test_performance.csv") %>%
#   mutate(model_type = "mbl", .before = 1)
# 
# perf.cubist <- read_csv("outputs/tab_CT-KSSL_Cubist_test_performance.csv") %>%
#   mutate(model_type = "cubist", .before = 1)
# 
# performance <- bind_rows(perf.plsr, perf.mbl, perf.cubist)
# 
# unique(performance$prep_spectra)
# unique(performance$model_type)
# 
# performance <- performance %>%
#   mutate(prep_spectra = recode(prep_spectra, "SNVplusSG1stDer" = "SNV+SG1stDer")) %>%
#   mutate(prep_spectra = factor(prep_spectra,
#                                levels = c("raw",
#                                           "BOC",
#                                           "SG1stDer",
#                                           "SNV",
#                                           "SNV+SG1stDer",
#                                           "wavelet",
#                                           "SST"))) %>%
#   mutate(model_type = recode(model_type,
#                              "cubist" = "Cubist",
#                              "plsr" = "PLSR",
#                              "mbl" = "MBL")) %>%
#   mutate(model_type = factor(model_type,
#                              levels = c("PLSR",
#                                         "MBL",
#                                         "Cubist")))

## 10-fold cross-validation

cv.performance <- read_csv(paste0("outputs/tab_int10CVrep10_PLSR_performance_metrics.csv"))

## Check low ccc values for BOC

boc.check <- cv.performance %>%
  group_by(soil_property, organization) %>%
  mutate(average_ccc = median(ccc, na.rm = T), .before = ccc) %>%
  mutate(ccc_flag = ifelse(ccc <= average_ccc-0.1, TRUE, FALSE), .before = average_ccc) %>%
  ungroup()

# View(boc.check)

boc.check %>%
  filter(ccc_flag) %>%
  count(organization)

clip.boc.check <- boc.check %>%
  filter(ccc_flag) %>%
  count(organization)

# clipr::write_clip(clip.boc.check)
#   organization     n
# 1            4     2: Argonne - PerkinElmer Spectrum 100
# 2            6     3: AgroCares - Alpha I
# 3            9     1: IAEA - Thermo Fisher Nicolet
# 4           12     1: UIUC - Termo Fisher Nicolet
# 5           14     1: OSU - Thermo Fisher Nicolet
# 6           15     2: ETHZ-SAE - Alpha II
# 7           16     1: KSSL - Vertex 70
# 8           17     1: CSU-SoIL - Bruker Invenio-R
# 9           19     2: Rothamsted - Bruker Tensor II

## Checking BOC spectra

soil.data <- read_csv(paste0(dir.preprocessed, "RT_wetchem_soildata.csv"), show_col_types = FALSE)

preprocessed <- read_csv(paste0(dir.preprocessed, "RT_STD_allMIRspectra_BOC.csv"), show_col_types = F) %>%
  # left_join(soil.data, by = "sample_id") %>%
  mutate(organization = recode(organization, !!!new_codes)) %>%
  mutate(organization = factor(organization, levels = as.character(new_codes)))

# Visualization of instrument 6
iorganization <- 6
preprocessed %>%
  filter(organization == iorganization) %>%
  pivot_longer(-all_of(c("organization", "sample_id")), names_to = "wavenumber", values_to = "absorbance") %>%
  ggplot(aes(x = as.numeric(wavenumber), y = absorbance, group = sample_id)) +
  labs(x = bquote(Wavenumber~(cm^-1)), y = bquote(Absorbance~(log[10]~units))) +
  scale_x_continuous(breaks = c(650, 1200, 1800, 2400, 3000, 3600, 4000),
                     trans = "reverse") +
  geom_line(alpha = 0.25) +
  # labs(title = paste0("MIR return for instrument ", iorganization, ", BOC preprocessing")) +
  theme_light()

preprocessed.baseline <- preprocessed %>%
  rowwise(organization, sample_id) %>%
  summarise(baseline = names(preprocessed)[which.min(c_across(everything()))]) %>%
  ungroup()

preprocessed.baseline %>%
  filter(organization == iorganization) %>%
  count(organization, baseline)

clip.preprocessed.baseline <- preprocessed.baseline %>%
  filter(organization == iorganization) %>%
  count(organization, baseline)

clipr::write_clip(clip.preprocessed.baseline)

# all instruments with BOC issue

preprocessed.baseline %>%
  filter(organization %in% c(4, 5, 6, 15, 16, 19)) %>%
  count(organization, baseline) %>%
  View()

## Checking predictions

modeling.combinations <- read_csv("outputs/modeling_combinations_int10CVrep10_PLSR.csv")
modeling.combinations

iinstrument <- 6
list.files(dir.predictions)
predictions1 <- read_csv(paste0(dir.predictions,
                                "tab_plsr_inst",
                                iinstrument, "_",
                                "int10CVrep10_",
                                "clay_perc_",
                                "withoutTransform_",
                                "BOC.csv"),
                         col_types = cols())

predictions1 %>%
  ggplot(aes(x = observed, y = prediction_20comp)) +
  geom_point() + theme_light()

predictions1 %>%
  ggplot(aes(x = log10(prediction_20comp))) +
  geom_histogram()  + theme_light()

predictions1 %>%
  filter(prediction_20comp > 100) %>%
  count(sample_id)

predictions1 %>%
  filter(prediction_20comp < 0) %>%
  count(sample_id)

selected.ids <- predictions1 %>%
  filter(prediction_20comp < 0) %>%
  count(sample_id) %>%
  pull(sample_id) %>%
  c("RT_44")

preprocessed.baseline %>%
  filter(organization == 6) %>%
  count(organization, baseline)

preprocessed.baseline %>%
  filter(sample_id %in% selected.ids) %>%
  filter(organization == 6)
  