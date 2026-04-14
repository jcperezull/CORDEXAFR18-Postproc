#!/usr/bin/env bash
set -euo pipefail

# ---- MAIN ---

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
./make_manifest.sh "$CSV_FILE" "$YEAR" "$DOMAIN" "$PROJECT" "${DIR_OUT}" "$FREQ_FILTER"

manifest="manifest_${PROJECT}_${YEAR}_${DOMAIN}.txt"

N=$(wc -l < "$manifest")

if [[ "$N" -le 0 ]]; then
  echo "No tasks to submit. Exiting."
  exit 0
fi


ARRAY_JOBID=$(sbatch --parsable \
  --job-name="pCMOR_${PROJECT}_${YEAR}_${DOMAIN}" \
  --array=1-"$N" \
  --ntasks=1 \
  --partition="priority" \
  --cpus-per-task=1 \
  --exclude="node1501-4,node0315-3,node0312-[1,4],node0301-[1,3],node0302-3" \
  --output="logs/%x_%A_%a.out" \
  --error="logs/%x_%A_%a.err" \
  run_array_task.sh "$manifest" "$DIR_IN" "$DIR_OUT")

sbatch \
  --dependency=afterany:$ARRAY_JOBID \
  --job-name="pCMOR_finalize_${PROJECT}_${YEAR}_${DOMAIN}" \
  --output="logs/finalize_%j.out" \
  --error="logs/finalize_%j.err" \
  delete_temp_files.sh "$CSV_FILE" "$manifest" "false" "$ARRAY_JOBID"

