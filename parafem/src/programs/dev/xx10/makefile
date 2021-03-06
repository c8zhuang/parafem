# MAKEFILE src/programs/5th_ed/xx10/makefile
# Author: Louise M. Lever; Lee Margetts
# -----------------------------------------------------------------------
# Compiles xx10 program executable as RELEASE or DEBUG
# Links with RELEASE STATIC library libParaFEM_mpi.$(VERSION).a
#    or with RELEASE STATIC library libParaFEM_mpi_D.$(VERSION).a
# -----------------------------------------------------------------------
# Available Rules:
#   (default) : execute the release rule
#
#   release: Build xx10 executable as RELEASE edition
#   debug: Build xx10 executable as DEBUG edition
#   install: Copy xx10 executable into global bin directory
#   clean: Remove .o object files
#   execlean: Remove the local xx10 executable
#   relink: Rebuild xx10 from object files and libraries
# -----------------------------------------------------------------------
# Notes:
# -----------------------------------------------------------------------

include ../../../../build/mk_defs.inc
include ../../../../build/$(MACHINE).inc

MODULE	= ../../../../include/mpi
LIB	= ../../../../lib
.SUFFIXES: .o .f90 .c


# C compiler flags not set in parafem included makefiles
XX10_MPI_REL_CFLAGS=-O3
XX10_MPI_DBG_CFLAGS=-g

COBJS = opencl_funcs.o
EXES = xx10

all:	release

release:
	@echo
	@echo "Building $(EXES) RELEASE"
	$(MAKE) $(EXES) \
	FFLAGS="-c -I$(MODULE) $(XX10_MPI_REL_FFLAGS)" \
	CFLAGS="-c $(XX10_MPI_REL_CFLAGS) $(GPU_OCL_INC) $(GPU_OCL_FLAGS)" \
	LDFLAGS="-L$(LIB) -lParaFEM_mpi.$(VERSION) $(XX10_MPI_REL_LDFLAGS) $(GPU_OCL_LIB)"
	@echo "Done $(EXES) RELEASE"

debug:
	@echo
	@echo "Building $(EXES) DEBUG"
	$(MAKE) $(EXES) \
	FFLAGS="-c -I$(MODULE) $(XX10_MPI_DBG_FFLAGS)" \
	CFLAGS="-c $(XX10_MPI_DBG_CFLAGS) $(GPU_OCL_INC) $(GPU_OCL_FLAGS)" \
	LDFLAGS="-L$(LIB) -lParaFEM_mpi_D.$(VERSION) $(XX10_MPI_DBG_LDFLAGS) $(GPU_OCL_LIB)"
	@echo "Done $(EXES) DEBUG"

xx10: $(COBJS) xx10.o
	$(FC) xx10.o $(COBJS) -o $@ $(LDFLAGS)


# Fortran files
xx10.o: xx10.f90
	$(FC) $(FFLAGS) $<


# OpenCL C files (from xx4 directory)
opencl_funcs.o: ../xx4/opencl_funcs.c
	$(CC) -c $(CFLAGS) $<

clean:
	rm -f *.o

execlean:
	rm -f $(EXES) ../../../../bin/xx10

relink: $(EXES)

install:
	cp $(EXES) ../../../../bin
