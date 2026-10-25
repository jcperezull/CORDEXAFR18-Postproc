#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Uso: $0 <path_al_manifest>"
    exit 1
fi

MANIFEST="$1"
DIR="ls"

# Verificar si manifest existe
if [ ! -f "$MANIFEST" ]; then
    echo "Archivo $MANIFEST no encontrado."
    exit 1
fi

# Verificar si dir existe
if [ ! -d "$DIR" ]; then
    echo "Directorio $DIR no encontrado."
    exit 1
fi

# Extraer variables
awk '{print $3}' "$MANIFEST" | sort | uniq > variables.txt

# Listar subdirs
ls -1d "$DIR"/*/ 2>/dev/null | xargs -n1 basename | sort > existing.txt

# Faltantes
echo "Variables faltantes:"
comm -23 variables.txt existing.txt

# Limpiar
rm variables.txt existing.txt