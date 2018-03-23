program route_runoff

! ******
! provide access to desired data types / structures...
! ****************************************************

! variable types
USE nrtype                                    ! variable types, etc.
USE dataTypes, only : var_ilength             ! integer type:          var(:)%dat
USE dataTypes, only : var_dlength             ! double precision type: var(:)%dat

! data structures
USE dataTypes,  only : remap                  ! remapping data type
USE dataTypes,  only : runoff                 ! runoff data type

! global data
USE public_var
USE globalData, only : NETOPO                 ! network topology structure
USE globalData, only : RPARAM                 ! reach parameter structure
USE globalData, only : RCHFLX                 ! reach flux structure
USE globalData, only : KROUTE                 ! routing states

! metadata
USE var_lookup, only : ixHRU     , nVarsHRU      ! index of variables for data structure
USE var_lookup, only : ixHRU2SEG , nVarsHRU2SEG  ! index of variables for data structure
USE var_lookup, only : ixSEG     , nVarsSEG      ! index of variables for data structure
USE var_lookup, only : ixNTOPO   , nVarsNTOPO    ! index of variables for data structure

! ******
! provide access to desired subroutines...
! ****************************************

! subroutines: utility
USE nr_utility_module, only: findIndex        ! find index within a vector

! subroutines: populate metadata
USE popMetadat_module, only : popMetadat      ! populate metadata

! subroutines: model control
USE read_control_module, only : read_control  ! read the control file
USE ascii_util_module, only : file_open       ! open file (performs a few checks as well)

! subroutines: netcdf output
USE write_simoutput, only : defineFile        ! define netcdf output file
USE write_restart,   only : define_state_nc,& ! define netcdf state output file
                            write_state_nc    ! write netcdf state output file
USE read_restart,    only : read_state_nc     ! read netcdf state output file
USE write_netcdf,    only : write_nc          ! write a variable to the NetCDF file

! subroutines: model set up
USE process_ntopo, only : ntopo               ! process the network topology
USE getAncillary_module, only : getAncillary  ! get ancillary data

! subroutines: basin routing
USE basinUH_module, only : basinUH, &         ! basin unit hydrograph
                           IRF_route_basin    ! perform UH convolution for basin routing

! subroutines: get runoff for each basin in the routing layer
USE read_runoff, only : get_runoff            ! read simulated runoff data
USE remapping,   only : remap_runoff          ! remap runoff from input polygons to routing basins
USE remapping,   only : basin2reach           ! remap runoff from routing basins to routing reaches

! subroutines: routing
USE kwt_route,   only : QROUTE_RCH            ! kinematic wave routing method
USE irf_route,   only : make_uh               ! network unit hydrograph

! ******
! define variables
! ************************
implicit none

! index for printing (set to negative to supress printing
integer(i4b),parameter        :: ixPrint = -9999     ! index for printing

! model control
integer(i4b),parameter        :: nEns=1              ! number of ensemble members
character(len=strLen)         :: fileout             ! name of the output file
! index of looping variables
integer(i4b)                  :: iens                ! ensemble member
integer(i4b)                  :: iHRU                ! index for HRU
integer(i4b)                  :: iRch,jRch           ! index for the stream segment
integer(i4b)                  :: iTime               ! index for time
!    integer(i4b)                  :: jtime               ! index for time
integer(i4b)                  :: iRoute              ! index in routing vector

! error control
integer(i4b)                  :: ierr                ! error code
character(len=strLen)         :: cmessage            ! error message of downwind routine

!  network topology data structures
type(var_dlength),allocatable :: structHRU(:)        ! HRU properties
type(var_dlength),allocatable :: structSeg(:)        ! stream segment properties
type(var_ilength),allocatable :: structHRU2seg(:)    ! HRU-to-segment mapping
type(var_ilength),allocatable :: structNTOPO(:)      ! network topology

! read control file
character(len=strLen)         :: cfile_name          ! name of the control file
integer(i4b)                  :: iunit               ! file unit

! define desired reaches
integer(i4b)                  :: nHRU                ! number of HRUs
integer(i4b)                  :: nRch                ! number of desired reaches

! ancillary data on model input
type(remap)                   :: remap_data          ! data structure to remap data from a polygon (e.g., grid) to another polygon (e.g., basin)
type(runoff)                  :: runoff_data         ! runoff for one time step for all HRUs
integer(i4b)                  :: nSpatial            ! number of spatial elements
integer(i4b)                  :: nTime               ! number of time steps
character(len=strLen)         :: time_units          ! time units

! routing variables
real(dp)                      :: T0,T1               ! entry/exit time for the reach
integer(i4b), allocatable     :: basinID(:)          ! basin ID
integer(i4b), allocatable     :: reachID(:)          ! reach ID
real(dp)    , allocatable     :: basinRunoff(:)      ! basin runoff (m/s)
real(dp)    , allocatable     :: reachRunoff(:)      ! reach runoff (m/s)
integer(i4b), parameter       :: lakeFlag=0          ! no lakes
integer(i4b)                  :: ixDesire            ! desired reach index
integer(i4b)                  :: ixOutlet            ! outlet reach index

! desired routing ids
integer(i4b), parameter       :: desireId=integerMissing  ! turn off checks

! namelist parameters
real(dp)                      :: fshape              ! shape parameter in time delay histogram (=gamma distribution) [-]
real(dp)                      :: tscale              ! scaling factor for the time delay histogram [sec]
real(dp)                      :: velo                ! velocity [m/s] for Saint-Venant equation   added by NM
real(dp)                      :: diff                ! diffusivity [m2/s] for Saint-Venant equation   added by NM
real(dp)                      :: mann_n              ! manning's roughness coefficient [unitless]  added by NM
real(dp)                      :: wscale              ! scaling factor for river width [-] added by NM
namelist /HSLOPE/fshape,tscale  ! route simulated runoff through the local basin
namelist /IRF_UH/velo,diff      ! route delayed runoff through river network with St.Venant UH
namelist /KWT/mann_n,wscale     ! route kinematic waves through the river network

! ======================================================================================================
! ======================================================================================================
! ======================================================================================================
! ======================================================================================================
! ======================================================================================================
! ======================================================================================================

! start of model/network configuration code

! *****
! *** Populate metadata...
! ************************

! populate the metadata files
call popMetadat(ierr,cmessage)
if(ierr/=0) call handle_err(ierr, cmessage)

! *****
! *** Read control files...
! *************************

! get command-line argument defining the full path to the control file
call getarg(1,cfile_name)
if(len_trim(cfile_name)==0) call handle_err(50,'need to supply name of the control file as a command-line argument')

! read the control file
call read_control(trim(cfile_name), ierr, cmessage)
if(ierr/=0) call handle_err(ierr, cmessage)

! read the name list
call file_open(trim(param_nml),iunit,ierr,cmessage)
if(ierr/=0) call handle_err(ierr, cmessage)
read(iunit, nml=HSLOPE)
read(iunit, nml=IRF_UH)
read(iunit, nml=KWT)
close(iunit)

! *****
! *** Process the network topology...
! ***********************************

! get the network topology
call ntopo(&
           ! output: model control
           nHRU,             & ! number of HRUs
           nRch,             & ! number of stream segments
           ! output: populate data structures
           structHRU,        & ! ancillary data for HRUs
           structSeg,        & ! ancillary data for stream segments
           structHRU2seg,    & ! ancillary data for mapping hru2basin
           structNTOPO,      & ! ancillary data for network topology
           ! output: error control
           ierr, cmessage)
if(ierr/=0) call handle_err(ierr, cmessage)
!print*, 'PAUSE: after getting network topology'; read(*,*)

! specify some additional routing parameters (temporary "fix")
! NOTE: include here because using namelist parameters
if(hydGeometryOption==compute)then
 if (routOpt==allRoutingMethods .or. routOpt==kinematicWave) then
  RPARAM(:)%R_WIDTH = wscale * sqrt(RPARAM(:)%TOTAREA)  ! channel width (m)
  RPARAM(:)%R_MAN_N = mann_n                            ! Manning's "n" paramater (unitless)
 end if
endif  ! computing network topology

! *****
! *** Get ancillary data for routing...
! *************************************

! compute the time-delay histogram (to route runoff within basins)
! NOTE: allocates and populates global data FRAC_FUTURE
call basinUH(dt, fshape, tscale, ierr, cmessage)
call handle_err(ierr, cmessage)

! For IRF routing scheme: Compute unit hydrograph for each segment
! NOTE: include here because using namelist parameters
if (routOpt==allRoutingMethods .or. routOpt==impulseResponseFunc) then
 call make_uh(nRch, dt, velo, diff, ierr, cmessage)
 call handle_err(ierr, cmessage)
end if

! get ancillary data for routing
call getAncillary(&
                  ! data structures
                  nHRU,            & ! input:  number of HRUs in the routing layer
                  structHRU2seg,   & ! input:  ancillary data for mapping hru2basin
                  remap_data,      & ! output: data structure to remap data
                  runoff_data,     & ! output: data structure for runoff
                  ! dimensions
                  nSpatial,        & ! output: number of spatial elements in runoff data
                  nTime,           & ! output: number of time steps
                  time_units,      & ! output: time units
                  ! error control
                  ierr, cmessage)
if(ierr/=0) call handle_err(ierr, cmessage)

! *****
! *** Initialize state
! *************************************

! allocate space for the routing structures
allocate(RCHFLX(nEns,nRch), KROUTE(nEns,nRch), stat=ierr)
if(ierr/=0) call handle_err(ierr, 'unable to allocate space for routing structures')

if (isRestart)then

 !Read restart file and initialize states
 call read_state_nc(trim(output_dir)//trim(fname_state_in), routOpt, T0, T1, ierr, cmessage)
 if(ierr/=0) call handle_err(ierr, cmessage)

else

 ! Cold start .......
 ! initialize flux structures
 RCHFLX(:,:)%BASIN_QI = 0._dp
 forall(iRoute=0:1) RCHFLX(:,:)%BASIN_QR(iRoute) = 0._dp

 ! initialize time
 T0 = 0._dp
 T1 = dt

endif

! ======================================================================================================
! ======================================================================================================
! ======================================================================================================
! ======================================================================================================
! ======================================================================================================
! ======================================================================================================

! start of time-stepping simulation code

! *****
! *** Allocate space...
! *********************

! allocate space for runoff vectors
allocate(basinID(nHRU), reachID(nRch), basinRunoff(nHRU), reachRunoff(nRch), stat=ierr)
if(ierr/=0) call handle_err(ierr, 'unable to allocate space for runoff vectors')

! define ensemble member
iens=1

! *****
! *** Define model output file...
! *******************************

!   ! temporary time loop
!   do jTime=1,100
!
!   ! update filename
!   fileout=trim(output_dir)
!   write(fileout,'(a,i0,a)') trim(fileout)//'temp-', jTime, '.nc'
!   print*, 'output file = ', trim(fileout)

! define output file
fileout=trim(output_dir)//trim(fname_output)
call defineFile(trim(fileout),                         &  ! input: file name
                nEns,                                  &  ! input: number of HRUs
                nHRU,                                  &  ! input: number of HRUs
                nRch,                                  &  ! input: number of stream segments
                time_units,                            &  ! input: time units
                ierr,cmessage)                            ! output: error control
if(ierr/=0) call handle_err(ierr, cmessage)

! define basin ID
forall(iHRU=1:nHRU) basinID(iHRU) = structHRU2seg(iHRU)%var(ixHRU2seg%hruId)%dat(1)
call write_nc(trim(fileout), 'basinID', basinID, (/1/), (/nHRU/), ierr, cmessage)
call handle_err(ierr,cmessage)

! define reach ID
forall(iRch=1:nRch) reachID(iRch) = structNTOPO(iRch)%var(ixNTOPO%segId)%dat(1)
call write_nc(trim(fileout), 'reachID', reachID, (/1/), (/nRch/), ierr, cmessage)
call handle_err(ierr,cmessage)

! find index of desired reach
ixDesire = findIndex(reachID,desireId,integerMissing)

! find index of desired reach
ixOutlet = findIndex(reachID,idSegOut,integerMissing)

! *****
! *** Route runoff...
! *******************

! loop through time
do iTime=1, nTime

 ! *****
 ! * Get the simulated runoff for the current time step...
 ! *******************************************************

 ! get the simulated runoff for the current time step
 call get_runoff(trim(input_dir)//trim(fname_qsim), & ! input: filename
                 iTime,                             & ! input: time index
                 nSpatial,                          &  ! input:number of HRUs
                 runoff_data%time,                  & ! output: time
                 runoff_data%qSim,                  & ! output: runoff data
                 ierr, cmessage)                      ! output: error control
 call handle_err(ierr, cmessage)

 ! map simulated runoff to the basins in the river network
 if (is_remap) then
  call remap_runoff(runoff_data, remap_data, structHRU2seg, basinRunoff, ierr, cmessage)
  if(ierr/=0) call handle_err(ierr,cmessage)
 else
  basinRunoff=runoff_data%qsim
 end if

 ! write time -- note time is just carried across from the input
 call write_nc(trim(fileout), 'time', (/runoff_data%time/), (/iTime/), (/1/), ierr, cmessage)
 call handle_err(ierr,cmessage)

 ! write the basin runoff to the netcdf file
 call write_nc(trim(fileout), 'basRunoff', basinRunoff, (/1,iTime/), (/nHRU,1/), ierr, cmessage)
 call handle_err(ierr,cmessage)

 !print*, 'PAUSE: after getting simulated runoff'; read(*,*)

 ! *****
 ! * Map the basin runoff to the stream network...
 ! ***********************************************

 ! map the basin runoff to the stream network...
 call basin2reach(&
                  ! input
                  basinRunoff,       & ! intent(in):  basin runoff (m/s)
                  structNTOPO,       & ! intent(in):  Network topology structure
                  structSEG,         & ! intent(in):  Network attributes structure
                  ! output
                  reachRunoff,       & ! intent(out): reach runoff (m/s)
                  ierr, cmessage)      ! intent(out): error control
 if(ierr/=0) call handle_err(ierr,cmessage)

! ! NOTE: Use BASIN_QR here because input runoff is already routed
! RCHFLX(iens,:)%BASIN_QR(0) = RCHFLX(iens,:)%BASIN_QR(1)       ! streamflow from previous step
! RCHFLX(iens,:)%BASIN_QR(1) = reachRunoff(:)*RPARAM(:)%BASAREA ! streamflow (m3/s)

 ! convert runoff to m3/s
 RCHFLX(iens,:)%BASIN_QI = reachRunoff(:)*RPARAM(:)%BASAREA ! instantaneous runoff (m3/s)

 ! ensure that routed streamflow is non-zero
 do iRch=1,nRch
  if(RCHFLX(iens,iRch)%BASIN_QI < runoffMin) RCHFLX(iens,iRch)%BASIN_QI = runoffMin
 end do

 ! write instataneous local runoff in each stream segment (m3/s)
 call write_nc(trim(fileout), 'instRunoff', RCHFLX(iens,:)%BASIN_QI, (/1,iTime/), (/nRch,1/), ierr, cmessage)
 call handle_err(ierr,cmessage)

 ! perform Basin routing
 call IRF_route_basin(iens, nRch, ierr, cmessage)
 call handle_err(ierr,cmessage)

 ! write routed local runoff in each stream segment (m3/s)
 call write_nc(trim(fileout), 'dlayRunoff', RCHFLX(iens,:)%BASIN_QR(1), (/1,iTime/), (/nRch,1/), ierr, cmessage)
 call handle_err(ierr,cmessage)

 !print*, 'PAUSE: after getting reach runoff'; read(*,*)

 ! *****
 ! * Perform the routing...
 ! ************************

 ! route streamflow through the river network
 do iRch=1,nRch

  ! identify reach to process
  jRch = NETOPO(iRch)%RHORDER

  ! check
  if(reachId(jRch) == desireId)then
   print*, 'reachRunoff(jRch), RPARAM(jRch)%BASAREA, RCHFLX(iens,jRch)%BASIN_QR(1) = ', &
            reachRunoff(jRch), RPARAM(jRch)%BASAREA, RCHFLX(iens,jRch)%BASIN_QR(1)
  endif

  ! route kinematic waves through the river network
  call QROUTE_RCH(iens,jrch,           & ! input: array indices
                  ixDesire,            & ! input: index of the desired reach
                  ixOutlet,            & ! input: index of the outlet reach
                  T0,T1,               & ! input: start and end of the time step
                  MAXQPAR,             & ! input: maximum number of particle in a reach
                  LAKEFLAG,            & ! input: flag if lakes are to be processed
                  ierr,cmessage)         ! output: error control
  if (ierr/=0) call handle_err(ierr,cmessage)

 end do  ! (looping through stream segments)

 ! write routed runoff (m3/s)
 call write_nc(trim(fileout), 'KWTroutedRunoff', RCHFLX(iens,:)%REACH_Q, (/1,iTime/), (/nRch,1/), ierr, cmessage)
 if (ierr/=0) call handle_err(ierr,cmessage)

 ! increment time bounds
 T0 = T0 + dt
 T1 = T0 + dt

!      print*, 'itime, jtime, ntime = ', itime, jtime, ntime
 !print*, 'PAUSE: after routing'; read(*,*)

end do  ! looping through time

!     end do  ! temporary time loop

! *****
! * Restart file output
! ************************
! Note: Write routing states for the entire network at one time step
 ! Define state netCDF
 call define_state_nc(trim(output_dir)//trim(fname_state_out), time_units, routOpt, ierr, cmessage)
 if(ierr/=0) call handle_err(ierr, cmessage)

 ! Write states to netCDF
 call write_state_nc(trim(output_dir)//trim(fname_state_out), routOpt, runoff_data%time, 1, T0, T1, reachID, ierr, cmessage)
 if(ierr/=0) call handle_err(ierr, cmessage)

stop

contains

 subroutine handle_err(err,message)
 ! handle error codes
 implicit none
 integer(i4b),intent(in)::err             ! error code
 character(*),intent(in)::message         ! error message
 if(err/=0)then
  print*,'FATAL ERROR: '//trim(message)
  call flush(6)
  stop
 endif
 end subroutine handle_err

end
