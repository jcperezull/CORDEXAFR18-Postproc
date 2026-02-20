#!/usr/bin/env bash
set -euo pipefail
source /home/jcperez/data/Projects/CORDEXAfr/Teide/WRFintelteide/WRF_pnetcdf/WRF_4.6.1/Intel2024/envvars.sh

# Use: <DATAPATH> <YEAR> <VARNAME> <METHOD>
if [[ "$#" -lt 4 ]]; then
  echo "Usage: $0 <DATAPATH> <YEAR> <VARNAME> <METHOD>"
  exit 1
fi

DATAPATH=$1
YEAR=$2
VARIABLE=$3
METHOD=$4

# To adjust
VERSION="v20240806"

# tasmin/tasmax vienen del fichero tas
if [[ "$VARIABLE" == "tasmin" || "$VARIABLE" == "tasmax" ]]; then
  VARFILE="tas"
else
  VARFILE="$VARIABLE"
fi

IN_DIR="$DATAPATH"
OUTDIR="$DATAPATH/../../../day/$VARIABLE/$VERSION"
mkdir -p "$OUTDIR"

if [[ ! -d "$IN_DIR" ]]; then
  echo "$VARIABLE not processed, no 1hr dir: $IN_DIR"
  exit 0
fi

shopt -s nullglob
files=( "$IN_DIR"/*_"$YEAR"*.nc )
shopt -u nullglob

if (( ${#files[@]} == 0 )); then
  echo "$VARIABLE not processed, no 1hr files for year $YEAR in $IN_DIR"
  exit 0
fi

echo "Aggregating daily: VAR=$VARIABLE (from $VARFILE), METHOD=day$METHOD, YEAR=$YEAR"
for file in "${files[@]}"; do
  FNAME=$(basename "$file")

  FNAME_DAY="${FNAME/_1hr_/_day_}"
  FNAME_DAY="${FNAME_DAY//0000/}"
  FNAME_DAY="${FNAME_DAY//2300/}"
  FNAME_DAY="${FNAME_DAY//0030/}"
  FNAME_DAY="${FNAME_DAY//2330/}"

  out="$OUTDIR/$FNAME_DAY"

  cdo "day$METHOD" "$file" "$out"

  ncatted -O -h -a CDI,global,d,, "$out"
  ncatted -O -h -a history,global,d,, "$out"
  ncatted -O -h -a CDO,global,d,, "$out"
  ncatted -O -h -a tracking_id,global,m,c,"hdl:21.14103/$(uuidgen)" "$out"

  if [[ "$VARIABLE" == "tasmin" || "$VARIABLE" == "tasmax" ]]; then
    ncrename -h -v "$VARFILE","$VARIABLE" "$out"
    ncatted  -h -a long_name,"$VARIABLE",m,c,"Daily ${METHOD^} Near-Surface Air Temperature" "$out"
    ncatted  -h -a cell_methods,"$VARIABLE",m,c,"time: $METHOD" "$out"
    ncatted  -h -a variable_id,global,m,c,"$VARIABLE" "$out"
    rename "${VARFILE}_" "${VARIABLE}_" "$out" 2>/dev/null || true
  fi
done

echo "Done daily aggregation for $VARIABLE"

