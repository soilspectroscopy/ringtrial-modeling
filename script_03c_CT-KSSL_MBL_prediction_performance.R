
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("qs")

## Folders
mnt.dir <- "~/mnt-ringtrial/"
# mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.predictions <- paste0(mnt.dir, "predictions/CT-KSSL_MBL/")

## Modeling combinations
modeling.combinations <- read_csv("outputs/tab_CT-KSSL_PLSR_10CVrep1_performance_metrics.csv")
modeling.combinations

test.ids <- qread("outputs/RT_test_ids.qs")

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
  
  if(iprep_spectra == "SST") {
    
    predictions <- qread(paste0(dir.predictions,
                                "tab_predictions_",
                                itrain, "_MBL_",
                                isoil_property, "_",
                                iprep_transfom, "_",
                                iprep_spectra, ".qs")) %>%
      filter(sample_id %in% test.ids)
    
    predictions.performance <- predictions %>%
      group_by(organization, ct_subset, diss_method, k_diss) %>%
      summarise(n = n(),
                rmse = rmse_vec(truth = observed, estimate = predicted),
                bias = msd_vec(truth = observed, estimate = predicted),
                rsq = rsq_vec(truth = observed, estimate = predicted),
                ccc = ccc_vec(truth = observed, estimate = predicted, bias = T),
                rpd = rpd_vec(truth = observed, estimate = predicted),
                rpiq = rpiq_vec(truth = observed, estimate = predicted),
                .groups = "drop") %>%
      group_by(organization, ct_subset) %>%
      summarise(across(all_of(c("n", "rmse", "bias", "rsq", "ccc", "rpd", "rpiq")),
                       mean), .groups = "drop")
    
  } else {
    
    predictions <- qread(paste0(dir.predictions,
                                "tab_predictions_",
                                itrain, "_MBL_",
                                isoil_property, "_",
                                iprep_transfom, "_",
                                iprep_spectra, ".qs")) %>%
      filter(sample_id %in% test.ids)
    
    predictions.performance <- predictions %>%
      group_by(organization, diss_method, k_diss) %>%
      summarise(n = n(),
                rmse = rmse_vec(truth = observed, estimate = predicted),
                bias = msd_vec(truth = observed, estimate = predicted),
                rsq = rsq_vec(truth = observed, estimate = predicted),
                ccc = ccc_vec(truth = observed, estimate = predicted, bias = T),
                rpd = rpd_vec(truth = observed, estimate = predicted),
                rpiq = rpiq_vec(truth = observed, estimate = predicted),
                .groups = "drop") %>%
      group_by(organization) %>%
      summarise(across(all_of(c("n", "rmse", "bias", "rsq", "ccc", "rpd", "rpiq")),
                       mean), .groups = "drop")
    
  }
  
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

performance.metrics <- Reduce(bind_rows, predictions.list) %>%
  relocate(ct_subset, .after = organization) %>%
  mutate(ct_subset = ifelse(is.na(ct_subset), "original", ct_subset))

performance.metrics <- performance.metrics %>%
  filter(!(ct_subset %in% c("beforeSST"))) %>%
  select(-ct_subset)

performance.metrics %>%
  select(all_of(c("n", "rmse", "bias", "rsq", "ccc", "rpd", "rpiq"))) %>%
  summarise_all(function(x) {sum(is.na(x))})

write_csv(performance.metrics,
          paste0("outputs/tab_CT-KSSL_MBL_test_performance.csv"))

## Visualization

data <- read_csv(paste0("outputs/tab_CT-KSSL_MBL_test_performance.csv"))

p.ccc <- ggplot(data) +
  geom_boxplot(aes(x = prep_spectra, y = ccc, color = prep_spectra),
               show.legend = F) +
  facet_wrap(~soil_property, ncol = 1) +
  labs(x = "", y = "Lin's CCC", color = "") +
  ylim(-0.2, 1) +
  coord_flip() +
  theme_light() +
  theme(legend.position = "bottom"); p.ccc

ggsave(paste0("outputs/plot_CT-KSSL_MBL_test_performance.png"),
       p.ccc, dpi = 300, width = 8, height = 7,
       units = "in", scale = 1)
