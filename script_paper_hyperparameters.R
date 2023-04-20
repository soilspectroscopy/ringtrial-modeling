
library("tidyverse")
library("clipr")

plsr.10cv.perf <- read_csv("outputs/tab_CT-KSSL_PLSR_10CVrep1_performance_metrics.csv")
plsr.10cv.perf

# plsr.10cv.perf %>%
#   mutate(model_type = "PLSR", .before = 1) %>%
#   select(soil_property, prep_spectra, components, rmse, bias, rsq, ccc, rpiq) %>%
#   mutate_if(is.numeric, round, 3) %>%
#   write_clip()

cubist.10cv.perf <- read_csv("outputs/tab_CT-KSSL_Cubist_10CVrep1_performance_metrics.csv")
cubist.10cv.perf

# cubist.10cv.perf %>%
#   mutate(model_type = "Cubist", .before = 1) %>%
#   select(soil_property, prep_spectra, committees, neighbors, rmse, bias, rsq, ccc, rpiq) %>%
#   mutate_if(is.numeric, round, 3) %>%
#   write_clip()
