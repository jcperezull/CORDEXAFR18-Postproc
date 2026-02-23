#!/bin/bash
#SBATCH --job-name=cmor
#SBATCH --output=cmor%j.out
#SBATCH --error=cmor%j.error
#SBATCH --ntasks=1
##SBATCH --qos=meteo_high
##SBATCH --ntasks-per-node=16
#SBATCH --cpus-per-task=1
#SBATCH --time=24:00:00
##SBATCH --exclusive
##SBATCH --mem-per-cpu=8G
##SBATCH --mem=60G
#SBATCH --hint=nomultithread
##SBATCH --nodelist=wncompute051
#SBATCH --mail-user=jcperez@ull.edu.es
#SBATCH --partition=batch
##SBATCH --exclude=wncompute051


# Set the enviroment
source /home/jcperez/data/Projects/CORDEXAfr/Teide/WRFintelteide/WRF_pnetcdf/WRF_4.6.1/Intel2024/envvars.sh
module load Python/3.10.8-GCCcore-12.2.0

# Adjust to your situations
export YEAR=$1 	
export YEAR_next=$(date -u --date="$YEAR-01-01 1 year" '+%Y')
export DOM=$2 
export VARNAME=$3
export PROJECT=$4
export FREQ=$5

if [[ ${PROJECT} == "I4C" ]]; then
  export dir_data_in="set-full-path-to-raw-wrfoutput-files"
elif [[ ${PROJECT} == "EUROCORDEX" ]]; then
  export dir_data_in="set-full-path-to-raw-wrfoutput-files"
elif [[ ${PROJECT} == "AFRCORDEX18" ]]; then
  #export dir_data_in="/disk/barbusano/barbusano1/WRF4G_monitor/CORDEX-AFR18_4611_256_p-198001-06_v1/results/CORDEX-AFR18_4611_256_p-198001-06_v1/output"
  export dir_data_in="/home/jcperez/data/Projects/CORDEXAfr/Teide/WRFintelteide/WRF_pnetcdf/WRF_4.6.1/Intel2024/Software/pCMORIzer/Inputs/1980"
else
  echo "Provide full path to you raw wrfout files."
fi

nvar=1 

# Set cases according to the data in the pCMORizer code
case $FREQ in
    1hr)
        freq_id=1 ;;
    3hr)
        freq_id=2 ;;
    6hr)
        freq_id=3 ;;
    day)
        freq_id=4 ;;
    fx)
        freq_id=7 ;;
    *)
        echo "Unknown frequency." ;;
esac

echo "Starting: $(date +%H:%M:%S)"

echo "Changing in pCMORizer.f90 freq_id to $freq_id for the frequency $FREQ"

# Create working directory
dir_home=$(pwd)
dir_work=${dir_home}/${PROJECT}/${DOM}_${FREQ}/${YEAR}
mkdir -p ${dir_work}; cd ${dir_work}
ln -sf ${dir_data_in}/wrf*_${DOM}_${YEAR}* ${dir_work}/
##JC ln -sf ${dir_data_in}/wrf*_${DOM}_${YEAR_next}-01-01* ${dir_work}/

# Create working directory per variable
mkdir -p ${dir_work}/${VARNAME}
cd ${dir_work}/${VARNAME}

# Adapt general namelist for the seleted variabels
cp -f ${dir_home}/runctrl.current.nml_template_${DOM}_${PROJECT} ${dir_work}/${VARNAME}/runctrl.current.nml_${DOM}
sed -i "s/__YYYY__/$Y/g" runctrl.current.nml_${DOM}
sed -i "s/__nvar__/$nvar/g" runctrl.current.nml_${DOM}
ln -sf runctrl.current.nml_${DOM} runctrl.current.nml

# Generate namelist for the selected variables
cp -f ${dir_home}/generate_vars_namelist.py ${dir_work}/${VARNAME}/
cp -f ${dir_home}/CORDEX_CMIP6_variables.csv ${dir_work}/${VARNAME}/
python generate_vars_namelist.py ${VARNAME}
mv runctrl.vars.${VARNAME}.nml runctrl.vars.nml

# Compile the code for the specific varlist
# JC changed to copy the precompiled code to pCMORizer.exe 12/02/2026

##cp -f ${dir_home}/Makefile ${dir_work}/${VARNAME}/
##cp -f ${dir_home}/pCMORizer.f90 ${dir_work}/${VARNAME}/pCMORizer.f90
##sed -i "s/DO ifrq = 1, 1, 1/DO ifrq = $freq_id, $freq_id, 1/g" ${dir_work}/${VARNAME}/pCMORizer.f90
##make veryclean
##make
##sleep 2
##mv pCMORizer pCMORizer.exe
##sleep 2
cp -f ${dir_home}/pCMORizer_${FREQ} ${dir_work}/${VARNAME}/pCMORizer.exe

# running the code
cd ${dir_work}/${VARNAME}/
./pCMORizer.exe  > log.txt  2>&1              # run directly in the interface
# srun --cpu-bind=cores ./pCMORizer.exe # when sending job and running on nodes

echo "Finishing: $(date +%H:%M:%S)"
exit 0
