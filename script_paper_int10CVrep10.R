
## Loading packages
library("tidyverse")
library("scales")

## Folders
mnt.dir <- "~/mnt-ringtrial/"

## Load data
performance.metrics.best <- read_csv(paste0("outputs/tab_int10CVrep10_PLSR_performance_metrics.csv"))

performance.metrics.best <- performance.metrics.best %>%
  mutate(prep_spectra = recode(prep_spectra, "SNVplusSG1stDer" = "SNV+SG1stDer")) %>%
  mutate(prep_spectra = factor(prep_spectra,
                               levels = c("raw",
                                          "BOC",
                                          "SG1stDer",
                                          "SNV",
                                          "SNV+SG1stDer",
                                          "wavelet",
                                          "SST"))) %>%
  mutate(soil_property = recode(soil_property,
                                "carbon_org_perc" = "OC",
                                "clay_perc" = "Clay",
                                "pH_H20" = "pH",
                                "potassium_cmolkg" = "K")) %>%
  filter(!(prep_spectra == "wavelet")) %>%
  mutate(soil_property = factor(soil_property,
                                levels = c("OC",
                                           "Clay",
                                           "pH",
                                           "K")))

performance.metrics.best

## Visualization

p.metrics.inst <- performance.metrics.best %>%
  mutate(organization = as.factor(organization)) %>%
  select(organization, soil_property, prep_spectra, ccc) %>%
  ggplot() +
  geom_col(aes(x = organization, y = ccc, fill = prep_spectra),
           width=.85, position = "dodge", show.legend = T) +
  labs(x = "Instrument", y = "Lin's CCC", fill = "") + facet_wrap(~soil_property, ncol = 1) +
  scale_y_continuous(labels = number_format(accuracy = 0.01)) +
  scale_fill_manual(values = c("gray20", "gray35", "gray50", "gray65", "gray80")) +
  theme_light() +
  theme(legend.position = "bottom") +
  guides(fill = guide_legend(nrow = 1, byrow = TRUE)); p.metrics.inst

ggsave(paste0("outputs/plot_paper_int10CVrep10_performance.png"),
       p.metrics.inst, dpi = 300, width = 7, height = 8,
       units = "in", scale = 1)
