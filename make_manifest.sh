#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# make_manifest.sh
#
# Uso:
#   ./make_manifest.sh <CSV_FILE> <YEAR> <DOMAIN> <PROJECT> <OUTPUT_DIRECTORY> [optional: FREQUENCY]
#
# Genera:
#   manifest_<PROJECT>_<YEAR>_<DOMAIN>.txt
#
# Formato de cada línea:
#   YEAR DOMAIN VARIABLE PROJECT FREQ FREQ_AGGREGATE METHOD DATAPATH
# ============================================================

# ---------- Helpers ----------

get_nml_quoted() {
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

extract_time_method() {
  # Extrae el valor tras "time:" del campo cell_methods
  # Ejemplos:
  #   "time: mean"     -> mean
  #   "time: maximum"  -> maximum
  #   ""               -> ""
  local s="${1:-}"
  awk '
    {
      m = match($0, /time:[[:space:]]*[^[:space:]]+/)
      if (m) {
        x = substr($0, RSTART, RLENGTH)
        sub(/^time:[[:space:]]*/, "", x)
        print x
      }
    }
  ' <<< "$s"
}

map_method_to_cdo() {
  local m="${1:-}"
  case "$m" in
    maximum) echo "max" ;;
    minimum) echo "min" ;;
    ""      ) echo "na"  ;;
    *       ) echo "$m"  ;;
  esac
}

csv_has_var_freq() {
  local var="$1"
  local freq="$2"
  [[ -n "${CSV_INDEX[$var|$freq]:-}" ]]
}

# ---------- Argumentos ----------

if [[ "$#" -lt 5 ]]; then
  echo "Usage: $0 <CSV_FILE> <YEAR> <DOMAIN> <PROJECT> <OUTPUT_DIRECTORY> [optional: FREQUENCY]"
  exit 1
fi

CSV_FILE=$1
YEAR=$2
DOMAIN=$3
PROJECT=$4
DIR_OUT=$5
FREQ_FILTER=${6:-}

TEMPLATE="runctrl.current.nml_template_${DOMAIN}_${PROJECT}"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: Template not found: $TEMPLATE"
  exit 2
fi

# ---------- Leer template ----------

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

BASEPATH="${DIR_OUT}/${project_id_nml}/${mip_era}/${activity_id}/${domain_id}/${institution_id}/${driving_source_id}/${driving_experiment_id}/${driving_variant_label}/${source_id}/${version_realization}"

# ---------- Descargar CSV si es URL ----------

if [[ "${CSV_FILE:0:5}" == "https" ]]; then
  echo "Downloading the csv file: $CSV_FILE"
  wget -q "$CSV_FILE" -O data_request.csv
  CSV_FILE="data_request.csv"
fi

# ---------- Filtrar por frecuencia si se pide ----------
# OJO: esto mantiene solo filas cuya frecuencia coincide exactamente.
# Si quieres construir manifest a partir de varias frecuencias relacionadas
# (por ejemplo day dependiente de 1hr), es mejor NO filtrar.
if [[ -n "$FREQ_FILTER" ]]; then
  echo "Creating sub-csv with frequency=${FREQ_FILTER}"
  outcsv="data_request_${PROJECT}_${FREQ_FILTER}.csv"
  head -n 1 "$CSV_FILE" > "$outcsv"
  grep ",${FREQ_FILTER}," "$CSV_FILE" >> "$outcsv" || true
  CSV_FILE="$outcsv"
fi

if [[ ! -s "$CSV_FILE" ]]; then
  echo "ERROR: CSV file is empty or missing: $CSV_FILE"
  exit 3
fi

# ---------- Mapear columnas por nombre ----------
IFS=',' read -r -a headers < <(head -n 1 "$CSV_FILE")

declare -A COL
for i in "${!headers[@]}"; do
  h="${headers[$i]}"
  h="${h//$'\r'/}"
  COL["$h"]=$i
done

required_cols=(out_name frequency cell_methods)
for c in "${required_cols[@]}"; do
  if [[ -z "${COL[$c]:-}" && "${COL[$c]:-0}" != "0" ]]; then
    echo "ERROR: Required column '$c' not found in CSV header"
    exit 4
  fi
done

idx_out_name=${COL[out_name]}
idx_frequency=${COL[frequency]}
idx_cell_methods=${COL[cell_methods]}

# ---------- Precargar índice variable|freq -> cell_methods ----------
declare -A CSV_INDEX
declare -a CSV_LINES

line_no=0
while IFS= read -r line; do
  ((line_no++)) || true

  # Saltar cabecera
  if [[ "$line_no" -eq 1 ]]; then
    continue
  fi

  [[ -z "${line//[[:space:]]/}" ]] && continue

  IFS=',' read -r -a row <<< "$line"

  out_name="${row[$idx_out_name]:-}"
  frequency="${row[$idx_frequency]:-}"
  cell_methods="${row[$idx_cell_methods]:-}"

  out_name="${out_name//$'\r'/}"
  frequency="${frequency//$'\r'/}"
  cell_methods="${cell_methods//$'\r'/}"

  [[ -z "$out_name" || -z "$frequency" ]] && continue

  CSV_INDEX["$out_name|$frequency"]="$cell_methods"
  CSV_LINES+=("$line")
done < "$CSV_FILE"

manifest="manifest_${PROJECT}_${YEAR}_${DOMAIN}.txt"
: > "$manifest"

notproc="variables_not_processed_${PROJECT}.txt"
rm -f "$notproc"

# ---------- Bucle principal ----------
for line in "${CSV_LINES[@]}"; do
  IFS=',' read -r -a row <<< "$line"

  VARIABLE="${row[$idx_out_name]:-}"
  FREQ_RAW="${row[$idx_frequency]:-}"
  CELL_METHODS_RAW="${row[$idx_cell_methods]:-}"

  VARIABLE="${VARIABLE//$'\r'/}"
  FREQ_RAW="${FREQ_RAW//$'\r'/}"
  CELL_METHODS_RAW="${CELL_METHODS_RAW//$'\r'/}"

  # ---- Comprobaciones que quieres conservar ----

  if [[ "$VARIABLE" == "evspsblpot" ]] && grep -q "^${VARIABLE},-999" CORDEX_CMIP6_variables.csv; then
    echo "${VARIABLE} not available in the current version of pCMORizer" >> "$notproc"
    continue
  fi

  if [[ "$VARIABLE" == "tasmin" || "$VARIABLE" == "tasmax" ]]; then
    echo "${VARIABLE} for 1hr not needed. Daily values will be extracted from tas." >> "$notproc"
    continue
  fi

  if ! grep -q "^${VARIABLE}," CORDEX_CMIP6_variables.csv; then
    echo "Warning: Variable $VARIABLE not found in Fortran 90 file. Skipping..." >> "$notproc"
    echo "$VARIABLE" >> "$notproc"
    continue
  fi

  # ---- Reglas nuevas de normalización freq/aggregate/method ----

  FREQ=""
  FREQ_AGGREGATE=""
  METHOD="na"

  case "$FREQ_RAW" in
    1hr)
      FREQ="1hr"

      if csv_has_var_freq "$VARIABLE" "day"; then
        FREQ_AGGREGATE="day"
        day_cell_methods="${CSV_INDEX[$VARIABLE|day]}"
        day_time_method="$(extract_time_method "$day_cell_methods")"
        METHOD="$(map_method_to_cdo "$day_time_method")"
      else
        FREQ_AGGREGATE="1hr"
        own_time_method="$(extract_time_method "$CELL_METHODS_RAW")"
        METHOD="$(map_method_to_cdo "$own_time_method")"
      fi
      ;;
    6hr)
      FREQ="6hr"
      FREQ_AGGREGATE="6hr"
      METHOD="na"
      ;;
    day)
      # Si ya existe 1hr para esa variable, se procesará desde la fila 1hr.
      # Saltamos esta para evitar duplicar tareas.
      if csv_has_var_freq "$VARIABLE" "1hr"; then
        continue
      fi

      FREQ="1hr"
      FREQ_AGGREGATE="day"
      day_time_method="$(extract_time_method "$CELL_METHODS_RAW")"
      METHOD="$(map_method_to_cdo "$day_time_method")"
      ;;
    mon)
      continue
      ;;
    fx)
      FREQ="fx"
      FREQ_AGGREGATE="fx"
      METHOD="na"
      ;;
    *)
      # Para cualquier otra frecuencia no contemplada explícitamente:
      # se conserva freq=freq_raw y se intenta leer el método de su propia fila.
      FREQ="$FREQ_RAW"
      FREQ_AGGREGATE="$FREQ_RAW"
      own_time_method="$(extract_time_method "$CELL_METHODS_RAW")"
      METHOD="$(map_method_to_cdo "$own_time_method")"
      ;;
  esac

  DATAPATH="${BASEPATH}/${FREQ}/${VARIABLE}/${VERSION}"

  echo "$YEAR $DOMAIN $VARIABLE $PROJECT $FREQ $FREQ_AGGREGATE $METHOD $DATAPATH" >> "$manifest"
done

echo "Manifest created: $manifest"
echo "Tasks: $(wc -l < "$manifest")"
[[ -f "$notproc" ]] && echo "Warnings written to: $notproc"
