#!/usr/bin/env python
# coding: utf-8
#
# runctrl.vars.nml generator 
# The script generates namelist for CORDEX CMIP6 variables based on the list published on zenodo:
# https://zenodo.org/records/8414798
# 
# To run the script a csv file with variables containing all the metadata is necessary to be placed in the running directory.
# The csv file is CORDEX_CMIP6_variables.csv
#
#
# To run the script in the command line:
#     python generate_vars_namelist.py custom var1 var2 var3  --> runctrl.vars.custom.nml will be created, with info on var1 var2 var3
#     python generate_vars_namelist.py var1  --> runctrl.vars.var1.nml will be created, with info on var1
#     python generate_vars_namelist.py core  --> runctrl.vars.core.nml will be created, with info on core variables
#     python generate_vars_namelist.py trier1  --> runctrl.vars.trier1.nml will be created, with info on trier1 variables
#
#
# Contact: milovacj@unican.es

wrfpress_levels=[1000, 925, 850, 700, 600, 500, 400, 300, 250, 200]

def print_instructions():
    """Prints instructions."""
    instructions = """
    Usage:
    generate_vars_namelist.py [options]

    Options:
        custom <variables>  (list variables in form - var1 var2 var3 ...)
            output: runctrl.vars.custom.nml

        <variable>  (list variable in form - var1)
        output: runctrl.vars.var1.nml

        <variable_list>  (one of already set variable lists, e.g. - core)
        output: runctrl.vars.variable_list.nml    

            variable_lists:
                core, trier1, trier2, 
                trier1_sfc, trier1_int, trier1_plevel, trier1_height,
                trier2_sfc, trier2_int, trier2_plevel, trier2_height,trier2_fx
    """
    print(instructions)

# Define all the functions:
def generate_namelist(varlist, nvars):
    
    # Set header and footer:
    header = "&vars\n"
    footer = "/\n"
    
    # Set titles:
    titles = [
        '   cordexID',
        '   var_wrf',
        '   var_cmip',
        '   standard_name',
        '   long_name',
        '   units',
        '   height',
        '   plevel',
        '   positive',
        '   timefx',
        '   cmfx',
        '   time1hr',
        '   cm1hr',
        '   time3hr',
        '   cm3hr',
        '   time6hr',
        '   cm6hr',
        '   timeDay',
        '   cmDay',
        '   timeMon',
        '   cmMon',
        '   timeSea',
        '   cmSea',
        '   filetype',
        '   interpolate'
    ]
    
    # Calculate the maximum length of each column
    column_length = max(len(title) for title in titles) + 5  # Add padding for better readability
    
    # Create lines in the template
    variable_lines = ""
    for title,j in zip(titles,range(0,len(titles))):
        variable_lines += "{:<{}} = ".format(title,20)
        for i in range(0,nvars):
            if varlist[i] is None:
                print(f"Warning:{title} for {varnames[i]} is not available.")
            else:
                if i > len(varlist)-1:
                    nspace = max(len(varline) for varline in fill_varlist) + 1  # Add padding for better readability
                    variable_lines += "{:<{}},".format(fill_varlist[j], nspace)
            
                else:
                    nspace = max(len(varline) for varline in varlist[i]) + 1  # Add padding for better readability
                    variable_lines += "{:<{}},".format(varlist[i][j], nspace)
            
        variable_lines += "\n"

    # Create the template
    template = f"{header}{variable_lines}{footer}"
    return template

def map_to_tf(value):
    return {'x': 'T', 'other': 'F'}.get(value, 'F')

def find_height(name):
    numbers = ''.join(char for char in name if char.isdigit())
    value = numbers if numbers else "-999"
    if value == "999":
        value = "-999"
    return value

def create_vararray(varname, filepath):
    import csv

    def read_variable_info(filepath):
        data = []

        with open(filepath, 'r') as file:
            reader = csv.DictReader(file, delimiter=',')
            for row in reader:
                data.append(row)

        return data

    filepath = filepath  # Change this to the actual file path
    variable_info = read_variable_info(filepath)

    # Print the variable information
    for entry in variable_info:
        if entry['output variable name']==varname:
            if entry['ag']=="a":
                cm1hr = cm3hr = cm6hr = cmDay = "'mean'"
            elif varname=="sund":
                cm1hr = cm3hr = cm6hr = cmDay = "'sum'"
            elif "max" in varname:
                cm1hr = cm3hr = cm6hr = cmDay = "'max'"
            elif "min" in varname:
                cm1hr = cm3hr = cm6hr = cmDay = "'min'"
            else:
                cm1hr = cm3hr = cm6hr = "'point'"
                cmDay = "'mean'"
                
            if "down" in entry['standard_name'] or \
            "incoming" in entry['standard_name'] or \
            varname=="rsdt":
                positive = f"'down'"
            elif "upward" in entry['standard_name'] or \
            "upwelling" in entry['standard_name'] or \
            "outgoing"  in entry['standard_name']:
                positive = f"'up'"
            else:
                positive = f"'-999'"                
             
                
            height="-999"                 
            plevel="-999"
            
            if any(char.isdigit() for char in entry['WRF variable']):
                height = find_height(entry['WRF variable'])  
              
            
            for name in ["ua","va","wa","ta","zg","hus"]:
                if name in varname:
                    if "m" in varname:       
                        height = find_height(varname)
                    else:
                        plevel = find_height(varname)                          
                         
            if "tasmax" in varname or "tasmin" in varname:
                #ftype="'x'"
                ftype="'s'"
            elif plevel != "-999" and "wa" not in varname and plevel in map(str, wrfpress_levels): 
                ftype="'p'" 
            elif varname == "od550aer": 
                ftype="'p'"               
            else:
                ftype="'s'"            
                                         

            vararray = ["999",\
                        f"'{entry['WRF variable']}'",\
                        f"'{entry['output variable name']}'",\
                        f"'{entry['standard_name']}'",\
                        f"'{entry['long_name']}'",\
                        f"'{entry['units']}'",\
                       height,\
                       plevel,\
                       positive,\
                       "T",\
                       "'point'",
                       "T",\
                       cm1hr,\
                       "T",\
                       cm3hr,\
                       "T",\
                       cm6hr,\
                       "T",\
                       cmDay,\
                       "T",\
                       "'mean'",\
                       "F",\
                       "'mean'",\
                       ftype,\
                       "T",\
                      ]   
            return vararray

def create_multi_vararray(filepath,*varnames):
    result = []
    
    for varname in varnames:
        vararray = create_vararray(varname,filepath)
        result.append(vararray)
    
    return result


# Complete lists of core, trier1, and trier2 CORDEX-CMIP6 variables:
core = ('tas', 'tasmax', 'tasmin', 'pr', 'evspsbl', 'huss', 'hurs', 'ps', 
                 'psl', 'sfcWind', 'uas', 'vas', 'clt', 'rsds', 'rlds', 'orog', 'sftlf')

trier1 = ('ts', 'tsl', 'prc', 'prhmax', 'prsn', 'mrros', 'mrro', 'snm', 'tauu', \
                   'tauv', 'sfcWindmax', 'sund', 'rsdsdir', 'rsus', 'rlus', 'rlut', 'rsdt', \
                   'rsut', 'hfls', 'hfss', 'mrfso', 'mrfsos', 'mrsfl', 'mrso', 'mrsos', \
                   'mrsol', 'snw', 'snc', 'snd', 'siconca', 'zmla', 'prw', 'clwvi', 'clivi', \
                   'ua1000', 'ua925', 'ua850', 'ua700', 'ua600', 'ua500', 'ua400', 'ua300', \
                   'ua250', 'ua200', 'va1000', 'va925', 'va850', 'va700', 'va600', 'va500', \
                   'va400', 'va300', 'va250', 'va200', 'ta1000', 'ta925', 'ta850', 'ta700', \
                   'ta600', 'ta500', 'ta400', 'ta300', 'ta250', 'ta200', 'hus1000', 'hus925', \
                   'hus850', 'hus700', 'hus600', 'hus500', 'hus400', 'hus300', 'hus250', \
                   'hus200', 'zg1000', 'zg925', 'zg850', 'zg700', 'zg600', 'zg500', 'zg400', \
                   'zg300', 'zg250', 'zg200', 'wa1000', 'wa925', 'wa850', 'wa700', 'wa600', \
                   'wa500', 'wa400', 'wa300', 'wa250', 'wa200', 'ua50m', 'ua100m', 'ua150m', \
                   'va50m', 'va100m', 'va150m', 'ta50m', 'hus50m')

trier2 = ('evspsblpot', 'wsgsmax', 'clh', 'clm', 'cll', 'rsdscs', 'rldscs', \
                   'rsuscs', 'rluscs', 'rsutcs', 'rlutcs', 'z0', 'CAPE', 'LI', 'CIN', \
                   'CAPEmax', 'LImax', 'CINmax', 'od550aer', 'ua150', 'ua100', 'ua70', \
                   'ua50', 'ua30', 'ua20', 'ua10', 'va150', 'va100', 'va70', 'va50', \
                   'va30', 'va20', 'va10', 'ta150', 'ta100', 'ta70', 'ta50', 'ta30', \
                   'ta20', 'ta10', 'hus150', 'hus100', 'hus70', 'hus50', 'hus30', \
                   'hus20', 'hus10', 'zg150', 'zg100', 'zg70', 'zg50', 'zg30', 'zg20', \
                   'zg10', 'wa150', 'wa100', 'wa70', 'wa50', 'wa30', 'wa20', 'wa10', \
                   'ua750', 'va750', 'ta750', 'hus750', 'zg750', 'wa750', 'ua200m', \
                   'ua250m', 'ua300m', 'va200m', 'va250m', 'va300m', 'sftgif', 'mrsofc', \
                   'rootd', 'sftlaf', 'sfturf', 'dtb', 'areacella')

# Variables separated in smaller chunks for trier1 and trier2
trier1_sfc = ('ts', 'tsl', 'prc', 'prhmax', 'prsn', 'mrros', 'mrro', 'snm', 'tauu', \
                   'tauv', 'sfcWindmax', 'sund', 'rsdsdir', 'rsus', 'rlus', 'rlut', 'rsdt', \
                   'rsut', 'hfls', 'hfss', 'mrfso', 'mrfsos', 'mrsfl', 'mrso', 'mrsos', \
                   'mrsol', 'snw', 'snc', 'snd', 'siconca', 'zmla', 'prw', 'clwvi', 'clivi')

trier1_int = ('prw', 'clwvi', 'clivi')

trier1_plevel = ( 'ua1000', 'ua925', 'ua850', 'ua700', 'ua600', 'ua500', 'ua400', 'ua300', \
                   'ua250', 'ua200', 'va1000', 'va925', 'va850', 'va700', 'va600', 'va500', \
                   'va400', 'va300', 'va250', 'va200', 'ta1000', 'ta925', 'ta850', 'ta700', \
                   'ta600', 'ta500', 'ta400', 'ta300', 'ta250', 'ta200', 'hus1000', 'hus925', \
                   'hus850', 'hus700', 'hus600', 'hus500', 'hus400', 'hus300', 'hus250', \
                   'hus200', 'zg1000', 'zg925', 'zg850', 'zg700', 'zg600', 'zg500', 'zg400', \
                   'zg300', 'zg250', 'zg200', 'wa1000', 'wa925', 'wa850', 'wa700', 'wa600', \
                   'wa500', 'wa400', 'wa300', 'wa250', 'wa200')

trier1_height = ('ua50m', 'ua100m', 'ua150m', 'va50m', 'va100m', 'va150m', 'ta50m', 'hus50m')

trier2_sfc = ('evspsblpot', 'wsgsmax', 'rsdscs', 'rldscs', 'rsuscs', 'rluscs', 'rsutcs', 'rlutcs', 'z0') 

trier2_int = ( 'clh', 'clm', 'cll', 'CAPE', 'LI', 'CIN','CAPEmax', 'LImax', 'CINmax', 'od550aer')
                       
trier2_plevel = ( 'ua150', 'ua100', 'ua70', \
                   'ua50', 'ua30', 'ua20', 'ua10', 'va150', 'va100', 'va70', 'va50', \
                   'va30', 'va20', 'va10', 'ta150', 'ta100', 'ta70', 'ta50', 'ta30', \
                   'ta20', 'ta10', 'hus150', 'hus100', 'hus70', 'hus50', 'hus30', \
                   'hus20', 'hus10', 'zg150', 'zg100', 'zg70', 'zg50', 'zg30', 'zg20', \
                   'zg10', 'wa150', 'wa100', 'wa70', 'wa50', 'wa30', 'wa20', 'wa10', \
                   'ua750', 'va750', 'ta750', 'hus750', 'zg750', 'wa750') 
                        
trier2_height = ('ua200m', 'ua250m', 'ua300m', 'va200m', 'va250m', 'va300m')
                          
trier2_fx = ( 'sftgif', 'mrsofc', 'rootd', 'sftlaf', 'sfturf', 'dtb', 'areacella')


# Running the script:
import sys

varlists_dic = {
    'core': core,
    'trier1': trier1,
    'trier2': trier2,
    'trier1_sfc': trier1_sfc,
    'trier1_int': trier1_int,
    'trier1_plevel': trier1_plevel,
    'trier1_height': trier1_height,
    'trier2_sfc': trier2_sfc,
    'trier2_int': trier2_int,
    'trier2_plevel': trier2_plevel,
    'trier2_height': trier2_height,
    'trier2_fx': trier2_fx,
}

def write_namelist_file(filepath, template):
    try:
        with open(filepath, "w") as f:
            f.write(template)
        print(f"Namelist file created successfully at {filepath}")
    except Exception as e:
        print(f"Error writing namelist file: {e}")

def main():
    if len(sys.argv) < 2:
        print("Error: Too few arguments")
        print_instructions()
        sys.exit(1)

    filepath = "CORDEX_CMIP6_variables.csv"
    varlist = sys.argv[1:]
    output_file = f"runctrl.vars.{varlist[0]}.nml"

    print(f"Processing variables: {varlist}")

    vararray = create_multi_vararray(filepath, *varlist)
    if vararray:
        template = generate_namelist(vararray, len(vararray))
        write_namelist_file(output_file, template)
    else:
        print("No valid variables found to process")

if __name__ == "__main__":
    main()
