#!/usr/bin/env bash
set -euo pipefail

# Function to read namelist template to generate Output path
get_nml_quoted () {
  local file="$1" key="$2"
  awk -v k="$key" '
    $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
      if (match($0, /"[^"]*"/)) {
        v = substr($0, RSTART+1, RLENGTH-2)
        print v
        exit
      }
    }
  ' "$file"
}

###########

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <CSV_FILE> <YEAR> <DOMAIN> <PROJECT> [optional: FREQUENCY]"
  exit 1
fi

CSV_FILE=$1
YEAR=$2
DOMAIN=$3
PROJECT=$4
FREQ_FILTER=${5:-}

TEMPLATE="runctrl.current.nml_template_${DOMAIN}_${PROJECT}"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: Template not found: $TEMPLATE"
  exit 2
fi

##Build BasePath from template namelist file

DirOutputPostProRoot=$(get_nml_quoted "$TEMPLATE" "DirOutputPostProRoot")
project_id_nml=$(get_nml_quoted "$TEMPLATE" "project_id")
mip_era=$(get_nml_quoted "$TEMPLATE" "mip_era")
activity_id=$(get_nml_quoted "$TEMPLATE" "activity_id")
domain_id=$(get_nml_quoted "$TEMPLATE" "domain_id")
institution_id=$(get_nml_quoted "$TEMPLATE" "institution_id")
driving_source_id=$(get_nml_quoted "$TEMPLATE" "driving_source_id")
driving_experiment_id=$(get_nml_quoted "$TEMPLATE" "driving_experiment_id")
driving_variant_label=$(get_nml_quoted "$TEMPLATE" "driving_variant_label")
source_id=$(get_nml_quoted "$TEMPLATE" "source_id")
version_realization=$(get_nml_quoted "$TEMPLATE" "version_realization")
VERSION=$(get_nml_quoted "$TEMPLATE" "version")

BASEPATH="${DirOutputPostProRoot}/${project_id_nml}/${mip_era}/${activity_id}/${domain_id}/${institution_id}/${driving_source_id}/${driving_experiment_id}/${driving_variant_label}/${source_id}/${version_realization}"
####

# Si CSV_FILE es URL, descargar
if [[ ${CSV_FILE:0:5} == "https" ]]; then
  echo "Downloading the csv file: $CSV_FILE"
  wget -q "$CSV_FILE" -O data_request.csv
  CSV_FILE="data_request.csv"
fi

# Si filtras por frecuencia, crea sub-CSV
if [[ -n "${FREQ_FILTER}" ]]; then
  echo "Creating sub-csv with frequency=${FREQ_FILTER}"
  outcsv="data_request_${PROJECT}_${FREQ_FILTER}.csv"
  head -n 1 "$CSV_FILE" > "$outcsv"
  grep ",${FREQ_FILTER}," "$CSV_FILE" >> "$outcsv" || true
  CSV_FILE="$outcsv"
fi

# Leer cabecera para mapear columnas -> variables en bash
IFS=',' read -r -a headers < <(head -n 1 "$CSV_FILE")
read_template=$(printf ' %s' "${headers[@]}")

manifest="manifest_${PROJECT}_${YEAR}_${DOMAIN}.txt"
: > "$manifest"

notproc="variables_not_processed_${PROJECT}.txt"
rm -f "$notproc"

tail -n +2 "$CSV_FILE" | while IFS=, eval "read $read_template"; do
  VARIABLE=$out_name
  FREQ_AGGREGATE=$frequency
  FREQ=$FREQ_ORIG
  
  # Process cell_method to extract aggregate information to cdo

#  cell_method=$(grep "time:" <<< "$cell_methods" | awk -F"time: " '{print $2}' | awk '{print $1}')

  # Extraer cell_method (puede no existir "time:" -> entonces queda vacío)
  cell_method=$(awk '
    {
      m = match($0, /time:[[:space:]]*[^[:space:]]+/)
      if (m) {
        s = substr($0, RSTART, RLENGTH)
        sub(/^time:[[:space:]]*/, "", s)
        print s
      }
    }
  ' <<< "${cell_methods:-}" )

# Mapear a CDO
  if [[ "$cell_method" == "maximum" ]]; then
    METHOD="max"
  elif [[ "$cell_method" == "minimum" ]]; then
    METHOD="min"
  elif [[ -n "$cell_method" ]]; then
    METHOD="$cell_method"
  else
    METHOD="na"   # o "" si prefieres vacío
  fi

  # 1 hour variables that have to be day  aggregated

  if { [ "$FREQ" == "1hr" ] || [ "$FREQ" = "6hr" ]; }  && grep -q "${VARIABLE},day" "$CSV_FILE"; then
    FREQ_AGGREGATE="day"
  fi

  # Frequency update-- Converts to 1hr frq day and monthly variables to aggregate later
  if [ "$FREQ" == "day" ] && ! grep -q "$VARIABLE,1hr" "$CSV_FILE"; then
    FREQ="1hr"
  elif [ "$FREQ" == "mon" ] && ! grep -q "$VARIABLE,day" "$CSV_FILE"; then
    FREQ="1hr"
  fi



  # Reglas de “procesable”
  if [[ "${VARIABLE}" == "evspsblpot" ]] && grep -q "${VARIABLE},-999" CORDEX_CMIP6_variables.csv; then
    echo "${VARIABLE} not available in the current version of pCMORzier" >> "$notproc"
    continue
  fi

  if [[ "${VARIABLE}" == "tasmin" || "${VARIABLE}" == "tasmax" ]]; then
    echo "${VARIABLE} for 1hr not needed. Daily values will be extracted from tas." >> "$notproc"
    continue
  fi

  if ! grep -q "${VARIABLE}" CORDEX_CMIP6_variables.csv; then
    echo "Warning: Variable $VARIABLE not found in Fortran 90 file. Skipping..." >> "$notproc"
    echo "$VARIABLE" >> "$notproc"
    continue
  fi

  # Saltar mon/day si no está implementado (como tu script)
  if [[ "$FREQ" == "mon" || "$FREQ" == "day" ]]; then
    continue
  fi

  DATAPATH="${BASEPATH}/${FREQ}/${VARIABLE}/${VERSION}"


  # ✅ En vez de sbatch: añadimos una tarea al manifest
  echo "$YEAR $DOMAIN $VARIABLE $PROJECT $FREQ $FREQ_AGGREGATE $METHOD $DATAPATH" >> "$manifest"
done

echo "Manifest created: $manifest"
echo "Tasks: $(wc -l < "$manifest")"

