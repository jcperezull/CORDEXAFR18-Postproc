EBROOTNETCDFMINFORTRAN=/home/jcperez/data/Projects/CORDEXAfr/Teide/WRFintelteide/WRF_pnetcdf/WRF_4.6.1/Intel2024/Software/NetCDF
EBROOTNETCDF=/home/jcperez/data/Projects/CORDEXAfr/Teide/WRFintelteide/WRF_pnetcdf/WRF_4.6.1/Intel2024/Software/NetCDF
# gfortran flags (uncomment if using gfortran)
#FC = gfortran
#FCFLAGS = -O2 -cpp -DSERIAL
#FCFLAGS += -Wall
#FCFLAGS += -ffree-line-length-none
#FCFLAGS += -Wno-tabs -Wno-unused-variable -Wno-maybe-uninitialized

# intel flags (comment out if not using intel compiler)
#FC = mpiifort
FC = ifx
FCFLAGS = -O2 -assume realloc_lhs -cpp -DSERIAL
FCFLAGS += -fp-model precise -prec-div 

# Flags for gfortran and intel (never comment out)
FCFLAGS += -I$(EBROOTNETCDFMINFORTRAN)/include -I$(EBROOTNETCDF)/include
LDFLAGS = -L$(EBROOTNETCDFMINFORTRAN)/lib -lnetcdff -L${EBROOTNETCDF}/lib -lnetcdf

PROGRAMS = pCMORizer

all: $(PROGRAMS)

%: %.o
	$(FC) $(FCFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.f90
	$(FC) $(FCFLAGS) -c $<

.PHONY: clean veryclean

clean:
	rm -f *.o *.mod *.MOD *_genmod.f90

veryclean: clean
	rm -rf *~ $(PROGRAMS)

