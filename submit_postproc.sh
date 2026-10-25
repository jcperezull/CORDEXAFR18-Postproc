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


set -euo pipefail

mkdir -p logs

# Máximo de procesos simultáneos.
# Ajusta según núcleos disponibles.
MAX_PARALLEL="${MAX_PARALLEL:-4}"

# Identificador local para agrupar la ejecución
ARRAY_JOBID="local_$(date +%Y%m%d_%H%M%S)_$$"

# Fichero para guardar pids y estados
PID_FILE="logs/${ARRAY_JOBID}.pids"
STATUS_FILE="logs/${ARRAY_JOBID}.status"
: > "$PID_FILE"
: > "$STATUS_FILE"

launch_task() {
  local task_id="$1"
  local out="logs/pCMOR_${PROJECT}_${YEAR}_${DOMAIN}_${ARRAY_JOBID}_${task_id}.out"
  local err="logs/pCMOR_${PROJECT}_${YEAR}_${DOMAIN}_${ARRAY_JOBID}_${task_id}.err"

  (
    export ARRAY_TASK_ID="$task_id"
    bash run_array_task.sh "$manifest" "$DIR_IN" "$DIR_OUT"
  ) >"$out" 2>"$err" &

  local pid=$!
  echo "${task_id},${pid}" >> "$PID_FILE"
}

# Cuenta procesos activos de este script
num_running() {
  jobs -rp | wc -l
}

# Lanza las N tareas con control de concurrencia
for ((i=1; i<=N; i++)); do
  while (( $(num_running) >= MAX_PARALLEL )); do
    sleep 1
  done
  launch_task "$i"
done

# Espera a todos los procesos y guarda estado
FAIL_COUNT=0

while IFS=, read -r task_id pid; do
  if wait "$pid"; then
    echo "${task_id},0" >> "$STATUS_FILE"
  else
    rc=$?
    echo "${task_id},${rc}" >> "$STATUS_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done < "$PID_FILE"

echo "ARRAY_JOBID=$ARRAY_JOBID"
echo "FAIL_COUNT=$FAIL_COUNT"

# Equivalente a afterany: se ejecuta siempre cuando terminen todas
bash delete_temp_files.sh "$CSV_FILE" "$manifest" "false" "$ARRAY_JOBID"
