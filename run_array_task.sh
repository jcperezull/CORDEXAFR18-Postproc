#!/usr/bin/env bash
set -euo pipefail
# Check input parameters
if [[ $# -lt 3 ]]; then
  echo "Use: $0 <manifest> <input_directory> <output_dir>"
  exit 1
fi

manifest="$1"
DIR_IN="$2"
OUT_DIR="$3"

line=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$manifest")
if [[ -z "${line}" ]]; then
  echo "No line for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}"
  exit 2
fi

read -r YEAR DOMAIN VARIABLE PROJECT FREQ FREQ_AGGREGATE METHOD DATAPATH<<< "$line"

echo "Running: YEAR=$YEAR DOMAIN=$DOMAIN VAR=$VARIABLE PROJECT=$PROJECT FREQ=$FREQ"
./run_pCMORizer_var.sh "$YEAR" "$DOMAIN" "$VARIABLE" "$PROJECT" "$FREQ" "$DIR_IN" "$OUT_DIR"

if [[ "$FREQ_AGGREGATE" == "day" ]]; then
    echo "Original frequency was 'day' → running daily aggregation"
    ./pCMORizer_aggregate_per_day.sh "$DATAPATH" "$YEAR" "$VARIABLE" "$METHOD"
fi

