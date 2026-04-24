#!/usr/bin/env bash

set -u

if [ $# -ne 3 ]; then
    echo "Uso: $0 AAAA MM FREQ"
    echo "Ejemplo: $0 1983 01 1hr"
    exit 1
fi

YEAR="$1"
MONTH="$2"
FREQ="$3"

if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
    echo "ERROR: el año debe tener formato AAAA"
    exit 1
fi

if ! [[ "$MONTH" =~ ^[0-9]{2}$ ]] || [ "$MONTH" -lt 1 ] || [ "$MONTH" -gt 12 ]; then
    echo "ERROR: el mes debe tener formato MM entre 01 y 12"
    exit 1
fi

if ! [[ "$FREQ" =~ ^(1hr|6hr|day)$ ]]; then
    echo "FREQ no es ni 1hr, ni 6hr, ni day"
fi


YYYYMM="${YEAR}${MONTH}"

VERSION_DIR="v20240806"
FIXED_MIDDLE="_AFR-18f_ECMWF-ERA5_evaluation_r1i1p1f1_ULL_WRF4611Q_v1-r1_${FREQ}_"
OUTFILE="informe_postproceso_${YYYYMM}.txt"

found_missing=0
found_suspicious=0
found_multiple=0

{
    echo "Informe de comprobación de ficheros postprocesados"
    echo "Directorio base: $(pwd)"
    echo "Fecha: $(date)"
    echo "Periodo buscado: ${YYYYMM}"
    echo "============================================================"
    echo
} > "$OUTFILE"

for vardir in */ ; do
    [ -d "$vardir" ] || continue

    var="${vardir%/}"
    pattern="${var}/${VERSION_DIR}/${var}${FIXED_MIDDLE}${YYYYMM}*.nc"

    shopt -s nullglob
    files=( $pattern )
    shopt -u nullglob

    if [ ${#files[@]} -eq 0 ]; then
        echo "[FALTA] No existe fichero para patrón: $pattern" >> "$OUTFILE"
        found_missing=1
        continue
    fi

    if [ ${#files[@]} -gt 1 ]; then
        echo "[AVISO] Múltiples ficheros encontrados para ${var}:" >> "$OUTFILE"
        for f in "${files[@]}"; do
            echo "        $f" >> "$OUTFILE"
        done
        found_multiple=1
    fi

    filepath="${files[0]}"

    info_output=$(cdo info "$filepath" 2>&1 | head -5)
    cdo_status=$?

    if [ $cdo_status -ne 0 ] || echo "$info_output" | grep -Eqi "No such file|Open failed|Unsupported|Error"; then
        echo "[ERROR CDO] Problema ejecutando cdo info sobre: $filepath" >> "$OUTFILE"
        echo "$info_output" >> "$OUTFILE"
        echo >> "$OUTFILE"
        found_suspicious=1
        continue
    fi

    data_lines=$(echo "$info_output" | tail -n +2 | head -n 3)
    nlines=$(echo "$data_lines" | sed '/^[[:space:]]*$/d' | wc -l)

    if [ "$nlines" -lt 3 ]; then
        echo "[SOSPECHOSO] Menos de 3 líneas de datos en cdo info para: $filepath" >> "$OUTFILE"
        echo "$info_output" >> "$OUTFILE"
        echo >> "$OUTFILE"
        found_suspicious=1
        continue
    fi

    line_num=0
    suspicious_this_file=0



    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        line_num=$((line_num + 1))

        # Extraemos la sección entre el primer y segundo ':'
        # La línea tiene este formato -> Num : Fecha Hora Nivel Grid Miss : Min Mean Max : Param
        stats_part=$(echo "$line" | cut -d':' -f5)

        # En la sección central (Min Mean Max), el Min es la col 1 y el Max la col 3
        # Usamos awk sin -F para que colapse los espacios automáticamente
        minval=$(echo "$stats_part" | awk '{print $1}')
        maxval=$(echo "$stats_part" | awk '{print $3}')

        if [ -z "$minval" ] || [ -z "$maxval" ]; then
            echo "[SOSPECHOSO] No se pudo interpretar min/max en $filepath, línea $line_num" >> "$OUTFILE"
            echo "              Línea: $line" >> "$OUTFILE"
            suspicious_this_file=1
            found_suspicious=1
            continue
        fi

        # Comparación de cadenas (funciona para números con decimales en bash)
        if [ "$minval" = "$maxval" ]; then
            echo "[SOSPECHOSO] min = max en $filepath, línea $line_num" >> "$OUTFILE"
            echo "              min=$minval max=$maxval" >> "$OUTFILE"
            echo "              Línea: $line" >> "$OUTFILE"
            suspicious_this_file=1
            found_suspicious=1
        fi
    done <<< "$data_lines"


    if [ $suspicious_this_file -eq 0 ]; then
        echo "[OK] $filepath" >> "$OUTFILE"
    fi
done

{
    echo
    echo "============================================================"
    if [ $found_missing -eq 0 ] && [ $found_suspicious -eq 0 ] && [ $found_multiple -eq 0 ]; then
        echo "Resultado final: no se detectaron problemas."
    else
        echo "Resultado final: revisar entradas marcadas como [FALTA], [AVISO], [ERROR CDO] o [SOSPECHOSO]."
    fi
} >> "$OUTFILE"

echo "Informe generado en: $OUTFILE"
