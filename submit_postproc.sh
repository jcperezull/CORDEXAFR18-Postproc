#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 6 ]]; then
    echo "ERROR: Incorrect number of arguments."
    echo "Uso: $0 CSV_FILE YEAR DOMAIN PROJECT DIR_IN DIR_OUT [FREQ_FILTER]"
    echo "Example: $0 variables.csv 1980 AFR18 CORDEX /path/in /path/out mon"
    exit 1
fi
CSV_FILE=$1
YEAR=$2
DOMAIN=$3
PROJECT=$4
DIR_IN=$5    # Input directory (wrfout and wrfpress files)
DIR_OUT=$6   # Output directory (where pCMORizer.exe builds output tree)
FREQ_FILTER=${7:-} # Output frequency (optional)

# 1. Validación básica de presencia de argumentos
if [[ -z "$DIR_OUT" ]]; then
    echo "Use: $0 CSV_FILE YEAR DOMAIN PROJECT DIR_IN DIR_OUT [FREQ_FILTER]"
    exit 1
fi

# 2. Comprobar si DIR_IN existe como directorio
if [[ ! -d "$DIR_IN" ]]; then
    echo "ERROR: Input directory does not exist: $DIR_IN"
    exit 1
fi

# 3. CHECK WRFOUT AND WRFPRESS FILES PRESENT IN INPUT DIRECTORY
# Usamos 'compgen -G' para verificar si existen ficheros que coincidan con el patrón
if ! compgen -G "${DIR_IN}/wrfout*" > /dev/null; then
    echo "No wrfout files present in $DIR_IN"
    exit 1
fi

if ! compgen -G "${DIR_IN}/wrfpress*" > /dev/null; then
    echo "ERROR: No wrfpress files present in $DIR_IN"
    exit 1
fi

mkdir -p logs

START_TIME=$(date +%s)

# 1) generar manifest
./make_manifest.sh "$CSV_FILE" "$YEAR" "$DOMAIN" "$PROJECT" "$FREQ_FILTER"

manifest="manifest_${PROJECT}_${YEAR}_${DOMAIN}.txt"

N=$(wc -l < "$manifest")

if [[ "$N" -le 0 ]]; then
  echo "No tasks to submit. Exiting."
  exit 0
fi


# 2) lanzar array: 1 core por tarea
ARRAY_JOBID=$(sbatch --parsable --wait \
  --job-name="pCMOR_${PROJECT}_${YEAR}_${DOMAIN}" \
  --array=1-"$N" \
  --ntasks=1 \
  --partition="batch" \
  --cpus-per-task=1 \
  --output="logs/%x_%A_%a.out" \
  --error="logs/%x_%A_%a.err" \
  run_array_task.sh "$manifest" "$DIR_IN" "$DIR_OUT")

echo "Submitted array job: $ARRAY_JOBID with $N tasks"
END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
echo "---------------------------------"
echo "ARRAY JOB $ARRAY_JOBID FINISHED"
echo "TOTAL EXECUTION TIME:"
echo "$(date -u -d @$TOTAL_SECONDS +%T)"
echo "---------------------------------"

# 3) lanzar post-proceso cuando TODAS terminen OK
#POST_JOBID=$(sbatch --parsable \
#  --job-name="post_${PROJECT}_${YEAR}_${DOMAIN}" \
#  --dependency=afterok:"$ARRAY_JOBID" \
#  --ntasks=1 \
#  --cpus-per-task=1 \
#  --output="logs/%x_%j.out" \
#  --error="logs/%x_%j.err" \
#  ./mi_script_final.sh "$YEAR" "$DOMAIN" "$PROJECT")

#echo "Submitted post job: $POST_JOBID (afterok:$ARRAY_JOBID)"

