
## Loading packages

library("tidyverse")
library("readr")
library("qs")

## Mounted disk for storing big files
mnt.dir <- "~/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
list.files(dir.preprocessed)

## Load data

# RT spectra
wavelet.rt <- read_csv(paste0(dir.preprocessed, "RT_STD_allMIRspectra_wavelet.csv"))

set.seed(1993)
wavelet.rt.rescaled <- wavelet.rt %>%
  select(organization, sample_id, starts_with("H9_")) %>%
  sample_n(100) %>%
  pivot_longer(-all_of(c("sample_id", "organization")),
               names_to = "haar_levels", values_to = "value") %>%
  separate(haar_levels, into = c("trend", "flux"), sep = "_") %>%
  mutate(trend = factor(trend, levels = paste0("H", seq(0, 11, 1)))) %>%
  mutate(flux = as.numeric(gsub("I", "", flux))) %>%
  group_by(sample_id, trend) %>%
  mutate(flux_scaled = flux/max(flux))

ggplot(wavelet.rt.rescaled) +
  geom_line(aes(x = flux_scaled, y = value, group = sample_id), show.legend = F, alpha = 0.25) +
  geom_point(aes(x = flux_scaled, y = value, group = sample_id), show.legend = F, size = 0.1, alpha = 0.25) +
  labs(x = "Relative index", y = "Intensity") +
  scale_x_continuous(breaks = c(0, 0.25, 0.5, 0.75, 1),
                     trans = "reverse") +
  theme_light()

# KSSL spectra
wavelet.kssl <- qread(paste0(dir.preprocessed, "KSSL_soilMIRspectra_wavelet.qs"))

set.seed(1993)
wavelet.kssl.rescaled <- wavelet.kssl %>%
  select(sample_id, starts_with("H9_")) %>%
  sample_n(100) %>%
  pivot_longer(-all_of(c("sample_id")),
               names_to = "haar_levels", values_to = "value") %>%
  separate(haar_levels, into = c("trend", "flux"), sep = "_") %>%
  mutate(trend = factor(trend, levels = paste0("H", seq(0, 11, 1)))) %>%
  mutate(flux = as.numeric(gsub("I", "", flux))) %>%
  group_by(sample_id, trend) %>%
  mutate(flux_scaled = flux/max(flux))

ggplot(wavelet.kssl.rescaled) +
  geom_line(aes(x = flux_scaled, y = value, group = sample_id), show.legend = F, alpha = 0.25) +
  geom_point(aes(x = flux_scaled, y = value, group = sample_id), show.legend = F, size = 0.1, alpha = 0.25) +
  labs(x = "Relative index", y = "Intensity") +
  scale_x_continuous(breaks = c(0, 0.25, 0.5, 0.75, 1),
                     trans = "reverse") +
  theme_light()
