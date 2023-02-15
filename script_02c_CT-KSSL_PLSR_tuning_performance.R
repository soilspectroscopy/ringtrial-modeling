
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("qs")

## Folders
mnt.dir <- "~/mnt-ringtrial/"
# mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.predictions <- paste0(mnt.dir, "predictions/CT-KSSL_PLSR/")
dir.performance <- paste0(mnt.dir, "performance/")

## Modeling combinations
modeling.combinations <- read_csv("outputs/modeling_combinations_CT-KSSL_PLSR.csv")
modeling.combinations

## Reading predictions

predictions.list <- list()
i=1

for(i in 1:nrow(modeling.combinations)) {
  
  # Iterators
  
  isoil_property <- modeling.combinations[[i,"soil_property"]]
  iprep_transfom <- modeling.combinations[[i,"prep_transform"]]
  itrain <- unlist(modeling.combinations[[i,"train"]])
  iprep_spectra <- modeling.combinations[[i,"prep_spectra"]]
  
  # File
  
  predictions <- qread(paste0(dir.predictions,
                                 "tab_predictions_10CVrep1_",
                                 itrain, "_",
                                 isoil_property, "_",
                                 iprep_transfom, "_",
                                 iprep_spectra, ".qs"))
  
  predictions.performance <- predictions %>%
    pivot_longer(starts_with("prediction"), names_to = "components", values_to = "predicted") %>%
    mutate(predicted = as.numeric(predicted),
           observed = as.numeric(observed)) %>%
    group_by(components) %>%
    summarise(n = n(),
              rmse = rmse_vec(truth = observed, estimate = predicted),
              bias = msd_vec(truth = observed, estimate = predicted),
              rsq = rsq_vec(truth = observed, estimate = predicted),
              ccc = ccc_vec(truth = observed, estimate = predicted, bias = T),
              rpd = rpd_vec(truth = observed, estimate = predicted),
              rpiq = rpiq_vec(truth = observed, estimate = predicted),
              .groups = "drop") %>%
    mutate(components = as.numeric(gsub("prediction_|comp", "", components))) %>%
    filter(components >=5)
  
  predictions.list[[i]] <- predictions.performance %>%
    mutate(soil_property = isoil_property,
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
          paste0(dir.performance, "tab_CT-KSSL_PLSR_perf_components.csv"))

performance.metrics.best <- performance.metrics %>%
  group_by(soil_property, prep_transform, train, prep_spectra) %>%
  arrange(rmse) %>%
  summarise_all(first) %>%
  ungroup()

write_csv(performance.metrics.best,
          paste0("outputs/tab_CT-KSSL_PLSR_10CVrep1_performance_metrics.csv"))

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

ggsave(paste0("outputs/plot_CT-KSSL_PLSR_10CVrep1_performance_preprocessing.png"),
       p.metrics.preps, dpi = 300, width = 8, height = 7,
       units = "in", scale = 1)
