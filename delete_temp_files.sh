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

if [[ $# -lt 3 ]]; then
    echo "ERROR: Incorrect number of arguments."
    echo "Uso: $0 CSV_FILE MANIFEST_FILE ARRAY_JOB_ID [DRY_RUN]"
    echo "Example: $0 variables.csv  manifest_AFRCORDEX18_1979_d01.txt 134278 false"
    exit 1
fi
CSV_FILE=$1
MANIFEST=$2
ARRAY_JOBID=$3
DRYRUN=${4:-false}

# 1. Validación básica de presencia de argumentos
if [[ ! -f "$CSV_FILE" ]]; then
    echo "First argument should be a valid data request csv file"
    exit 1
fi

# 2. Comprobar si DIR_IN existe como directorio
if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: Second argument should be a manifest file generated with make_manifest.sh"
    exit 1
fi

echo "Array job $ARRAY_JOBID finished at $(date)"

echo "Running cleanup process"
START_TIME=$(date +%s)
cleanup_unused_day_variables "$CSV_FILE" "$MANIFEST" "$DRYRUN"
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
echo "Cleanup time: $(date -u -d @$ELAPSED +%T)"
exit 0


