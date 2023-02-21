
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("purrr")
library("qs")

options(scipen = 999)

## Folders
# mnt.dir <- "~/projects/mnt-ringtrial/"
mnt.dir <- "~/mnt-ringtrial/"
dir.predictions <- paste0(mnt.dir, "predictions/CT-KSSL_Cubist/")
dir.hyperparameters <- paste0(mnt.dir, "performance/cubist_hyperparameters/")
dir.performance <- paste0(mnt.dir, "performance/")

## Modeling combinations
modeling.combinations <- read_csv("outputs/modeling_combinations_CT-KSSL_Cubist.csv")
modeling.combinations

## Hyperparameters
list.files(dir.hyperparameters)

all.hyperparameters <- list.files(dir.hyperparameters,
                                  pattern = "tab_all_hp", full.names = T) %>%
  map_dfr(., qread)

write_csv(all.hyperparameters,
          paste0(dir.performance, "tab_CT-KSSL_Cubist_perf_hyperparameters.csv"))

all.hyperparameters %>%
  mutate(neighbors = as.factor(neighbors),
         prep_transform = as.factor(prep_transform)) %>%
  filter(soil_property == "carbon_org_perc") %>%
  ggplot() +
  geom_line(aes(x = committees, y = rmse, color = neighbors,
                group = neighbors)) +
  facet_wrap(~prep_spectra, ncol = 2) +
  labs(title = "carbon_org_perc") +
  theme_light() +
  theme(legend.position = "bottom")

all.hyperparameters %>%
  mutate(neighbors = as.factor(neighbors),
         prep_transform = as.factor(prep_transform)) %>%
  filter(soil_property == "pH_H20") %>%
  ggplot() +
  geom_line(aes(x = committees, y = rmse, color = neighbors,
                group = neighbors)) +
  facet_wrap(~prep_spectra, ncol = 2) +
  labs(title = "pH_H20") +
  theme_light() +
  theme(legend.position = "bottom")

## Reading predictions for calculating extra metrics

predictions.list <- list()
i=8

for(i in 1:nrow(modeling.combinations)) {
  
  # Iterators
  
  isoil_property <- modeling.combinations[[i,"soil_property"]]
  iprep_transform <- modeling.combinations[[i,"prep_transform"]]
  itrain <- unlist(modeling.combinations[[i,"train"]])
  iprep_spectra <- modeling.combinations[[i,"prep_spectra"]]
  
  # File
  
  predictions <- qread(paste0(dir.predictions,
                              "tab_predictions_10CVrep1_",
                              itrain, "_",
                              isoil_property, "_",
                              iprep_transform, "_",
                              iprep_spectra, ".qs"))
  
  predictions.performance <- predictions %>%
    group_by(committees, neighbors) %>%
    summarise(n = n(),
              rmse = rmse_vec(truth = observed, estimate = predicted),
              bias = msd_vec(truth = observed, estimate = predicted),
              rsq = rsq_vec(truth = observed, estimate = predicted),
              ccc = ccc_vec(truth = observed, estimate = predicted, bias = T),
              rpd = rpd_vec(truth = observed, estimate = predicted),
              rpiq = rpiq_vec(truth = observed, estimate = predicted),
              .groups = "drop")
  
  predictions.list[[i]] <- predictions.performance %>%
    mutate(soil_property = isoil_property,
           prep_transform = iprep_transform,
           train = itrain,
           prep_spectra = iprep_spectra,
           .before = 1)
  
  cat(paste0("Iteration ", paste0(i, "/", nrow(modeling.combinations)),
             paste0(" - estimated performance metrics - ", now(), "\n")))
  
}

performance.metrics <- Reduce(bind_rows, predictions.list)

write_csv(performance.metrics,
          "outputs/tab_CT-KSSL_Cubist_10CVrep1_performance_metrics.csv")

## Visualization

p.metrics.preps <- performance.metrics %>%
  select(soil_property, prep_spectra, ccc) %>%
  ggplot() +
  geom_col(aes(x = soil_property, y = ccc, fill = prep_spectra),
           width = 0.95, position = "dodge", show.legend = T) +
  labs(x = "", y = "Lin's CCC", fill = "") +
  scale_y_continuous(labels = number_format(accuracy = 0.01)) +
  theme_light() +
  theme(legend.position = "bottom") +
  coord_flip() +
  guides(fill = guide_legend(nrow = 1, byrow = TRUE)); p.metrics.preps

ggsave(paste0("outputs/plot_CT-KSSL_Cubist_10CVrep1_performance_preprocessing.png"),
       p.metrics.preps, dpi = 300, width = 8, height = 7,
       units = "in", scale = 1)
