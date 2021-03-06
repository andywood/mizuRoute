#========================================================================
# Makefile to compile the routing model
#========================================================================
#
# Need to edit FC, FC_EXE, EXE, F_MASTER, NCDF_PATH
# Feel free to modify compiler flag (FLAGS)
# Do not leave space after your edits
#
#========================================================================
# User configure part 
#========================================================================
# Define fortran compiler - gfortran, ifort or pgf90
FC  =

# Define the compiler exe
FC_EXE =

# Define the compiled executable
EXE = route_runoff.develop.exe

# Define optional setting
# fast:      Enables optimizations
# debug:     Minimum debug options, still 
# profile:   Enables profiling
MODE = debug

# Define core directory below which everything resides
# parent directory of the 'build' directory
# do not put space at the end of path
F_MASTER =

# Define the NetCDF libraries and path to include files
ifeq "$(FC)" "gfortran"
 NCDF_PATH =
endif
ifeq "$(FC)" "ifort"
 NCDF_PATH =
endif
ifeq "$(FC)" "pgf90"
 NCDF_PATH = 
endif

LIBNETCDF = -Wl,-rpath,$(NCDF_PATH)/lib \
            -L$(NCDF_PATH)/lib -lnetcdff -lnetcdf
INCNETCDF = -I$(NCDF_PATH)/include

#========================================================================
# Define flags
#========================================================================
ifeq "$(FC)" "gfortran"
  ifeq "$(MODE)" "fast"
    FLAGS = -O3 -fmax-errors=0 -ffree-line-length-none
  endif
  ifeq "$(MODE)" "debug"
    FLAGS = -g -Wall -fmax-errors=0 -fbacktrace -fcheck=all -ffpe-trap=zero -ffree-line-length-none 
  endif
  ifeq "$(MODE)" "profile"
    FLAGS = -p -g -Wall -fmax-errors=0 -fbacktrace -fcheck=all -ffpe-trap=zero -ffree-line-length-none 
  endif
endif

ifeq "$(FC)" "ifort"
  ifeq "$(MODE)" "fast"
    FLAGS = -O3 -FR -auto -fltconsistency -fpe0
  endif
  ifeq "$(MODE)" "debug"
    FLAGS = -g -debug -warn all -check all -FR -O0 -auto -WB -fpe0 -traceback -fltconsistency
  endif
  ifeq "$(MODE)" "profile"
    FLAGS = -p -g -debug -warn all -check all -noerror_limit -FR -O0 -auto -WB -fpe0 -traceback -fltconsistency
  endif
endif

ifeq "$(FC)" "pgf90"
  ifeq "$(MODE)" "fast"
    FLAGS = -O2 -mp -c -Mdclchk
  endif
  ifeq "$(MODE)" "debug"
    FLAGS = -g -Mbounds -Mlist -Minfo  -Mdclchk
  endif
endif


#========================================================================
# Define directory paths
#========================================================================
# Core directory that contains source code
F_KORE_DIR = $(F_MASTER)build/src/

# Location of the compiled modules
MOD_PATH = $(F_MASTER)build/

# Define the directory for the executables
EXE_PATH = $(F_MASTER)bin

#========================================================================
# Assemble all of the sub-routines
#========================================================================
# Define subroutines
#
# data types
DATATYPES = \
    nrtype.f90 \
    public_var.f90 \
    dataTypes.f90 \
    var_lookup.f90 \
    globalData.f90 \
    popMetadat.f90 \
    allocation.f90 
# define utilities
UTILS = \
    nr_utility.f90 \
    ascii_util.f90 \
    time_utils.f90 \
    ncio_utils.f90 \
    gamma_func.f90
# read/write files
IO = \
    remap.f90 \
    read_control.f90 \
    read_param.f90 \
    read_streamSeg.f90 \
    write_streamSeg.f90 \
    read_runoff.f90 \
    get_basin_runoff.f90 \
    read_remap.f90 \
    read_restart.f90 \
    write_restart.f90 \
    write_simoutput.f90
# initialization
INIT = \
    process_time.f90 \
    network_topo.f90 \
    process_param.f90 \
    process_ntopo.f90
# CORE
CORE = \
    accum_runoff.f90 \
    basinUH.f90 \
    irf_route.f90 \
    kwt_route.f90 \
    main_route.f90 \
    model_setup.f90

# concatanate model subroutines
TEMP_MODSUB = $(DATATYPES) $(UTILS) $(IO) $(INIT) $(CORE)

# insert appropriate directory name
MODSUB = $(patsubst %, $(F_KORE_DIR)%, $(TEMP_MODSUB))

#========================================================================
# Define driver programs
#========================================================================
# Define the driver routine
DRIVER = $(F_KORE_DIR)route_runoff.f90

#========================================================================
# Compile the puppy
#========================================================================
# tasks
all: compile install clean

# compile
compile:
	$(FC_EXE) $(FLAGS) $(MODSUB) $(DRIVER) \
	$(LIBNETCDF) $(INCNETCDF) -o $(EXE)

# Remove object files
clean:
						rm -f *.o
						rm -f *.mod
						rm -f *__genmod.f90
#
# Copy the executable to the bin directory
install:
	@mkdir -p $(EXE_PATH)
	@mv $(EXE) $(EXE_PATH)
