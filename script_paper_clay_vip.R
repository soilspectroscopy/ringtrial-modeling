
## Loading packages
library("tidyverse")
library("tidymodels")
library("lubridate")
library("readxl")
# library("mixOmics")

options(scipen = 999)

## Mounted disk for storing big files
mnt.dir <- "~/projects/mnt-ringtrial/"
dir.preprocessed <- paste0(mnt.dir, "preprocessed/")
dir.vip <- paste0(mnt.dir, "vip/")

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

## 10-fold cross-validation results

cv.performance <- read_csv(paste0("outputs/tab_int10CVrep10_PLSR_performance_metrics.csv"))

cv.performance <- cv.performance %>%
  filter(soil_property %in% c("clay_perc", "carbon_org_perc")) %>%
  filter(prep_spectra %in% c("BOC", "SNV"))

# ## Automated prediction
# 
# i=1
# 
# for(i in 1:nrow(cv.performance)) {
#   
#   # Iterators
#   
#   iinstrument <- cv.performance[[i,"organization"]]
#   isoil_property <- cv.performance[[i,"soil_property"]]
#   iprep_transfom <- cv.performance[[i,"prep_transform"]]
#   itrain <- unlist(cv.performance[[i,"train"]])
#   iprep_spectra <- cv.performance[[i,"prep_spectra"]]
#   icomponents <- cv.performance[[i,"components"]]
#   
#   cat(paste0("Run ", i, "/", nrow(cv.performance), " - ", now(), "\n"))
#   
#   # Modeling data
#   
#   soil.data <- read_csv(paste0(dir.preprocessed, "RT_wetchem_soildata.csv"), show_col_types = FALSE)
#   
#   spectra.columns <- as.character(seq(650, 4000, by = 2))
#   column.ids <- c("organization", "sample_id")
#   
#   # modeling.combinations %>%
#   #   distinct(spectra_prep) %>%
#   #   pull(spectra_prep)
#   
#   if(iprep_spectra == "wavelet") {
#     
#     preprocessed <- read_csv(paste0(dir.preprocessed, "RT_STD_allMIRspectra_wavelet.csv"), show_col_types = F) %>%
#       left_join(soil.data, by = "sample_id") %>%
#       filter(!is.na(!!as.name(isoil_property))) %>%
#       select(all_of(column.ids), all_of(isoil_property), starts_with("H9_")) %>%
#       mutate(organization = recode(organization, !!!new_codes)) %>%
#       mutate(organization = factor(organization, levels = as.character(new_codes))) %>%
#       filter(organization == iinstrument)
#     
#   } else {
#     
#     preprocessed <- read_csv(paste0(dir.preprocessed, "RT_STD_allMIRspectra_", iprep_spectra, ".csv"), show_col_types = F) %>%
#       left_join(soil.data, by = "sample_id") %>%
#       filter(!is.na(!!as.name(isoil_property))) %>%
#       select(all_of(column.ids), all_of(isoil_property), any_of(spectra.columns)) %>%
#       mutate(organization = recode(organization, !!!new_codes)) %>%
#       mutate(organization = factor(organization, levels = as.character(new_codes))) %>%
#       filter(organization == iinstrument)
#     
#   }
#   
#   gc()
#   cat(paste0("Modeling data imported in ", now(), "\n"))
#   
#   # Recipe model
#   
#   if(iprep_transfom == "withoutTransform") {
#     
#     recipe.model <- function(dataset){
#       dataset %>%
#         recipe() %>%
#         update_role(everything()) %>%
#         update_role(all_of(all_of(column.ids)), new_role = "id") %>%
#         update_role(all_of(isoil_property), new_role = "outcome") %>%
#         prep()
#     }
#     
#   } else if(iprep_transfom == "logTransform") {
#     
#     recipe.model <- function(dataset){
#       dataset %>%
#         recipe() %>%
#         update_role(everything()) %>%
#         update_role(all_of(all_of(column.ids)), new_role = "id") %>%
#         update_role(all_of(isoil_property), new_role = "outcome") %>%
#         step_log(all_outcomes()) %>%
#         prep()
#     }
#     
#   }
#   
#   # Preparing pls matrices
#   
#   training.outcome <- juice(recipe.model(preprocessed), composition = "matrix", all_outcomes())
#   
#   training.predictors <- juice(recipe.model(preprocessed), composition = "matrix", all_predictors())
#   
#   pls.model <- mixOmics::pls(training.predictors, training.outcome,
#                              ncomp = icomponents, scale = TRUE,
#                              mode = "regression")
#   
#   # Variable Importance in the Projection (VIP)
#   
#   vip.model <- mixOmics::vip(pls.model) %>%
#     as.data.frame() %>%
#     rownames_to_column(var = "wavenumber") %>%
#     as_tibble() %>%
#     mutate_all(as.numeric)
#   
#   # ggplot(vip.model) +
#   #   geom_line(aes(x = wavenumber, y = comp1, group = 1)) +
#   #   theme_light()
#   # 
#   # vip.model.wide <- vip.model %>%
#   #   pivot_longer(-wavenumber, names_to = "component", values_to = "vip") %>%
#   #   group_by(wavenumber) %>%
#   #   summarise(mean_vip = mean(vip), min_vip = min(vip),
#   #             max_vip = max(vip), .groups = "drop")
#   # 
#   # ggplot(vip.model.wide) +
#   #   geom_ribbon(aes(x = wavenumber, ymin = min_vip, ymax = max_vip),
#   #               fill = "grey70") +
#   #   geom_line(aes(x = wavenumber, y = mean_vip)) +
#   #   theme_light()
#   
#   vip.model <- vip.model %>%
#     mutate(organization = iinstrument,
#            soil_property = isoil_property,
#            prep_transform = iprep_transfom,
#            train = "fullSamplesCal",
#            prep_spectra = iprep_spectra,
#            .before = 1)
#   
#   # Exporting results
#   
#   write_csv(vip.model, paste0(dir.vip,
#                                  "tab_plsrVIP_inst",
#                                  iinstrument, "_",
#                                  "fullSamplesCal_",
#                                  isoil_property, "_",
#                                  iprep_transfom, "_",
#                                  iprep_spectra, ".csv"))
#   
#   cat(paste0("Exported results  - ", now(), "\n\n"))
#   
#   # Cleaning iteration and freeing memory
#   
#   keep.objects <- c("mnt.dir", "dir.preprocessed", "dir.vip",
#                     "metadata", "organization", "code", "new_codes",
#                     "cv.performance")
#   
#   remove.objects <- ls()[-grep(paste(keep.objects, collapse = "|"), ls())]
#   rm(list = remove.objects)
#   gc()
#   
# }

list.files(dir.vip)

listed.files <- list.files(dir.vip)

vip.list <- list()

i=1
for(i in 1:length(listed.files)) {
  
  vip.model <- read_csv(paste(dir.vip, listed.files[i], sep = "/"))
  
  id.columns <- c("organization", "soil_property", "prep_transform",
                  "train", "prep_spectra", "wavenumber")
  
  vip.model.long <- vip.model %>%
    pivot_longer(-all_of(id.columns), names_to = "component", values_to = "vip")
  
  vip.list[[i]] <- vip.model.long
  
}

vip.results <- Reduce(bind_rows, vip.list)

vip.results <- vip.results %>%
  select(-prep_transform, -train) %>%
  mutate(soil_property = recode(soil_property,
                                "carbon_org_perc" = "OC",
                                "clay_perc" = "Clay",
                                "pH_H20" = "pH",
                                "potassium_cmolkg" = "K")) %>%
  mutate(soil_property = factor(soil_property,
                                levels = c("OC",
                                           "Clay",
                                           "pH",
                                           "K")))

## All lines

vip.results %>%
  ggplot() +
  geom_line(aes(x = wavenumber, y = vip,
                group = interaction(organization, prep_spectra, component)), alpha = 0.05) +
  facet_grid(soil_property~prep_spectra) +
  theme_light() +
  theme(panel.grid.major = element_blank(),
        panel.grid.minor = element_blank());


## Shaded area

vip.results.summary <- vip.results %>%
  group_by(soil_property, prep_spectra, wavenumber) %>%
  summarise(median_vip = median(vip),
            iqr_vip = IQR(vip),
            p05_vip = quantile(vip, p=0.05),
            p95_vip = quantile(vip, p=0.95), .groups = "drop")

vip.results.summary <- vip.results.summary %>%
  mutate(soil_property = recode(soil_property,
                                "carbon_org_perc" = "OC",
                                "clay_perc" = "Clay",
                                "pH_H20" = "pH",
                                "potassium_cmolkg" = "K")) %>%
  mutate(soil_property = factor(soil_property,
                                levels = c("OC",
                                           "Clay",
                                           "pH",
                                           "K")))

# ggplot(vip.results.summary) +
#   geom_ribbon(aes(x = wavenumber,
#                   ymin = median_vip-iqr_vip,
#                   ymax = median_vip+iqr_vip),
#               fill = "grey70") +
#   facet_grid(soil_property~prep_spectra) +
#   geom_line(aes(x = wavenumber, y = median_vip)) +
#   theme_light()

p.vip <- ggplot(vip.results.summary) +
  geom_ribbon(aes(x = wavenumber,
                  ymin = median_vip-p05_vip,
                  ymax = median_vip+p95_vip),
              fill = "grey80") +
  facet_grid(soil_property~prep_spectra) +
  geom_line(aes(x = wavenumber, y = median_vip)) +
  scale_x_continuous(trans = "reverse") +
  labs(x = bquote(Wavenumber~(cm^-1)), y = "Variable Importance in the Projection (VIP)") +
  theme_light(); p.vip

ggsave("outputs/plot_paper_vip.png", p.vip,
       width = 8, height = 6, dpi = 300, scale = 1, units = "in")
