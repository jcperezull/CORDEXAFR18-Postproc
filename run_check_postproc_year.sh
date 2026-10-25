#!/bin/bash

if [ $# -ne 1 ]; then
	    echo "Uso: $0 YEAR"
	        echo "Ejemplo: $0 2010"
		    exit 1
fi

YEAR="$1"
# Comprobar que YEAR es numérico
if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
    echo "ERROR: El año debe ser un número de cuatro dígitos."
    exit 1
fi

# Seleccionar directorio base según el año
if (( YEAR >= 2010 && YEAR <= 2019 )); then

    BASE="/disk/barbusano/barbusano2/Projects/AFR-CORDEX/Utils/Postproc/Tests/Output/0920/CORDEX/CMIP6/DD/AFR-18f/ULL/ECMWF-ERA5/evaluation/r1i1p1f1/WRF4611Q/v1-r1"

elif (( YEAR >= 1990 && YEAR <= 1999 )); then

    BASE="/disk/barbusano/barbusano2/Projects/AFR-CORDEX/Utils/Postproc/Tests/Output/CORDEX/CMIP6/DD/AFR-18f/ULL/ECMWF-ERA5/evaluation/r1i1p1f1/WRF4611Q/v1-r1"

else
    echo "ERROR: Año $YEAR no soportado."
    echo "Los rangos válidos son 1990-1999 y 2010-2019."
    exit 1
fi

echo "Año: $YEAR"
echo "Directorio base: $BASE"
echo

for freq in 1hr day; do
	    for month in {01..12}; do

		    echo "=========================================="
			  echo "Procesando: $YEAR / $month / $freq"
				echo "=========================================="

				./check_postproc.sh \
				  "${BASE}/${freq}/" \
				            "$YEAR" \
						       "$month" \
						       "$freq"

			done
done
