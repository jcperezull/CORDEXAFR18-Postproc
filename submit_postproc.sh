#!/usr/bin/env bash
set -euo pipefail

# --- FUNCTION DEFINITION ---

cleanup_unused_day_variables() {
    local csv_file="$1"
    local manifest_file="$2"
    local dry_run="${3:-true}" # Defaults to true if not provided

    echo "-----------------------------------------------------------------"
    echo "STARTING POST-PROCESS DIRECTORY CLEANUP"
    echo "Condition: Variables in CSV with 'day' but without '1hr'"
    echo "Dry-run mode: $dry_run"
    echo "-----------------------------------------------------------------"

    # 1. Identify variables that have 'day' frequency but NOT '1hr' in the original CSV
    # We use 'comm' on the sorted lists of variable names
    local vars_to_clean
    vars_to_clean=$(comm -23 <(grep ",day," "$csv_file" | cut -d',' -f1 | sort -u) \
                             <(grep ",1hr," "$csv_file" | cut -d',' -f1 | sort -u))

    if [[ -z "$vars_to_clean" ]]; then
        echo "No variables matching the cleanup criteria were detected."
        return 0
    fi
    local var_count
    var_count=$(echo "$vars_to_clean" | wc -w)

    echo "Found $var_count variable(s) matching the cleanup criteria."

    #-------------

    for var in $vars_to_clean; do
        echo "Variable identified for cleanup: $var"

        # 1. Extract the specific paths for '1hr' frequency
        local dir_list
        dir_list=$(awk -v v="$var" '$3 == v && $5 == "1hr" {print $NF}' "$manifest_file")

        if [[ -z "$dir_list" ]]; then
            echo "  --> Skipping: No '1hr' entries found in manifest for variable '$var'."
            continue
        fi

        for path_in_manifest in $dir_list; do
            # 2. Calculate the target directory (2 levels up)
            # Example: .../1hr/tas/v20240806 -> .../1hr
            local dir_to_del
            dir_to_del=$(dirname "$path_in_manifest")

            if [[ -d "$dir_to_del" ]]; then
                if [ "$dry_run" = "true" ]; then
                    echo "  [DRY-RUN] Manifest path: $path_in_manifest"
                    echo "  [DRY-RUN] Target (1 level up) to delete: $dir_to_del"
                else
                    echo "  [DELETING] $dir_to_del"
                    rm -rf "$dir_to_del"
                fi
            else
                echo "  --> Warning: Target directory does not exist: $dir_to_del"
            fi
        done
    done

    echo "-----------------------------------------------------------------"
    echo "CLEANUP PROCESS FINISHED"
    echo "-----------------------------------------------------------------"
}

# ---- MAIN ---
# 

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


# 2) lanzar array: 1 core por tarea
#ARRAY_JOBID=$(sbatch --parsable --wait \
#  --job-name="pCMOR_${PROJECT}_${YEAR}_${DOMAIN}" \
#  --array=1-"$N" \
#  --ntasks=1 \
#  --partition="batch" \
#  --cpus-per-task=1 \
#  --exclude="node1501-4,node0315-3,node0312-[1,4],node0301-[1,3],node0302-3" \
#  --output="logs/%x_%A_%a.out" \
#  --error="logs/%x_%A_%a.err" \
#  run_array_task.sh "$manifest" "$DIR_IN" "$DIR_OUT")


ARRAY_JOBID=$(sbatch --parsable \
  --job-name="pCMOR_${PROJECT}_${YEAR}_${DOMAIN}" \
  --array=1-"$N" \
  --ntasks=1 \
  --partition="batch" \
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

#echo "Submitted array job: $ARRAY_JOBID with $N tasks"
#END_TIME=$(date +%s)
#TOTAL_SECONDS=$((END_TIME - START_TIME))
#echo "---------------------------------"
#echo "ARRAY JOB $ARRAY_JOBID FINISHED"
#echo "TOTAL EXECUTION TIME:"
#echo "$(date -u -d @$TOTAL_SECONDS +%T)"
#echo "---------------------------------"
#
# Call the function for testing (Dry-run is true by default)
#cleanup_unused_day_variables "$CSV_FILE" "$manifest" "false"
#exit 0
#

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

