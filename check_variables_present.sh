#!/usr/bin/env bash

CSV_FILE="data-request_eurocordex.csv"
OUTPUT_DIR="/home/jcperez/data/Projects/CORDEXAfr/Teide/Postprocdir/pCMOR18282/pCMORizerPack/Output/CORDEX/CMIP6/DD/AFR-18f/ULL/ECMWF-ERA5/evaluation/r1i1p1f1/WRF4611Q/v1-r1/1hr" # Ajusta esta ruta

echo "-------------------------------------------------------"
echo "AUDITING: Checking if all 1hr variables exist in $OUTPUT_DIR"
echo "-------------------------------------------------------"

# 1. Get the list of unique variables with '1hr' frequency from the CSV
expected_vars=$(grep ",1hr," "$CSV_FILE" | cut -d',' -f1 | sort -u)
expected_count=$(echo "$expected_vars" | wc -w)

echo "Expected variables (1hr): $expected_count"

# 2. Check each variable against the directory contents
missing_count=0
missing_vars=""

for var in $expected_vars; do
    if [[ ! -d "${OUTPUT_DIR}/${var}" ]]; then
        echo "  [MISSING] Variable folder not found: ${var}"
        missing_vars+="${var} "
        ((missing_count++))
    fi
done

echo "-------------------------------------------------------"
if [[ $missing_count -eq 0 ]]; then
    echo "SUCCESS: All $expected_count variables are present."
else
    echo "FAILURE: $missing_count variable(s) are missing from the directory."
    echo "Missing list: $missing_vars"
fi
echo "-------------------------------------------------------"
