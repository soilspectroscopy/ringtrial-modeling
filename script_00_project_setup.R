## Loading packages
library("tidyverse")

## Creating input/output dirs
if(!dir.exists("outputs")){dir.create("outputs")}

## Mounted disck for storing big files
# mnt.dir <- "~/projects/mnt-ringtrial/"
mnt.dir <- "~/mnt-ringtrial/"

## Creating predictions folder
if(!dir.exists(paste0(mnt.dir, "predictions"))){dir.create(paste0(mnt.dir, "predictions"))}
if(!dir.exists(paste0(mnt.dir, "predictions/int10CVrep10"))){dir.create(paste0(mnt.dir, "predictions/int10CVrep10"))}
if(!dir.exists(paste0(mnt.dir, "predictions/CT-KSSL_PLSR"))){dir.create(paste0(mnt.dir, "predictions/CT-KSSL_PLSR"))}
if(!dir.exists(paste0(mnt.dir, "predictions/CT-KSSL_MBL"))){dir.create(paste0(mnt.dir, "predictions/CT-KSSL_MBL"))}

## Creating performance folder
if(!dir.exists(paste0(mnt.dir, "performance"))){dir.create(paste0(mnt.dir, "performance"))}

## Copying map and summary statistics tables
prep.dir <- "~/projects/soilspec4gg-mac/ringtrial-prep/"
eda.dir <- "~/projects/soilspec4gg-mac/ringtrial-eda/"

map.file <- paste0(eda.dir, "outputs/map_ring_trial.png")
distribution.plot.file <- paste0(prep.dir, "outputs/sst_subsets/plot_soil_properties_distribution.png")
summary.original.file <- paste0(eda.dir, "outputs/RT_wetchem_summary_beforeLog.csv")
summary.log.file  <- paste0(eda.dir, "outputs/RT_wetchem_summary_afterLog.csv")

file.copy(from = map.file, to = paste0("outputs/", basename(map.file)), overwrite = T)
file.copy(from = distribution.plot.file, to = paste0("outputs/", basename(distribution.plot.file)), overwrite = T)
file.copy(from = summary.original.file, to = paste0("outputs/", basename(summary.original.file)), overwrite = T)
file.copy(from = summary.log.file, to = paste0("outputs/", basename(summary.log.file)), overwrite = T)

## Copying list of test ids
sst.ids <- paste0(prep.dir, "outputs/sst_subsets/RT_sst_ids.qs")
test.ids <- paste0(prep.dir, "outputs/sst_subsets/RT_test_ids.qs")
