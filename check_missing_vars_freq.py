#!/usr/bin/env python3
"""
Script para verificar variables faltantes en el directorio de salida CORDEX.

Uso:
    python check_missing_vars_freq.py <directorio_base>

Ejemplo:
    python check_missing_vars_freq.py /home/jcperez/data/WRF4G_rocky/repository/output/CORDEXAFR-18/Evaluation/AFR18_4611p_Eval_7990/AFR18_4611p_Eval_7990/Postproc/1983/07/CORDEX/CMIP6/DD/AFR-18f/ULL/ECMWF-ERA5/evaluation/r1i1p1f1/WRF4611Q/v1-r1/
"""

import csv
import os
import sys
from collections import defaultdict

def verificar_variables(csv_path, base_dir):
    """
    Verifica qué variables faltan en el directorio de salida.
    
    Args:
        csv_path: ruta al archivo CORDEX_CMIP6_variables.csv
        base_dir: directorio base de salida donde están las frecuencias
    """
    
    # Diccionario para agrupar variables esperadas por frecuencia
    # Estructura: {'1hr': set('tas', 'pr'), 'day': set(...)}
    esperado = defaultdict(set)
    
    # 1. Leer el archivo CSV
    try:
        with open(csv_path, mode='r', encoding='utf-8') as f:
            lector = csv.reader(f)
            # Saltar cabecera
            header = next(lector)
            
            for fila in lector:
                if not fila or fila[0].startswith('#'):
                    continue
                
                var = fila[0].strip()  # output variable name
                
                # Las columnas de frecuencia son: mon(6), day(7), 6hr(8), 3hr(9), 1hr(10)
                frequencies = {
                    'mon': 6,
                    'day': 7,
                    '6hr': 8,
                    '3hr': 9,
                    '1hr': 10,
                }
                
                for freq_name, col_idx in frequencies.items():
                    if col_idx < len(fila) and fila[col_idx].strip() == 'x':
                        esperado[freq_name].add(var)
                
                # Si la variable no tiene frecuencia marcada pero tiene nombre, puede ser fx
                if var and not any(col_idx < len(fila) and fila[col_idx].strip() == 'x' 
                                   for col_idx in frequencies.values()):
                    # Posibles variables fx (orog, sftlf, etc)
                    if var in ['orog', 'sftlf']:
                        esperado['fx'].add(var)
                        
    except FileNotFoundError:
        print(f"Error: No se encontró el archivo CSV en {csv_path}")
        return False
    except Exception as e:
        print(f"Error al leer CSV: {e}")
        return False

    # Verificar que base_dir existe
    if not os.path.isdir(base_dir):
        print(f"Error: El directorio base no existe: {base_dir}")
        return False

    print(f"Verificando variables en: {base_dir}\n")
    print("=" * 70)
    
    hay_faltantes_global = False
    resumen_faltantes = defaultdict(list)

    # 2. Comprobar existencia en el sistema de archivos
    for freq in sorted(esperado.keys()):
        freq_dir = os.path.join(base_dir, freq)
        
        # Verificar si existe el directorio de frecuencia
        if not os.path.isdir(freq_dir):
            print(f"\n⚠️  ADVERTENCIA: Directorio de frecuencia no encontrado: {freq}/")
            hay_faltantes_global = True
            resumen_faltantes[freq] = sorted(esperado[freq])
            continue
        
        faltantes_en_freq = []
        presentes_en_freq = 0
        
        # Obtener variables existentes en este directorio de frecuencia
        try:
            vars_existentes = {d for d in os.listdir(freq_dir) 
                              if os.path.isdir(os.path.join(freq_dir, d))}
        except OSError as e:
            print(f"\n❌ Error al listar {freq_dir}: {e}")
            continue
        
        # Comparar variables esperadas vs existentes
        for var in esperado[freq]:
            if var not in vars_existentes:
                faltantes_en_freq.append(var)
            else:
                presentes_en_freq += 1
        
        # 3. Mostrar resultados por frecuencia
        total = len(esperado[freq])
        emoji = "✓" if not faltantes_en_freq else "❌"
        print(f"\n{emoji} {freq:6} - {presentes_en_freq}/{total} variables presentes")
        
        if faltantes_en_freq:
            hay_faltantes_global = True
            resumen_faltantes[freq] = sorted(faltantes_en_freq)
            print(f"   Variables faltantes ({len(faltantes_en_freq)}):")
            for v in sorted(faltantes_en_freq):
                print(f"      - {v}")

    print("\n" + "=" * 70)
    print("\n📋 RESUMEN:\n")
    
    total_faltantes = sum(len(vars) for vars in resumen_faltantes.values())
    
    if not hay_faltantes_global:
        print("✓ ¡Todas las variables están presentes!")
        return True
    else:
        print(f"❌ Total de variables faltantes: {total_faltantes}\n")
        for freq in sorted(resumen_faltantes.keys()):
            if resumen_faltantes[freq]:
                vars_list = ', '.join(resumen_faltantes[freq])
                print(f"  {freq:6}: {len(resumen_faltantes[freq])} variables")
                print(f"           {vars_list}")
        return False


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    
    base_dir = sys.argv[1]
    
    # Construir ruta al CSV basada en la ubicación del script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    csv_path = os.path.join(script_dir, 'CORDEX_CMIP6_variables.csv')
    
    # Ejecutar verificación
    success = verificar_variables(csv_path, base_dir)
    sys.exit(0 if success else 1)
        else:
            print(f"\n[OK] Frecuencia '{freq}': Todas las variables presentes.")

    if not hay_faltantes_global:
        print("\n✅ Verificación completada: No falta ninguna variable.")
    else:
        print("\n❌ Verificación completada: Se detectaron ausencias.")

# --- CONFIGURACIÓN ---
fichero_csv = 'tu_fichero.csv'  # Nombre de tu archivo
ruta_base = '/home/jcperez/data/WRF4G_rocky/repository/output/CORDEXAFR-18/Evaluation/AFR18_4611p_Eval_7990/AFR18_4611p_Eval_7990/Postproc/1983/07/CORDEX/CMIP6/DD/AFR-18f/ULL/ECMWF-ERA5/evaluation/r1i1p1f1/WRF4611Q/v1-r1/'

verificar_variables(fichero_csv, ruta_base)
