# Sys.setenv(TRIAL = "hvtn705")
#-----------------------------------------------
# obligatory to append to the top of each script
renv::activate(project = here::here(".."))

# There is a bug on Windows that prevents renv from working properly. The following code provides a workaround:
if (.Platform$OS.type == "windows") .libPaths(c(paste0(Sys.getenv ("R_HOME"), "/library"), .libPaths()))

source(here::here("..", "_common.R"))
#-----------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
job_id <- as.numeric(args[2])

## load required libraries 
suppressPackageStartupMessages(library(tidyverse, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(tidyr, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(purrr, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(dplyr, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(stringr, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(quadprog, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(here, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(methods, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(SuperLearner, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(e1071, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(glmnet, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(kyotil, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(argparse, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(vimp, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(nloptr, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(RhpcBLASctl, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(reticulate, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(FSDAM, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(ranger, warn.conflicts = FALSE))
suppressPackageStartupMessages(library(xgboost, warn.conflicts = FALSE))
suppressPackageStartupMessages(library(conflicted, warn.conflicts = FALSE))
suppressMessages(conflicted::conflict_prefer("filter", "dplyr"))
suppressMessages(conflict_prefer("summarise", "dplyr"))


# Define code version to run
# the demo version is simpler and runs faster!
# the production version runs SL with a diverse set of learners
run_prod <- !grepl("Mock", study_name)

# load required files and functions 
source(here("code", "day57or29analyses.R")) # set up analyses for markers
source(here("code", "sl_screens.R")) # set up the screen/algorithm combinations
source(here("code", "utils.R")) # get CV-AUC for all algs

# SL optimal surrogate analysis: Superlearner code requires computing environment with more than 10 cores!
num_cores <- parallel::detectCores()
# if(num_cores < 10) stop("Number of cores on this computing environment are less than 10! Superlearner code needs atleast 11 cores to run smoothly.")

############ SETUP INPUT #######################
# Read data_clean
if(study_name %in% c("COVE", "MockCOVE")){
  briskfactors <- c("risk_score", "HighRiskInd", "MinorityInd")
  briskfactors_correction <- "Y ~ x + X$risk_score + X$HighRiskInd + X$MinorityInd"
  
  markerVars <- c("Day57bindSpike", "Delta57overBbindSpike", "Delta57overBbindSpike_2fold", "Delta57overBbindSpike_4fold",
                    "Day57bindRBD", "Delta57overBbindRBD", "Delta57overBbindRBD_2fold", "Delta57overBbindRBD_4fold",
                    "Day57pseudoneutid50", "Delta57overBpseudoneutid50", "Delta57overBpseudoneutid50_2fold", "Delta57overBpseudoneutid50_4fold",
                    "Day57pseudoneutid80", "Delta57overBpseudoneutid80", "Delta57overBpseudoneutid80_2fold", "Delta57overBpseudoneutid80_4fold", 
                    
                    "Day29bindSpike", "Delta29overBbindSpike", "Delta29overBbindSpike_2fold", "Delta29overBbindSpike_4fold",
                    "Day29bindRBD", "Delta29overBbindRBD", "Delta29overBbindRBD_2fold", "Delta29overBbindRBD_4fold",
                    "Day29pseudoneutid50", "Delta29overBpseudoneutid50", "Delta29overBpseudoneutid50_2fold", "Delta29overBpseudoneutid50_4fold",
                    "Day29pseudoneutid80", "Delta29overBpseudoneutid80", "Delta29overBpseudoneutid80_2fold", "Delta29overBpseudoneutid80_4fold")
  
  # Identify the endpoint variable
  endpoint <- "EventIndPrimaryD57"
  wt <- "wt.D57"
  
  # Create combined new dataset which has imputed values of demographics (for phase 1 data) from dat.covar.imp AND 
  # imputed values for markers (for phase 2 data) from dat.wide.v
  dat.ph1 <- dat.mock %>%
    filter(Perprotocol == 1 & Trt == 1 & Bserostatus == 0) %>% 
    mutate(Delta57overBbindSpike_2fold = ifelse(Day57bindSpike > (BbindSpike + log10(2)), 1, 0),
           Delta57overBbindSpike_4fold = ifelse(Day57bindSpike > (BbindSpike + log10(4)), 1, 0),
           Delta57overBbindRBD_2fold = ifelse(Day57bindRBD > (BbindRBD  + log10(2)), 1, 0),
           Delta57overBbindRBD_4fold = ifelse(Day57bindRBD > (BbindRBD  + log10(4)), 1, 0),
           Delta57overBpseudoneutid50_2fold = ifelse(Day57pseudoneutid50 > (Bpseudoneutid50  + log10(2)), 1, 0), 
           Delta57overBpseudoneutid50_4fold = ifelse(Day57pseudoneutid50 > (Bpseudoneutid50  + log10(4)), 1, 0), 
           Delta57overBpseudoneutid80_2fold = ifelse(Day57pseudoneutid80 > (Bpseudoneutid80  + log10(2)), 1, 0), 
           Delta57overBpseudoneutid80_4fold = ifelse(Day57pseudoneutid80 > (Bpseudoneutid80  + log10(4)), 1, 0),
           
           Delta29overBbindSpike_2fold = ifelse(Day29bindSpike > (BbindSpike + log10(2)), 1, 0),
           Delta29overBbindSpike_4fold = ifelse(Day29bindSpike > (BbindSpike + log10(4)), 1, 0),
           Delta29overBbindRBD_2fold = ifelse(Day29bindRBD > (BbindRBD  + log10(2)), 1, 0),
           Delta29overBbindRBD_4fold = ifelse(Day29bindRBD > (BbindRBD  + log10(4)), 1, 0),
           Delta29overBpseudoneutid50_2fold = ifelse(Day29pseudoneutid50 > (Bpseudoneutid50  + log10(2)), 1, 0), 
           Delta29overBpseudoneutid50_4fold = ifelse(Day29pseudoneutid50 > (Bpseudoneutid50  + log10(4)), 1, 0), 
           Delta29overBpseudoneutid80_2fold = ifelse(Day29pseudoneutid80 > (Bpseudoneutid80  + log10(2)), 1, 0), 
           Delta29overBpseudoneutid80_4fold = ifelse(Day29pseudoneutid80 > (Bpseudoneutid80  + log10(4)), 1, 0)) %>%
    # Drop any observation with NA values in Ptid, Trt, briskfactors, endpoint and wt.D57
    drop_na(Ptid, Trt, all_of(briskfactors), all_of(endpoint), all_of(wt)) %>%
    arrange(desc(get(endpoint)))
  
  dat.ph2 <- dat.ph1 %>%
    filter(TwophasesampIndD57 == TRUE) %>%
    select(Ptid, Trt, all_of(briskfactors), all_of(endpoint), all_of(wt), any_of(markerVars)) %>%
    drop_na(Day57bindSpike, Day57bindRBD, Day57pseudoneutid50, Day57pseudoneutid80) %>%
    arrange(desc(get(endpoint)))
}


if(study_name == "HVTN705"){
  # Add BAMA antigen data
  dat.mock <- dat.mock %>% 
    left_join(read.csv("../../data/hvtn705_lum_pdata_assay_agnostic.csv") %>%
                filter(aval_cd == "delta") %>%
                select(ptid, avisit, paramcd, parcat1, parcat2, analyte_pan, aval, crit1fl) %>%
                mutate(#aval = ifelse(crit1fl == 0 & aval > 100, 100, aval),
                       aval = log10(aval),
                       avisit = ifelse(avisit == "Month 0", "Day1", "Day210"),
                       parcat2 = paste0(avisit, "_", parcat2)) %>%
                select(-c(avisit, paramcd, parcat1, analyte_pan, crit1fl)) %>%
                pivot_wider(names_from = "parcat2", values_from = "aval") %>%
                select(ptid, "Day210_Con 6 gp120/B", "Day210_1394C9_G1.D11gp120.avi", "Day210_1428_D11gp120.avi/293F", "Day210_1012_11.TC21D11gp120.avi", "Day210_1086C_D7gp120.avi/293F",
                       "Day210_gp140 Mos1 fibritin", "Day210_gp140 C97ZA fibritin", "Day210_Con S gp140 CFI", "Day210_1012_gp140C.avi/293F", "Day210_1394C9_gp140C.avi/293F", "Day210_1086C gp140C_avi",     
                       "Day210_BF1266_gp140C.avi/293F", "Day210_9004S.gp140C.avi",
                       "Day210_AE.A244 V1V2 Tags/293F", "Day210_C.1086C_V1_V2 Tags", "Day210_gp70_B.CaseA_V1_V2", "Day210_gp70-1012.11.TC21.3257 V1V2", 
                       "Day210_gp70-1394C9G1 V1V2", "Day210_gp70-BF1266_431a_V1V2", "Day210_gp70-001428.2.42 V1V2", "Day210_gp70-Ce1086_B2 V1V2", 
                       "Day210_gp41"), 
              by = c("Subjectid" = "ptid")) %>% 
    rename(`Day210IgG3Con6gp120B40delta` = `Day210_Con 6 gp120/B`,
           `Day210IgG31394C9G1.D11gp120.avi40delta` = `Day210_1394C9_G1.D11gp120.avi`,
           `Day210IgG31428D11gp120.avi293F40delta` = `Day210_1428_D11gp120.avi/293F`, 
           `Day210IgG31012.11.TC21D11gp120.avi40delta` = `Day210_1012_11.TC21D11gp120.avi`, 
           `Day210IgG31086C.D7gp120.avi293F40delta` = `Day210_1086C_D7gp120.avi/293F`,
           #`Day210IgG3gp140Mos1fibritin40deltaNEW` = `Day210_gp140 Mos1 fibritin`, 
           #`Day210IgG3gp140C97ZAfibritin40deltaNEW` = `Day210_gp140 C97ZA fibritin`, 
           `Day210IgG3ConSgp140CFI40delta` = `Day210_Con S gp140 CFI`, 
           `Day210IgG31012gp140C.avi293F40delta` = `Day210_1012_gp140C.avi/293F`, 
           `Day210IgG31394C9gp140C.avi293F40delta` = `Day210_1394C9_gp140C.avi/293F`, 
           `Day210IgG31086Cgp140C.avi40delta` = `Day210_1086C gp140C_avi`,     
           `Day210IgG3BF1266gp140C.avi293F40delta` = `Day210_BF1266_gp140C.avi/293F`, 
           `Day210IgG39004Sgp140C.avi40delta` = `Day210_9004S.gp140C.avi`,
           `Day210IgG3AEA244V1V2Tags.293F40delta` = `Day210_AE.A244 V1V2 Tags/293F`, 
           `Day210IgG3C1086CV1V2Tags40delta` = `Day210_C.1086C_V1_V2 Tags`, 
           `Day210IgG3gp70BCaseA.V1V240delta` = `Day210_gp70_B.CaseA_V1_V2`, 
           `Day210IgG3gp70.1012.11.TC21.3257.V1V240delta` = `Day210_gp70-1012.11.TC21.3257 V1V2`, 
           `Day210IgG3gp70.1394C9G1.V1V240delta` = `Day210_gp70-1394C9G1 V1V2`, 
           `Day210IgG3gp70.BF1266.431a.V1V240delta` = `Day210_gp70-BF1266_431a_V1V2`, 
           `Day210IgG3gp70.001428.2.42V1V240delta` = `Day210_gp70-001428.2.42 V1V2`, 
           `Day210IgG3gp70.Ce1086.B2.V1V240delta` = `Day210_gp70-Ce1086_B2 V1V2`
           #Day210IgG3gp4140deltaNEW = Day210_gp41
           )
  
  briskfactors <- c("RSA", "Age", "BMI", "Riskscore")
  briskfactors_correction <- "Y ~ x + X$Riskscore + X$Age + X$BMI + X$RSA"
  
  markerVars <- c("Day210ELCZ", "Day210ELMo", 
                  "Day210ADCPgp140C97ZAfib",
                  # All BAMA IgG3 markers
                  "Day210IgG3Con6gp120B40delta", "Day210IgG31394C9G1.D11gp120.avi40delta", "Day210IgG31428D11gp120.avi293F40delta", "Day210IgG31012.11.TC21D11gp120.avi40delta", 
                  "Day210IgG31086C.D7gp120.avi293F40delta", 
                  #"Day210IgG3gp140Mos1fibritin40deltaNEW", #"Day210IgG3gp140C97ZAfibritin40deltaNEW", 
                  "Day210IgG3gp140Mos1fibritin40delta", "Day210IgG3gp140C97ZAfibritin40delta", 
                  "Day210IgG3ConSgp140CFI40delta", "Day210IgG31012gp140C.avi293F40delta", "Day210IgG31394C9gp140C.avi293F40delta", "Day210IgG31086Cgp140C.avi40delta",     
                  "Day210IgG3BF1266gp140C.avi293F40delta", "Day210IgG39004Sgp140C.avi40delta", "Day210IgG3AEA244V1V2Tags.293F40delta", "Day210IgG3C1086CV1V2Tags40delta", 
                  "Day210IgG3gp70BCaseA.V1V240delta", "Day210IgG3gp70.1012.11.TC21.3257.V1V240delta", "Day210IgG3gp70.1394C9G1.V1V240delta", "Day210IgG3gp70.BF1266.431a.V1V240delta", 
                  "Day210IgG3gp70.001428.2.42V1V240delta", "Day210IgG3gp70.Ce1086.B2.V1V240delta", 
                  "Day1IgG3gp4140delta", 
                  #Day210IgG3gp4140deltaNEW,
                  "Day210IgG3gp4140delta", 
                  #######
                  "Day210IgG340mdw_gp120", "Day210IgG340mdw_gp140", "Day210IgG340mdw_V1V2", 
                  "Day210IgG340mdw_multi",
                  "Day210IgG340mdw_gp120_gp140_vm", 
                  "Day210mdw_xassay")
    
  # Identify the endpoint variable
  endpoint <- "Delta.D210"
  wt <- "wt.D210"
  
  # Create combined new dataset which has imputed values of demographics (for phase 1 data) from dat.covar.imp AND 
  # imputed values for markers (for phase 2 data) from dat.wide.v
  dat.ph1 <- dat.mock %>%
    rename(Ptid = Subjectid) %>%
    filter(Ph1ptids.D210 == 1 & Trt == 1) %>% 
    # Drop any observation with NA values in Ptid, Trt, briskfactors, endpoint and wt.D210
    drop_na(Ptid, Trt, all_of(briskfactors), all_of(endpoint), all_of(wt)) %>%
    arrange(desc(get(endpoint)))
  
  dat.ph2 <- dat.ph1 %>%
    filter(Ph2ptids.D210 == 1) %>%
    select(Ptid, Trt, all_of(briskfactors), all_of(endpoint), all_of(wt), any_of(markerVars)) %>%
    #drop_na(Day57bindSpike, Day57bindRBD, Day57pseudoneutid50, Day57pseudoneutid80) %>%
    arrange(desc(get(endpoint)))
}
################################################    

# Limit total variables that will be included in models 
nv <- sum(dat.ph2 %>% select(matches(endpoint)))

# Remove any predictor variables that are indicator variables and have fewer than 10  0's or 1's
dat.ph2 <- drop_riskVars_with_fewer_0s_or_1s(dat.ph2, c(briskfactors, markerVars))

# Update predictor variables
pred_vars <- dat.ph2 %>%
  select(-Ptid, -Trt, -all_of(endpoint), -all_of(wt)) %>% 
  colnames()

# Remove any baseline risk factors with more than 5% missing values. Impute the missing
# values for other risk variables using mice package!
dat.ph2 <- drop_riskVars_with_high_total_missing_values(dat.ph2, briskfactors)

# Update risk_vars
pred_vars <- dat.ph2 %>%
  select(-Ptid, -Trt, -all_of(endpoint), -all_of(wt)) %>%
  colnames()

# Save ptids to merge with predictions later
ph2_vacc_ptids <- dat.ph2 %>% select(Ptid, all_of(endpoint), all_of(wt))

Z_plus_weights <- dat.ph1 %>% 
  select(Ptid, all_of(endpoint), all_of(wt), Trt, all_of(briskfactors)) %>%
  # Drop any observation with NA values in Ptid, Trt, briskfactors, endpoint or wt.D57
  drop_na(Ptid, Trt, all_of(briskfactors), all_of(endpoint), all_of(wt)) 
  
###########################################################################
if(study_name %in% c("COVE", "MockCOVE")){
  # Create combination scores across the 5 markers
  dat.ph2 <- dat.ph2 %>%
    # generate combination scores for d57
    left_join(get.pca.scores(dat.ph2 %>%
                               select(Ptid, Day57bindSpike, Day57bindRBD, Day57pseudoneutid50, Day57pseudoneutid80)) %>%
                rename(comb_PC1_d57 = PC1,
                       comb_PC2_d57 = PC2), 
              by = "Ptid") %>%
    mutate(comb_maxsig.div.score_d57 = get.maxSignalDivScore(dat.ph2 %>%
                                                               select(Day57bindSpike, Day57bindRBD, Day57pseudoneutid50, Day57pseudoneutid80), "Day57")) %>%
    # generate combination scores for d29
    left_join(get.pca.scores(dat.ph2 %>%
                               select(Ptid, Day29bindSpike, Day29bindRBD, Day29pseudoneutid50, Day29pseudoneutid80)) %>%
                rename(comb_PC1_d29 = PC1,
                       comb_PC2_d29 = PC2), 
              by = "Ptid") %>%
    mutate(comb_maxsig.div.score_d29 = get.maxSignalDivScore(dat.ph2 %>%
                                                               select(Day29bindSpike, Day29bindRBD, Day29pseudoneutid50, Day29pseudoneutid80), "Day29")) %>%
    # generate combination scores for both d57 and d29
    left_join(get.pca.scores(dat.ph2 %>%
                               select(Ptid, Day57bindSpike, Day57bindRBD, Day57pseudoneutid50, Day57pseudoneutid80,
                                      Day29bindSpike, Day29bindRBD, Day29pseudoneutid50, Day29pseudoneutid80)) %>%
                rename(comb_PC1_d57_d29 = PC1,
                       comb_PC2_d57_d29 = PC2), 
              by = "Ptid") %>%
    mutate(comb_maxsig.div.score_d57_d29 = get.maxSignalDivScore(dat.ph2 %>%
                                                                   select(Day57bindSpike, Day57bindRBD, Day57pseudoneutid50, Day57pseudoneutid80,
                                                                          Day29bindSpike, Day29bindRBD, Day29pseudoneutid50, Day29pseudoneutid80), "Day57_29"))
  
  if(run_prod){
    dat.ph2 <- dat.ph2 %>%
      mutate(comb_nlPCA1_d57 = comb_PC1_d57,
             comb_nlPCA2_d57 = comb_PC2_d57,
             comb_nlPCA1_d29 = comb_PC1_d29,
             comb_nlPCA2_d29 = comb_PC2_d29,
             comb_nlPCA1_d57_d29 = comb_PC1_d57_d29,
             comb_nlPCA2_d57_d29 = comb_PC1_d57_d29
             )
      # # generate non-linear combination scores for d57
      # left_join(get.nonlinearPCA.scores(dat.ph2 %>%
      #                                     select(Ptid, Day57bindSpike, Day57bindRBD, Day57pseudoneutid50, Day57pseudoneutid80)) %>%
      #             rename(comb_nlPCA1_d57 = nlPCA1,
      #                    comb_nlPCA2_d57 = nlPCA2),
      #           by = "Ptid") %>%
      # # generate non-linear combination scores for d29
      # left_join(get.nonlinearPCA.scores(dat.ph2 %>%
      #                                     select(Ptid, Day29bindSpike, Day29bindRBD, Day29pseudoneutid50, Day29pseudoneutid80)) %>%
      #             rename(comb_nlPCA1_d29 = nlPCA1,
      #                    comb_nlPCA2_d29 = nlPCA2),
      #           by = "Ptid") %>%
      # # generate non-linear combination scores for both d57 and d29
      # left_join(get.nonlinearPCA.scores(dat.ph2 %>%
      #                                     select(Ptid, Day57bindSpike, Day57bindRBD, Day57pseudoneutid50, Day57pseudoneutid80,
      #                                            Day29bindSpike, Day29bindRBD, Day29pseudoneutid50, Day29pseudoneutid80)) %>%
      #             rename(comb_nlPCA1_d57_d29 = nlPCA1,
      #                    comb_nlPCA2_d57_d29 = nlPCA2),
      #           by = "Ptid")
  }
  
  markers <- dat.ph2 %>%
    select(-Ptid, -Trt, -risk_score, -HighRiskInd, -MinorityInd, -EventIndPrimaryD57, -wt.D57) %>%
    colnames()
  
}


if(study_name == "HVTN705"){
# There are no combination scores in HVTN705
markers <- dat.ph2 %>%
  select(-Ptid, -Trt, -Riskscore, -Age, -BMI, -RSA, -all_of(endpoint), -all_of(wt)) %>%
  colnames()
}

###########################################################################
if(study_name %in% c("COVE", "MockCOVE")){
  ## Create variable sets and set up X, Y for super learning
  # Baseline risk variables are default in all sets
  
  # 1. None (No markers; only baseline risk variables), phase 2 data
  varset_baselineRiskFactors <- rep(FALSE, length(markers))
  
  # 2-12 (Day57)
  varset_bAbSpike_D57 <- create_varsets(markers, grep("(?=.*57)(?=.*bindSpike)", markers, value=TRUE, perl=TRUE))
  varset_bAbRBD_D57 <- create_varsets(markers, grep("(?=.*57)(?=.*bindRBD)", markers, value=TRUE, perl=TRUE))
  varset_pnabID50_D57 <- create_varsets(markers, grep("(?=.*57)(?=.*id50)", markers, value=TRUE, perl=TRUE))
  varset_pnabID80_D57 <- create_varsets(markers, grep("(?=.*57)(?=.*id80)", markers, value=TRUE, perl=TRUE))
  #varset_lnabMN50_D57 <- create_varsets(markers, grep("(?=.*57)(?=.*mn50)", markers, value=TRUE, perl=TRUE)) 
  varset_bAb_pnabID50_D57 <- create_varsets(markers, c(grep("(?=.*57)(?=.*bind)", markers, value=TRUE, perl=TRUE),   
                                                       grep("(?=.*57)(?=.*id50)", markers, value=TRUE, perl=TRUE)))
  varset_bAb_pnabID80_D57 <- create_varsets(markers, c(grep("(?=.*57)(?=.*bind)", markers, value=TRUE, perl=TRUE),   
                                                       grep("(?=.*57)(?=.*id80)", markers, value=TRUE, perl=TRUE)))
  # varset_bAb_lnabMN50_D57 <- create_varsets(markers, grep(paste(c('bindSpike', 'bindRBD', 'liveneutmn50'), 
  #                                                           collapse="|"), markers, value=TRUE, perl=TRUE))
  varset_bAb_combScores_D57 <- create_varsets(markers, c(grep("(?=.*57)(?=.*bind)", markers, value=TRUE, perl=TRUE),   
                                                         grep("(?=.*57)(?=.*comb)(^((?!29).)*$)", markers, value=TRUE, perl=TRUE)))
  varset_allMarkers_D57 <- create_varsets(markers, grep("(?=.*57)(^((?!comb).)*$)", markers, value=TRUE, perl=TRUE))
  varset_allMarkers_combScores_D57 <- create_varsets(markers, grep("(?=.*57)(^((?!29).)*$)", markers, value=TRUE, perl=TRUE))
  
  # 13-23 (Day29)
  varset_bAbSpike_D29 <- create_varsets(markers, grep("(?=.*29)(?=.*bindSpike)", markers, value=TRUE, perl=TRUE))
  varset_bAbRBD_D29 <- create_varsets(markers, grep("(?=.*29)(?=.*bindRBD)", markers, value=TRUE, perl=TRUE))
  varset_pnabID50_D29 <- create_varsets(markers, grep("(?=.*29)(?=.*id50)", markers, value=TRUE, perl=TRUE))
  varset_pnabID80_D29 <- create_varsets(markers, grep("(?=.*29)(?=.*id80)", markers, value=TRUE, perl=TRUE))
  #varset_lnabMN50_D29 <- create_varsets(markers, grep("(?=.*29)(?=.*mn50)", markers, value=TRUE, perl=TRUE)) 
  varset_bAb_pnabID50_D29 <- create_varsets(markers, c(grep("(?=.*29)(?=.*bind)", markers, value=TRUE, perl=TRUE),   
                                                       grep("(?=.*29)(?=.*id50)", markers, value=TRUE, perl=TRUE)))
  varset_bAb_pnabID80_D29 <- create_varsets(markers, c(grep("(?=.*29)(?=.*bind)", markers, value=TRUE, perl=TRUE),   
                                                       grep("(?=.*29)(?=.*id80)", markers, value=TRUE, perl=TRUE)))
  # varset_bAb_lnabMN50_D29 <- create_varsets(markers, grep(paste(c('bindSpike', 'bindRBD', 'liveneutmn50'), 
  #                                                           collapse="|"), markers, value=TRUE, perl=TRUE))
  varset_bAb_combScores_D29 <- create_varsets(markers, c(grep("(?=.*29)(?=.*bind)", markers, value=TRUE, perl=TRUE),   
                                                         grep("(?=.*29)(?=.*comb)(^((?!57).)*$)", markers, value=TRUE, perl=TRUE)))
  varset_allMarkers_D29 <- create_varsets(markers, grep("(?=.*29)(^((?!comb).)*$)", markers, value=TRUE, perl=TRUE))
  varset_allMarkers_combScores_D29 <- create_varsets(markers, grep("(?=.*29)(^((?!57).)*$)", markers, value=TRUE, perl=TRUE))
  
  # 24-34 (Day29)
  varset_bAbSpike_D29_D57 <- create_varsets(markers, grep("(?=.*bindSpike)", markers, value=TRUE, perl=TRUE))
  varset_bAbRBD_D29_D57 <- create_varsets(markers, grep("(?=.*bindRBD)", markers, value=TRUE, perl=TRUE))
  varset_pnabID50_D29_D57 <- create_varsets(markers, grep("(?=.*id50)", markers, value=TRUE, perl=TRUE))
  varset_pnabID80_D29_D57 <- create_varsets(markers, grep("(?=.*id80)", markers, value=TRUE, perl=TRUE))
  #varset_lnabMN50_D29_D57 <- create_varsets(markers, grep("(?=.*mn50)", markers, value=TRUE, perl=TRUE)) 
  varset_bAb_pnabID50_D29_D57 <- create_varsets(markers, c(grep("(?=.*bind)", markers, value=TRUE, perl=TRUE),   
                                                       grep("(?=.*id50)", markers, value=TRUE, perl=TRUE)))
  varset_bAb_pnabID80_D29_D57 <- create_varsets(markers, c(grep("(?=.*bind)", markers, value=TRUE, perl=TRUE),   
                                                           grep("(?=.*id80)", markers, value=TRUE, perl=TRUE)))
  # varset_bAb_lnabMN50_D29_D57 <- create_varsets(markers, c(grep("(?=.*bind)", markers, value=TRUE, perl=TRUE), 
  #                                                           grep("(?=.*mn50)", markers, value=TRUE, perl=TRUE)))
  varset_bAb_combScores_D29_D57 <- create_varsets(markers, c(grep("(?=.*bind)", markers, value=TRUE, perl=TRUE),   
                                                         grep("(?=.*comb)(?=.*d57_d29)", markers, value=TRUE, perl=TRUE)))
  varset_allMarkers_D29_D57 <- create_varsets(markers, grep("(^((?!comb).)*$)", markers, value=TRUE, perl=TRUE))
  varset_allMarkers_combScores_D29_D57 <- create_varsets(markers, c(grep("(^((?!comb).)*$)", markers, value=TRUE, perl=TRUE),
                                                                    grep("(?=.*comb)(?=.*d57_d29)", markers, value=TRUE, perl=TRUE)))
  
  varset_names <- c("1_baselineRiskFactors",
                    "2_bAbSpike_D57", "3_bAbRBD_D57", "4_pnabID50_D57", "5_pnabID80_D57", 
                    "6_bAb_pnabID50_D57", "7_bAb_pnabID80_D57", 
                    "8_bAb_combScores_D57", "9_allMarkers_D57", "10_allMarkers_combScores_D57",
                    
                    "11_bAbSpike_D29", "12_bAbRBD_D29", "13_pnabID50_D29", "14_pnabID80_D29", 
                    "15_bAb_pnabID50_D29", "16_bAb_pnabID80_D29", 
                    "17_bAb_combScores_D29", "18_allMarkers_D29", "19_allMarkers_combScores_D29",
                    
                    "20_bAbSpike_D29_D57", "21_bAbRBD_D29_D57", "22_pnabID50_D29_D57", "23_pnabID80_D29_D57", 
                    "24_bAb_pnabID50_D29_D57", "25_bAb_pnabID80_D29_D57", 
                    "26_bAb_combScores_D29_D57", "27_allMarkers_D29_D57", "28_allMarkers_combScores_D29_D57")
  
  ## set up a matrix of all
  varset_matrix <- rbind(varset_baselineRiskFactors,
                         
                         varset_bAbSpike_D57, varset_bAbRBD_D57, varset_pnabID50_D57, varset_pnabID80_D57, 
                         varset_bAb_pnabID50_D57, varset_bAb_pnabID80_D57, varset_bAb_combScores_D57, 
                         varset_allMarkers_D57, varset_allMarkers_combScores_D57,
                         
                         varset_bAbSpike_D29, varset_bAbRBD_D29, varset_pnabID50_D29, varset_pnabID80_D29, 
                         varset_bAb_pnabID50_D29, varset_bAb_pnabID80_D29, varset_bAb_combScores_D29, 
                         varset_allMarkers_D29, varset_allMarkers_combScores_D29,
                         
                         varset_bAbSpike_D29_D57, varset_bAbRBD_D29_D57, varset_pnabID50_D29_D57, varset_pnabID80_D29_D57, 
                         varset_bAb_pnabID50_D29_D57, varset_bAb_pnabID80_D29_D57, varset_bAb_combScores_D29_D57, 
                         varset_allMarkers_D29_D57, varset_allMarkers_combScores_D29_D57)
}




if(study_name == "HVTN705"){
  ## Create variable sets and set up X, Y for super learning
  # Baseline risk variables are default in all sets
  
  # 1. None (No markers; only baseline risk variables), phase 2 data
  varset_baselineRiskFactors <- rep(FALSE, length(markers))
  
  # 2-12 (Day57)
  varset_M7ELISA <- create_varsets(markers, grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE))
  #varset_M7ELISpot <- create_varsets(markers, grep("ELspotCZ|ELspotMo", markers, value=TRUE, perl=TRUE))
  varset_M7ADCP <- create_varsets(markers, grep("ADCP", markers, value=TRUE, perl=TRUE))
  varset_M7IgG3 <- create_varsets(markers, grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE))
  varset_M7IgG3_gp140 <- create_varsets(markers, grep("(?=.*IgG3)(?=.*gp140)", markers, value=TRUE, perl=TRUE))
  varset_M7IgG3_gp120 <- create_varsets(markers, grep("(?=.*IgG3)(?=.*gp120)", markers, value=TRUE, perl=TRUE))
  varset_M7IgG3_V1V2 <- create_varsets(markers, grep("(?=.*IgG3)(?=.*V1V2)", markers, value=TRUE, perl=TRUE))
  varset_M7IgG3_gp41 <- create_varsets(markers, grep("(?=.*IgG3)(?=.*gp41)", markers, value=TRUE, perl=TRUE))
  varset_M7IgG3_breadthScores <- create_varsets(markers, grep("(?=.*IgG3)(?=.*mdw)(^((?!multi).)*$)", markers, value=TRUE, perl=TRUE))
  varset_M7IgG3_multi <- create_varsets(markers, grep("(?=.*IgG3)(?=.*mdw)(?=.*multi)", markers, value=TRUE, perl=TRUE))
  varset_M7IgG3_overallScore <- create_varsets(markers, grep("(?=.*mdw)(?=.*xassay)", markers, value=TRUE, perl=TRUE)) 
  # varset_M7_2_3 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE),   
  #                                            grep("ELspotCZ|ELspotMo", markers, value=TRUE, perl=TRUE)))
  varset_M7_2_4 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE),   
                                             grep("ADCP", markers, value=TRUE, perl=TRUE)))
  varset_M7_2_5 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE),   
                                             grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE)))
  # varset_M7_3_4 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE),   
  #                                            grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE)))
  # varset_M7_3_5 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE),   
  #                                            grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE)))
  varset_M7_4_5 <- create_varsets(markers, c(grep("ADCP", markers, value=TRUE, perl=TRUE),   
                                             grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE)))
  # varset_M7_2_3_4 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE),   
  #                                            grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE)))
  # varset_M7_2_3_5 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE),   
  #                                            grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE)))
  # varset_M7_3_4_5 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE),   
  #                                              grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE)))
  # varset_M7_2_3_4_5 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE),   
  #                                              grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE)))
  varset_M7_2_4_5 <- create_varsets(markers, c(grep("ELCZ|ELMo", markers, value=TRUE, perl=TRUE), 
                                               grep("ADCP", markers, value=TRUE, perl=TRUE),  
                                               grep("(?=.*IgG3)", markers, value=TRUE, perl=TRUE)))
  
  varset_names <- c("1_baselineFactors", "2_M7_ELISA", #"3_M7_ELISpot", 
                    "4_M7_ADCP", "5_M7_IgG3", 
                    "6_M7_IgG3gp140", "7_M7_IgG3gp120", "8_M7_IgG3V1V2", "9_M7_IgG3gp41", "10_M7_IgG3bScores",
                    "11_M7_IgG3multi", "12_M7_IgG3overall", 
                    #"13_2+3", 
                    "14_2+4", 
                    "15_2+5", 
                    #"16_3+4", "17_3+5", 
                    "18_4+5", 
                    #"19_2+3+4", "20_2+3+5", "21_3+4+5", "22_2+3+4+5",
                    "22_2+4+5")
  
  ## set up a matrix of all
  varset_matrix <- rbind(varset_baselineRiskFactors, varset_M7ELISA, #varset_M7ELISpot,
                         varset_M7ADCP, varset_M7IgG3, varset_M7IgG3_gp140, varset_M7IgG3_gp120,
                         varset_M7IgG3_V1V2, varset_M7IgG3_gp41, varset_M7IgG3_breadthScores, 
                         varset_M7IgG3_multi, varset_M7IgG3_overallScore, #varset_M7_2_3, 
                         varset_M7_2_4, varset_M7_2_5, # varset_M7_3_4, # varset_M7_3_5, 
                         varset_M7_4_5, # varset_M7_2_3_4, varset_M7_2_3_5, varset_M7_3_4_5, varset_M7_2_3_4_5, 
                         varset_M7_2_4_5)
}



#job_id = 1
this_var_set <- varset_matrix[job_id, ]
cat("\n Running", varset_names[job_id], "variable set \n")

X_covars2adjust_ph2 <- dat.ph2 %>% select(all_of(c(briskfactors, markers)))


## scale covars2adjust to have mean 0, sd 1 for all vars
for (a in colnames(X_covars2adjust_ph2)) {
  X_covars2adjust_ph2[[a]] <- scale(X_covars2adjust_ph2[[a]],
                                    center = mean(X_covars2adjust_ph2[[a]], na.rm = T),
                                    scale = sd(X_covars2adjust_ph2[[a]], na.rm = T))
}

markers_start <- length(briskfactors) + 1

if(job_id == 1){
  X_markers_varset <- X_covars2adjust_ph2[1:length(briskfactors)] %>%
    select_if(function(x) any(!is.na(x))) # Drop column if it has 0 variance, and returned all NAN's from scale function.
}else{
  X_markers_varset <- bind_cols(X_covars2adjust_ph2[1:length(briskfactors)],
                                X_covars2adjust_ph2[markers_start:length(X_covars2adjust_ph2)][this_var_set]) %>%
    select_if(function(x) any(!is.na(x))) # Drop column if it has 0 variance, and returned all NAN's from scale function.
}

sl_lib <- SL_library
Y = dat.ph2 %>% pull(endpoint)

if(study_name %in% c("COVE", "MockCOVE")){
  weights = dat.ph2$wt.D57
  treatmentDAT <- dat.ph2 %>% 
    select(Ptid, Trt, wt.D57, EventIndPrimaryD57, all_of(c(briskfactors, markers))) %>%
    filter(Trt == 1) %>%
    select(-Trt)
} else if(study_name == "HVTN705"){
  weights = dat.ph2$wt.D210
  treatmentDAT <- dat.ph2 %>% 
    select(Ptid, Trt, wt.D210, Delta.D210, all_of(c(briskfactors, markers))) %>%
    filter(Trt == 1) %>%
    select(-Trt)
}
  

# match the rows in treatmentDAT to get Z, C
all_cc_treatment <- Z_plus_weights %>%
  filter(Ptid %in% treatmentDAT$Ptid)
# pull out the participants who are NOT in the cc cohort and received the vaccine
all_non_cc_treatment <- Z_plus_weights %>%
  filter(!(Ptid %in% treatmentDAT$Ptid))
# put them back together
phase_1_data_treatmentDAT <- dplyr::bind_rows(all_cc_treatment, all_non_cc_treatment) %>%
  select(-Trt)
if(study_name %in% c("COVE", "MockCOVE")){
  Z_treatmentDAT <- phase_1_data_treatmentDAT %>%
    select(-Ptid, -wt.D57)
  all_ipw_weights_treatment <- phase_1_data_treatmentDAT %>%
    pull(wt.D57)
} else if(study_name == "HVTN705"){
  Z_treatmentDAT <- phase_1_data_treatmentDAT %>%
    select(-Ptid, -wt.D210)
  all_ipw_weights_treatment <- phase_1_data_treatmentDAT %>%
    pull(wt.D210)
}

C <- (phase_1_data_treatmentDAT$Ptid %in% treatmentDAT$Ptid)

## set up outer folds for cv variable importance; do stratified sampling
V_outer <- 5
if (sum(dat.ph2 %>% pull(endpoint)) <= 25){
  V_inner <- length(Y) - 1
  maxVar <- 5
} else if(sum(dat.ph2 %>% pull(endpoint)) > 25){
  V_inner <- 5
  maxVar <- floor(nv/6)
}

if (study_name == "COVE"){
  V_inner <- length(Y) - 1
  maxVar <- 5
} 

# Use inner leave-one-out CV even though there are enough number of HIV cases in phase 2 (51 HIV cases)
# Based off Peter's email, Thu 11/11/2021 3:08 PM
if (study_name == "HVTN705"){
  V_inner <- length(Y) - 1
  maxVar <- floor(nv/6)
} 

## ---------------------------------------------------------------------------------
## run super learner, with leave-one-out cross-validation and all screens
## do 10 random starts, average over these
## use assay groups as screens
## ---------------------------------------------------------------------------------
## ensure reproducibility
set.seed(20210216)
seeds <- round(runif(10, 1000, 10000)) # average over 10 random starts

# ##solve cores issue
# library(RhpcBLASctl)
# blas_get_num_procs()
# blas_set_num_threads(1)
# print(blas_get_num_procs())
# stopifnot(blas_get_num_procs()==1)

# disable parallelization in openBLAS and openMP 
library(RhpcBLASctl)
blas_get_num_procs()
blas_set_num_threads(1L)
stopifnot(blas_get_num_procs() == 1L)
omp_set_num_threads(1L)


fits <- parallel::mclapply(seeds, FUN = run_cv_sl_once,
                           Y = Y,
                           X_mat = X_markers_varset,
                           family = "binomial",
                           obsWeights = weights,
                           all_weights = all_ipw_weights_treatment,
                           ipc_est_type = "ipw",
                           sl_lib = sl_lib,
                           method = "method.CC_nloglik",
                           cvControl = list(V = V_outer, stratifyCV = TRUE),
                           innerCvControl = list(list(V = V_inner)),
                           Z = Z_treatmentDAT,
                           C = C,
                           z_lib = "SL.glm",
                           scale = "identity", # new argument
                           vimp = FALSE,
                           mc.cores = num_cores
)


cvaucs <- list()
cvfits <- list()

for(i in 1:length(seeds)) {
  cvaucs[[i]] = fits[[i]]$cvaucs$aucs
  cvfits[[i]] = fits[[i]]$cvfits
}

saveRDS(cvaucs, file = here("output", paste0("CVSLaucs_vacc_", endpoint, "_", varset_names[job_id], ".rds")))
save(cvfits, file = here("output", paste0("CVSLfits_vacc_", endpoint, "_", varset_names[job_id], ".rda")))
save(ph2_vacc_ptids, file = here("output", "ph2_vacc_ptids.rda"))
save(run_prod, Y, dat.ph1, dat.ph2, weights, dat.mock, briskfactors, endpoint, maxVar,
     V_outer, file = here("output", "objects_for_running_SL.rda"))

