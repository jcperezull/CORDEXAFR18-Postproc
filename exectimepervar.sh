#!/bin/bash

# 1. Validación de argumentos
if [ "$#" -ne 4 ]; then
    echo "Uso: $0 <job_id> <max_jobs> <year> <logdir>"
    echo "Ejemplo: $0 138480 329 1980 Logs/139458/"
    exit 1
fi

JOBID=$1
MAX_JID=$2
YEAR=$3
PREFIX=$4

# Inicialización de variables para extremos
# Ponemos el mínimo inicial en un valor muy alto (9999999 segundos)
MIN_TIME=9999999
MAX_TIME=-1

MIN_INFO=""
MAX_INFO=""

# Variable para sumar el tiempo total en segundos
TOTAL_SECONDS=0
RESULTS=()

# 2. Bucle sobre el rango de JIDs
for jid in $(seq 0 "$MAX_JID"); do
    #FILE="cmor${jid}.out"
    #FILE="$PREFIX/worker_${JOBID}_${jid}.out"
    FILE="$PREFIX/pCMOR_AFRCORDEX18_${YEAR}_d01_${JOBID}_${jid}.out"
    if [ -f "$FILE" ]; then
        # Extraer nombre de la variable
	VAR_NAME=$(head $FILE | grep "Processing variables: " | awk -F"Processing variables: " '{print $2}' | awk -F"[]'[]" '{print $3}')

        # Extraer horas de inicio y fin
        T_START=$(grep "Starting:" "$FILE" | awk -F"Starting: " '{print $2}' | awk '{print $1}')
        T_END=$(grep "Finishing:" "$FILE" | awk -F"Finishing: " '{print $2}' | awk '{print $1}')
	NODE=$(grep "Node:" "$FILE" | awk '{print $2}')
        [ -z "$NODE" ] && NODE="N/A" # Por si la línea no existe aún

        # Si ambas horas existen, calcular diferencia
        if [[ -n "$T_START" && -n "$T_END" ]]; then
            S_START=$(date -d "$T_START" +%s)
            S_END=$(date -d "$T_END" +%s)

            DIFF=$(( S_END - S_START ))

            # Corrección por si el proceso cruzó la medianoche
            if [ $DIFF -lt 0 ]; then
                DIFF=$(( DIFF + 86400 ))
            fi
	    
	    # Comparación para el Máximo
            if [ $DIFF -gt $MAX_TIME ]; then
                MAX_TIME=$DIFF
                MAX_INFO="Fichero: $FILE | Variable: $VAR_NAME | Tiempo: $(date -u -d @"$DIFF" +"%T")"
            fi

            # Comparación para el Mínimo
            if [ $DIFF -lt $MIN_TIME ]; then
                MIN_TIME=$DIFF
                MIN_INFO="Fichero: $FILE | Variable: $VAR_NAME | Tiempo: $(date -u -d @"$DIFF" +"%T")"
            fi

            # Formatear duración de este fichero
            DURATION=$(date -u -d @"$DIFF" +"%T")
	    RESULTS+=("$DIFF|$jid|$VAR_NAME|$NODE|$DURATION")

#            printf "%-7s | %-10s | %s\n" "$jid" "$VAR_NAME" "$DURATION"
        fi
    else
        echo "JID $jid: Archivo $FILE no encontrado."
    fi
done
echo "-----------------------------------------------------------------------"
echo "RESULTADOS ORDENADOS (mayor a menor tiempo):"
printf "%-7s | %-12s | %-15s | %s\n" "JID" "VARIABLE" "NODO" "DURATION"
echo "-----------------------------------------------------------------------"

# Procesar y mostrar resultados incluyendo el Nodo
printf "%s\n" "${RESULTS[@]}" | sort -t'|' -nr -k1 | while IFS='|' read -r DIFF jid var node duration; do
    printf "%-7s | %-12s | %-15s | %s\n" "$jid" "$var" "$node" "$duration"
done

# 3. Mostrar los resultados de los extremos
echo "-------------------------------"
if [ "$MAX_TIME" -ne -1 ]; then
    echo "TIEMPOS EXTREMOS DETECTADOS:"
    echo "MÁXIMO -> $MAX_INFO"
    echo "MÍNIMO -> $MIN_INFO"
else
    echo "No se encontraron datos válidos para procesar."
fi


