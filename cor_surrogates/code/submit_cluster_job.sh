#!/bin/bash
ml R/4.0.4-foss-2020b
#ml PyTorch/1.7.1-fosscuda-2020b
#virtualenv ./pytorch
#pip install -r requirements.txt
#ml jbigkit
#sbatch -c10 --mem 11G --time=7-0 --constraint=gizmok code/run_cvsl_varsets.sh
sbatch -c10 --mem 11G --time=7-0 --array=1-15 --constraint=gizmok code/run_cvsl_varsets.sh
