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
mnt.dir <- "~/mnt-ringtrial/"
# mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.predictions <- paste0(mnt.dir, "predictions/int10CVrep10/")
dir.performance <- paste0(mnt.dir, "performance/")

## Number of cores available
n.cores <- 30

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

## Reading predictions

predictions.list <- list()
i=1

for(i in 1:nrow(modeling.combinations)) {
  
  # Iterators
  
  iinstrument <- modeling.combinations[[i,"instrument"]]
  isoil_property <- modeling.combinations[[i,"soil_property"]]
  iprep_transfom <- modeling.combinations[[i,"prep_transform"]]
  itrain <- unlist(modeling.combinations[[i,"train"]])
  iprep_spectra <- modeling.combinations[[i,"prep_spectra"]]
  
  # File
  
  predictions <- read_csv(paste0(dir.predictions,
                                 "tab_plsr_inst",
                                 iinstrument, "_",
                                 itrain, "_",
                                 isoil_property, "_",
                                 iprep_transfom, "_",
                                 iprep_spectra, ".csv"),
                          col_types = cols())
  
  predictions.performance <- predictions %>%
    separate(id, into = c("rep", "fold")) %>%
    pivot_longer(starts_with("prediction"), names_to = "components", values_to = "predicted") %>%
    mutate(predicted = as.numeric(predicted),
           observed = as.numeric(observed)) %>%
    group_by(rep, components) %>%
    summarise(n = n(),
              rmse = rmse_vec(truth = observed, estimate = predicted),
              bias = msd_vec(truth = observed, estimate = predicted),
              rsq = rsq_vec(truth = observed, estimate = predicted),
              ccc = ccc_vec(truth = observed, estimate = predicted, bias = T),
              rpd = rpd_vec(truth = observed, estimate = predicted),
              rpiq = rpiq_vec(truth = observed, estimate = predicted),
              .groups = "drop") %>%
    mutate(components = as.numeric(gsub("prediction_|comp", "", components))) %>%
    group_by(components) %>%
    summarise_if(is.numeric, mean) %>%
    filter(components >=5)
  
  predictions.list[[i]] <- predictions.performance %>%
    mutate(organization = iinstrument,
           soil_property = isoil_property,
           prep_transform = iprep_transfom,
           train = itrain,
           prep_spectra = iprep_spectra,
           .before = 1)
  
  cat(paste0("Iteration ", paste0(i, "/", nrow(modeling.combinations)),
             paste0(" - estimated performance metrics - ", now(), "\n")))
  
}

## Exporting summary of prediction performance

performance.metrics <- Reduce(bind_rows, predictions.list)

write_csv(performance.metrics,
          paste0(dir.performance, "tab_int10CVrep10_perf_instruments_components.csv"))

performance.metrics.best <- performance.metrics %>%
  group_by(organization, soil_property, prep_transform, train, prep_spectra) %>%
  arrange(rmse) %>%
  summarise_all(first) %>%
  ungroup()

write_csv(performance.metrics.best,
          paste0("outputs/tab_int10CVrep10_performance_metrics.csv"))

## Visualization

p.metrics.inst <- performance.metrics.best %>%
  mutate(organization = as.factor(organization)) %>%
  select(organization, soil_property, prep_spectra, ccc) %>%
  ggplot() +
  geom_col(aes(x = organization, y = ccc, fill = prep_spectra),
           width=.5, position = "dodge", show.legend = T) +
  labs(x = "", y = "Lin's CCC", fill = "") + facet_wrap(~soil_property, ncol = 1) +
  scale_y_continuous(labels = number_format(accuracy = 0.01)) +
  theme_light() +
  theme(legend.position = "bottom") +
  guides(fill = guide_legend(nrow = 1, byrow = TRUE)); p.metrics.inst

ggsave(paste0("outputs/plot_int10CVrep10_performance_instruments.png"),
       p.metrics.inst, dpi = 300, width = 8, height = 7,
       units = "in", scale = 1)
