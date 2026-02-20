#!/usr/bin/env bash
set -euo pipefail

CSV_FILE=$1
YEAR=$2
DOMAIN=$3
PROJECT=$4
FREQ_FILTER=${5:-}

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
  run_array_task.sh "$manifest")

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

