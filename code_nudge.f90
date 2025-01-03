././@LongLink                                                                                       0000000 0000000 0000000 00000000150 00000000000 011561  L                                                                                                    ustar   root                            root                                                                                                                                                                                                                   chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.cam/                                                                                                                                                                                                                                                                                                                                                                                                                         chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.c0000755 0143640 0000777 00000000000 14250570446 030563  5                                                                                                    ustar   ychwang                         lccr                                                                                                                                                                                                                   ././@LongLink                                                                                       0000000 0000000 0000000 00000000163 00000000000 011565  L                                                                                                    ustar   root                            root                                                                                                                                                                                                                   chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.cam/nudging.F90                                                                                                                                                                                                                                                                                                                                                                                                              chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.c0000644 0143640 0000777 00000345520 12571760540 030576  0                                                                                                    ustar   ychwang                         lccr                                                                                                                                                                                                                   module nudging
!=====================================================================
!
! Purpose: Implement Nudging of the model state of U,V,T,Q, and/or PS
!          toward specified values from analyses.
!
! Author: Patrick Callaghan
!
! Description:
!    This module assumes that the user has {U,V,T,Q,PS} analyses which 
!    have been preprocessed onto the current model grid and are stored 
!    in individual files which are indexed with respect to year, month, 
!    day, and second of the day. When the model is inbetween the given 
!    begining and ending times, forcing is added to nudge the model toward
!    the appropriate analyses values. After the model passes the ending 
!    analyses time, the forcing discontinues.
!
! Revisions:
!    01/14/13 - Modified to manage 'GAPS' in analyses data. For now the
!               approach is to coast through the gaps...  If a given
!               analyses file is missing, nudging is turned off for 
!               that interval of time. Once an analyses file is found, 
!               the Nudging is switched back on.
!    02/22/13 - Modified to add functionality for FV and EUL dynamical 
!               cores.
!    03/03/13 - For ne120 runs, the automatic arrays used for reading in
!               U,V,T,Q,PS values were putting too much of a burden on the
!               stack memory. Until Parallel I/O is implemented, the impact
!               on the stack was reduced by using only one automatic array
!               to read in and scatter the data.
!    04/01/13 - Added Heaviside window function for localized nudging
!    04/10/13 - Modified call to physics_ptend_init() to accomodate the
!               new interface (in CESM1_2_BETA05).
!    05/06/13 - 'WRAP_NF' was modified from a generic interface so that 
!               now it can only read in 1D arrays from netCDF files. 
!               To eliminate errors from future meddling of this sort, all 
!               refenences to the 'wrap_nf' module were removed and replaced 
!               with direct nf90 calls.
!    08/19/13 - Add optional forms for Nudging force.
!    10/16/13 - Add option for Nudging Diagnostic outputs.
!               Move application Nudging tendency from the end of tphysbc()
!               to the end of tphysac() [DONE IN PHYSPKG.F90]
!    11/11/13 - Remove the FV kludge to use staggered winds (US,VS) 
!               instead of (U,V) - for FV the input datasets are assumed 
!               to contain both (US,VS) and (U,V).
!    11/12/13 - Add diurnal filter forcing options.
!               ** Forcing options 1 and 2 have swapped from what they were
!               ** before this date.
!    11/27/13 - Add routine to calc Dry Static Energy and modify the
!               tendency values from temperature only to DSE values.
!               Added 'Nudge_TSmode' (internal only) to toggle between 
!               nudging DSE or temperature only.
!     4/01/14 - Fixed Radian->Degree error with windows (Pedro DiNezio)
!
! Input/Output Values:
!    Forcing contributions are available for history file output by 
!    the names:    {'Nudge_U','Nudge_V','Nudge_T',and 'Nudge_Q'}
!
!    The nudging of the model toward the analyses data is controlled by 
!    the 'nudging_nl' namelist in 'user_nl_cam'; whose variables control the
!    time interval over which nudging is applied, the strength of the nudging
!    tendencies, and its spatial distribution. The strength of the nudging is
!    specified as a fractional coeffcient between [0,1]. The spatial distribution 
!    is specified with a profile index:
!
!        (U,V,T,Q) Profiles:      0 == OFF      (No Nudging of this variable)
!        -------------------      1 == CONSTANT (Spatially Uniform Nudging)
!                                 2 == HEAVISIDE WINDOW FUNCTION
!
!        (PS) Profiles:           0 == OFF (Not Implemented)
!        -------------------      1 == N/A (Not Implemented)
!                  
!    The Heaviside window function is the product of separate horizonal and vertical 
!    windows that are controled via 14 parameters:
!        Nudge_Hwin_lat0:     Provide the horizontal center of the window in degrees. 
!        Nudge_Hwin_lon0:     The longitude must be in the range [0,360] and the 
!                             latitude should be [-90,+90].
!
!        Nudge_Hwin_latWidth: Specify the lat and lon widths of the window as positive 
!        Nudge_Hwin_lonWidth: values in degrees.Setting a width to a large value (e.g. 999) 
!                             renders the window a constant in that direction.
!                                                 
!        Nudge_Hwin_latDelta: Controls the sharpness of the window transition with a 
!        Nudge_Hwin_lonDelta: length in degrees. Small non-zero values yeild a step 
!                             function while a large value leads to a smoother transition.
!
!        Nudge_Vwin_Lindex:   In the vertical, the window is specified in terms of model 
!        Nudge_Vwin_Ldelta:   level indcies. The High and Low transition levels should 
!        Nudge_Vwin_Hindex:   range from [0,(NCOL+1)]. The transition lengths are also 
!        Nudge_Vwin_Hdelta:   specified in terms of model indices. For a window function 
!                             constant in the vertical, the Low index should be set to 0,
!                             the High index should be set to (NCOL+1), and the transition 
!                             lengths should be set to 0.1 
!
!        Nudge_Hwin_lo:       For a given set of spatial parameters, the raw window 
!        Nudge_Hwin_hi:       function may not span the range [0,1], so those values are 
!        Nudge_Vwin_lo:       mapped to the range of values specified in by the user. 
!        Nudge_Vwin_hi:       The 'hi' values are mapped to the maximum of the raw window 
!                             function and 'lo' values are mapped to its minimum. 
!                             Typically the 'hi' values will be set equal to 1, and the 
!                             'lo' values set equal 0 or the desired window minimum. 
!                             Specifying the 'lo' value as 1 and the 'hi' value as 0 acts 
!                             to invert the window function. For a properly specified
!                             window its maximum should be equal to 1: MAX('lo','hi')==1
!
!        EXAMPLE: For a channel window function centered at the equator and independent 
!                 of the vertical (30 levels):
!                        Nudge_Hwin_lo = 0.               Nudge_Vwin_lo = 0.
!                        Nudge_Hwin_hi = 1.               Nudge_Vwin_hi = 1.
!                        Nudge_Hwin_lat0     = 0.         Nudge_Vwin_Lindex = 0.
!                        Nudge_Hwin_latWidth = 30.        Nudge_Vwin_Ldelta = 0.1
!                        Nudge_Hwin_latDelta = 5.0        Nudge_Vwin_Hindex = 31.
!                        Nudge_Hwin_lon0     = 180.       Nudge_Vwin_Hdelta = 0.1
!                        Nudge_Hwin_lonWidth = 999.
!                        Nudge_Hwin_lonDelta = 1.0
!
!                 If on the other hand one desired to apply nudging at the poles and
!                 not at the equator, the settings would be similar but with:
!                        Nudge_Hwin_lo = 1.
!                        Nudge_Hwin_hi = 0.
!
!    &nudging_nl
!      Nudge_Model         - LOGICAL toggle to activate nudging.
!      Nudge_Path          - CHAR path to the analyses files.
!      Nudge_File_Template - CHAR Analyses filename with year, month, day, and second
!                                 values replaced by %y, %m, %d, and %s respectively.
!      Nudge_Force_Opt     - INT Index to select the nudging force with the form:
!
!                                       F_nudge = Alpha*((Target-Model(t_curr))/TimeScale
!           
!            (default)     0 -->  Target=Anal(t'_next)            , TimeScale=Tdlt_Anal
!                          1 -->  Target=Anal(t'_next)            , TimeScale=(t'_next - t_curr )
!                          2 -->  Target=Anal(t'_curr)            , TimeScale=Tdlt_Anal
!                          3 -->  Target=Anal(t'_curr)            , TimeScale=(t_curr  - t'_curr)
!                          4 -->  Target=Diurnal_Estimate(t'_next), TimeScale=Tdlt_Anal
!                          5 -->  Target=Diurnal_Estimate(t'_next), TimeScale=(t'_next - t_curr )
!                          6 -->  Target=*STABLE*_Diurnal(t'_next), TimeScale=Tdlt_Anal
!                          7 -->  Target=*STABLE*_Diurnal(t'_next), TimeScale=(t'_next - t_curr )
!
!                                where (t'==Analysis times ; t==Model Times) and Diurnal estimates 
!                                are calcualted using 1 cycle of previous values[Nudge_Times_Per_Day]. 
!
!      Nudge_Diag_Opt      - INT Index to select diagnostic output.
!            (default)     0 -->  No diagnostic outputs.
!                          1 -->  10 [U,V,T,Q] outputs in tphysbc().
!                          2 -->  10 [U,V,T,Q] outputs mostly in tphysac().
!                          3 -->  What do you want??
!
!      Nudge_Times_Per_Day - INT Number of analyses files available per day.
!      Model_Times_Per_Day - INT Number of times to update the model state (used for nudging) 
!                                each day. The value is restricted to be longer than the 
!                                current model timestep and shorter than the analyses 
!                                timestep. As this number is increased, the nudging
!                                force has the form of newtonian cooling.
!      Nudge_Uprof         - INT index of profile structure to use for U.  [0,1,2]
!      Nudge_Vprof         - INT index of profile structure to use for V.  [0,1,2]
!      Nudge_Tprof         - INT index of profile structure to use for T.  [0,1,2]
!      Nudge_Qprof         - INT index of profile structure to use for Q.  [0,1,2]
!      Nudge_PSprof        - INT index of profile structure to use for PS. [0,N/A]
!      Nudge_Ucoef         - REAL fractional nudging coeffcient for U. 
!                                    Utau=(Nudge_Ucoef/analyses_timestep)
!      Nudge_Vcoef         - REAL fractional nudging coeffcient for V. 
!                                    Vtau=(Nudge_Vcoef/analyses_timestep)
!      Nudge_Tcoef         - REAL fractional nudging coeffcient for T. 
!                                    Stau=(Nudge_Tcoef/analyses_timestep)
!      Nudge_Qcoef         - REAL fractional nudging coeffcient for Q. 
!                                    Qtau=(Nudge_Qcoef/analyses_timestep)
!      Nudge_PScoef        - REAL fractional nudging coeffcient for PS. 
!                                    PStau=(Nudge_PScoef/analyses_timestep)
!      Nudge_Beg_Year      - INT nudging begining year.
!      Nudge_Beg_Month     - INT nudging begining month.
!      Nudge_Beg_Day       - INT nudging begining day.
!      Nudge_End_Year      - INT nudging ending year.
!      Nudge_End_Month     - INT nudging ending month.
!      Nudge_End_Day       - INT nudging ending day.
!      Nudge_Hwin_lo       - REAL value mapped to RAW horizontal window minimum. [0]
!      Nudge_Hwin_hi       - REAL value mapped to RAW horizontal window maximum. [1]
!      Nudge_Vwin_lo       - REAL value mapped to RAW vertical window minimum.   [0]
!      Nudge_Vwin_hi       - REAL value mapped to RAW vertical window maximum.   [1]
!      Nudge_Hwin_lat0     - REAL latitudinal center of window in degrees.
!      Nudge_Hwin_lon0     - REAL longitudinal center of window in degrees.
!      Nudge_Hwin_latWidth - REAL latitudinal width of window in degrees.
!      Nudge_Hwin_lonWidth - REAL longitudinal width of window in degrees.
!      Nudge_Hwin_latDelta - REAL latitudinal transition length of window in degrees.
!      Nudge_Hwin_lonDelta - REAL longitudinal transition length of window in degrees.
!      Nudge_Vwin_Lindex   - REAL LO model index of transition
!      Nudge_Vwin_Hindex   - REAL HI model index of transition
!      Nudge_Vwin_Ldelta   - REAL LO transition length 
!      Nudge_Vwin_Hdelta   - REAL HI transition length 
!    /
!
!================
!
! TO DO:
! -----------
!    ** Currently the surface pressure is read in, but there is no forcing
!       meachnism implemented.
!    ** Analyses data is read in and then distributed to processing elements 
!       via 'scatted_field_to_chunk' calls. The SE's want this to be changed
!       to parallel I/O calls.
!    ** Possibly implement time variation to nudging coeffcients, so that 
!       rather than just bashing the model with a sledge hammer, the user has the
!       option to ramp up the nudging coefs over a startup time frame via a 
!       heavyside step function.
!          
!=====================================================================
  ! Useful modules
  !------------------
  use shr_kind_mod,only:r8=>SHR_KIND_R8,cs=>SHR_KIND_CS,cl=>SHR_KIND_CL
  use time_manager,only:timemgr_time_ge,timemgr_time_inc,get_curr_date,dtime
  use phys_grid   ,only:scatter_field_to_chunk
  use abortutils  ,only:endrun
  use spmd_utils  ,only:masterproc
  use cam_logfile ,only:iulog
#ifdef SPMD
  use mpishorthand
#endif

  ! Set all Global values and routines to private by default 
  ! and then explicitly set their exposure.
  !----------------------------------------------------------
  implicit none
  private

  public:: Nudge_Model,Nudge_ON,Nudge_Diag_Opt
  public:: nudging_readnl
  public:: nudging_init
  public:: nudging_timestep_init
  public:: nudging_timestep_tend
  public:: nudging_diag_init
  public:: nudging_diag
  private::nudging_update_analyses_se
  private::nudging_update_analyses_eul
  private::nudging_update_analyses_fv
  private::nudging_set_PSprofile
  private::nudging_set_profile
  private::calc_DryStaticEnergy

  ! Nudging Parameters
  !--------------------
  logical::         Nudge_Model       =.false.
  logical::         Nudge_ON          =.false.
  logical::         Nudge_Initialized =.false.
  character(len=cl) Nudge_Path
  character(len=cs) Nudge_File,Nudge_File_Template
  integer           Nudge_Force_Opt
  integer           Nudge_Diag_Opt
  integer           Nudge_TSmode
  integer           Nudge_Times_Per_Day
  integer           Model_Times_Per_Day
  real(r8)          Nudge_Ucoef,Nudge_Vcoef
  integer           Nudge_Uprof,Nudge_Vprof
  real(r8)          Nudge_Qcoef,Nudge_Tcoef
  integer           Nudge_Qprof,Nudge_Tprof
  real(r8)          Nudge_PScoef
  integer           Nudge_PSprof
  integer           Nudge_Beg_Year ,Nudge_Beg_Month
  integer           Nudge_Beg_Day  ,Nudge_Beg_Sec
  integer           Nudge_End_Year ,Nudge_End_Month
  integer           Nudge_End_Day  ,Nudge_End_Sec
  integer           Nudge_Curr_Year,Nudge_Curr_Month
  integer           Nudge_Curr_Day ,Nudge_Curr_Sec
  integer           Nudge_Next_Year,Nudge_Next_Month
  integer           Nudge_Next_Day ,Nudge_Next_Sec
  integer           Nudge_Step
  integer           Model_Curr_Year,Model_Curr_Month
  integer           Model_Curr_Day ,Model_Curr_Sec
  integer           Model_Next_Year,Model_Next_Month
  integer           Model_Next_Day ,Model_Next_Sec
  integer           Model_Step
  real(r8)          Nudge_Hwin_lo
  real(r8)          Nudge_Hwin_hi
  real(r8)          Nudge_Hwin_lat0
  real(r8)          Nudge_Hwin_latWidth
  real(r8)          Nudge_Hwin_latDelta
  real(r8)          Nudge_Hwin_lon0
  real(r8)          Nudge_Hwin_lonWidth
  real(r8)          Nudge_Hwin_lonDelta
  real(r8)          Nudge_Vwin_lo
  real(r8)          Nudge_Vwin_hi
  real(r8)          Nudge_Vwin_Hindex
  real(r8)          Nudge_Vwin_Hdelta
  real(r8)          Nudge_Vwin_Lindex
  real(r8)          Nudge_Vwin_Ldelta
  real(r8)          Nudge_Hwin_latWidthH
  real(r8)          Nudge_Hwin_lonWidthH
  real(r8)          Nudge_Hwin_max
  real(r8)          Nudge_Hwin_min

  ! Nudging State Arrays
  !-----------------------
  integer Nudge_nlon,Nudge_nlat,Nudge_ncol,Nudge_nlev
  real(r8),allocatable::Target_U(:,:,:)     !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Target_V(:,:,:)     !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Target_T(:,:,:)     !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Target_S(:,:,:)     !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Target_Q(:,:,:)     !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Target_PS(:,:)      !(pcols,begchunk:endchunk)
  real(r8),allocatable::Model_U(:,:,:)      !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Model_V(:,:,:)      !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Model_T(:,:,:)      !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Model_S(:,:,:)      !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Model_Q(:,:,:)      !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Model_PS(:,:)       !(pcols,begchunk:endchunk)
  real(r8),allocatable::Nudge_Utau(:,:,:)   !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Nudge_Vtau(:,:,:)   !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Nudge_Stau(:,:,:)   !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Nudge_Qtau(:,:,:)   !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Nudge_PStau(:,:)    !(pcols,begchunk:endchunk)
  real(r8),allocatable::Nudge_Ustep(:,:,:)  !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Nudge_Vstep(:,:,:)  !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Nudge_Sstep(:,:,:)  !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Nudge_Qstep(:,:,:)  !(pcols,pver,begchunk:endchunk)
  real(r8),allocatable::Nudge_PSstep(:,:)   !(pcols,begchunk:endchunk)

  ! Nudging Observation Arrays
  !-----------------------------
  integer               Nudge_NumObs
  integer,allocatable:: Nudge_ObsInd(:)
  logical ,allocatable::Nudge_File_Present(:)
  real(r8)              Nudge_Acoef
  real(r8),allocatable::Nudge_Bcoef(:)
  real(r8),allocatable::Nudge_Ccoef(:)
  real(r8),allocatable::Nobs_U(:,:,:,:) !(pcols,pver,begchunk:endchunk,Nudge_NumObs)
  real(r8),allocatable::Nobs_V(:,:,:,:) !(pcols,pver,begchunk:endchunk,Nudge_NumObs)
  real(r8),allocatable::Nobs_T(:,:,:,:) !(pcols,pver,begchunk:endchunk,Nudge_NumObs)
  real(r8),allocatable::Nobs_Q(:,:,:,:) !(pcols,pver,begchunk:endchunk,Nudge_NumObs)
  real(r8),allocatable::Nobs_PS(:,:,:)  !(pcols,begchunk:endchunk,Nudge_NumObs)
  real(r8),allocatable::Mobs_U(:,:,:,:) !(pcols,pver,begchunk:endchunk,Nudge_NumObs)
  real(r8),allocatable::Mobs_V(:,:,:,:) !(pcols,pver,begchunk:endchunk,Nudge_NumObs)
  real(r8),allocatable::Mobs_T(:,:,:,:) !(pcols,pver,begchunk:endchunk,Nudge_NumObs)
  real(r8),allocatable::Mobs_Q(:,:,:,:) !(pcols,pver,begchunk:endchunk,Nudge_NumObs)
  real(r8),allocatable::Mobs_PS(:,:,:)  !(pcols,begchunk:endchunk,Nudge_NumObs)

contains
  !================================================================
  subroutine nudging_readnl(nlfile)
   ! 
   ! NUDGING_READNL: Initialize default values controlling the Nudging 
   !                 process. Then read namelist values to override 
   !                 them.
   !===============================================================
   use ppgrid        ,only: pver
   use namelist_utils,only:find_group_name
   use units         ,only:getunit,freeunit
   !
   ! Arguments
   !-------------
   character(len=*),intent(in)::nlfile
   !
   ! Local Values
   !---------------
   integer ierr,unitn

   namelist /nudging_nl/ Nudge_Model,Nudge_Path,                       &
                         Nudge_File_Template,Nudge_Force_Opt,          &
                         Nudge_Diag_Opt,                               &
                         Nudge_Times_Per_Day,Model_Times_Per_Day,      &
                         Nudge_Ucoef ,Nudge_Uprof,                     &
                         Nudge_Vcoef ,Nudge_Vprof,                     &
                         Nudge_Qcoef ,Nudge_Qprof,                     &
                         Nudge_Tcoef ,Nudge_Tprof,                     &
                         Nudge_PScoef,Nudge_PSprof,                    &
                         Nudge_Beg_Year,Nudge_Beg_Month,Nudge_Beg_Day, &
                         Nudge_End_Year,Nudge_End_Month,Nudge_End_Day, &
                         Nudge_Hwin_lo,Nudge_Hwin_hi,                  &
                         Nudge_Vwin_lo,Nudge_Vwin_hi,                  &
                         Nudge_Hwin_lat0,Nudge_Hwin_lon0,              &
                         Nudge_Hwin_latWidth,Nudge_Hwin_lonWidth,      &
                         Nudge_Hwin_latDelta,Nudge_Hwin_lonDelta,      &
                         Nudge_Vwin_Lindex,Nudge_Vwin_Hindex,          &
                         Nudge_Vwin_Ldelta,Nudge_Vwin_Hdelta           

   ! Nudging is NOT initialized yet, For now
   ! Nudging will always begin/end at midnight.
   !--------------------------------------------
   Nudge_Initialized =.false.
   Nudge_ON          =.false.
   Nudge_Beg_Sec=0
   Nudge_End_Sec=0

   ! Set Default Namelist values
   !-----------------------------
   Nudge_Model         =.false.
   Nudge_Path          ='./Data/YOTC_ne30np4_001/'
   Nudge_File_Template ='YOTC_ne30np4_L30.cam2.i.%y-%m-%d-%s.nc'
   Nudge_Force_Opt=0
   Nudge_Diag_Opt =0
   Nudge_TSmode   =0
   Nudge_Times_Per_Day=4
   Model_Times_Per_Day=4
   Nudge_Ucoef  =0._r8
   Nudge_Vcoef  =0._r8
   Nudge_Qcoef  =0._r8
   Nudge_Tcoef  =0._r8
   Nudge_PScoef =0._r8
   Nudge_Uprof  =0
   Nudge_Vprof  =0
   Nudge_Qprof  =0
   Nudge_Tprof  =0
   Nudge_PSprof =0
   Nudge_Beg_Year =2008
   Nudge_Beg_Month=5
   Nudge_Beg_Day  =1
   Nudge_End_Year =2008
   Nudge_End_Month=9
   Nudge_End_Day  =1
   Nudge_Hwin_lo      =0.0_r8
   Nudge_Hwin_hi      =1.0_r8
   Nudge_Hwin_lat0    =0._r8
   Nudge_Hwin_latWidth=9999._r8
   Nudge_Hwin_latDelta=1.0_r8
   Nudge_Hwin_lon0    =180._r8
   Nudge_Hwin_lonWidth=9999._r8
   Nudge_Hwin_lonDelta=1.0_r8
   Nudge_Vwin_lo      =0.0_r8
   Nudge_Vwin_hi      =1.0_r8
   Nudge_Vwin_Hindex  =float(pver+1)
   Nudge_Vwin_Hdelta  =0.1_r8
   Nudge_Vwin_Lindex  =0.0_r8
   Nudge_Vwin_Ldelta  =0.1_r8

   ! Read in namelist values
   !------------------------
   if(masterproc) then
     unitn = getunit()
     open(unitn,file=trim(nlfile),status='old')
     call find_group_name(unitn,'nudging_nl',status=ierr)
     if(ierr.eq.0) then
       read(unitn,nudging_nl,iostat=ierr)
       if(ierr.ne.0) then
         call endrun('nudging_readnl:: ERROR reading namelist')
       endif
     endif
     close(unitn)
     call freeunit(unitn)
   endif

   ! Check for valid namelist values 
   !----------------------------------
   if((max(Nudge_Hwin_lo,Nudge_Hwin_hi).ne.1.0).or. &
      (max(Nudge_Vwin_lo,Nudge_Vwin_hi).ne.1.0)   ) then
     write(iulog,*) 'NUDGING: The window function must have a maximum value of 1'
     write(iulog,*) 'NUDGING:  Nudge_Hwin_lo=',Nudge_Hwin_lo
     write(iulog,*) 'NUDGING:  Nudge_Hwin_hi=',Nudge_Hwin_hi
     write(iulog,*) 'NUDGING:  Nudge_Vwin_lo=',Nudge_Vwin_lo
     write(iulog,*) 'NUDGING:  Nudge_Vwin_hi=',Nudge_Vwin_hi
     call endrun('nudging_readnl:: ERROR in namelist')
   endif

   if((Nudge_Hwin_lat0.lt.-90.).or.(Nudge_Hwin_lat0.gt.+90.)) then
     write(iulog,*) 'NUDGING: Window lat0 must be in [-90,+90]'
     write(iulog,*) 'NUDGING:  Nudge_Hwin_lat0=',Nudge_Hwin_lat0
     call endrun('nudging_readnl:: ERROR in namelist')
   endif

   if((Nudge_Hwin_lon0.lt.0.).or.(Nudge_Hwin_lon0.ge.360.)) then
     write(iulog,*) 'NUDGING: Window lon0 must be in [0,+360)'
     write(iulog,*) 'NUDGING:  Nudge_Hwin_lon0=',Nudge_Hwin_lon0
     call endrun('nudging_readnl:: ERROR in namelist')
   endif

   if((Nudge_Vwin_Lindex.gt.Nudge_Vwin_Hindex)                         .or. &
      (Nudge_Vwin_Hindex.gt.float(pver+1)).or.(Nudge_Vwin_Hindex.lt.0.).or. &
      (Nudge_Vwin_Lindex.gt.float(pver+1)).or.(Nudge_Vwin_Lindex.lt.0.)   ) then
     write(iulog,*) 'NUDGING: Window Lindex must be in [0,pver+1]'
     write(iulog,*) 'NUDGING: Window Hindex must be in [0,pver+1]'
     write(iulog,*) 'NUDGING: Lindex must be LE than Hindex'
     write(iulog,*) 'NUDGING:  Nudge_Vwin_Lindex=',Nudge_Vwin_Lindex
     write(iulog,*) 'NUDGING:  Nudge_Vwin_Hindex=',Nudge_Vwin_Hindex
     call endrun('nudging_readnl:: ERROR in namelist')
   endif

   if((Nudge_Hwin_latDelta.le.0.).or.(Nudge_Hwin_lonDelta.le.0.).or. &
      (Nudge_Vwin_Hdelta  .le.0.).or.(Nudge_Vwin_Ldelta  .le.0.)    ) then
     write(iulog,*) 'NUDGING: Window Deltas must be positive'
     write(iulog,*) 'NUDGING:  Nudge_Hwin_latDelta=',Nudge_Hwin_latDelta
     write(iulog,*) 'NUDGING:  Nudge_Hwin_lonDelta=',Nudge_Hwin_lonDelta
     write(iulog,*) 'NUDGING:  Nudge_Vwin_Hdelta=',Nudge_Vwin_Hdelta
     write(iulog,*) 'NUDGING:  Nudge_Vwin_Ldelta=',Nudge_Vwin_Ldelta
     call endrun('nudging_readnl:: ERROR in namelist')

   endif

   if((Nudge_Hwin_latWidth.le.0.).or.(Nudge_Hwin_lonWidth.le.0.)) then
     write(iulog,*) 'NUDGING: Window widths must be positive'
     write(iulog,*) 'NUDGING:  Nudge_Hwin_latWidth=',Nudge_Hwin_latWidth
     write(iulog,*) 'NUDGING:  Nudge_Hwin_lonWidth=',Nudge_Hwin_lonWidth
     call endrun('nudging_readnl:: ERROR in namelist')
   endif

   ! Broadcast namelist variables
   !------------------------------
#ifdef SPMD
   call mpibcast(Nudge_Path         ,len(Nudge_Path)         ,mpichar,0,mpicom)
   call mpibcast(Nudge_File_Template,len(Nudge_File_Template),mpichar,0,mpicom)
   call mpibcast(Nudge_Model        , 1, mpilog, 0, mpicom)
   call mpibcast(Nudge_Initialized  , 1, mpilog, 0, mpicom)
   call mpibcast(Nudge_ON           , 1, mpilog, 0, mpicom)
   call mpibcast(Nudge_Force_Opt    , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Diag_Opt     , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_TSmode       , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Times_Per_Day, 1, mpiint, 0, mpicom)
   call mpibcast(Model_Times_Per_Day, 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Ucoef        , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Vcoef        , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Tcoef        , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Qcoef        , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_PScoef       , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Uprof        , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Vprof        , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Tprof        , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Qprof        , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_PSprof       , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Beg_Year     , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Beg_Month    , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Beg_Day      , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Beg_Sec      , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_End_Year     , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_End_Month    , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_End_Day      , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_End_Sec      , 1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Hwin_lo      , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_hi      , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_lat0    , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_latWidth, 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_latDelta, 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_lon0    , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_lonWidth, 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_lonDelta, 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Vwin_lo      , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Vwin_hi      , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Vwin_Hindex  , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Vwin_Hdelta  , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Vwin_Lindex  , 1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Vwin_Ldelta  , 1, mpir8 , 0, mpicom)
#endif

   ! End Routine
   !------------
   return
  end subroutine ! nudging_readnl
  !================================================================


  !================================================================
  subroutine nudging_diag_init
   ! 
   ! NUDGING_DIAG_INIT: Register diagnostic outputs fo U,V,T,Q
   !                    so values can be incrementally sampled
   !                    as physics paramterizations are added
   !===============================================================
   use ppgrid        ,only: pver
   use cam_history   ,only: addfld,phys_decomp

   ! Register Diagnostic output fields at 10 points
   !-----------------------------------------------------
   call addfld('UAP0','m/s'  ,pver,'A','U AfterPhysics Diag 0',phys_decomp)
   call addfld('VAP0','m/s'  ,pver,'A','V AfterPhysics Diag 0',phys_decomp)
   call addfld('TAP0','K'    ,pver,'A','T AfterPhysics Diag 0',phys_decomp)
   call addfld('SAP0','J'    ,pver,'A','S AfterPhysics Diag 0',phys_decomp)
   call addfld('QAP0','kg/kg',pver,'A','Q AfterPhysics Diag 0',phys_decomp)

   call addfld('UAP1','m/s'  ,pver,'A','U AfterPhysics Diag 1',phys_decomp)
   call addfld('VAP1','m/s'  ,pver,'A','V AfterPhysics Diag 1',phys_decomp)
   call addfld('TAP1','K'    ,pver,'A','T AfterPhysics Diag 1',phys_decomp)
   call addfld('SAP1','J'    ,pver,'A','S AfterPhysics Diag 1',phys_decomp)
   call addfld('QAP1','kg/kg',pver,'A','Q AfterPhysics Diag 1',phys_decomp)

   call addfld('UAP2','m/s'  ,pver,'A','U AfterPhysics Diag 2',phys_decomp)
   call addfld('VAP2','m/s'  ,pver,'A','V AfterPhysics Diag 2',phys_decomp)
   call addfld('TAP2','K'    ,pver,'A','T AfterPhysics Diag 2',phys_decomp)
   call addfld('SAP2','J'    ,pver,'A','S AfterPhysics Diag 2',phys_decomp)
   call addfld('QAP2','kg/kg',pver,'A','Q AfterPhysics Diag 2',phys_decomp)

   call addfld('UAP3','m/s'  ,pver,'A','U AfterPhysics Diag 3',phys_decomp)
   call addfld('VAP3','m/s'  ,pver,'A','V AfterPhysics Diag 3',phys_decomp)
   call addfld('TAP3','K'    ,pver,'A','T AfterPhysics Diag 3',phys_decomp)
   call addfld('SAP3','J'    ,pver,'A','S AfterPhysics Diag 3',phys_decomp)
   call addfld('QAP3','kg/kg',pver,'A','Q AfterPhysics Diag 3',phys_decomp)

   call addfld('UAP4','m/s'  ,pver,'A','U AfterPhysics Diag 4',phys_decomp)
   call addfld('VAP4','m/s'  ,pver,'A','V AfterPhysics Diag 4',phys_decomp)
   call addfld('TAP4','K'    ,pver,'A','T AfterPhysics Diag 4',phys_decomp)
   call addfld('SAP4','J'    ,pver,'A','S AfterPhysics Diag 4',phys_decomp)
   call addfld('QAP4','kg/kg',pver,'A','Q AfterPhysics Diag 4',phys_decomp)

   call addfld('UAP5','m/s'  ,pver,'A','U AfterPhysics Diag 5',phys_decomp)
   call addfld('VAP5','m/s'  ,pver,'A','V AfterPhysics Diag 5',phys_decomp)
   call addfld('TAP5','K'    ,pver,'A','T AfterPhysics Diag 5',phys_decomp)
   call addfld('SAP5','J'    ,pver,'A','S AfterPhysics Diag 5',phys_decomp)
   call addfld('QAP5','kg/kg',pver,'A','Q AfterPhysics Diag 5',phys_decomp)
   call addfld('UAP6','m/s'  ,pver,'A','U AfterPhysics Diag 6',phys_decomp)
   call addfld('VAP6','m/s'  ,pver,'A','V AfterPhysics Diag 6',phys_decomp)
   call addfld('TAP6','K'    ,pver,'A','T AfterPhysics Diag 6',phys_decomp)
   call addfld('SAP6','J'    ,pver,'A','S AfterPhysics Diag 6',phys_decomp)
   call addfld('QAP6','kg/kg',pver,'A','Q AfterPhysics Diag 6',phys_decomp)

   call addfld('UAP7','m/s'  ,pver,'A','U AfterPhysics Diag 7',phys_decomp)
   call addfld('VAP7','m/s'  ,pver,'A','V AfterPhysics Diag 7',phys_decomp)
   call addfld('TAP7','K'    ,pver,'A','T AfterPhysics Diag 7',phys_decomp)
   call addfld('SAP7','J'    ,pver,'A','S AfterPhysics Diag 7',phys_decomp)
   call addfld('QAP7','kg/kg',pver,'A','Q AfterPhysics Diag 7',phys_decomp)

   call addfld('UAP8','m/s'  ,pver,'A','U AfterPhysics Diag 8',phys_decomp)
   call addfld('VAP8','m/s'  ,pver,'A','V AfterPhysics Diag 8',phys_decomp)
   call addfld('TAP8','K'    ,pver,'A','T AfterPhysics Diag 8',phys_decomp)
   call addfld('SAP8','J'    ,pver,'A','S AfterPhysics Diag 8',phys_decomp)
   call addfld('QAP8','kg/kg',pver,'A','Q AfterPhysics Diag 8',phys_decomp)

   call addfld('UAP9','m/s'  ,pver,'A','U AfterPhysics Diag 9',phys_decomp)
   call addfld('VAP9','m/s'  ,pver,'A','V AfterPhysics Diag 9',phys_decomp)
   call addfld('TAP9','K'    ,pver,'A','T AfterPhysics Diag 9',phys_decomp)
   call addfld('SAP9','J'    ,pver,'A','S AfterPhysics Diag 9',phys_decomp)
   call addfld('QAP9','kg/kg',pver,'A','Q AfterPhysics Diag 9',phys_decomp)

   ! End Routine
   !------------
   return
  end subroutine ! nudging_diag_init
  !================================================================


  !================================================================
  subroutine nudging_diag(state,indx)
   ! NUDGING_DIAG: Write out the current state of U,V,T,Q to the
   !               specified increment index.
   !===============================================================
   use physics_types, only: physics_state
   use ppgrid,        only: pcols
   use cam_history   ,only: outfld

   ! Arguments
   !-----------
   type(physics_state),intent(in):: state
   integer            ,intent(in):: indx

   ! Local values
   !----------------
   integer  lchnk

   ! Write out the current state to the variables of the given index
   !------------------------------------------------------------------
   lchnk = state%lchnk

   if(indx.eq.0) then
     call outfld('UAP0',state%u       ,pcols,lchnk)
     call outfld('VAP0',state%v       ,pcols,lchnk)
     call outfld('TAP0',state%t       ,pcols,lchnk)
     call outfld('SAP0',state%s       ,pcols,lchnk)
     call outfld('QAP0',state%q(1,1,1),pcols,lchnk)
   elseif(indx.eq.1) then
     call outfld('UAP1',state%u       ,pcols,lchnk)
     call outfld('VAP1',state%v       ,pcols,lchnk)
     call outfld('TAP1',state%t       ,pcols,lchnk)
     call outfld('SAP1',state%s       ,pcols,lchnk)
     call outfld('QAP1',state%q(1,1,1),pcols,lchnk)
   elseif(indx.eq.2) then
     call outfld('UAP2',state%u       ,pcols,lchnk)
     call outfld('VAP2',state%v       ,pcols,lchnk)
     call outfld('TAP2',state%t       ,pcols,lchnk)
     call outfld('SAP2',state%s       ,pcols,lchnk)
     call outfld('QAP2',state%q(1,1,1),pcols,lchnk)
   elseif(indx.eq.3) then
     call outfld('UAP3',state%u       ,pcols,lchnk)
     call outfld('VAP3',state%v       ,pcols,lchnk)
     call outfld('TAP3',state%t       ,pcols,lchnk)
     call outfld('SAP3',state%s       ,pcols,lchnk)
     call outfld('QAP3',state%q(1,1,1),pcols,lchnk)
   elseif(indx.eq.4) then
     call outfld('UAP4',state%u       ,pcols,lchnk)
     call outfld('VAP4',state%v       ,pcols,lchnk)
     call outfld('TAP4',state%t       ,pcols,lchnk)
     call outfld('SAP4',state%s       ,pcols,lchnk)
     call outfld('QAP4',state%q(1,1,1),pcols,lchnk)
   elseif(indx.eq.5) then
     call outfld('UAP5',state%u       ,pcols,lchnk)
     call outfld('VAP5',state%v       ,pcols,lchnk)
     call outfld('TAP5',state%t       ,pcols,lchnk)
     call outfld('SAP5',state%s       ,pcols,lchnk)
     call outfld('QAP5',state%q(1,1,1),pcols,lchnk)
   elseif(indx.eq.6) then
     call outfld('UAP6',state%u       ,pcols,lchnk)
     call outfld('VAP6',state%v       ,pcols,lchnk)
     call outfld('TAP6',state%t       ,pcols,lchnk)
     call outfld('SAP6',state%s       ,pcols,lchnk)
     call outfld('QAP6',state%q(1,1,1),pcols,lchnk)
   elseif(indx.eq.7) then
     call outfld('UAP7',state%u       ,pcols,lchnk)
     call outfld('VAP7',state%v       ,pcols,lchnk)
     call outfld('TAP7',state%t       ,pcols,lchnk)
     call outfld('SAP7',state%s       ,pcols,lchnk)
     call outfld('QAP7',state%q(1,1,1),pcols,lchnk)
   elseif(indx.eq.8) then
     call outfld('UAP8',state%u       ,pcols,lchnk)
     call outfld('VAP8',state%v       ,pcols,lchnk)
     call outfld('TAP8',state%t       ,pcols,lchnk)
     call outfld('SAP8',state%s       ,pcols,lchnk)
     call outfld('QAP8',state%q(1,1,1),pcols,lchnk)
   elseif(indx.eq.9) then
     call outfld('UAP9',state%u       ,pcols,lchnk)
     call outfld('VAP9',state%v       ,pcols,lchnk)
     call outfld('TAP9',state%t       ,pcols,lchnk)
     call outfld('SAP9',state%s       ,pcols,lchnk)
     call outfld('QAP9',state%q(1,1,1),pcols,lchnk)
   else
     write(iulog,*) 'ERROR: nudging_diag(): indx=',indx
     call endrun('NUDGING: Unknown index for nudging_diag()')
   endif

   ! End Routine
   !------------
   return
  end subroutine ! nudging_diag
  !================================================================


  !================================================================
  subroutine nudging_init
   ! 
   ! NUDGING_INIT: Allocate space and initialize Nudging values
   !===============================================================
   use ppgrid        ,only: pver,pcols,begchunk,endchunk
   use error_messages,only: alloc_err
   use dycore        ,only: dycore_is
   use dyn_grid      ,only: get_horiz_grid_dim_d
   use phys_grid     ,only: get_rlat_p,get_rlon_p,get_ncols_p
   use cam_history   ,only: addfld,phys_decomp
   use shr_const_mod ,only: SHR_CONST_PI

   ! Local values
   !----------------
   integer  Year,Month,Day,Sec
   integer  YMD1,YMD
   logical  After_Beg,Before_End
   integer  istat,lchnk,ncol,icol,ilev
   integer  hdim1_d,hdim2_d
   real(r8) rlat,rlon
   real(r8) Wprof(pver)
   real(r8) lonp,lon0,lonn,latp,lat0,latn
   real(r8) Val1_p,Val2_p,Val3_p,Val4_p
   real(r8) Val1_0,Val2_0,Val3_0,Val4_0
   real(r8) Val1_n,Val2_n,Val3_n,Val4_n
   integer               nn
   real(r8)              NumObs,Freq
   real(r8),allocatable::CosVal(:)
   real(r8),allocatable::SinVal(:)

   ! Allocate Space for Nudging data arrays
   !-----------------------------------------
   allocate(Target_U(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Target_U',pcols*pver*((endchunk-begchunk)+1))
   allocate(Target_V(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Target_V',pcols*pver*((endchunk-begchunk)+1))
   allocate(Target_T(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Target_T',pcols*pver*((endchunk-begchunk)+1))
   allocate(Target_S(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Target_S',pcols*pver*((endchunk-begchunk)+1))
   allocate(Target_Q(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Target_Q',pcols*pver*((endchunk-begchunk)+1))
   allocate(Target_PS(pcols,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Target_PS',pcols*((endchunk-begchunk)+1))

   allocate(Model_U(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Model_U',pcols*pver*((endchunk-begchunk)+1))
   allocate(Model_V(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Model_V',pcols*pver*((endchunk-begchunk)+1))
   allocate(Model_T(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Model_T',pcols*pver*((endchunk-begchunk)+1))
   allocate(Model_S(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Model_S',pcols*pver*((endchunk-begchunk)+1))
   allocate(Model_Q(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Model_Q',pcols*pver*((endchunk-begchunk)+1))
   allocate(Model_PS(pcols,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Model_PS',pcols*((endchunk-begchunk)+1))

   ! Allocate Space for spatial dependence of 
   ! Nudging Coefs and Nudging Forcing.
   !-------------------------------------------
   allocate(Nudge_Utau(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_Utau',pcols*pver*((endchunk-begchunk)+1))
   allocate(Nudge_Vtau(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_Vtau',pcols*pver*((endchunk-begchunk)+1))
   allocate(Nudge_Stau(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_Stau',pcols*pver*((endchunk-begchunk)+1))
   allocate(Nudge_Qtau(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_Qtau',pcols*pver*((endchunk-begchunk)+1))
   allocate(Nudge_PStau(pcols,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_PStau',pcols*((endchunk-begchunk)+1))

   allocate(Nudge_Ustep(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_Ustep',pcols*pver*((endchunk-begchunk)+1))
   allocate(Nudge_Vstep(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_Vstep',pcols*pver*((endchunk-begchunk)+1))
   allocate(Nudge_Sstep(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_Sstep',pcols*pver*((endchunk-begchunk)+1))
   allocate(Nudge_Qstep(pcols,pver,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_Qstep',pcols*pver*((endchunk-begchunk)+1))
   allocate(Nudge_PSstep(pcols,begchunk:endchunk),stat=istat)
   call alloc_err(istat,'nudging_init','Nudge_PSstep',pcols*((endchunk-begchunk)+1))

   ! Register output fields with the cam history module
   !-----------------------------------------------------
   call addfld('Nudge_U','m/s/s'  ,pver,'A','U Nudging Tendency',phys_decomp)
   call addfld('Nudge_V','m/s/s'  ,pver,'A','V Nudging Tendency',phys_decomp)
   call addfld('Nudge_T','K/s'    ,pver,'A','T Nudging Tendency',phys_decomp)
   call addfld('Nudge_Q','kg/kg/s',pver,'A','Q Nudging Tendency',phys_decomp)

   ! Add diagnistic output fileds
   !-------------------------------
   if(Nudge_Diag_Opt.ne.0) then
     call nudging_diag_init
   endif
   
   !-----------------------------------------
   ! Values initialized only by masterproc
   !-----------------------------------------
   if(masterproc) then

     ! Set the Stepping intervals for Model and Nudging values
     ! Ensure that the Model_Step is not smaller then one timestep
     !  and not larger then the Nudge_Step.
     !--------------------------------------------------------
     Model_Step=86400/Model_Times_Per_Day
     Nudge_Step=86400/Nudge_Times_Per_Day
     if(Model_Step.lt.dtime) then
       write(iulog,*) ' '
       write(iulog,*) 'NUDGING: Model_Step cannot be less than a model timestep'
       write(iulog,*) 'NUDGING:  Setting Model_Step=dtime , dtime=',dtime
       write(iulog,*) ' '
       Model_Step=dtime
     endif
     if(Model_Step.gt.Nudge_Step) then
       write(iulog,*) ' '
       write(iulog,*) 'NUDGING: Model_Step cannot be more than Nudge_Step'
       write(iulog,*) 'NUDGING:  Setting Model_Step=Nudge_Step, Nudge_Step=',Nudge_Step
       write(iulog,*) ' '
       Model_Step=Nudge_Step
     endif

     ! Initialize column and level dimensions
     !--------------------------------------------------------
     call get_horiz_grid_dim_d(hdim1_d,hdim2_d)
     Nudge_nlon=hdim1_d
     Nudge_nlat=hdim2_d
     Nudge_ncol=hdim1_d*hdim2_d
     Nudge_nlev=pver

     ! Check the time relative to the nudging window
     !------------------------------------------------
     call get_curr_date(Year,Month,Day,Sec)
     YMD=(Year*10000) + (Month*100) + Day
     YMD1=(Nudge_Beg_Year*10000) + (Nudge_Beg_Month*100) + Nudge_Beg_Day
     call timemgr_time_ge(YMD1,Nudge_Beg_Sec,         &
                          YMD ,Sec          ,After_Beg)
     YMD1=(Nudge_End_Year*10000) + (Nudge_End_Month*100) + Nudge_End_Day
     call timemgr_time_ge(YMD ,Sec          ,          &
                          YMD1,Nudge_End_Sec,Before_End)
  
     if((After_Beg).and.(Before_End)) then
       ! Set Time indicies so that the next call to 
       ! timestep_init will initialize the data arrays.
       !--------------------------------------------
       Model_Next_Year =Year
       Model_Next_Month=Month
       Model_Next_Day  =Day
       Model_Next_Sec  =(Sec/Model_Step)*Model_Step
       Nudge_Next_Year =Year
       Nudge_Next_Month=Month
       Nudge_Next_Day  =Day
       Nudge_Next_Sec  =(Sec/Nudge_Step)*Nudge_Step
     elseif(.not.After_Beg) then
       ! Set Time indicies to Nudging start,
       ! timestep_init will initialize the data arrays.
       !--------------------------------------------
       Model_Next_Year =Nudge_Beg_Year
       Model_Next_Month=Nudge_Beg_Month
       Model_Next_Day  =Nudge_Beg_Day
       Model_Next_Sec  =Nudge_Beg_Sec
       Nudge_Next_Year =Nudge_Beg_Year
       Nudge_Next_Month=Nudge_Beg_Month
       Nudge_Next_Day  =Nudge_Beg_Day
       Nudge_Next_Sec  =Nudge_Beg_Sec
     elseif(.not.Before_End) then
       ! Nudging will never occur, so switch it off
       !--------------------------------------------
       Nudge_Model=.false.
       Nudge_ON   =.false.
       write(iulog,*) ' '
       write(iulog,*) 'NUDGING: WARNING - Nudging has been requested by it will'
       write(iulog,*) 'NUDGING:           never occur for the given time values'
       write(iulog,*) ' '
     endif

     ! Initialize values for window function  
     !----------------------------------------
     lonp= 180.
     lon0=   0.
     lonn=-180.
     latp=  90.-Nudge_Hwin_lat0
     lat0=   0.
     latn= -90.-Nudge_Hwin_lat0
    
     Nudge_Hwin_lonWidthH=Nudge_Hwin_lonWidth/2.
     Nudge_Hwin_latWidthH=Nudge_Hwin_latWidth/2.

     Val1_p=(1.+tanh((Nudge_Hwin_lonWidthH+lonp)/Nudge_Hwin_lonDelta))/2.
     Val2_p=(1.+tanh((Nudge_Hwin_lonWidthH-lonp)/Nudge_Hwin_lonDelta))/2.
     Val3_p=(1.+tanh((Nudge_Hwin_latWidthH+latp)/Nudge_Hwin_latDelta))/2.
     Val4_p=(1.+tanh((Nudge_Hwin_latWidthH-latp)/Nudge_Hwin_latDelta))/2.

     Val1_0=(1.+tanh((Nudge_Hwin_lonWidthH+lon0)/Nudge_Hwin_lonDelta))/2.
     Val2_0=(1.+tanh((Nudge_Hwin_lonWidthH-lon0)/Nudge_Hwin_lonDelta))/2.
     Val3_0=(1.+tanh((Nudge_Hwin_latWidthH+lat0)/Nudge_Hwin_latDelta))/2.
     Val4_0=(1.+tanh((Nudge_Hwin_latWidthH-lat0)/Nudge_Hwin_latDelta))/2.

     Val1_n=(1.+tanh((Nudge_Hwin_lonWidthH+lonn)/Nudge_Hwin_lonDelta))/2.
     Val2_n=(1.+tanh((Nudge_Hwin_lonWidthH-lonn)/Nudge_Hwin_lonDelta))/2.
     Val3_n=(1.+tanh((Nudge_Hwin_latWidthH+latn)/Nudge_Hwin_latDelta))/2.
     Val4_n=(1.+tanh((Nudge_Hwin_latWidthH-latn)/Nudge_Hwin_latDelta))/2.

     Nudge_Hwin_max=     Val1_0*Val2_0*Val3_0*Val4_0
     Nudge_Hwin_min=min((Val1_p*Val2_p*Val3_n*Val4_n), &
                        (Val1_p*Val2_p*Val3_p*Val4_p), &
                        (Val1_n*Val2_n*Val3_n*Val4_n), &
                        (Val1_n*Val2_n*Val3_p*Val4_p))

     ! Initialize number of nudging observation values to keep track of.
     ! Allocate and initialize observation indices 
     !-----------------------------------------------------------------
     if((Nudge_Force_Opt.ge.0).and.(Nudge_Force_Opt.le.3)) then
       Nudge_NumObs=2
     else
       Nudge_NumObs=Nudge_Times_Per_Day
       if(Nudge_NumObs.lt.4) then
         write(iulog,*) 'NUDGING: Nudge_NumObs=',Nudge_NumObs
         write(iulog,*) 'NUDGING: The Diurnal Filter was forumlated for a minimum'
         write(iulog,*) 'NUDGING: of 4 observations per day. What your doing may'
         write(iulog,*) 'NUDGING: work, but you better check it first before you'
         write(iulog,*) 'NUDGING: remove this stop.'
         call endrun('NUDGING DIURNAL FILTER ONLY CONFIGURED FOR >4 OBS/DAY')
       endif
     endif
     allocate(Nudge_ObsInd(Nudge_NumObs),stat=istat)
     call alloc_err(istat,'nudging_init','Nudge_ObsInd',Nudge_NumObs)
     allocate(Nudge_File_Present(Nudge_NumObs),stat=istat)
     call alloc_err(istat,'nudging_init','Nudge_File_Present',Nudge_NumObs)
     do nn=1,Nudge_NumObs
       Nudge_ObsInd(nn) = Nudge_NumObs+1-nn
     end do
     Nudge_File_Present(:)=.false.

     ! Allocate/Initialize values for Diurnal Filter Coefs
     !------------------------------------------------------
     allocate(Nudge_Bcoef(Nudge_NumObs),stat=istat)
     call alloc_err(istat,'nudging_init','Nudge_Bcoef',Nudge_NumObs)
     allocate(Nudge_Ccoef(Nudge_NumObs),stat=istat)
     call alloc_err(istat,'nudging_init','Nudge_Ccoef',Nudge_NumObs)

     if((Nudge_Force_Opt.ge.0).and.(Nudge_Force_Opt.le.3)) then
       ! These coefs are never used.
       !------------------------------
       Nudge_Acoef   =1._r8
       Nudge_Bcoef(:)=0._r8
       Nudge_Ccoef(:)=0._r8
     elseif((Nudge_Force_Opt.ge.4).and.(Nudge_Force_Opt.le.7)) then
       ! Load Sin/Cos for 1 Diurnal Cycle
       !----------------------------------
       NumObs=float(Nudge_NumObs)
       Freq = (2._r8*SHR_CONST_PI)/NumObs
       allocate(CosVal(Nudge_NumObs),stat=istat)
       call alloc_err(istat,'nudging_init','CosVal',Nudge_NumObs)
       allocate(SinVal(Nudge_NumObs),stat=istat)
       call alloc_err(istat,'nudging_init','SinVal',Nudge_NumObs)
       do nn=1,Nudge_NumObs
         CosVal(nn)=cos(Freq*(1.5_r8-float(nn)))
         SinVal(nn)=sin(Freq*(1.5_r8-float(nn)))
       end do

       ! Load Diurnal Filter Coefs
       !----------------------------------
       Nudge_Acoef   = (NumObs-2._r8*(1._r8 - (CosVal(1)*CosVal(2)         &
                                              +SinVal(1)*SinVal(2))))/NumObs
       Nudge_Bcoef(:)=0._r8
       Nudge_Ccoef(:)=0._r8
       do nn=2,Nudge_NumObs
         Nudge_Bcoef(nn)=(Nudge_Acoef*(1._r8 + 4._r8*(CosVal(nn)*CosVal(1)        &
                                                     +SinVal(nn)*SinVal(1)))/5._r8)
         Nudge_Ccoef(nn)=2._r8*(CosVal(nn)*(CosVal(2)-CosVal(1))       &
                               +SinVal(nn)*(SinVal(2)-SinVal(1)))/NumObs
       end do

       ! For forcing options 6,7 force the square peg into the round hole...
       !  -the diurnal filter is *made* stable by using abs(Bcoef).
       !-------------------------------------------------------------------
       if((Nudge_Force_Opt.eq.6).or.(Nudge_Force_Opt.eq.7)) then
         Nudge_Bcoef(:)=abs(Nudge_Bcoef(:))
       endif

       ! For coding simplicity later on...
       !-----------------------------------
       Nudge_Ccoef(:)=Nudge_Ccoef(:)-Nudge_Bcoef(:)
       
       deallocate(CosVal)
       deallocate(SinVal)
     endif ! ((Nudge_Force_Opt.ge.4).and.(Nudge_Force_Opt.le.7)) then

     ! Initialization is done, 
     !--------------------------
     Nudge_Initialized=.true.

     ! Check that this is a valid DYCORE model
     !------------------------------------------
     if((.not.dycore_is('UNSTRUCTURED')).and. &
        (.not.dycore_is('EUL')         ).and. &
        (.not.dycore_is('LR')          )      ) then
       call endrun('NUDGING IS CURRENTLY ONLY CONFIGURED FOR CAM-SE, FV, or EUL')
     endif

     ! Informational Output
     !---------------------------
     write(iulog,*) ' '
     write(iulog,*) '---------------------------------------------------------'
     write(iulog,*) '  MODEL NUDGING INITIALIZED WITH THE FOLLOWING SETTINGS: '
     write(iulog,*) '---------------------------------------------------------'
     write(iulog,*) 'NUDGING: Nudge_Model=',Nudge_Model
     write(iulog,*) 'NUDGING: Nudge_Path=',Nudge_Path
     write(iulog,*) 'NUDGING: Nudge_File_Template =',Nudge_File_Template
     write(iulog,*) 'NUDGING: Nudge_Force_Opt=',Nudge_Force_Opt    
     write(iulog,*) 'NUDGING: Nudge_Diag_Opt =',Nudge_Diag_Opt    
     write(iulog,*) 'NUDGING: Nudge_TSmode=',Nudge_TSmode
     write(iulog,*) 'NUDGING: Nudge_Times_Per_Day=',Nudge_Times_Per_Day
     write(iulog,*) 'NUDGING: Model_Times_Per_Day=',Model_Times_Per_Day
     write(iulog,*) 'NUDGING: Nudge_Step=',Nudge_Step
     write(iulog,*) 'NUDGING: Model_Step=',Model_Step
     write(iulog,*) 'NUDGING: Nudge_Ucoef  =',Nudge_Ucoef
     write(iulog,*) 'NUDGING: Nudge_Vcoef  =',Nudge_Vcoef
     write(iulog,*) 'NUDGING: Nudge_Qcoef  =',Nudge_Qcoef
     write(iulog,*) 'NUDGING: Nudge_Tcoef  =',Nudge_Tcoef
     write(iulog,*) 'NUDGING: Nudge_PScoef =',Nudge_PScoef
     write(iulog,*) 'NUDGING: Nudge_Uprof  =',Nudge_Uprof
     write(iulog,*) 'NUDGING: Nudge_Vprof  =',Nudge_Vprof
     write(iulog,*) 'NUDGING: Nudge_Qprof  =',Nudge_Qprof
     write(iulog,*) 'NUDGING: Nudge_Tprof  =',Nudge_Tprof
     write(iulog,*) 'NUDGING: Nudge_PSprof =',Nudge_PSprof
     write(iulog,*) 'NUDGING: Nudge_Beg_Year =',Nudge_Beg_Year
     write(iulog,*) 'NUDGING: Nudge_Beg_Month=',Nudge_Beg_Month
     write(iulog,*) 'NUDGING: Nudge_Beg_Day  =',Nudge_Beg_Day
     write(iulog,*) 'NUDGING: Nudge_End_Year =',Nudge_End_Year
     write(iulog,*) 'NUDGING: Nudge_End_Month=',Nudge_End_Month
     write(iulog,*) 'NUDGING: Nudge_End_Day  =',Nudge_End_Day
     write(iulog,*) 'NUDGING: Nudge_Hwin_lo       =',Nudge_Hwin_lo
     write(iulog,*) 'NUDGING: Nudge_Hwin_hi       =',Nudge_Hwin_hi
     write(iulog,*) 'NUDGING: Nudge_Hwin_lat0     =',Nudge_Hwin_lat0
     write(iulog,*) 'NUDGING: Nudge_Hwin_latWidth =',Nudge_Hwin_latWidth
     write(iulog,*) 'NUDGING: Nudge_Hwin_latDelta =',Nudge_Hwin_latDelta
     write(iulog,*) 'NUDGING: Nudge_Hwin_lon0     =',Nudge_Hwin_lon0
     write(iulog,*) 'NUDGING: Nudge_Hwin_lonWidth =',Nudge_Hwin_lonWidth
     write(iulog,*) 'NUDGING: Nudge_Hwin_lonDelta =',Nudge_Hwin_lonDelta
     write(iulog,*) 'NUDGING: Nudge_Vwin_lo       =',Nudge_Vwin_lo
     write(iulog,*) 'NUDGING: Nudge_Vwin_hi       =',Nudge_Vwin_hi
     write(iulog,*) 'NUDGING: Nudge_Vwin_Hindex   =',Nudge_Vwin_Hindex
     write(iulog,*) 'NUDGING: Nudge_Vwin_Hdelta   =',Nudge_Vwin_Hdelta
     write(iulog,*) 'NUDGING: Nudge_Vwin_Lindex   =',Nudge_Vwin_Lindex
     write(iulog,*) 'NUDGING: Nudge_Vwin_Ldelta   =',Nudge_Vwin_Ldelta
     write(iulog,*) 'NUDGING: Nudge_Hwin_latWidthH=',Nudge_Hwin_latWidthH
     write(iulog,*) 'NUDGING: Nudge_Hwin_lonWidthH=',Nudge_Hwin_lonWidthH
     write(iulog,*) 'NUDGING: Nudge_Hwin_max      =',Nudge_Hwin_max
     write(iulog,*) 'NUDGING: Nudge_Hwin_min      =',Nudge_Hwin_min
     write(iulog,*) 'NUDGING: Nudge_Initialized   =',Nudge_Initialized
     write(iulog,*) ' '
     write(iulog,*) 'NUDGING: Nudge_NumObs=',Nudge_NumObs
     write(iulog,*) 'NUDGING: Nudge_Acoef =',Nudge_Acoef
     write(iulog,*) 'NUDGING: Nudge_Bcoef =',Nudge_Bcoef
     write(iulog,*) 'NUDGING: Nudge_Ccoef =',Nudge_Ccoef
     write(iulog,*) ' '

   endif ! (masterproc) then

   ! Broadcast other variables that have changed
   !---------------------------------------------
#ifdef SPMD
   call mpibcast(Model_Step          ,            1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Step          ,            1, mpir8 , 0, mpicom)
   call mpibcast(Model_Next_Year     ,            1, mpiint, 0, mpicom)
   call mpibcast(Model_Next_Month    ,            1, mpiint, 0, mpicom)
   call mpibcast(Model_Next_Day      ,            1, mpiint, 0, mpicom)
   call mpibcast(Model_Next_Sec      ,            1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Next_Year     ,            1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Next_Month    ,            1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Next_Day      ,            1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Next_Sec      ,            1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Model         ,            1, mpilog, 0, mpicom)
   call mpibcast(Nudge_ON            ,            1, mpilog, 0, mpicom)
   call mpibcast(Nudge_Initialized   ,            1, mpilog, 0, mpicom)
   call mpibcast(Nudge_ncol          ,            1, mpiint, 0, mpicom)
   call mpibcast(Nudge_nlev          ,            1, mpiint, 0, mpicom)
   call mpibcast(Nudge_nlon          ,            1, mpiint, 0, mpicom)
   call mpibcast(Nudge_nlat          ,            1, mpiint, 0, mpicom)
   call mpibcast(Nudge_Hwin_max      ,            1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_min      ,            1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_lonWidthH,            1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Hwin_latWidthH,            1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_NumObs        ,            1, mpiint, 0, mpicom)
#endif

   ! All non-masterproc processes also need to allocate space
   ! before the broadcast of Nudge_NumObs dependent data.
   !------------------------------------------------------------
   if(.not.masterproc) then
     allocate(Nudge_ObsInd(Nudge_NumObs),stat=istat)
     call alloc_err(istat,'nudging_init','Nudge_ObsInd',Nudge_NumObs)
     allocate(Nudge_File_Present(Nudge_NumObs),stat=istat)
     call alloc_err(istat,'nudging_init','Nudge_File_Present',Nudge_NumObs)
     allocate(Nudge_Bcoef(Nudge_NumObs),stat=istat)
     call alloc_err(istat,'nudging_init','Nudge_Bcoef',Nudge_NumObs)
     allocate(Nudge_Ccoef(Nudge_NumObs),stat=istat)
     call alloc_err(istat,'nudging_init','Nudge_Ccoef',Nudge_NumObs)
   endif
#ifdef SPMD
   call mpibcast(Nudge_ObsInd        , Nudge_NumObs, mpiint, 0, mpicom)
   call mpibcast(Nudge_File_Present  , Nudge_NumObs, mpilog, 0, mpicom)
   call mpibcast(Nudge_Acoef         ,            1, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Bcoef         , Nudge_NumObs, mpir8 , 0, mpicom)
   call mpibcast(Nudge_Ccoef         , Nudge_NumObs, mpir8 , 0, mpicom)
#endif

   ! Allocate Space for Nudging observation arrays, initialize with 0's
   !---------------------------------------------------------------------
   allocate(Nobs_U(pcols,pver,begchunk:endchunk,Nudge_NumObs),stat=istat)
   call alloc_err(istat,'nudging_init','Nobs_U',pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)
   allocate(Nobs_V(pcols,pver,begchunk:endchunk,Nudge_NumObs),stat=istat)
   call alloc_err(istat,'nudging_init','Nobs_V',pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)
   allocate(Nobs_T(pcols,pver,begchunk:endchunk,Nudge_NumObs),stat=istat)
   call alloc_err(istat,'nudging_init','Nobs_T',pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)
   allocate(Nobs_Q(pcols,pver,begchunk:endchunk,Nudge_NumObs),stat=istat)
   call alloc_err(istat,'nudging_init','Nobs_Q',pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)
   allocate(Nobs_PS(pcols,begchunk:endchunk,Nudge_NumObs),stat=istat)
   call alloc_err(istat,'nudging_init','Nobs_PS',pcols*((endchunk-begchunk)+1)*Nudge_NumObs)
   allocate(Mobs_U(pcols,pver,begchunk:endchunk,Nudge_NumObs),stat=istat)

   call alloc_err(istat,'nudging_init','Mobs_U',pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)
   allocate(Mobs_V(pcols,pver,begchunk:endchunk,Nudge_NumObs),stat=istat)
   call alloc_err(istat,'nudging_init','Mobs_V',pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)
   allocate(Mobs_T(pcols,pver,begchunk:endchunk,Nudge_NumObs),stat=istat)
   call alloc_err(istat,'nudging_init','Mobs_T',pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)
   allocate(Mobs_Q(pcols,pver,begchunk:endchunk,Nudge_NumObs),stat=istat)
   call alloc_err(istat,'nudging_init','Mobs_Q',pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)
   allocate(Mobs_PS(pcols,begchunk:endchunk,Nudge_NumObs),stat=istat)
   call alloc_err(istat,'nudging_init','Mobs_PS',pcols*((endchunk-begchunk)+1)*Nudge_NumObs)

   Nobs_U(:pcols,:pver,begchunk:endchunk,:Nudge_NumObs)=0._r8
   Nobs_V(:pcols,:pver,begchunk:endchunk,:Nudge_NumObs)=0._r8
   Nobs_T(:pcols,:pver,begchunk:endchunk,:Nudge_NumObs)=0._r8
   Nobs_Q(:pcols,:pver,begchunk:endchunk,:Nudge_NumObs)=0._r8
   Nobs_PS(:pcols     ,begchunk:endchunk,:Nudge_NumObs)=0._r8
   Mobs_U(:pcols,:pver,begchunk:endchunk,:Nudge_NumObs)=0._r8
   Mobs_V(:pcols,:pver,begchunk:endchunk,:Nudge_NumObs)=0._r8
   Mobs_T(:pcols,:pver,begchunk:endchunk,:Nudge_NumObs)=0._r8
   Mobs_Q(:pcols,:pver,begchunk:endchunk,:Nudge_NumObs)=0._r8
   Mobs_PS(:pcols     ,begchunk:endchunk,:Nudge_NumObs)=0._r8

!!DIAG
   if(masterproc) then
     write(iulog,*) 'NUDGING: nudging_init() OBS arrays allocated and initialized'
     write(iulog,*) 'NUDGING: nudging_init() SIZE#',(9*pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)
     write(iulog,*) 'NUDGING: nudging_init() MB:',float(8*9*pcols*pver*((endchunk-begchunk)+1)*Nudge_NumObs)/(1024.*1024.)
     write(iulog,*) 'NUDGING: nudging_init() pcols=',pcols,' pver=',pver
     write(iulog,*) 'NUDGING: nudging_init() begchunk:',begchunk,' endchunk=',endchunk
     write(iulog,*) 'NUDGING: nudging_init() chunk:',(endchunk-begchunk+1),' Nudge_NumObs=',Nudge_NumObs
     write(iulog,*) 'NUDGING: nudging_init() Nudge_ObsInd=',Nudge_ObsInd
     write(iulog,*) 'NUDGING: nudging_init() Nudge_File_Present=',Nudge_File_Present
     write(iulog,*) 'NUDGING: nudging_init() Nudge_Acoef=',Nudge_Acoef
     write(iulog,*) 'NUDGING: nudging_init() Nudge_Bcoef=',Nudge_Bcoef
     write(iulog,*) 'NUDGING: nudging_init() Nudge_Ccoef=',Nudge_Ccoef
   endif
!!DIAG

   ! Initialize Nudging Coeffcient profiles in local arrays
   ! Load zeros into nudging arrays
   !------------------------------------------------------
   do lchnk=begchunk,endchunk
     ncol=get_ncols_p(lchnk)
     do icol=1,ncol
       rlat=get_rlat_p(lchnk,icol)*180._r8/SHR_CONST_PI
       rlon=get_rlon_p(lchnk,icol)*180._r8/SHR_CONST_PI

       call nudging_set_profile(rlat,rlon,Nudge_Uprof,Wprof,pver)
       Nudge_Utau(icol,:,lchnk)=Wprof(:)
       call nudging_set_profile(rlat,rlon,Nudge_Vprof,Wprof,pver)
       Nudge_Vtau(icol,:,lchnk)=Wprof(:)
       call nudging_set_profile(rlat,rlon,Nudge_Tprof,Wprof,pver)
       Nudge_Stau(icol,:,lchnk)=Wprof(:)
       call nudging_set_profile(rlat,rlon,Nudge_Qprof,Wprof,pver)
       Nudge_Qtau(icol,:,lchnk)=Wprof(:)

       Nudge_PStau(icol,lchnk)=nudging_set_PSprofile(rlat,rlon,Nudge_PSprof)
     end do
     Nudge_Utau(:ncol,:pver,lchnk) =                             &
     Nudge_Utau(:ncol,:pver,lchnk) * Nudge_Ucoef/float(Nudge_Step)
     Nudge_Vtau(:ncol,:pver,lchnk) =                             &
     Nudge_Vtau(:ncol,:pver,lchnk) * Nudge_Vcoef/float(Nudge_Step)
     Nudge_Stau(:ncol,:pver,lchnk) =                             &
     Nudge_Stau(:ncol,:pver,lchnk) * Nudge_Tcoef/float(Nudge_Step)
     Nudge_Qtau(:ncol,:pver,lchnk) =                             &
     Nudge_Qtau(:ncol,:pver,lchnk) * Nudge_Qcoef/float(Nudge_Step)
     Nudge_PStau(:ncol,lchnk)=                             &
     Nudge_PStau(:ncol,lchnk)* Nudge_PScoef/float(Nudge_Step)

     Nudge_Ustep(:pcols,:pver,lchnk)=0._r8
     Nudge_Vstep(:pcols,:pver,lchnk)=0._r8
     Nudge_Sstep(:pcols,:pver,lchnk)=0._r8
     Nudge_Qstep(:pcols,:pver,lchnk)=0._r8
     Nudge_PSstep(:pcols,lchnk)=0._r8
     Target_U(:pcols,:pver,lchnk)=0._r8
     Target_V(:pcols,:pver,lchnk)=0._r8
     Target_T(:pcols,:pver,lchnk)=0._r8
     Target_S(:pcols,:pver,lchnk)=0._r8
     Target_Q(:pcols,:pver,lchnk)=0._r8
     Target_PS(:pcols,lchnk)=0._r8
   end do

!DIAG
!  if(masterproc) then
!    write(iulog,*) 'NUDGING: exiting nudging_init()'
!  endif
!DIAG

   ! End Routine
   !------------
   return
  end subroutine ! nudging_init
  !================================================================


  !================================================================
  subroutine nudging_timestep_init(phys_state)
   ! 
   ! NUDGING_TIMESTEP_INIT: 
   !                 Check the current time and update Model/Nudging 
   !                 arrays when necessary. Toggle the Nudging flag
   !                 when the time is withing the nudging window.
   !===============================================================
   use physconst    ,only: cpair
   use physics_types,only: physics_state
   use constituents ,only: cnst_get_ind
   use dycore       ,only: dycore_is
   use ppgrid       ,only: pver,pcols,begchunk,endchunk
   use filenames    ,only: interpret_filename_spec
   use ESMF

   ! Arguments
   !-----------
   type(physics_state),intent(in):: phys_state(begchunk:endchunk)

   ! Local values
   !----------------
   integer Year,Month,Day,Sec
   integer YMD1,YMD2,YMD
   logical Update_Model,Update_Nudge,Sync_Error
   logical After_Beg   ,Before_End
   integer lchnk,ncol,indw

   type(ESMF_Time)         Date1,Date2
   type(ESMF_TimeInterval) DateDiff
   integer                 DeltaT
   real(r8)                Tscale
   integer                 rc
   integer                 nn
   integer                 kk
   real(r8)                Sbar,Qbar,Wsum

!DIAG
!  if(masterproc) then
!    write(iulog,*) 'NUDGING: entering nudging_timestep_init()'
!  endif
!DIAG
   ! Check if Nudging is initialized
   !---------------------------------
   if(.not.Nudge_Initialized) then
     call endrun('nudging_timestep_init:: Nudging NOT Initialized')
   endif

   ! Get Current time
   !--------------------
   call get_curr_date(Year,Month,Day,Sec)
   YMD=(Year*10000) + (Month*100) + Day

   !-------------------------------------------------------
   ! Determine if the current time is AFTER the begining time
   ! and if it is BEFORE the ending time.
   !-------------------------------------------------------
   YMD1=(Nudge_Beg_Year*10000) + (Nudge_Beg_Month*100) + Nudge_Beg_Day
   call timemgr_time_ge(YMD1,Nudge_Beg_Sec,         &
                        YMD ,Sec          ,After_Beg)

   YMD1=(Nudge_End_Year*10000) + (Nudge_End_Month*100) + Nudge_End_Day
   call timemgr_time_ge(YMD ,Sec,                    &
                        YMD1,Nudge_End_Sec,Before_End)

   !--------------------------------------------------------------
   ! When past the NEXT time, Update Model Arrays and time indices
   !--------------------------------------------------------------
   YMD1=(Model_Next_Year*10000) + (Model_Next_Month*100) + Model_Next_Day
   call timemgr_time_ge(YMD1,Model_Next_Sec,            &
                        YMD ,Sec           ,Update_Model)

   if((Before_End).and.(Update_Model)) then
     ! Increment the Model times by the current interval
     !---------------------------------------------------
     Model_Curr_Year =Model_Next_Year
     Model_Curr_Month=Model_Next_Month
     Model_Curr_Day  =Model_Next_Day
     Model_Curr_Sec  =Model_Next_Sec
     YMD1=(Model_Curr_Year*10000) + (Model_Curr_Month*100) + Model_Curr_Day
     call timemgr_time_inc(YMD1,Model_Curr_Sec,              &
                           YMD2,Model_Next_Sec,Model_Step,0,0)

     ! Check for Sync Error where NEXT model time after the update
     ! is before the current time. If so, reset the next model 
     ! time to a Model_Step after the current time.
     !--------------------------------------------------------------
     call timemgr_time_ge(YMD2,Model_Next_Sec,            &
                          YMD ,Sec           ,Sync_Error)
     if(Sync_Error) then
       Model_Curr_Year =Year
       Model_Curr_Month=Month
       Model_Curr_Day  =Day
       Model_Curr_Sec  =Sec
       call timemgr_time_inc(YMD ,Model_Curr_Sec,              &
                             YMD2,Model_Next_Sec,Model_Step,0,0)
       write(iulog,*) 'NUDGING: WARNING - Model_Time Sync ERROR... CORRECTED'
     endif
     Model_Next_Year =(YMD2/10000)
     YMD2            = YMD2-(Model_Next_Year*10000)
     Model_Next_Month=(YMD2/100)
     Model_Next_Day  = YMD2-(Model_Next_Month*100)

     ! Load values at Current into the Model arrays
     !-----------------------------------------------
     call cnst_get_ind('Q',indw)
     do lchnk=begchunk,endchunk
       ncol=phys_state(lchnk)%ncol
       Model_U(:ncol,:pver,lchnk)=phys_state(lchnk)%u(:ncol,:pver)
       Model_V(:ncol,:pver,lchnk)=phys_state(lchnk)%v(:ncol,:pver)
       Model_T(:ncol,:pver,lchnk)=phys_state(lchnk)%t(:ncol,:pver)
       Model_Q(:ncol,:pver,lchnk)=phys_state(lchnk)%q(:ncol,:pver,indw)
       Model_PS(:ncol,lchnk)=phys_state(lchnk)%ps(:ncol)
     end do

     ! Load Dry Static Energy values for Model
     !-----------------------------------------
     if(Nudge_TSmode.eq.0) then
       ! DSE tendencies from Temperature only
       !---------------------------------------
       do lchnk=begchunk,endchunk
         ncol=phys_state(lchnk)%ncol
         Model_S(:ncol,:pver,lchnk)=cpair*Model_T(:ncol,:pver,lchnk)
       end do
     elseif(Nudge_TSmode.eq.1) then
       ! Caluculate DSE tendencies from Temperature, Water Vapor, and Surface Pressure
       !------------------------------------------------------------------------------
       do lchnk=begchunk,endchunk
         ncol=phys_state(lchnk)%ncol
         call calc_DryStaticEnergy(Model_T(:,:,lchnk)  , Model_Q(:,:,lchnk), &
                                 phys_state(lchnk)%phis,  Model_PS(:,lchnk), &
                                                  Model_S(:,:,lchnk), ncol)
       end do
     endif 
!PFCDIAG
!    if(.FALSE.) then
!      ! OPTIONALLY remove vertical mean from Model_S
!      !-----------------------------------------------
!      do lchnk=begchunk,endchunk
!        ncol=phys_state(lchnk)%ncol
!        do nn=1,ncol
!          Sbar=0._r8
!          do kk=1,pver
!            Sbar=Sbar+Model_S(nn,kk,lchnk)
!          end do
!          Sbar=Sbar/float(pver)
!          Model_S(nn,:,lchnk)=Model_S(nn,:,lchnk)-Sbar
!        end do
!      end do
!    elseif(.TRUE.) then
!      ! OPTIONALLY remove weighted vertical mean from Model_S
!      !-------------------------------------------------------
!      do lchnk=begchunk,endchunk
!        ncol=phys_state(lchnk)%ncol
!        do nn=1,ncol
!          Sbar=0._r8
!          Qbar=0._r8
!          Wsum=0._r8
!          do kk=1,pver
!            Sbar=Sbar+Model_S(nn,kk,lchnk)*(phys_state(lchnk)%pdel(nn,kk)/phys_state(lchnk)%pmid(nn,kk))
!            Qbar=Qbar+Model_Q(nn,kk,lchnk)*(phys_state(lchnk)%pdel(nn,kk)/phys_state(lchnk)%pmid(nn,kk))
!            Wsum=Wsum+(phys_state(lchnk)%pdel(nn,kk)/phys_state(lchnk)%pmid(nn,kk))
!          end do
!          Sbar=Sbar/Wsum
!          Qbar=Qbar/Wsum
!          Model_S(nn,:,lchnk)=Model_S(nn,:,lchnk)-Sbar
!          Model_Q(nn,:,lchnk)=Model_Q(nn,:,lchnk)-Qbar
!        end do
!      end do
!    endif
!PFCDIAG

   endif ! ((Before_End).and.(Update_Model)) then

   !----------------------------------------------------------------
   ! When past the NEXT time, Update Nudging Arrays and time indices
   !----------------------------------------------------------------
   YMD1=(Nudge_Next_Year*10000) + (Nudge_Next_Month*100) + Nudge_Next_Day
   call timemgr_time_ge(YMD1,Nudge_Next_Sec,            &
                        YMD ,Sec           ,Update_Nudge)

   if((Before_End).and.(Update_Nudge)) then
     ! Increment the Nudge times by the current interval
     !---------------------------------------------------
     Nudge_Curr_Year =Nudge_Next_Year
     Nudge_Curr_Month=Nudge_Next_Month
     Nudge_Curr_Day  =Nudge_Next_Day
     Nudge_Curr_Sec  =Nudge_Next_Sec
     YMD1=(Nudge_Curr_Year*10000) + (Nudge_Curr_Month*100) + Nudge_Curr_Day
     call timemgr_time_inc(YMD1,Nudge_Curr_Sec,              &
                           YMD2,Nudge_Next_Sec,Nudge_Step,0,0)
     Nudge_Next_Year =(YMD2/10000)
     YMD2            = YMD2-(Nudge_Next_Year*10000)
     Nudge_Next_Month=(YMD2/100)
     Nudge_Next_Day  = YMD2-(Nudge_Next_Month*100)

     ! Set the analysis filename at the NEXT time.
     !---------------------------------------------------------------
     Nudge_File=interpret_filename_spec(Nudge_File_Template      , &
                                         yr_spec=Nudge_Next_Year , &
                                        mon_spec=Nudge_Next_Month, &
                                        day_spec=Nudge_Next_Day  , &
                                        sec_spec=Nudge_Next_Sec    )
     if(masterproc) then
      write(iulog,*) 'NUDGING: Reading analyses:',trim(Nudge_Path)//trim(Nudge_File)
     endif

     ! Rotate Nudge_ObsInd() indices for new data, then update 
     ! the Nudge observation arrays with analysis data at the 
     ! NEXT==Nudge_ObsInd(1) time.
     !----------------------------------------------------------
     if(dycore_is('UNSTRUCTURED')) then
       call nudging_update_analyses_se (trim(Nudge_Path)//trim(Nudge_File))
     elseif(dycore_is('EUL')) then
       call nudging_update_analyses_eul(trim(Nudge_Path)//trim(Nudge_File))
     else !if(dycore_is('LR')) then
       call nudging_update_analyses_fv (trim(Nudge_Path)//trim(Nudge_File))
     endif

     ! Update the Model observation arrays with model data at 
     ! the CURR==Nudge_ObsInd(2) time.
     !---------------------------------------------------------------
     call cnst_get_ind('Q',indw)
     do lchnk=begchunk,endchunk
       ncol=phys_state(lchnk)%ncol
       Mobs_U(:ncol,:pver,lchnk,Nudge_ObsInd(2))=phys_state(lchnk)%u(:ncol,:pver)
       Mobs_V(:ncol,:pver,lchnk,Nudge_ObsInd(2))=phys_state(lchnk)%v(:ncol,:pver)
       Mobs_T(:ncol,:pver,lchnk,Nudge_ObsInd(2))=phys_state(lchnk)%t(:ncol,:pver)
       Mobs_Q(:ncol,:pver,lchnk,Nudge_ObsInd(2))=phys_state(lchnk)%q(:ncol,:pver,indw)
       Mobs_PS(:ncol     ,lchnk,Nudge_ObsInd(2))=phys_state(lchnk)%ps(:ncol)
     end do

     ! Now Load the Target values for nudging tendencies
     !---------------------------------------------------
     if((Nudge_Force_Opt.eq.0).or.(Nudge_Force_Opt.eq.1)) then
       ! Target is OBS data at NEXT time
       !----------------------------------
       do lchnk=begchunk,endchunk
         ncol=phys_state(lchnk)%ncol
         Target_U(:ncol,:pver,lchnk)=Nobs_U(:ncol,:pver,lchnk,Nudge_ObsInd(1))
         Target_V(:ncol,:pver,lchnk)=Nobs_V(:ncol,:pver,lchnk,Nudge_ObsInd(1))
         Target_T(:ncol,:pver,lchnk)=Nobs_T(:ncol,:pver,lchnk,Nudge_ObsInd(1))
         Target_Q(:ncol,:pver,lchnk)=Nobs_Q(:ncol,:pver,lchnk,Nudge_ObsInd(1))
         Target_PS(:ncol     ,lchnk)=Nobs_PS(:ncol     ,lchnk,Nudge_ObsInd(1))
       end do
     elseif((Nudge_Force_Opt.eq.2).or.(Nudge_Force_Opt.eq.3)) then
       ! Target is OBS data at CURR time
       !----------------------------------
       do lchnk=begchunk,endchunk
         ncol=phys_state(lchnk)%ncol
         Target_U(:ncol,:pver,lchnk)=Nobs_U(:ncol,:pver,lchnk,Nudge_ObsInd(2))
         Target_V(:ncol,:pver,lchnk)=Nobs_V(:ncol,:pver,lchnk,Nudge_ObsInd(2))
         Target_T(:ncol,:pver,lchnk)=Nobs_T(:ncol,:pver,lchnk,Nudge_ObsInd(2))
         Target_Q(:ncol,:pver,lchnk)=Nobs_Q(:ncol,:pver,lchnk,Nudge_ObsInd(2))
         Target_PS(:ncol     ,lchnk)=Nobs_PS(:ncol     ,lchnk,Nudge_ObsInd(2))
       end do
     elseif((Nudge_Force_Opt.ge.4).or.(Nudge_Force_Opt.le.7)) then
       ! Target is Diurnal Estimate at NEXT time
       !-----------------------------------------
       do lchnk=begchunk,endchunk
         ncol=phys_state(lchnk)%ncol
         Target_U(:ncol,:pver,lchnk)=Nudge_Acoef*Nobs_U(:ncol,:pver,lchnk,Nudge_ObsInd(1))
         Target_V(:ncol,:pver,lchnk)=Nudge_Acoef*Nobs_V(:ncol,:pver,lchnk,Nudge_ObsInd(1))
         Target_T(:ncol,:pver,lchnk)=Nudge_Acoef*Nobs_T(:ncol,:pver,lchnk,Nudge_ObsInd(1))
         Target_Q(:ncol,:pver,lchnk)=Nudge_Acoef*Nobs_Q(:ncol,:pver,lchnk,Nudge_ObsInd(1))
         Target_PS(:ncol     ,lchnk)=Nudge_Acoef*Nobs_PS(:ncol     ,lchnk,Nudge_ObsInd(1))
         do nn=2,Nudge_NumObs
           Target_U(:ncol,:pver,lchnk) = Target_U(:ncol,:pver,lchnk)                   &
                         +(Nudge_Bcoef(nn)*Nobs_U(:ncol,:pver,lchnk,Nudge_ObsInd(nn))) &
                         +(Nudge_Ccoef(nn)*Mobs_U(:ncol,:pver,lchnk,Nudge_ObsInd(nn)))
           Target_V(:ncol,:pver,lchnk) = Target_V(:ncol,:pver,lchnk)                   &
                         +(Nudge_Bcoef(nn)*Nobs_V(:ncol,:pver,lchnk,Nudge_ObsInd(nn))) &
                         +(Nudge_Ccoef(nn)*Mobs_V(:ncol,:pver,lchnk,Nudge_ObsInd(nn)))
           Target_T(:ncol,:pver,lchnk) = Target_T(:ncol,:pver,lchnk)                   &
                         +(Nudge_Bcoef(nn)*Nobs_T(:ncol,:pver,lchnk,Nudge_ObsInd(nn))) &
                         +(Nudge_Ccoef(nn)*Mobs_T(:ncol,:pver,lchnk,Nudge_ObsInd(nn)))
           Target_Q(:ncol,:pver,lchnk) = Target_Q(:ncol,:pver,lchnk)                   &
                         +(Nudge_Bcoef(nn)*Nobs_Q(:ncol,:pver,lchnk,Nudge_ObsInd(nn))) &
                         +(Nudge_Ccoef(nn)*Mobs_Q(:ncol,:pver,lchnk,Nudge_ObsInd(nn)))
           Target_PS(:ncol     ,lchnk) =Target_PS(:ncol      ,lchnk)                   &
                        +(Nudge_Bcoef(nn)*Nobs_PS(:ncol      ,lchnk,Nudge_ObsInd(nn))) &
                        +(Nudge_Ccoef(nn)*Mobs_PS(:ncol      ,lchnk,Nudge_ObsInd(nn)))
         end do
       end do ! lchnk=begchunk,endchunk
     else
       write(iulog,*) 'NUDGING: Unknown Nudge_Force_Opt=',Nudge_Force_Opt
       call endrun('nudging_timestep_init:: ERROR unknown Nudging_Force_Opt')
     endif

     ! Now load Dry Static Energy values for Target
     !---------------------------------------------
     if(Nudge_TSmode.eq.0) then
       ! DSE tendencies from Temperature only
       !---------------------------------------
       do lchnk=begchunk,endchunk
         ncol=phys_state(lchnk)%ncol
         Target_S(:ncol,:pver,lchnk)=cpair*Target_T(:ncol,:pver,lchnk)
       end do
     elseif(Nudge_TSmode.eq.1) then
       ! Caluculate DSE tendencies from Temperature, Water Vapor, and Surface Pressure
       !------------------------------------------------------------------------------
       do lchnk=begchunk,endchunk
         ncol=phys_state(lchnk)%ncol
         call calc_DryStaticEnergy(Target_T(:,:,lchnk), Target_Q(:,:,lchnk), &
                                 phys_state(lchnk)%phis, Target_PS(:,lchnk), &
                                                  Target_S(:,:,lchnk), ncol)
       end do
     endif
!PFCDIAG
!    if(.FALSE.) then
!      ! OPTIONALLY remove vertical mean from Target_S
!      !-----------------------------------------------
!      do lchnk=begchunk,endchunk
!        ncol=phys_state(lchnk)%ncol
!        do nn=1,ncol
!          Sbar=0._r8
!          do kk=1,pver
!            Sbar=Sbar+Target_S(nn,kk,lchnk)
!          end do
!          Sbar=Sbar/float(pver)
!          Target_S(nn,:,lchnk)=Target_S(nn,:,lchnk)-Sbar
!        end do
!      end do
!    elseif(.TRUE.) then
!      ! OPTIONALLY remove weighted vertical mean from Target_S
!      !-------------------------------------------------------
!      do lchnk=begchunk,endchunk
!        ncol=phys_state(lchnk)%ncol
!        do nn=1,ncol
!          Sbar=0._r8
!          Qbar=0._r8
!          Wsum=0._r8
!          do kk=1,pver
!            Sbar=Sbar+Target_S(nn,kk,lchnk)*(phys_state(lchnk)%pdel(nn,kk)/phys_state(lchnk)%pmid(nn,kk))
!            Qbar=Qbar+Target_Q(nn,kk,lchnk)*(phys_state(lchnk)%pdel(nn,kk)/phys_state(lchnk)%pmid(nn,kk))
!            Wsum=Wsum+(phys_state(lchnk)%pdel(nn,kk)/phys_state(lchnk)%pmid(nn,kk))
!          end do
!          Sbar=Sbar/Wsum
!          Qbar=Qbar/Wsum
!          Target_S(nn,:,lchnk)=Target_S(nn,:,lchnk)-Sbar
!          Target_Q(nn,:,lchnk)=Target_Q(nn,:,lchnk)-Qbar
!        end do
!      end do
!    endif
!PFCDIAG

   endif ! ((Before_End).and.(Update_Nudge)) then

   !----------------------------------------------------------------
   ! Toggle Nudging flag when the time interval is between 
   ! beginning and ending times, and all of the analyses files exist.
   !----------------------------------------------------------------
   if((After_Beg).and.(Before_End)) then
     if(    (Nudge_Force_Opt.eq.0).or.(Nudge_Force_Opt.eq.1)) then
       ! Verify that the NEXT analyses are available
       !---------------------------------------------
       Nudge_ON=Nudge_File_Present(Nudge_ObsInd(1))
     elseif((Nudge_Force_Opt.eq.2).or.(Nudge_Force_Opt.eq.3)) then
       ! Verify that the CURR analyses are available
       !---------------------------------------------
       Nudge_ON=Nudge_File_Present(Nudge_ObsInd(2))
     else
       ! Verify that the ALL analyses are available
       !---------------------------------------------
       Nudge_ON=.true.
       do nn=1,Nudge_NumObs
         if(.not.Nudge_File_Present(nn)) Nudge_ON=.false.
       end do
     endif
     if(.not.Nudge_ON) then
       if(masterproc) then
         write(iulog,*) 'NUDGING: WARNING - analyses file NOT FOUND. Switching '
         write(iulog,*) 'NUDGING:           nudging OFF to coast thru the gap. '
       endif
     endif
   else
     Nudge_ON=.false.
   endif

   !-------------------------------------------------------
   ! HERE Implement time dependence of Nudging Coefs HERE
   !-------------------------------------------------------


   !---------------------------------------------------
   ! If Data arrays have changed update stepping arrays
   !---------------------------------------------------
   if((Before_End).and.((Update_Nudge).or.(Update_Model))) then

     ! Set Tscale for the specified Forcing Option 
     !-----------------------------------------------
     if((Nudge_Force_Opt.eq.0).or.(Nudge_Force_Opt.eq.2).or. &
        (Nudge_Force_Opt.eq.4).or.(Nudge_Force_Opt.eq.6)     ) then
       Tscale=1._r8
     elseif(Nudge_Force_Opt.eq.3) then
       call ESMF_TimeSet(Date1,YY=Year,MM=Month,DD=Day,S=Sec)
       call ESMF_TimeSet(Date2,YY=Nudge_Curr_Year,MM=Nudge_Curr_Month, &
                               DD=Nudge_Curr_Day , S=Nudge_Curr_Sec    )
       DateDiff =Date1-Date2
       call ESMF_TimeIntervalGet(DateDiff,S=DeltaT,rc=rc)
       DeltaT=DeltaT+dtime
       Tscale=float(Nudge_Step)/float(DeltaT)
     elseif((Nudge_Force_Opt.eq.1).or.(Nudge_Force_Opt.eq.5).or. &
            (Nudge_Force_Opt.eq.7)                               ) then
       call ESMF_TimeSet(Date1,YY=Year,MM=Month,DD=Day,S=Sec)
       call ESMF_TimeSet(Date2,YY=Nudge_Next_Year,MM=Nudge_Next_Month, &
                               DD=Nudge_Next_Day , S=Nudge_Next_Sec    )
       DateDiff =Date2-Date1
       call ESMF_TimeIntervalGet(DateDiff,S=DeltaT,rc=rc)
       Tscale=float(Nudge_Step)/float(DeltaT)
     endif

     ! Update the nudging tendencies
     !--------------------------------
     do lchnk=begchunk,endchunk
       ncol=phys_state(lchnk)%ncol
       Nudge_Ustep(:ncol,:pver,lchnk)=(  Target_U(:ncol,:pver,lchnk)      &
                                         -Model_U(:ncol,:pver,lchnk))     &
                                      *Tscale*Nudge_Utau(:ncol,:pver,lchnk)
       Nudge_Vstep(:ncol,:pver,lchnk)=(  Target_V(:ncol,:pver,lchnk)      &
                                         -Model_V(:ncol,:pver,lchnk))     &
                                      *Tscale*Nudge_Vtau(:ncol,:pver,lchnk)
       Nudge_Sstep(:ncol,:pver,lchnk)=(  Target_S(:ncol,:pver,lchnk)      &
                                         -Model_S(:ncol,:pver,lchnk))     &
                                      *Tscale*Nudge_Stau(:ncol,:pver,lchnk)
       Nudge_Qstep(:ncol,:pver,lchnk)=(  Target_Q(:ncol,:pver,lchnk)      &
                                         -Model_Q(:ncol,:pver,lchnk))     &
                                      *Tscale*Nudge_Qtau(:ncol,:pver,lchnk)
       Nudge_PSstep(:ncol,     lchnk)=(  Target_PS(:ncol,lchnk)      &
                                         -Model_PS(:ncol,lchnk))     &
                                      *Tscale*Nudge_PStau(:ncol,lchnk)
     end do

     !******************
     ! DIAG
     !******************
!    if(masterproc) then
!      write(iulog,*) 'PFC: Target_T(1,:pver,begchunk)=',Target_T(1,:pver,begchunk)  
!      write(iulog,*) 'PFC:  Model_T(1,:pver,begchunk)=',Model_T(1,:pver,begchunk)
!      write(iulog,*) 'PFC: Target_S(1,:pver,begchunk)=',Target_S(1,:pver,begchunk)  
!      write(iulog,*) 'PFC:  Model_S(1,:pver,begchunk)=',Model_S(1,:pver,begchunk)
!      write(iulog,*) 'PFC:      Target_PS(1,begchunk)=',Target_PS(1,begchunk)  
!      write(iulog,*) 'PFC:       Model_PS(1,begchunk)=',Model_PS(1,begchunk)
!      write(iulog,*) 'PFC: Nudge_Sstep(1,:pver,begchunk)=',Nudge_Sstep(1,:pver,begchunk)
!      write(iulog,*) 'PFC: Nudge_Xstep arrays updated:'
!    endif
   endif ! ((Before_End).and.((Update_Nudge).or.(Update_Model))) then

!DIAG
!  if(masterproc) then
!    write(iulog,*) 'NUDGING: exiting nudging_timestep_init()'
!  endif
!DIAG

   ! End Routine
   !------------
   return
  end subroutine ! nudging_timestep_init
  !================================================================


  !================================================================
  subroutine nudging_timestep_tend(phys_state,phys_tend)
   ! 
   ! NUDGING_TIMESTEP_TEND: 
   !                If Nudging is ON, return the Nudging contributions 
   !                to forcing using the current contents of the Nudge 
   !                arrays. Send output to the cam history module as well.
   !===============================================================
   use physconst    ,only: cpair
   use physics_types,only: physics_state,physics_ptend,physics_ptend_init
   use constituents ,only: cnst_get_ind,pcnst
   use ppgrid       ,only: pver,pcols,begchunk,endchunk
   use cam_history  ,only: outfld

   ! Arguments
   !-------------
   type(physics_state), intent(in) :: phys_state
   type(physics_ptend), intent(out):: phys_tend

   ! Local values
   !--------------------
   integer indw,ncol,lchnk
   logical lq(pcnst)

!DIAG
!  if(masterproc) then
!    write(iulog,*) 'NUDGING: entering nudging_timestep_tend()'
!  endif
!DIAG
   call cnst_get_ind('Q',indw)
   lq(:)   =.false.
   lq(indw)=.true.
   call physics_ptend_init(phys_tend,phys_state%psetcols,'nudging',lu=.true.,lv=.true.,ls=.true.,lq=lq)

   if(Nudge_ON) then
     lchnk=phys_state%lchnk
     ncol =phys_state%ncol
     phys_tend%u(:ncol,:pver)     =Nudge_Ustep(:ncol,:pver,lchnk)
     phys_tend%v(:ncol,:pver)     =Nudge_Vstep(:ncol,:pver,lchnk)
     phys_tend%s(:ncol,:pver)     =Nudge_Sstep(:ncol,:pver,lchnk)
     phys_tend%q(:ncol,:pver,indw)=Nudge_Qstep(:ncol,:pver,lchnk)

     call outfld('Nudge_U',phys_tend%u          ,pcols,lchnk)
     call outfld('Nudge_V',phys_tend%v          ,pcols,lchnk)
     call outfld('Nudge_T',phys_tend%s          ,pcols,lchnk)
     call outfld('Nudge_Q',phys_tend%q(1,1,indw),pcols,lchnk)
   endif

!DIAG
!  if(masterproc) then
!    write(iulog,*) 'NUDGING: exiting nudging_timestep_tend()'
!  endif
!DIAG
   ! End Routine
   !------------
   return
  end subroutine ! nudging_timestep_tend
  !================================================================


  !================================================================
  subroutine nudging_update_analyses_se(anal_file)
   ! 
   ! NUDGING_UPDATE_ANALYSES_SE: 
   !                 Open the given analyses data file, read in 
   !                 U,V,T,Q, and PS values and then distribute
   !                 the values to all of the chunks.
   !===============================================================
   use ppgrid ,only: pver,begchunk
   use netcdf

   ! Arguments
   !-------------
   character(len=*),intent(in):: anal_file

   ! Local values
   !-------------
   integer lev
   integer ncol,plev,istat
   integer ncid,varid
   real(r8) Xanal(Nudge_ncol,Nudge_nlev)
   real(r8) PSanal(Nudge_ncol)
   real(r8) Lat_anal(Nudge_ncol)
   real(r8) Lon_anal(Nudge_ncol)
   integer  nn,Nindex

!DIAG
!  if(masterproc) then
!    write(iulog,*) 'NUDGING: entering nudging_update_analyses_se()'
!  endif
!DIAG
   ! Rotate Nudge_ObsInd() indices, then check the existence of the analyses 
   ! file; broadcast the updated indices and file status to all the other MPI nodes. 
   ! If the file is not there, then just return.
   !------------------------------------------------------------------------
   if(masterproc) then
     Nindex=Nudge_ObsInd(Nudge_NumObs)
     do nn=Nudge_NumObs,2,-1
       Nudge_ObsInd(nn)=Nudge_ObsInd(nn-1)
     end do
     Nudge_ObsInd(1)=Nindex
     inquire(FILE=trim(anal_file),EXIST=Nudge_File_Present(Nudge_ObsInd(1)))
     write(iulog,*)'NUDGING: Nudge_ObsInd=',Nudge_ObsInd
     write(iulog,*)'NUDGING: Nudge_File_Present=',Nudge_File_Present
   endif
#ifdef SPMD
   call mpibcast(Nudge_File_Present, Nudge_NumObs, mpilog, 0, mpicom)
   call mpibcast(Nudge_ObsInd      , Nudge_NumObs, mpiint, 0, mpicom)
#endif
   if(.not.Nudge_File_Present(Nudge_ObsInd(1))) return

   ! masterporc does all of the work here
   !-----------------------------------------
   if(masterproc) then
   
     ! Open the given file
     !-----------------------
     istat=nf90_open(trim(anal_file),NF90_NOWRITE,ncid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*)'NF90_OPEN: failed for file ',trim(anal_file)
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif

     ! Read in Dimensions
     !--------------------
     istat=nf90_inq_dimid(ncid,'ncol',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
     istat=nf90_inquire_dimension(ncid,varid,len=ncol)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif

     istat=nf90_inq_dimid(ncid,'lev',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
     istat=nf90_inquire_dimension(ncid,varid,len=plev)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif

     istat=nf90_inq_varid(ncid,'lon',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
     istat=nf90_get_var(ncid,varid,Lon_anal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif

     istat=nf90_inq_varid(ncid,'lat',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
     istat=nf90_get_var(ncid,varid,Lat_anal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif

     if((Nudge_ncol.ne.ncol).or.(plev.ne.pver)) then
      write(iulog,*) 'ERROR: nudging_update_analyses_se: ncol=',ncol,' Nudge_ncol=',Nudge_ncol
      write(iulog,*) 'ERROR: nudging_update_analyses_se: plev=',plev,' pver=',pver
      call endrun('nudging_update_analyses_se: analyses dimension mismatch')
     endif

     ! Read in and scatter data arrays
     !----------------------------------
     istat=nf90_inq_varid(ncid,'U',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_ncol,Xanal,    &
                               Nobs_U(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
     istat=nf90_inq_varid(ncid,'V',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_ncol,Xanal,    &
                               Nobs_V(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
     istat=nf90_inq_varid(ncid,'T',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_ncol,Xanal,    &
                               Nobs_T(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
     istat=nf90_inq_varid(ncid,'Q',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_ncol,Xanal,    &
                               Nobs_Q(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
    istat=nf90_inq_varid(ncid,'PS',varid)
    if(istat.ne.NF90_NOERR) then
      write(iulog,*) nf90_strerror(istat)
      call endrun ('UPDATE_ANALYSES_SE')
    endif
    istat=nf90_get_var(ncid,varid,PSanal)
    if(istat.ne.NF90_NOERR) then
      write(iulog,*) nf90_strerror(istat)
      call endrun ('UPDATE_ANALYSES_SE')
    endif

     ! Close the analyses file
     !-----------------------
     istat=nf90_close(ncid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_SE')
     endif
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,1,1,Nudge_ncol,PSanal,           &
                               Nobs_PS(1,begchunk,Nudge_ObsInd(1)))

!DIAG
!  if(masterproc) then
!    write(iulog,*) 'NUDGING: exiting nudging_update_analyses_se()'
!  endif
!DIAG
   ! End Routine
   !------------
   return
  end subroutine ! nudging_update_analyses_se
  !================================================================


  !================================================================
  subroutine nudging_update_analyses_eul(anal_file)
   ! 
   ! NUDGING_UPDATE_ANALYSES_EUL: 
   !                 Open the given analyses data file, read in 
   !                 U,V,T,Q, and PS values and then distribute
   !                 the values to all of the chunks.
   !===============================================================
   use ppgrid ,only: pver,begchunk
   use netcdf

   ! Arguments
   !-------------
   character(len=*),intent(in):: anal_file

   ! Local values
   !-------------
   integer lev
   integer nlon,nlat,plev,istat
   integer ncid,varid
   integer ilat,ilon,ilev
   real(r8) Xanal(Nudge_nlon,Nudge_nlat,Nudge_nlev)
   real(r8) PSanal(Nudge_nlon,Nudge_nlat)
   real(r8) Lat_anal(Nudge_nlat)
   real(r8) Lon_anal(Nudge_nlon)
   real(r8) Xtrans(Nudge_nlon,Nudge_nlev,Nudge_nlat)
   integer  nn,Nindex

   ! Rotate Nudge_ObsInd() indices, then check the existence of the analyses 
   ! file; broadcast the updated indices and file status to all the other MPI nodes. 
   ! If the file is not there, then just return.
   !------------------------------------------------------------------------
   if(masterproc) then
     Nindex=Nudge_ObsInd(Nudge_NumObs)
     do nn=Nudge_NumObs,2,-1
       Nudge_ObsInd(nn)=Nudge_ObsInd(nn-1)
     end do
     Nudge_ObsInd(1)=Nindex
     inquire(FILE=trim(anal_file),EXIST=Nudge_File_Present(Nudge_ObsInd(1)))
   endif
#ifdef SPMD
   call mpibcast(Nudge_File_Present, Nudge_NumObs, mpilog, 0, mpicom)
   call mpibcast(Nudge_ObsInd      , Nudge_NumObs, mpiint, 0, mpicom)
#endif
   if(.not.Nudge_File_Present(Nudge_ObsInd(1))) return

   ! masterporc does all of the work here
   !-----------------------------------------
   if(masterproc) then
   
     ! Open the given file
     !-----------------------
     istat=nf90_open(trim(anal_file),NF90_NOWRITE,ncid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*)'NF90_OPEN: failed for file ',trim(anal_file)
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif

     ! Read in Dimensions
     !--------------------
     istat=nf90_inq_dimid(ncid,'lon',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     istat=nf90_inquire_dimension(ncid,varid,len=nlon)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif

     istat=nf90_inq_dimid(ncid,'lat',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     istat=nf90_inquire_dimension(ncid,varid,len=nlat)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif

     istat=nf90_inq_dimid(ncid,'lev',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     istat=nf90_inquire_dimension(ncid,varid,len=plev)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif

     istat=nf90_inq_varid(ncid,'lon',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     istat=nf90_get_var(ncid,varid,Lon_anal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif

     istat=nf90_inq_varid(ncid,'lat',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     istat=nf90_get_var(ncid,varid,Lat_anal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif

     if((Nudge_nlon.ne.nlon).or.(Nudge_nlat.ne.nlat).or.(plev.ne.pver)) then
      write(iulog,*) 'ERROR: nudging_update_analyses_eul: nlon=',nlon,' Nudge_nlon=',Nudge_nlon
      write(iulog,*) 'ERROR: nudging_update_analyses_eul: nlat=',nlat,' Nudge_nlat=',Nudge_nlat
      write(iulog,*) 'ERROR: nudging_update_analyses_eul: plev=',plev,' pver=',pver
      call endrun('nudging_update_analyses_eul: analyses dimension mismatch')
     endif

     ! Read in, transpose lat/lev indices, 
     ! and scatter data arrays
     !----------------------------------
     istat=nf90_inq_varid(ncid,'U',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     do ilat=1,nlat
     do ilev=1,plev
     do ilon=1,nlon
       Xtrans(ilon,ilev,ilat)=Xanal(ilon,ilat,ilev)
     end do
     end do
     end do
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_nlon,Xtrans,   &
                               Nobs_U(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
     istat=nf90_inq_varid(ncid,'V',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     do ilat=1,nlat
     do ilev=1,plev
     do ilon=1,nlon
       Xtrans(ilon,ilev,ilat)=Xanal(ilon,ilat,ilev)
     end do
     end do
     end do
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_nlon,Xtrans,   &
                               Nobs_V(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
     istat=nf90_inq_varid(ncid,'T',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     do ilat=1,nlat
     do ilev=1,plev
     do ilon=1,nlon
       Xtrans(ilon,ilev,ilat)=Xanal(ilon,ilat,ilev)
     end do
     end do
     end do
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_nlon,Xtrans,   &
                               Nobs_T(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
     istat=nf90_inq_varid(ncid,'Q',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
     do ilat=1,nlat
     do ilev=1,plev
     do ilon=1,nlon
       Xtrans(ilon,ilev,ilat)=Xanal(ilon,ilat,ilev)
     end do
     end do
     end do
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_nlon,Xtrans,   &
                               Nobs_Q(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
    istat=nf90_inq_varid(ncid,'PS',varid)
    if(istat.ne.NF90_NOERR) then
      write(iulog,*) nf90_strerror(istat)
      call endrun ('UPDATE_ANALYSES_SE')
    endif
    istat=nf90_get_var(ncid,varid,PSanal)
    if(istat.ne.NF90_NOERR) then
      write(iulog,*) nf90_strerror(istat)
      call endrun ('UPDATE_ANALYSES_SE')
    endif

     ! Close the analyses file
     !-----------------------
     istat=nf90_close(ncid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,1,1,Nudge_nlon,PSanal,           &
                               Nobs_PS(1,begchunk,Nudge_ObsInd(1)))

   ! End Routine
   !------------
   return
  end subroutine ! nudging_update_analyses_eul
  !================================================================


  !================================================================
  subroutine nudging_update_analyses_fv(anal_file)
   ! 
   ! NUDGING_UPDATE_ANALYSES_FV: 
   !                 Open the given analyses data file, read in 
   !                 U,V,T,Q, and PS values and then distribute
   !                 the values to all of the chunks.
   !===============================================================
   use ppgrid ,only: pver,begchunk
   use netcdf

   ! Arguments
   !-------------
   character(len=*),intent(in):: anal_file

   ! Local values
   !-------------
   integer lev
   integer nlon,nlat,plev,istat
   integer ncid,varid
   integer ilat,ilon,ilev
   real(r8) Xanal(Nudge_nlon,Nudge_nlat,Nudge_nlev)
   real(r8) PSanal(Nudge_nlon,Nudge_nlat)
   real(r8) Lat_anal(Nudge_nlat)
   real(r8) Lon_anal(Nudge_nlon)
   real(r8) Xtrans(Nudge_nlon,Nudge_nlev,Nudge_nlat)
   integer  nn,Nindex

   ! Rotate Nudge_ObsInd() indices, then check the existence of the analyses 
   ! file; broadcast the updated indices and file status to all the other MPI nodes. 
   ! If the file is not there, then just return.
   !------------------------------------------------------------------------
   if(masterproc) then
     Nindex=Nudge_ObsInd(Nudge_NumObs)
     do nn=Nudge_NumObs,2,-1
       Nudge_ObsInd(nn)=Nudge_ObsInd(nn-1)
     end do
     Nudge_ObsInd(1)=Nindex
     inquire(FILE=trim(anal_file),EXIST=Nudge_File_Present(Nudge_ObsInd(1)))
   endif
#ifdef SPMD
   call mpibcast(Nudge_File_Present, Nudge_NumObs, mpilog, 0, mpicom)
   call mpibcast(Nudge_ObsInd      , Nudge_NumObs, mpiint, 0, mpicom)
#endif
   if(.not.Nudge_File_Present(Nudge_ObsInd(1))) return

   ! masterporc does all of the work here
   !-----------------------------------------
   if(masterproc) then
   
     ! Open the given file
     !-----------------------
     istat=nf90_open(trim(anal_file),NF90_NOWRITE,ncid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*)'NF90_OPEN: failed for file ',trim(anal_file)
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif

     ! Read in Dimensions
     !--------------------
     istat=nf90_inq_dimid(ncid,'lon',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     istat=nf90_inquire_dimension(ncid,varid,len=nlon)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif

     istat=nf90_inq_dimid(ncid,'lat',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     istat=nf90_inquire_dimension(ncid,varid,len=nlat)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif

     istat=nf90_inq_dimid(ncid,'lev',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     istat=nf90_inquire_dimension(ncid,varid,len=plev)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif

     istat=nf90_inq_varid(ncid,'lon',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     istat=nf90_get_var(ncid,varid,Lon_anal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif

     istat=nf90_inq_varid(ncid,'lat',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     istat=nf90_get_var(ncid,varid,Lat_anal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif

     if((Nudge_nlon.ne.nlon).or.(Nudge_nlat.ne.nlat).or.(plev.ne.pver)) then
      write(iulog,*) 'ERROR: nudging_update_analyses_fv: nlon=',nlon,' Nudge_nlon=',Nudge_nlon
      write(iulog,*) 'ERROR: nudging_update_analyses_fv: nlat=',nlat,' Nudge_nlat=',Nudge_nlat
      write(iulog,*) 'ERROR: nudging_update_analyses_fv: plev=',plev,' pver=',pver
      call endrun('nudging_update_analyses_fv: analyses dimension mismatch')
     endif

     ! Read in, transpose lat/lev indices, 
     ! and scatter data arrays
     !----------------------------------
     istat=nf90_inq_varid(ncid,'U',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     do ilat=1,nlat
     do ilev=1,plev
     do ilon=1,nlon
       Xtrans(ilon,ilev,ilat)=Xanal(ilon,ilat,ilev)
     end do
     end do
     end do
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_nlon,Xtrans,   &
                               Nobs_U(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
     istat=nf90_inq_varid(ncid,'V',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     do ilat=1,nlat
     do ilev=1,plev
     do ilon=1,nlon
       Xtrans(ilon,ilev,ilat)=Xanal(ilon,ilat,ilev)
     end do
     end do
     end do
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_nlon,Xtrans,   &
                               Nobs_V(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
     istat=nf90_inq_varid(ncid,'T',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     do ilat=1,nlat
     do ilev=1,plev
     do ilon=1,nlon
       Xtrans(ilon,ilev,ilat)=Xanal(ilon,ilat,ilev)
     end do
     end do
     end do
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_nlon,Xtrans,   &
                               Nobs_T(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
     istat=nf90_inq_varid(ncid,'Q',varid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     istat=nf90_get_var(ncid,varid,Xanal)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_FV')
     endif
     do ilat=1,nlat
     do ilev=1,plev
     do ilon=1,nlon
       Xtrans(ilon,ilev,ilat)=Xanal(ilon,ilat,ilev)
     end do
     end do
     end do
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,Nudge_nlev,1,Nudge_nlon,Xtrans,   &
                               Nobs_Q(1,1,begchunk,Nudge_ObsInd(1)))

   if(masterproc) then
    istat=nf90_inq_varid(ncid,'PS',varid)
    if(istat.ne.NF90_NOERR) then
      write(iulog,*) nf90_strerror(istat)
      call endrun ('UPDATE_ANALYSES_SE')
    endif
    istat=nf90_get_var(ncid,varid,PSanal)
    if(istat.ne.NF90_NOERR) then
      write(iulog,*) nf90_strerror(istat)
      call endrun ('UPDATE_ANALYSES_SE')
    endif

     ! Close the analyses file
     !-----------------------
     istat=nf90_close(ncid)
     if(istat.ne.NF90_NOERR) then
       write(iulog,*) nf90_strerror(istat)
       call endrun ('UPDATE_ANALYSES_EUL')
     endif
   endif ! (masterproc) then
   call scatter_field_to_chunk(1,1,1,Nudge_nlon,PSanal,           &
                               Nobs_PS(1,begchunk,Nudge_ObsInd(1)))

   ! End Routine
   !------------
   return
  end subroutine ! nudging_update_analyses_fv
  !================================================================


  !================================================================
  subroutine nudging_set_profile(rlat,rlon,Nudge_prof,Wprof,nlev)
   ! 
   ! NUDGING_SET_PROFILE: for the given lat,lon, and Nudging_prof, set
   !                      the verical profile of window coeffcients.
   !                      Values range from 0. to 1. to affect spatial
   !                      variations on nudging strength.
   !===============================================================

   ! Arguments
   !--------------
   integer  nlev,Nudge_prof
   real(r8) rlat,rlon
   real(r8) Wprof(nlev)

   ! Local values
   !----------------
   integer  ilev
   real(r8) Hcoef,latx,lonx,Vmax,Vmin
   real(r8) lon_lo,lon_hi,lat_lo,lat_hi,lev_lo,lev_hi

   !---------------
   ! set coeffcient
   !---------------
   if(Nudge_prof.eq.0) then
     ! No Nudging
     !-------------
     Wprof(:)=0.0
   elseif(Nudge_prof.eq.1) then
     ! Uniform Nudging
     !-----------------
     Wprof(:)=1.0
   elseif(Nudge_prof.eq.2) then
     ! Localized Nudging with specified Heaviside window function
     !------------------------------------------------------------
     if(Nudge_Hwin_max.le.Nudge_Hwin_min) then
       ! For a constant Horizontal window function, 
       ! just set Hcoef to the maximum of Hlo/Hhi.
       !--------------------------------------------
       Hcoef=max(Nudge_Hwin_lo,Nudge_Hwin_hi)
     else
       ! get lat/lon relative to window center
       !------------------------------------------
       latx=rlat-Nudge_Hwin_lat0
       lonx=rlon-Nudge_Hwin_lon0
       if(lonx.gt. 180.) lonx=lonx-360.
       if(lonx.le.-180.) lonx=lonx+360.

       ! Calcualte RAW window value
       !-------------------------------
       lon_lo=(Nudge_Hwin_lonWidthH+lonx)/Nudge_Hwin_lonDelta
       lon_hi=(Nudge_Hwin_lonWidthH-lonx)/Nudge_Hwin_lonDelta
       lat_lo=(Nudge_Hwin_latWidthH+latx)/Nudge_Hwin_latDelta
       lat_hi=(Nudge_Hwin_latWidthH-latx)/Nudge_Hwin_latDelta
       Hcoef=((1.+tanh(lon_lo))/2.)*((1.+tanh(lon_hi))/2.) &
            *((1.+tanh(lat_lo))/2.)*((1.+tanh(lat_hi))/2.)

       ! Scale the horizontal window coef for specfied range of values.
       !--------------------------------------------------------
       Hcoef=(Hcoef-Nudge_Hwin_min)/(Nudge_Hwin_max-Nudge_Hwin_min)
       Hcoef=(1.-Hcoef)*Nudge_Hwin_lo + Hcoef*Nudge_Hwin_hi
     endif

     ! Load the RAW vertical window
     !------------------------------
     do ilev=1,nlev
       lev_lo=(float(ilev)-Nudge_Vwin_Lindex)/Nudge_Vwin_Ldelta
       lev_hi=(Nudge_Vwin_Hindex-float(ilev))/Nudge_Vwin_Hdelta
       Wprof(ilev)=((1.+tanh(lev_lo))/2.)*((1.+tanh(lev_hi))/2.)
     end do 

     ! Scale the Window function to span the values between Vlo and Vhi:
     !-----------------------------------------------------------------
     Vmax=maxval(Wprof)
     Vmin=minval(Wprof)
     if(Vmax.le.Vmin) then
       ! For a constant Vertical window function, 
       ! load maximum of Vlo/Vhi into Wprof()
       !--------------------------------------------
       Vmax=max(Nudge_Vwin_lo,Nudge_Vwin_hi)
       Wprof(:)=Vmax
     else
       ! Scale the RAW vertical window for specfied range of values.
       !--------------------------------------------------------
       Wprof(:)=(Wprof(:)-Vmin)/(Vmax-Vmin)
       Wprof(:)=Nudge_Vwin_lo + Wprof(:)*(Nudge_Vwin_hi-Nudge_Vwin_lo)
     endif

     ! The desired result is the product of the vertical profile 
     ! and the horizontal window coeffcient.
     !----------------------------------------------------
     Wprof(:)=Hcoef*Wprof(:)
   else
     call endrun('nudging_set_profile:: Unknown Nudge_prof value')
   endif

   ! End Routine
   !------------
   return
  end subroutine ! nudging_set_profile
  !================================================================


  !================================================================
  real(r8) function nudging_set_PSprofile(rlat,rlon,Nudge_PSprof)
   ! 
   ! NUDGING_SET_PSPROFILE: for the given lat and lon set the surface
   !                      pressure profile value for the specified index.
   !                      Values range from 0. to 1. to affect spatial
   !                      variations on nudging strength.
   !===============================================================

   ! Arguments
   !--------------
   real(r8) rlat,rlon
   integer  Nudge_PSprof

   ! Local values
   !----------------

   !---------------
   ! set coeffcient
   !---------------
   if(Nudge_PSprof.eq.0) then
     ! No Nudging
     !-------------
     nudging_set_PSprofile=0.0
   elseif(Nudge_PSprof.eq.1) then
     ! Uniform Nudging
     !-----------------
     nudging_set_PSprofile=1.0
   else
     call endrun('nudging_set_PSprofile:: Unknown Nudge_prof value')
   endif

   ! End Routine
   !------------
   return
  end function ! nudging_set_PSprofile
  !================================================================


  !================================================================
  subroutine calc_DryStaticEnergy(t, q, phis, ps, dse, ncol)
   ! 
   ! calc_DryStaticEnergy: Given the temperature, specific humidity, surface pressure,
   !                       and surface geopotential for a chunk containing 'ncol' columns, 
   !                       calculate and return the corresponding dry static energy values.
   !--------------------------------------------------------------------------------------
   use shr_kind_mod, only: r8 => shr_kind_r8
   use ppgrid,       only: pver, pverp
   use dycore,       only: dycore_is
   use hycoef,       only: hyai, hybi, ps0, hyam, hybm
   use physconst,    only: zvir, gravit, cpair, rair
   !
   ! Input/Output arguments
   !-----------------------
   integer , intent(in) :: ncol      ! Number of columns in chunk
   real(r8), intent(in) :: t(:,:)    ! (pcols,pver) - temperature
   real(r8), intent(in) :: q(:,:)    ! (pcols,pver) - specific humidity
   real(r8), intent(in) :: ps(:)     ! (pcols)      - surface pressure 
   real(r8), intent(in) :: phis(:)   ! (pcols)      - surface geopotential
   real(r8), intent(out):: dse(:,:)  ! (pcols,pver)  - dry static energy
   !
   ! Local variables
   !------------------
   logical  :: fvdyn                 ! finite volume dynamics
   integer  :: ii,kk                 ! Lon, level, level indices
   real(r8) :: tvfac                 ! Virtual temperature factor
   real(r8) :: hkk(ncol)             ! diagonal element of hydrostatic matrix
   real(r8) :: hkl(ncol)             ! off-diagonal element
   real(r8) :: pint(ncol,pverp)      ! Interface pressures
   real(r8) :: pmid(ncol,pver )      ! Midpoint pressures
   real(r8) :: zi(ncol,pverp)        ! Height above surface at interfaces
   real(r8) :: zm(ncol,pver )        ! Geopotential height at mid level

   ! Set dynamics flag
   !-------------------
   fvdyn = dycore_is ('LR')

   ! Load Pressure values and midpoint pressures 
   !----------------------------------------------
   do kk=1,pverp
     do ii=1,ncol
       pint(ii,kk)=(hyai(kk)*ps0)+(hybi(kk)*ps(ii))
     end do
   end do
   do kk=1,pver
     do ii=1,ncol
       pmid(ii,kk)=(hyam(kk)*ps0)+(hybm(kk)*ps(ii))
     end do
   end do

   ! The surface height is zero by definition.
   !-------------------------------------------
   do ii = 1,ncol
     zi(ii,pverp) = 0.0_r8
   end do

   ! Compute the dry static energy, zi, zm from bottom up
   ! Note, zi(i,k) is the interface above zm(i,k)
   !---------------------------------------------------------
   do kk=pver,1,-1

     ! First set hydrostatic elements consistent with dynamics
     !--------------------------------------------------------
     if(fvdyn) then
       do ii=1,ncol
         hkl(ii)=log(pint(ii,kk+1))-log(pint(ii,kk))
         hkk(ii)=1._r8-(hkl(ii)*pint(ii,kk)/(pint(ii,kk+1)-pint(ii,kk)))
       end do
     else
       do ii=1,ncol
         hkl(ii)=(pint(ii,kk+1)-pint(ii,kk))/pmid(ii,kk)
         hkk(ii)=0.5_r8*hkl(ii)
       end do
     endif

     ! Now compute zm, zi, and dse  (WACCM-X vars rairv/zairv/cpairv not used!)
     !------------------------------------------------------------------------
     do ii=1,ncol
       tvfac=t(ii,kk)*rair*(1._r8+(zvir*q(ii,kk)))/gravit
       zm (ii,kk)=zi(ii,kk+1) + (tvfac*hkk(ii))
       zi (ii,kk)=zi(ii,kk+1) + (tvfac*hkl(ii))
       dse(ii,kk)=(t(ii,kk)*cpair) + phis(ii) + (gravit*zm(ii,kk))
     end do

   end do ! kk=pver,1,-1

   ! End Routine
   !-----------
   return
  end subroutine calc_DryStaticEnergy
  !================================================================

end module nudging
                                                                                                                                                                                ././@LongLink                                                                                       0000000 0000000 0000000 00000000170 00000000000 011563  L                                                                                                    ustar   root                            root                                                                                                                                                                                                                   chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.cam/runtime_opts.F90                                                                                                                                                                                                                                                                                                                                                                                                         chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.c0000644 0143640 0000777 00000123064 12571760540 030573  0                                                                                                    ustar   ychwang                         lccr                                                                                                                                                                                                                   module runtime_opts

!----------------------------------------------------------------------- 
! 
! Purpose: This module is responsible for reading CAM namelist cam_inparm 
!          and broadcasting namelist values if needed.  
! 
! Author:
!   Original routines:  CMS
!   Module:             T. Henderson, September 2003
!
!-----------------------------------------------------------------------

!-----------------------------------------------------------------------
!- use statements ------------------------------------------------------
!-----------------------------------------------------------------------
use shr_kind_mod,    only: r8 => shr_kind_r8, SHR_KIND_CL
use spmd_utils,      only: masterproc
use namelist_utils,  only: find_group_name
use pmgrid,          only: plat, plev, plon
use cam_instance,    only: inst_suffix
use cam_history
use cam_control_mod
use cam_diagnostics, only: inithist_all
use cam_logfile,     only: iulog
use pspect
use units
use constituents,    only: pcnst, readtrace
use tracers,         only: tracers_flag
use time_manager,    only: dtime
use filenames,       only: ncdata, bnd_topo, &
                           absems_data, &
                           caseid, &
                           brnch_retain_casename
use dycore,          only: dycore_is
use abortutils,      only: endrun
use rayleigh_friction, only: rayk0, raykrange, raytau0

!-----------------------------------------------------------------------
!- module boilerplate --------------------------------------------------
!-----------------------------------------------------------------------
implicit none
private
save


!-----------------------------------------------------------------------
! Public interfaces ----------------------------------------------------
!-----------------------------------------------------------------------
public read_namelist        ! Set and/or get all runtime options

!-----------------------------------------------------------------------
! Private data ---------------------------------------------------------
!-----------------------------------------------------------------------

character(len=SHR_KIND_CL), private :: nlfilename = 'atm_in' ! Namelist filename

!-----------------------------------------------------------------------
!
! SOMEWHAT ALPHABETICAL listing of variables in the cam_inparm namelist:
!
! variable                description
! --------             -----------------
!
! bnd_topo             Path and filename of topography dataset
! 
! absems_data          Dataset with absorption and emissivity factors.
!
! dtime = nnnn,        Model time step in seconds. Default is dycore dependent.
! 
! fincl1 = 'field1', 'field2',...
!                      List of fields to add to the primary history file.
! fincl1lonlat = 'longitude by latitude','longitude by latitude',...
!                      List of columns ('longitude_latitude') or contiguous 
!                      columns ('longitude:longitude_latitude:latitude') at 
!                      which the fincl1 fields will be output. Individual 
!                      columns are specified as a string using a longitude
!                      degree (greater or equal to 0.) followed by a single 
!                      character (e)ast/(w)est identifer, an
!                      underscore '_' , and a latitude degree followed by a 
!                      single character (n)orth/(s)outh identifier.
!                      example '10e_20n' would pick the model column closest
!                      to 10 degrees east longitude by 20 degrees north 
!                      latitude.  A group of contiguous columns can be 
!                      specified by using lon lat ranges with their single
!                      character east/west or north/south identifiers
!                      example '10e:20e_15n:20n'.  Would outfield all 
!                      fincl1 fields at the model columns which fall
!                      with in the longitude range from 10 east to 20 east
!                      and the latitude range from 15 north to 20 north
!
! fincl[2..6] = 'field1', 'field2',...
!                      List of fields to add to the auxiliary history file.
!
! fincl2..6]lonlat = 'longitude by latitude','longitude by latitude',...
!                      List of columns ('longitude_latitude') or contiguous 
!                      columns ('longitude:longitude_latitude:latitude') at 
!                      which the fincl[2..6] fields will be output. Individual 
!                      columns are specified as a string using a longitude
!                      degree (greater or equal to 0.) followed by a single 
!                      character (e)ast/(w)est identifer, an
!                      underscore '_' , and a latitude degree followed by a 
!                      singel character (n)orth/(s)outh identifier.
!                      example '10e_20n' would pick the model column closest
!                      to 10 degrees east longitude by 20 degrees north 
!                      latitude.  A group of contiguous columns can be 
!                      specified by using lon lat ranges with their single
!                      character east/west or north/south identifiers
!                      example '10e:20e_15n:20n'.  Would outfield all 
!                      fincl[2..6] fields at the model columns which fall
!                      with in the longitude range from 10 east to 20 east
!                      and the latitude range from 15 north to 20 north
!
! fexcl1 = 'field1','field2',... 
!                      List of field names to exclude from default
!                      primary history file (default fields on the 
!                      Master Field List).
! 
! fexcl[2..6] = 'field1','field2',... 
!                      List of field names to exclude from
!                      auxiliary history files.
! 
! lcltod_start = nn,nn,nn,...
!                      Array containing the starting time of day for local time history
!                      averaging. Used in conjuction with lcltod_stop. If lcltod_stop
!                      is less than lcltod_start, then the time range wraps around
!                      24 hours. The start time is included in the interval. Time is
!                      in seconds and defaults to 39600 (11:00 AM).
!                      The first value applies to the primary hist. file,
!                      the second to the first aux. hist. file, etc.
! 
! lcltod_stop = nn,nn,nn,...
!                      Array containing the stopping time of day for local time history
!                      averaging. Used in conjuction with lcltod_start. If lcltod_stop
!                      is less than lcltod_start, then the time range wraps around
!                      24 hours. The stop time is not included in the interval. Time is
!                      in seconds and defaults to 0 (midnight).
!                      The first value applies to the primary hist. file,
!                      the second to the first aux. hist. file, etc.
! 
! lcltod_start = nn,nn,nn,...
!                      Array containing the starting time of day for local time history
!                      averaging. Used in conjuction with lcltod_stop. If lcltod_stop
!                      is less than lcltod_start, then the time range wraps around
!                      24 hours. The start time is included in the interval. Time is
!                      in seconds and defaults to 39600 (11:00 AM).
!                      The first value applies to the primary hist. file,
!                      the second to the first aux. hist. file, etc.
! 
! lcltod_stop = nn,nn,nn,...
!                      Array containing the stopping time of day for local time history
!                      averaging. Used in conjuction with lcltod_start. If lcltod_stop
!                      is less than lcltod_start, then the time range wraps around
!                      24 hours. The stop time is not included in the interval. Time is
!                      in seconds and defaults to 0 (midnight).
!                      The first value applies to the primary hist. file,
!                      the second to the first aux. hist. file, etc.
! 
! mfilt = nn,nn,nn     Array containing the maximum number of time 
!                      samples per disk history file. Defaults to 5.
!                      The first value applies to the primary hist. file,
!                      the second to the first aux. hist. file, etc.
! 
! ncdata               Path and filename of initial condition dataset.
! 
! nhtfrq = nn,nn,nn,.. Output history frequency for each tape
!
!                      If = 0 : monthly average
!                      If > 0 : output every nhtfrq time steps.
!                      If < 0 : output every abs(nhtfrq) hours.
! 
! nlvdry = nn,         Number of layers over which to do dry
!                      adjustment. Defaults to 3.
! 
! cam_branch_file      Filepath of restart file to branch from (nsrest=3)
!                      Full pathname required.
character(len=256) :: cam_branch_file = ' '
!
! use_64bit_nc         True if new 64-bit netCDF formit, false otherwise (default false)
! 

!------------------------------------------------------------------
! The following 3 are specific to Rayleigh friction
! integer rayk0         vertical level at which rayleigh friction term is centered
! real(r8) raykrange    range of rayleigh friction profile; if 0, range is set automatically
! real(r8) raytau0      approximate value of decay time at model top (days);
!                       if 0., no rayleigh friction is applied
!------------------------------------------------------------------
!
!
! hfilename_spec       Flexible filename specifier for history files
!
! 
! pertlim = n.n        Max size of perturbation to apply to initial
!                      temperature field.
!
! phys_alltoall        Dynamics/physics transpose option. See phys_grid module.
!
integer :: phys_alltoall
! 
! phys_loadbalance     Load balance option for performance tuning of 
!                      physics chunks.  See phys_grid module.  
integer :: phys_loadbalance
! 
! phys_twin_algorithm  Load balance option for performance tuning of 
!                      physics chunks.  See phys_grid module.  
integer :: phys_twin_algorithm
! 
! phys_chnk_per_thd    Performance tuning option for physics chunks.  See 
!                      phys_grid module.  
integer :: phys_chnk_per_thd
! 
! tracers_flag = .F.    If true, implement tracer test code. Number of tracers determined
!                      in tracers_suite.F90 must agree with PCNST
!
! readtrace = .T.      If true, tracer initial conditions obtained from 
!                      initial file. 
!
! inithist             Generate initial dataset as auxillary history file
!                      can be set to '6-HOURLY', 'DAILY', 'MONTHLY', 'YEARLY' or 'NONE'. 
!                      default: 'YEARLY'
!
! empty_htapes         true => no fields by default on history tapes
!
! print_step_cost      true => print per timestep cost info
!
! avgflag_pertape      A, I, X, or M means avg, instantaneous, max or min for all fields on
!                      that tape
!
!
!   logical indirect     
!                    ! true => include indirect radiative effects of
!                    ! sulfate aerosols.  Default is false.
!
! inithist_all         .false.:  include only REQUIRED fields on IC file
!                      .true. :  include required AND optional fields on IC file
!                      default:  .false.
!
! met_data_file        name of file that contains the offline meteorology data
! met_data_path        name of directory that contains the offline meteorology data
!
! met_filenames_list   name of file that contains names of the offline 
!                      meteorology data files
!
! met_remove_file      true => the offline meteorology file will be removed
!
! met_cell_wall_winds  true => the offline meteorology winds are defined on the model
!                      grid cell walls
! Physics buffer
logical :: pbuf_global_allocate       ! allocate all buffers as global (default: .true.)


! Conservation checks

logical            :: print_energy_errors ! switch for diagnostic output from check_energy module

! Radiative heating rate calculation options

integer :: iradsw        ! freq. of shortwave radiation calc in time steps (positive)
                         ! or hours (negative).  Default: -1
integer :: iradlw        ! frequency of longwave rad. calc. in time steps (positive)
                         ! or hours (negative).  Default: -1
integer :: iradae        ! frequency of absorp/emis calc in time steps (positive)
                         ! or hours (negative).  Default: -12
integer :: irad_always   ! Specifies length of time in timesteps (positive)
                         ! or hours (negative) SW/LW radiation will be run continuously
                         ! from the start of an initial run.  Default: 0
logical :: spectralflux  ! calculate fluxes (up and down) per band. Default: FALSE

#if (defined WACCM_PHYS)
! iondrag / efield
character(len=256) :: efield_lflux_file
character(len=256) :: efield_hflux_file
character(len=256) :: efield_wei96_file
! waccm qbo data variables
character(len=256) :: qbo_forcing_file
logical            :: qbo_use_forcing
logical            :: qbo_cyclic
#endif

! Upper atmosphere radiative processes (waccm phys)
logical :: nlte_use_mo              ! Determines which constituents are used from NLTE calculations
                                    !  = .true. uses MOZART constituents
                                    !  = .false. uses constituents from bnd dataset cftgcm

! SCM Options
logical  :: single_column
real(r8) :: scmlat,scmlon
integer, parameter :: max_chars = 128
character(len=max_chars) iopfile
character(len=200) :: scm_clubb_iop_name
logical  :: scm_iop_srf_prop
logical  :: scm_relaxation
logical  :: scm_diurnal_avg
logical  :: scm_crm_mode

contains

!=======================================================================

  subroutine read_namelist(single_column_in, scmlon_in, scmlat_in, nlfilename_in )

   !----------------------------------------------------------------------- 
   ! 
   ! Purpose: 
   ! Read data from namelist cam_inparm to define the run. Process some of the
   ! namelist variables to determine history and restart/branch file path 
   ! names.  Check input namelist variables for validity and print them
   ! to standard output. 
   ! 
   ! Method: 
   ! Important Note for running on SUN systems: "implicit automatic (a-z)"
   ! will not work because namelist data must be static.
   !
   ! Author: 
   ! Original version:  CCM1
   ! Standardized:      L. Bath, June 1992
   !                    T. Acker, March 1996
   !     
   !-----------------------------------------------------------------------

   ! Note that the following interfaces are prototypes proposed by Henderson 
   ! and Eaton.  They minimize coupling with other modules.  Design of these 
   ! interfaces should be refined via review by other CAM developers.  
   ! Interface *_defaultopts() gets default values from the responsible 
   ! module (Expert) prior to namelist read.  
   ! Interface *_setopts() sends values to the responsible module (Expert) 
   ! after namelist read.  Erroneous values are handled by Experts.  
   ! TBH  9/8/03 
   !
   use phys_grid,        only: phys_grid_defaultopts, phys_grid_setopts
   
#if (defined WACCM_PHYS)
   use iondrag,          only: iondrag_defaultopts, iondrag_setopts
   use qbo,              only: qbo_defaultopts, qbo_setopts
   use waccm_forcing,    only: waccm_forcing_readnl
#endif

   use chem_surfvals,    only: chem_surfvals_readnl
   use check_energy,     only: check_energy_defaultopts, check_energy_setopts
   use radiation,        only: radiation_defaultopts, radiation_setopts, radiation_printopts
   use cam_restart,      only: restart_defaultopts, restart_setopts, restart_printopts
   use radheat,          only: radheat_defaultopts, radheat_setopts
   use carma_flags_mod,  only: carma_readnl
   use co2_cycle,        only: co2_cycle_readnl
   use shr_string_mod,   only: shr_string_toUpper
   use scamMod,          only: scam_setopts,scam_default_opts

   ! Some modules read their own namelist input.
   use spmd_utils,          only: spmd_utils_readnl
   use physconst,           only: physconst_readnl
   use phys_control,        only: phys_ctl_readnl
   use wv_saturation,       only: wv_sat_readnl
   use ref_pres,            only: ref_pres_readnl
   use cam3_aero_data,      only: cam3_aero_data_readnl
   use cam3_ozone_data,     only: cam3_ozone_data_readnl
   use macrop_driver,       only: macrop_driver_readnl
   use microp_driver,       only: microp_driver_readnl
   use microp_aero,         only: microp_aero_readnl
   use cloud_fraction,      only: cldfrc_readnl
   use cldwat,              only: cldwat_readnl
   use zm_conv,             only: zmconv_readnl
   use hk_conv,             only: hkconv_readnl
   use uwshcu,              only: uwshcu_readnl
   use pkg_cld_sediment,    only: cld_sediment_readnl
   use gw_drag,             only: gw_drag_readnl
   use phys_debug_util,     only: phys_debug_readnl
   use rad_constituents,    only: rad_cnst_readnl
   use radiation_data,      only: rad_data_readnl
   use modal_aer_opt,       only: modal_aer_opt_readnl
   use chemistry,           only: chem_readnl
   use prescribed_volcaero, only: prescribed_volcaero_readnl
   use aerodep_flx,         only: aerodep_flx_readnl
   use solar_data,          only: solar_data_readnl
   use tropopause,          only: tropopause_readnl
   use aoa_tracers,         only: aoa_tracers_readnl
   use prescribed_ozone,    only: prescribed_ozone_readnl
   use prescribed_aero,     only: prescribed_aero_readnl
   use prescribed_ghg,      only: prescribed_ghg_readnl
   use aircraft_emit,       only: aircraft_emit_readnl
   use cospsimulator_intr,  only: cospsimulator_intr_readnl
   use sat_hist,            only: sat_hist_readnl
   use vertical_diffusion,  only: vd_readnl
   use cam_history_support, only: fieldname_len, fieldname_lenp2
   use cam_diagnostics,     only: diag_readnl
   use nudging,             only: nudging_readnl
#if ( defined OFFLINE_DYN )
   use metdata,             only: metdata_readnl
#endif

!---------------------------Arguments-----------------------------------

   logical , intent(in), optional :: single_column_in 
   real(r8), intent(in), optional :: scmlon_in
   real(r8), intent(in), optional :: scmlat_in
   character(len=*)    , optional :: nlfilename_in
!-----------------------------------------------------------------------

   include 'netcdf.inc'

!---------------------------Local variables-----------------------------
   character(len=*), parameter ::  subname = "read_namelist"
! 
   character ctemp*8      ! Temporary character strings
   integer ntspdy         ! number of timesteps per day
   integer t              ! history tape index
   integer lastchar       ! index to last char of a char variable
   integer ierr           ! error code
   integer unitn          ! namelist unit number

   integer f, i
   integer, parameter :: max_chars = 128

   character(len=fieldname_lenp2) fincl1(pflds)
   character(len=fieldname_lenp2) fincl2(pflds)
   character(len=fieldname_lenp2) fincl3(pflds)
   character(len=fieldname_lenp2) fincl4(pflds)
   character(len=fieldname_lenp2) fincl5(pflds)
   character(len=fieldname_lenp2) fincl6(pflds)

   character(len=max_chars) fincl1lonlat(pflds)
   character(len=max_chars) fincl2lonlat(pflds)
   character(len=max_chars) fincl3lonlat(pflds)
   character(len=max_chars) fincl4lonlat(pflds)
   character(len=max_chars) fincl5lonlat(pflds)
   character(len=max_chars) fincl6lonlat(pflds)

   character(len=fieldname_len) fexcl1(pflds)
   character(len=fieldname_len) fexcl2(pflds)
   character(len=fieldname_len) fexcl3(pflds)
   character(len=fieldname_len) fexcl4(pflds)
   character(len=fieldname_len) fexcl5(pflds)
   character(len=fieldname_len) fexcl6(pflds)


   character(len=fieldname_lenp2) fwrtpr1(pflds)
   character(len=fieldname_lenp2) fwrtpr2(pflds)
   character(len=fieldname_lenp2) fwrtpr3(pflds)
   character(len=fieldname_lenp2) fwrtpr4(pflds)
   character(len=fieldname_lenp2) fwrtpr5(pflds)
   character(len=fieldname_lenp2) fwrtpr6(pflds)

!
! Define the cam_inparm namelist
! ***NOTE*** If a namelist option is not described in the CAM Users Guide,
!            it is not supported.  

  namelist /cam_inparm/ ncdata, bnd_topo, &
                    cam_branch_file  ,ndens   ,nhtfrq  , &
                    mfilt   ,absems_data, &
                    lcltod_start, lcltod_stop, &
                    fincl1  ,fincl2  ,fincl3  ,fincl4  ,fincl5  , &
                    fincl1lonlat,fincl2lonlat,fincl3lonlat, &
                    fincl4lonlat  ,fincl5lonlat  , fincl6lonlat , &
                    collect_column_output, &
                    fincl6  ,fexcl1  ,fexcl2  ,fexcl3  ,fexcl4  , &
                    fexcl5  ,fexcl6  ,hfilename_spec, &
                    fwrtpr1 ,fwrtpr2 ,fwrtpr3, fwrtpr4 ,fwrtpr5 ,fwrtpr6 , &
                    dtime, &
                    nlvdry,  &
                    pertlim ,&
                    readtrace, rayk0, raykrange, raytau0, &
                    tracers_flag, &
                    inithist, indirect, &
                    empty_htapes, use_64bit_nc, &
                    print_step_cost, avgflag_pertape, &
                    phys_alltoall, phys_loadbalance, phys_twin_algorithm, &
                    phys_chnk_per_thd, &
                    inithist_all

  ! physics buffer
  namelist /cam_inparm/ pbuf_global_allocate

  ! conservation checks
  namelist /cam_inparm/ print_energy_errors

  ! radiative heating calculation options
  namelist /cam_inparm/ iradsw, iradlw, iradae, irad_always, spectralflux

#if (defined WACCM_PHYS)
  ! iondrag / efield options
  namelist /cam_inparm/ efield_lflux_file, efield_hflux_file, efield_wei96_file
  ! waccm qbo namelist variables
  namelist /cam_inparm/ qbo_use_forcing, qbo_forcing_file, qbo_cyclic
#endif

  ! upper atmosphere radiative processes
  namelist /cam_inparm/ nlte_use_mo

  ! scam
  namelist /cam_inparm/ iopfile,scm_iop_srf_prop,scm_relaxation, &
                        scm_diurnal_avg,scm_crm_mode, scm_clubb_iop_name

! 
!-----------------------------------------------------------------------
  if (present(nlfilename_in)) then
     nlfilename = nlfilename_in
  end if
!
! Determine preset values (this is currently being phased out)
!
   call preset ()
!
! Preset sulfate aerosol related variables

   indirect  = .false.

   ! restart write interval
   call restart_defaultopts( &
      cam_branch_file_out          =cam_branch_file            )

   ! Get default values of runtime options for physics chunking.
   call phys_grid_defaultopts(                      &
      phys_loadbalance_out    =phys_loadbalance,    &
      phys_twin_algorithm_out =phys_twin_algorithm, &
      phys_alltoall_out       =phys_alltoall,       &
      phys_chnk_per_thd_out   =phys_chnk_per_thd    )

   ! conservation
   call check_energy_defaultopts( &
      print_energy_errors_out = print_energy_errors )

   ! radiative heating calcs
   call radiation_defaultopts( &
      iradsw_out      = iradsw,     &
      iradlw_out      = iradlw,     &
      iradae_out      = iradae,     &
      irad_always_out = irad_always, &
      spectralflux_out = spectralflux )

#if (defined WACCM_PHYS)
   ! iondrag / efield
   call iondrag_defaultopts( &
      efield_lflux_file_out =efield_lflux_file, &
      efield_hflux_file_out =efield_hflux_file, &
      efield_wei96_file_out =efield_wei96_file )
   ! qbo forcing
   call qbo_defaultopts( &
      qbo_use_forcing_out  = qbo_use_forcing, &
      qbo_forcing_file_out = qbo_forcing_file,&
      qbo_cyclic_out       = qbo_cyclic       )
#endif

   ! Upper atmosphere radiative processes
   call radheat_defaultopts( nlte_use_mo_out =nlte_use_mo )

   if (present(single_column_in)) then
      call scam_default_opts(scmlat_out=scmlat,scmlon_out=scmlon, &
        single_column_out=single_column, &
        scm_iop_srf_prop_out=scm_iop_srf_prop,&
        scm_relaxation_out=scm_relaxation, &
        scm_diurnal_avg_out=scm_diurnal_avg, &
        scm_crm_mode_out=scm_crm_mode, &
        scm_clubb_iop_name_out=scm_clubb_iop_name)
   end if

   do f = 1, pflds
      fincl1(f) = ' '         
      fincl2(f) = ' '         
      fincl3(f) = ' '         
      fincl4(f) = ' '         
      fincl5(f) = ' '         
      fincl6(f) = ' '         
      fincl1lonlat(f) = ' '
      fincl2lonlat(f) = ' '
      fincl3lonlat(f) = ' '
      fincl4lonlat(f) = ' '
      fincl5lonlat(f) = ' '
      fincl6lonlat(f) = ' '
      fexcl1(f) = ' '
      fexcl2(f) = ' '
      fexcl3(f) = ' '
      fexcl4(f) = ' '
      fexcl5(f) = ' '
      fexcl6(f) = ' '
      fwrtpr1(f) = ' '
      fwrtpr2(f) = ' '
      fwrtpr3(f) = ' '
      fwrtpr4(f) = ' '
      fwrtpr5(f) = ' '
      fwrtpr6(f) = ' '
   enddo

   ! Read in the cam_inparm namelist from input filename

   if (masterproc) then
      write(iulog,*) 'Read in cam_inparm namelist from: ', trim(nlfilename)
      unitn = getunit()
      open( unitn, file=trim(nlfilename), status='old' )

      ! Look for cam_inparm group name in the input file.  If found, leave the
      ! file positioned at that namelist group.
      call find_group_name(unitn, 'cam_inparm', status=ierr)
      if (ierr == 0) then  ! found cam_inparm
         read(unitn, cam_inparm, iostat=ierr)  ! read the cam_inparm namelist group
         if (ierr /= 0) then
            call endrun( subname//':: namelist read returns an'// &
                          ' error condition for cam_inparm' )
         end if
      else
         call endrun(subname // ':: can''t find cam_inparm in file ' // trim(nlfilename))
      end if
      close( unitn )
      call freeunit( unitn )
      !
      ! Check CASE namelist variable
      !
      if (caseid==' ') then
         call endrun ('READ_NAMELIST: Namelist variable CASEID must be set')
      end if

      lastchar = len(caseid)
      if (caseid(lastchar:lastchar) /= ' ') then
         write(iulog,*)'READ_NAMELIST: CASEID must not exceed ', len(caseid)-1, ' characters'
         call endrun
      end if

      do f=1, pflds
         fincl(f, 1) = fincl1(f)
         fincl(f, 2) = fincl2(f)
         fincl(f, 3) = fincl3(f)
         fincl(f, 4) = fincl4(f)
         fincl(f, 5) = fincl5(f)
         fincl(f, 6) = fincl6(f)
         
         fincllonlat(f, 1) = fincl1lonlat(f)
         fincllonlat(f, 2) = fincl2lonlat(f)
         fincllonlat(f, 3) = fincl3lonlat(f)
         fincllonlat(f, 4) = fincl4lonlat(f)
         fincllonlat(f, 5) = fincl5lonlat(f)
         fincllonlat(f, 6) = fincl6lonlat(f)
         if(dycore_is('UNSTRUCTURED') ) then
            do i=1,6
               if (fincllonlat(f,i) .ne. ' ') then
                  call endrun('READ_NAMELIST: Column output is not supported in Unstructered Grids')
               end if
            end do
         end if


         fexcl(f, 1) = fexcl1(f)
         fexcl(f, 2) = fexcl2(f)
         fexcl(f, 3) = fexcl3(f)
         fexcl(f, 4) = fexcl4(f)
         fexcl(f, 5) = fexcl5(f)
         fexcl(f, 6) = fexcl6(f)

         fwrtpr(f, 1) = fwrtpr1(f)
         fwrtpr(f, 2) = fwrtpr2(f)
         fwrtpr(f, 3) = fwrtpr3(f)
         fwrtpr(f, 4) = fwrtpr4(f)
         fwrtpr(f, 5) = fwrtpr5(f)
         fwrtpr(f, 6) = fwrtpr6(f)
      enddo
   end if
!
! Scatter namelist data to all processes
#if ( defined SPMD )
   call distnl ( )
#endif
!
! Auxiliary history files:
! Store input auxf values in array aux (from common block /comhst/).
!
! If generate an initial conditions history file as an auxillary tape:
!
   ctemp = shr_string_toUpper(inithist) 
   inithist = trim(ctemp)
   if (inithist /= '6-HOURLY' .and. inithist /= 'DAILY' .and. &
       inithist /= 'MONTHLY'  .and. inithist /= 'YEARLY' .and. &
       inithist /= 'CAMIOP'   .and. inithist /= 'ENDOFRUN') then
      inithist = 'NONE'
   endif
! 
! History file write up times
! Convert write freq. of hist files from hours to timesteps if necessary.
! 
   do t=1,ptapes
      if (nhtfrq(t) < 0) then
         nhtfrq(t) = nint((-nhtfrq(t)*3600._r8)/dtime)
      end if
   end do
!
! Initialize the filename specifier if not already set
! This is the format for the history filenames:
! %c= caseid, %t=tape no., %y=year, %m=month, %d=day, %s=second, %%=%
! See the filenames module for more information
!
   do t = 1, ptapes
      if ( len_trim(hfilename_spec(t)) == 0 )then
         if ( nhtfrq(t) == 0 )then
            hfilename_spec(t) = '%c.cam' // trim(inst_suffix) // '.h%t.%y-%m.nc'        ! Monthly files
         else
            hfilename_spec(t) = '%c.cam' // trim(inst_suffix) // '.h%t.%y-%m-%d-%s.nc'
         end if
      end if
!
! Only one time sample allowed per monthly average file
! 
      if (nhtfrq(t) == 0) mfilt(t) = 1
   end do

   ! Print per-tape averaging flags
   if (masterproc) then
      do t=1,ptapes
         if (avgflag_pertape(t) /= ' ') then
            write(iulog,*)'Unless overridden by namelist input on a per-field basis (FINCL),'
            write(iulog,*)'All fields on history file ',t,' will have averaging flag ',avgflag_pertape(t)
         end if
      end do
   end if

   ! restart write interval
   call restart_setopts( nsrest,            &
      cam_branch_file_in          =cam_branch_file            )


   ! Set runtime options for physics chunking.
   call phys_grid_setopts(                          &
       phys_loadbalance_in    =phys_loadbalance,    &
       phys_twin_algorithm_in =phys_twin_algorithm, &
       phys_alltoall_in       =phys_alltoall,       &
       phys_chnk_per_thd_in   =phys_chnk_per_thd    )

   ! conservation
   call check_energy_setopts( &
      print_energy_errors_in = print_energy_errors )

   call radiation_setopts( dtime, nhtfrq(1), &
      iradsw_in      = iradsw,     &
      iradlw_in      = iradlw,     &
      iradae_in      = iradae,     &
      irad_always_in = irad_always, &
      spectralflux_in = spectralflux )

#if (defined WACCM_PHYS)
   ! iondrag / efield
   call iondrag_setopts( &
        efield_lflux_file_in =efield_lflux_file, &
        efield_hflux_file_in =efield_hflux_file, &
        efield_wei96_file_in =efield_wei96_file)
   ! qbo forcing
   call qbo_setopts( &
        qbo_use_forcing_in  = qbo_use_forcing, &
        qbo_forcing_file_in = qbo_forcing_file,&
        qbo_cyclic_in       = qbo_cyclic       )
#endif

   ! Upper atmosphere radiative processes
   call radheat_setopts( nlte_use_mo_in =nlte_use_mo )
! 
! Set runtime options for single column mode
!
   if (present(single_column_in) .and. present(scmlon_in) .and. present(scmlat_in)) then 
      if (single_column_in) then
         single_column = single_column_in
         scmlon = scmlon_in
         scmlat = scmlat_in
         call scam_setopts( scmlat_in=scmlat,scmlon_in=scmlon, &
                            iopfile_in=iopfile,single_column_in=single_column,&
                            scm_iop_srf_prop_in=scm_iop_srf_prop,&
                            scm_relaxation_in=scm_relaxation, &
                            scm_diurnal_avg_in=scm_diurnal_avg, &
                            scm_crm_mode_in=scm_crm_mode, &
                            scm_clubb_iop_name_in=scm_clubb_iop_name)
      end if
   endif

   ! Call subroutines for modules to read their own namelist.
   ! In some cases namelist default values may depend on settings from
   ! other modules, so there may be an order dependence in the following
   ! calls.
   ! ***N.B.*** In particular, physconst_readnl should be called before
   !            the other readnl methods in case that method is used to set
   !            physical constants, some of which are set at runtime
   !            by the physconst_readnl method.
   ! Modules that read their own namelist are responsible for making sure
   ! all processes receive the values.

   call spmd_utils_readnl(nlfilename)
   call physconst_readnl(nlfilename)
   call chem_surfvals_readnl(nlfilename)
   call phys_ctl_readnl(nlfilename)
   call wv_sat_readnl(nlfilename)
   call ref_pres_readnl(nlfilename)
   call cam3_aero_data_readnl(nlfilename)
   call cam3_ozone_data_readnl(nlfilename)
   call macrop_driver_readnl(nlfilename)
   call microp_driver_readnl(nlfilename)
   call microp_aero_readnl(nlfilename)
   call cldfrc_readnl(nlfilename)
   call zmconv_readnl(nlfilename)
   call cldwat_readnl(nlfilename)
   call hkconv_readnl(nlfilename)
   call uwshcu_readnl(nlfilename)
   call cld_sediment_readnl(nlfilename)
   call gw_drag_readnl(nlfilename)
   call phys_debug_readnl(nlfilename)
   call rad_cnst_readnl(nlfilename)
   call rad_data_readnl(nlfilename)
   call modal_aer_opt_readnl(nlfilename)
   call chem_readnl(nlfilename)
   call prescribed_volcaero_readnl(nlfilename)
   call solar_data_readnl(nlfilename)
   call carma_readnl(nlfilename)
   call tropopause_readnl(nlfilename)
   call aoa_tracers_readnl(nlfilename)
   call aerodep_flx_readnl(nlfilename)
   call prescribed_ozone_readnl(nlfilename)
   call prescribed_aero_readnl(nlfilename)
   call prescribed_ghg_readnl(nlfilename)
   call co2_cycle_readnl(nlfilename)
   call aircraft_emit_readnl(nlfilename)
   call cospsimulator_intr_readnl(nlfilename)
   call sat_hist_readnl(nlfilename, hfilename_spec, mfilt, fincl, nhtfrq, avgflag_pertape)
   call diag_readnl(nlfilename)
   call nudging_readnl(nlfilename)
#if (defined WACCM_PHYS)
   call waccm_forcing_readnl(nlfilename)
#endif
   call vd_readnl(nlfilename)
#if ( defined OFFLINE_DYN )
   call metdata_readnl(nlfilename)
#endif

! 
! Print cam_inparm input variables to standard output
! 
   if (masterproc) then
      write(iulog,*)' ------------------------------------------'
      write(iulog,*)'     *** INPUT VARIABLES (CAM_INPARM) ***'
      write(iulog,*)' ------------------------------------------'
      if (nsrest/=0) then
         write(iulog,*) '  Continuation of an earlier run'
      else
         write(iulog,*) '         Initial run'
      end if
      write(iulog,*) ' ********** CASE = ',trim(caseid),' **********'
      write(iulog,'(1x,a)') ctitle
      if (len_trim(ncdata) > 0) then
         write(iulog,*) 'Initial dataset is: ',trim(ncdata)
      end if
      write(iulog,*)'Topography dataset is: ', trim(bnd_topo)
      write(iulog,*)'Time-invariant (absorption/emissivity) factor dataset is: ', trim(absems_data)

      ! Type of run
      write(iulog,*)'Run type flag (NSREST) 0=initial, 1=restart, 3=branch ',nsrest

      call restart_printopts()

   end if
!
! History file info 
!
   if (masterproc) then
      if (inithist == '6-HOURLY' ) then
         write(iulog,*)'Initial conditions history files will be written 6-hourly.'
      else if (inithist == 'DAILY' ) then
         write(iulog,*)'Initial conditions history files will be written daily.'
      else if (inithist == 'MONTHLY' ) then
         write(iulog,*)'Initial conditions history files will be written monthly.'
      else if (inithist == 'YEARLY' ) then
         write(iulog,*)'Initial conditions history files will be written yearly.'
      else if (inithist == 'CAMIOP' ) then
         write(iulog,*)'Initial conditions history files will be written for IOP.'
      else if (inithist == 'ENDOFRUN' ) then
         write(iulog,*)'Initial conditions history files will be written at end of run.'
      else
         write(iulog,*)'Initial conditions history files will not be created'
      end if

!
! Write physics variables from namelist cam_inparm to std. output
!
      write(iulog,9108) nlvdry
9108 format('Lowest level for dry adiabatic adjust (NLVDRY)',i10)


      call radiation_printopts()

      if ( (adiabatic .and. ideal_phys) .or. (adiabatic .and. aqua_planet) .or. &
           (ideal_phys .and. aqua_planet) ) then
         call endrun ('READ_NAMELIST: Only one of ADIABATIC, IDEAL_PHYS, or AQUA_PLANET can be .true.')
      end if

#ifdef COUP_SOM
      if (adiabatic .or. ideal_phys .or. aqua_planet )then
         call endrun ('READ_NAMELIST: adiabatic, ideal_phys or aqua_planet can not be used with SOM')
      end if
#else
      if (adiabatic)   write(iulog,*) 'Model will run ADIABATICALLY (i.e. no physics)'
      if (ideal_phys)  write(iulog,*) 'Run ONLY the "idealized" dynamical core of the ', &
                                  'model  (dynamics + Held&Suarez-specified physics)'
      if (aqua_planet) write(iulog,*) 'Run model in "AQUA_PLANET" mode'
#endif
   end if

   ! set public data in cam_control_mod
   moist_physics = (.not. adiabatic) .and. (.not. ideal_phys)

#ifdef PERGRO
   if (masterproc) then
      write(iulog,*)'pergro for cloud water is true'
   end if
#endif

   ntspdy = nint(86400._r8/dtime) ! no. timesteps per day


end subroutine read_namelist


!=======================================================================

#ifdef SPMD
subroutine distnl
!-----------------------------------------------------------------------
!     
! Purpose:     
! Distribute namelist data to all processors.
!
! The cpp SPMD definition provides for the funnelling of all program i/o
! through the master processor. Processor 0 either reads restart/history
! data from the disk and distributes it to all processors, or collects
! data from all processors and writes it to disk.
!     
!---------------------------Code history-------------------------------
!
! Original version:  CCM2
! Standardized:      J. Rosinski, Oct 1995
!                    J. Truesdale, Feb. 1996
!
!-----------------------------------------------------------------------
   use mpishorthand
!-----------------------------------------------------------------------

!
!-----------------------------------------------------------------------
! 
   call mpibcast (dtime,       1,mpiint,0,mpicom)
   call mpibcast (ndens   ,ptapes,mpiint,0,mpicom)
   call mpibcast (nhtfrq  ,ptapes,mpiint,0,mpicom)
   call mpibcast (mfilt   ,ptapes,mpiint,0,mpicom)
   call mpibcast (lcltod_start ,ptapes,mpiint,0,mpicom)
   call mpibcast (lcltod_stop  ,ptapes,mpiint,0,mpicom)
   call mpibcast (nsrest  ,1,mpiint,0,mpicom)
   call mpibcast (nlvdry  ,1,mpiint,0,mpicom)

   call mpibcast (rayk0    ,1,mpiint,0,mpicom)
   call mpibcast (raykrange,1,mpir8,0,mpicom)
   call mpibcast (raytau0  ,1,mpir8,0,mpicom)

   call mpibcast (collect_column_output,ptapes,mpilog,0,mpicom)

   call mpibcast (tracers_flag,1,mpilog,0,mpicom)
   call mpibcast (readtrace   ,1,mpilog,0,mpicom)
   call mpibcast (adiabatic   ,1,mpilog,0,mpicom)
   call mpibcast (ideal_phys  ,1,mpilog,0,mpicom)
   call mpibcast (aqua_planet ,1,mpilog,0,mpicom)

   call mpibcast (empty_htapes,1,mpilog,0,mpicom)
   call mpibcast (use_64bit_nc,1,mpilog,0,mpicom)
   call mpibcast (print_step_cost,1,mpilog,0,mpicom)
   call mpibcast (inithist_all   ,1,mpilog,0,mpicom)
   call mpibcast (pertlim     ,1, mpir8,  0, mpicom )

   call mpibcast (caseid  ,len(caseid) ,mpichar,0,mpicom)
   call mpibcast (avgflag_pertape, ptapes, mpichar,0,mpicom)
   call mpibcast (ctitle  ,len(ctitle),mpichar,0,mpicom)
   call mpibcast (ncdata  ,len(ncdata) ,mpichar,0,mpicom)
   call mpibcast (bnd_topo  ,len(bnd_topo) ,mpichar,0,mpicom)
   call mpibcast (absems_data,len(absems_data),mpichar,0,mpicom)
   call mpibcast (cam_branch_file  ,len(cam_branch_file) ,mpichar,0,mpicom)
   call mpibcast (inithist,len(inithist)  ,mpichar,0,mpicom)
   call mpibcast (hfilename_spec, len(hfilename_spec(1))*ptapes, mpichar, 0, mpicom)
   call mpibcast (fincl   ,len(fincl (1,1))*pflds*ptapes,mpichar,0,mpicom)
   call mpibcast (fexcl   ,len(fexcl (1,1))*pflds*ptapes,mpichar,0,mpicom)

   call mpibcast (fincllonlat   ,len(fincllonlat (1,1))*pflds*ptapes,mpichar,0,mpicom)

   call mpibcast (fwrtpr  ,len(fwrtpr(1,1))*pflds*ptapes,mpichar,0,mpicom)

   call mpibcast (indirect     , 1 ,mpilog, 0,mpicom)

   ! Physics chunk tuning
   call mpibcast (phys_loadbalance   ,1,mpiint,0,mpicom)
   call mpibcast (phys_twin_algorithm,1,mpiint,0,mpicom)
   call mpibcast (phys_alltoall      ,1,mpiint,0,mpicom)
   call mpibcast (phys_chnk_per_thd  ,1,mpiint,0,mpicom)

   ! Physics buffer
   call mpibcast (pbuf_global_allocate, 1, mpilog, 0, mpicom)

   ! Conservation
   call mpibcast (print_energy_errors, 1, mpilog, 0, mpicom)

   ! Radiative heating calculation
   call mpibcast (iradsw,     1, mpiint, 0, mpicom)
   call mpibcast (iradlw,     1, mpiint, 0, mpicom)
   call mpibcast (iradae,     1, mpiint, 0, mpicom)
   call mpibcast (irad_always,1, mpiint, 0, mpicom)
   call mpibcast (spectralflux,1, mpilog, 0, mpicom)

#if (defined WACCM_PHYS)
   ! iondrag / efield options
   call mpibcast (efield_lflux_file, len(efield_lflux_file), mpichar, 0, mpicom)
   call mpibcast (efield_hflux_file, len(efield_hflux_file), mpichar, 0, mpicom)
   call mpibcast (efield_wei96_file, len(efield_wei96_file), mpichar, 0, mpicom)
   ! qbo variables
   call mpibcast (qbo_forcing_file,  len(qbo_forcing_file ), mpichar, 0, mpicom)
   call mpibcast (qbo_use_forcing,   1,                      mpilog,  0, mpicom)
   call mpibcast (qbo_cyclic,        1,                      mpilog,  0, mpicom)
#endif

   call mpibcast (nlte_use_mo,            1,  mpilog, 0, mpicom)

end subroutine distnl
#endif



subroutine preset
!----------------------------------------------------------------------- 
! 
! Purpose: Preset namelist CAM_INPARM input variables and initialize some other variables
! 
! Method: Hardwire the values
! 
! Author: CCM Core Group
! 
!-----------------------------------------------------------------------
   use cam_history,  only: fincl, fexcl, fwrtpr, fincllonlat, collect_column_output
   use rgrid
!-----------------------------------------------------------------------
   include 'netcdf.inc'
!-----------------------------------------------------------------------
!
! Preset character history variables here because module initialization of character arrays
! does not work on all machines
! $$$ TBH:  is this still true?  12/14/03
!
   fincl(:,:)  = ' '
   fincllonlat(:,:)  = ' '
   fexcl(:,:)  = ' '
   fwrtpr(:,:) = ' '
!
! Flags
!
   print_step_cost = .false.   ! print per timestep cost info
   collect_column_output = .false.
!
! rgrid: set default to full grid
!
   nlon(:) = plon
!!
!! Unit numbers: set to invalid
!!
!   ncid_ini = -1
!   ncid_sst = -1
!   ncid_trc = -1
!
   return
end subroutine preset

end module runtime_opts
                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ././@LongLink                                                                                       0000000 0000000 0000000 00000000163 00000000000 011565  L                                                                                                    ustar   root                            root                                                                                                                                                                                                                   chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.cam/physpkg.F90                                                                                                                                                                                                                                                                                                                                                                                                              chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.c0000644 0143640 0000777 00000255065 12571760540 030602  0                                                                                                    ustar   ychwang                         lccr                                                                                                                                                                                                                   module physpkg
  !-----------------------------------------------------------------------
  ! Purpose:
  !
  ! Provides the interface to CAM physics package
  !
  ! Revision history:
  ! Aug  2005,  E. B. Kluzek,  Creation of module from physpkg subroutine
  ! 2005-10-17  B. Eaton       Add contents of inti.F90 to phys_init().  Add
  !                            initialization of grid info in phys_state.
  ! Nov 2010    A. Gettelman   Put micro/macro physics into separate routines
  ! Oct 2014    Yi-Chi Wang    revise this scheme to put a flag (ideep) as
  !                            communication for deep and shallow scheme.
  !                            After CAM5.2, this file combines previous tphysbc.
  ! Jun 2015    Yi-Chi Wang    Modify the physpkg with nudging code v1.0 from Patrick of NCAR.
  !-----------------------------------------------------------------------

  use shr_kind_mod,     only: r8 => shr_kind_r8
  use spmd_utils,       only: masterproc
  use physconst,        only: latvap, latice, rh2o
  use physics_types,    only: physics_state, physics_tend, physics_state_set_grid, &
       physics_ptend, physics_tend_init, physics_update,    &
       physics_type_alloc, physics_ptend_dealloc
  use phys_grid,        only: get_ncols_p
  use phys_gmean,       only: gmean_mass
  use ppgrid,           only: begchunk, endchunk, pcols, pver, pverp
  use constituents,     only: pcnst, cnst_name, cnst_get_ind
  use camsrfexch,       only: cam_out_t, cam_in_t

  use cam_control_mod,  only: ideal_phys, adiabatic
  use phys_control,     only: phys_do_flux_avg, waccmx_is
  use scamMod,          only: single_column, scm_crm_mode
  use flux_avg,         only: flux_avg_init
  use infnan,           only: posinf, assignment(=)
#ifdef SPMD
  use mpishorthand
#endif
  use perf_mod
  use cam_logfile,     only: iulog
  use camsrfexch,      only: cam_export
  use phys_control,    only: do_waccm_phys

  implicit none
  private

  !  Physics buffer index
  integer ::  teout_idx          = 0  

  integer ::  tini_idx           = 0 
  integer ::  qini_idx           = 0 
  integer ::  cldliqini_idx      = 0 
  integer ::  cldiceini_idx      = 0 

  integer ::  prec_str_idx       = 0
  integer ::  snow_str_idx       = 0
  integer ::  prec_sed_idx       = 0
  integer ::  snow_sed_idx       = 0
  integer ::  prec_pcw_idx       = 0
  integer ::  snow_pcw_idx       = 0
  integer ::  prec_dp_idx        = 0
  integer ::  snow_dp_idx        = 0
  integer ::  prec_sh_idx        = 0
  integer ::  snow_sh_idx        = 0


  save

  ! Public methods
  public phys_register ! was initindx  - register physics methods
  public phys_init   ! Public initialization method
  public phys_run1   ! First phase of the public run method
  public phys_run2   ! Second phase of the public run method
  public phys_final  ! Public finalization method
  !
  ! Private module data
  !

  !======================================================================= 
contains


subroutine phys_register
    !----------------------------------------------------------------------- 
    ! 
    ! Purpose: Register constituents and physics buffer fields.
    ! 
    ! Author:    CSM Contact: M. Vertenstein, Aug. 1997
    !            B.A. Boville, Oct 2001
    !            A. Gettelman, Nov 2010 - put micro/macro physics into separate routines
    ! 
    !-----------------------------------------------------------------------
    use physics_buffer, only: pbuf_init_time
    use shr_kind_mod,       only: r8 => shr_kind_r8
    use spmd_utils,         only: masterproc
    use constituents,       only: pcnst, cnst_add, cnst_chk_dim, cnst_name

    use cam_control_mod,    only: moist_physics
    use phys_control,       only: phys_do_flux_avg, phys_getopts, waccmx_is
    use chemistry,          only: chem_register
    use cloud_fraction,     only: cldfrc_register
    use stratiform,         only: stratiform_register
    use microp_driver,      only: microp_driver_register
    use microp_aero,        only: microp_aero_register
    use macrop_driver,      only: macrop_driver_register
    use clubb_intr,         only: clubb_register_cam
    use conv_water,         only: conv_water_register
    use physconst,          only: mwdry, cpair, mwh2o, cpwv
    use tracers,            only: tracers_register
    use check_energy,       only: check_energy_register
    use aerosol_intr,       only: aerosol_register_cnst
    use carma_intr,         only: carma_register
    use cam3_aero_data,     only: cam3_aero_data_on, cam3_aero_data_register
    use cam3_ozone_data,    only: cam3_ozone_data_on, cam3_ozone_data_register
    use ghg_data,           only: ghg_data_register
    use vertical_diffusion, only: vd_register
    use convect_deep,       only: convect_deep_register
    use convect_shallow,    only: convect_shallow_register
    use radiation,          only: radiation_register
    use co2_cycle,          only: co2_register
    use flux_avg,           only: flux_avg_register
    use exbdrift,           only: exbdrift_register
    use gw_drag,            only: gw_drag_register
    use iondrag,            only: iondrag_register
    use ionosphere,         only: ionos_register
    use string_utils,       only: to_lower
    use prescribed_ozone,   only: prescribed_ozone_register
    use prescribed_volcaero,only: prescribed_volcaero_register
    use prescribed_aero,    only: prescribed_aero_register
    use prescribed_ghg,     only: prescribed_ghg_register
    use sslt_rebin,         only: sslt_rebin_register
    use aoa_tracers,        only: aoa_tracers_register
    use aircraft_emit,      only: aircraft_emit_register
    use cam_diagnostics,    only: diag_register
    use cloud_diagnostics,  only: cloud_diagnostics_register
    use physics_buffer,     only: pbuf_add_field, dtype_r8

    implicit none
    !---------------------------Local variables-----------------------------
    !
    integer  :: m        ! loop index
    integer  :: mm       ! constituent index 
    !-----------------------------------------------------------------------

    character(len=16) :: microp_scheme
    logical           :: do_clubb_sgs

    call phys_getopts( microp_scheme_out = microp_scheme )
    call phys_getopts( do_clubb_sgs_out  = do_clubb_sgs )

    ! Initialize pbuf_times
    call pbuf_init_time()

    ! Register water vapor.
    ! ***** N.B. ***** This must be the first call to cnst_add so that
    !                  water vapor is constituent 1.
    if (moist_physics) then
       call cnst_add('Q', mwh2o, cpwv, 1.E-12_r8, mm, &
            longname='Specific humidity', readiv=.true., is_convtran1=.true.)
    else
       call cnst_add('Q', mwh2o, cpwv, 0.0_r8, mm, &
            longname='Specific humidity', readiv=.false., is_convtran1=.true.)
    end if

    ! Fields for physics package diagnostics
    call pbuf_add_field('TINI',      'physpkg', dtype_r8, (/pcols,pver/), tini_idx)
    call pbuf_add_field('QINI',      'physpkg', dtype_r8, (/pcols,pver/), qini_idx)
    call pbuf_add_field('CLDLIQINI', 'physpkg', dtype_r8, (/pcols,pver/), cldliqini_idx)
    call pbuf_add_field('CLDICEINI', 'physpkg', dtype_r8, (/pcols,pver/), cldiceini_idx)

    ! check energy package
    call check_energy_register

    ! If using an ideal/adiabatic physics option, the CAM physics parameterizations 
    ! aren't called.
    if (moist_physics) then

       ! register fluxes for saving across time
       if (phys_do_flux_avg()) call flux_avg_register()

       call cldfrc_register()

       ! cloud water
       if( microp_scheme == 'RK' ) then
          call stratiform_register()
       elseif( microp_scheme == 'MG' ) then
          if (.not. do_clubb_sgs) call macrop_driver_register()
          call microp_aero_register()
          call microp_driver_register()
       end if
       
       ! Register CLUBB_SGS here
       if (do_clubb_sgs) call clubb_register_cam()
       

       call pbuf_add_field('PREC_STR',  'physpkg',dtype_r8,(/pcols/),prec_str_idx)
       call pbuf_add_field('SNOW_STR',  'physpkg',dtype_r8,(/pcols/),snow_str_idx)
       call pbuf_add_field('PREC_PCW',  'physpkg',dtype_r8,(/pcols/),prec_pcw_idx)
       call pbuf_add_field('SNOW_PCW',  'physpkg',dtype_r8,(/pcols/),snow_pcw_idx)
       call pbuf_add_field('PREC_SED',  'physpkg',dtype_r8,(/pcols/),prec_sed_idx)
       call pbuf_add_field('SNOW_SED',  'physpkg',dtype_r8,(/pcols/),snow_sed_idx)

       call conv_water_register()

       ! chemical constituents
       call chem_register()

       ! co2 constituents
       call co2_register()

       ! register data model ozone with pbuf
       if (cam3_ozone_data_on) then
          call cam3_ozone_data_register()
       end if
       call prescribed_volcaero_register()
       call prescribed_ozone_register()
       call prescribed_aero_register()
       call prescribed_ghg_register()
       call sslt_rebin_register

       ! CAM3 prescribed aerosols
       if (cam3_aero_data_on) then
          call cam3_aero_data_register()
       end if

       ! register various data model gasses with pbuf
       call ghg_data_register()

       ! Initialize e and b fields
       if (do_waccm_phys()) call exbdrift_register()

       ! waccm gravity wave drag
       call gw_drag_register()

       ! carma microphysics
       ! 
       ! NOTE: Needs to come before aerosol_register_cnst, so that the CARMA
       ! flags are defined by then.
       call carma_register()

       if ( waccmx_is('ionosphere') .or. waccmx_is('neutral') ) then
          ! Register iondrag variables with pbuf
          call iondrag_register()
          ! Register ionosphere variables with pbuf if mode set to ionosphere
          if( waccmx_is('ionosphere') ) then
             call ionos_register()
          endif
       endif

       ! aerosols
       call aerosol_register_cnst()

       call aircraft_emit_register()

       ! deep convection
       call convect_deep_register

       !  shallow convection
       call convect_shallow_register

       ! radiation
       call radiation_register
       call cloud_diagnostics_register

       ! vertical diffusion
       if (.not. do_clubb_sgs) call vd_register()
    end if

    ! Register diagnostics PBUF
    call diag_register()

    ! Register age of air tracers
    call aoa_tracers_register()

    ! Register test tracers
    ! ***** N.B. ***** This is the last call to register constituents because
    !                  the test tracers fill the remaining available slots up
    !                  to constituent number PCNST -- regardless of what PCNST is set to.
    call tracers_register()

    ! All tracers registered, check that the dimensions are correct
    call cnst_chk_dim()

    ! ***NOTE*** No registering constituents after the call to cnst_chk_dim.

end subroutine phys_register



  !======================================================================= 

subroutine phys_inidat( cam_out, pbuf2d )
    use abortutils, only : endrun

    use physics_buffer, only : pbuf_get_index, pbuf_get_field, physics_buffer_desc, pbuf_set_field, pbuf_times


    use cam_initfiles,       only: initial_file_get_id, topo_file_get_id
    use pio,                 only: file_desc_t
    use ncdio_atm,           only: infld
    use dycore,              only: dycore_is
    use polar_avg,           only: polar_average
    use short_lived_species, only: initialize_short_lived_species
    use comsrf,              only: landm, sgh, sgh30
    use cam_control_mod,     only: aqua_planet

    type(cam_out_t),     intent(inout) :: cam_out(begchunk:endchunk)
    type(physics_buffer_desc), pointer :: pbuf2d(:,:)
    integer :: lchnk, m, n, i, k, ncol
    type(file_desc_t), pointer :: fh_ini, fh_topo
    character(len=8) :: fieldname
    real(r8), pointer :: cldptr(:,:,:,:), convptr_3d(:,:,:,:)
    real(r8), pointer :: tptr(:,:), tptr3d(:,:,:), tptr3d_2(:,:,:)
    real(r8), pointer :: qpert(:,:)

    character*11 :: subname='phys_inidat' ! subroutine name
    integer :: tpert_idx, qpert_idx, pblh_idx

    logical :: found=.false., found2=.false.
    integer :: ierr
    character(len=4) :: dim1name
    integer :: ixcldice, ixcldliq
    nullify(tptr,tptr3d,tptr3d_2,cldptr,convptr_3d)

    fh_ini=>initial_file_get_id()

    !   dynamics variables are handled in dyn_init - here we read variables needed for physics 
    !   but not dynamics

    if(dycore_is('UNSTRUCTURED')) then  
       dim1name='ncol'
    else
       dim1name='lon'
    end if
    if(aqua_planet) then
       sgh = 0._r8
       sgh30 = 0._r8
       landm = 0._r8
    else
       fh_topo=>topo_file_get_id()
       call infld('SGH', fh_topo, dim1name, 'lat', 1, pcols, begchunk, endchunk, &
            sgh, found, grid_map='PHYS')
       if(.not. found) call endrun('ERROR: SGH not found on topo file')

       call infld('SGH30', fh_topo, dim1name, 'lat', 1, pcols, begchunk, endchunk, &
            sgh30, found, grid_map='PHYS')
       if(.not. found) then
          if (masterproc) write(iulog,*) 'Warning: Error reading SGH30 from topo file.'
          if (masterproc) write(iulog,*) 'The field SGH30 will be filled using data from SGH.'
          sgh30 = sgh
       end if

       call infld('LANDM_COSLAT', fh_topo, dim1name, 'lat', 1, pcols, begchunk, endchunk, &
            landm, found, grid_map='PHYS')

       if(.not.found) call endrun(' ERROR: LANDM_COSLAT not found on topo dataset.')
    end if

    allocate(tptr(1:pcols,begchunk:endchunk))

    call infld('PBLH', fh_ini, dim1name, 'lat', 1, pcols, begchunk, endchunk, &
         tptr(:,:), found, grid_map='PHYS')
    if(.not. found) then
       tptr(:,:) = 0._r8
       if (masterproc) write(iulog,*) 'PBLH initialized to 0.'
    end if
    pblh_idx = pbuf_get_index('pblh')

    call pbuf_set_field(pbuf2d, pblh_idx, tptr)

    call infld('TPERT', fh_ini, dim1name, 'lat', 1, pcols, begchunk, endchunk, &
         tptr(:,:), found, grid_map='PHYS')
    if(.not. found) then
       tptr(:,:) = 0._r8
       if (masterproc) write(iulog,*) 'TPERT initialized to 0.'
    end if
    tpert_idx = pbuf_get_index( 'tpert')
    call pbuf_set_field(pbuf2d, tpert_idx, tptr)

    fieldname='QPERT'  
    qpert_idx = pbuf_get_index( 'qpert',ierr)
    if (qpert_idx > 0) then
       call infld(fieldname, fh_ini, dim1name, 'lat', 1, pcols, begchunk, endchunk, &
            tptr, found, grid_map='PHYS')
       if(.not. found) then
          tptr=0_r8
          if (masterproc) write(iulog,*) trim(fieldname), ' initialized to 0.'
       end if

       allocate(tptr3d_2(pcols,pcnst,begchunk:endchunk))
       tptr3d_2 = 0_r8
       tptr3d_2(:,1,:) = tptr(:,:)

       call pbuf_set_field(pbuf2d, qpert_idx, tptr3d_2)
       deallocate(tptr3d_2)
    end if

    fieldname='CUSH'
    m = pbuf_get_index('cush')
    call infld(fieldname, fh_ini, dim1name, 'lat', 1, pcols, begchunk, endchunk, &
         tptr, found, grid_map='PHYS')
    if(.not.found) then
       if(masterproc) write(iulog,*) trim(fieldname), ' initialized to 1000.'
       tptr=1000._r8
    end if
    do n=1,pbuf_times
       call pbuf_set_field(pbuf2d, m, tptr, start=(/1,n/), kount=(/pcols,1/))
    end do
    deallocate(tptr)

    do lchnk=begchunk,endchunk
       cam_out(lchnk)%tbot(:) = posinf
    end do

    !
    ! 3-D fields
    !

    allocate(tptr3d(pcols,pver,begchunk:endchunk))

    fieldname='CLOUD'
    m = pbuf_get_index('CLD')
    call infld(fieldname, fh_ini, dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
         tptr3d, found, grid_map='PHYS')
    if(found) then
       do n = 1, pbuf_times
          call pbuf_set_field(pbuf2d, m, tptr3d, (/1,1,n/),(/pcols,pver,1/))
       end do
    else
       call pbuf_set_field(pbuf2d, m, 0._r8)
       if (masterproc) write(iulog,*) trim(fieldname), ' initialized to 0.'
    end if

    fieldname='QCWAT'
    m = pbuf_get_index(fieldname,ierr)
    if (m > 0) then
       call infld(fieldname, fh_ini, dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
            tptr3d, found, grid_map='PHYS')
       if(.not. found) then
          call infld('Q',fh_ini,dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
               tptr3d, found, grid_map='PHYS')
          if (found) then
             if (masterproc) write(iulog,*) trim(fieldname), ' initialized with Q'
             if(dycore_is('LR')) call polar_average(pver, tptr3d) 	
          else
             call endrun('  '//trim(subname)//' Error:  Q must be on Initial File')
          end if
       end if
       do n = 1, pbuf_times
          call pbuf_set_field(pbuf2d, m, tptr3d, (/1,1,n/),(/pcols,pver,1/))
       end do
    end if

    fieldname = 'ICCWAT'
    m = pbuf_get_index(fieldname, ierr)
    if (m > 0) then
       call infld(fieldname, fh_ini, dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
          tptr3d, found, grid_map='phys')
       if(found) then
          do n = 1, pbuf_times
             call pbuf_set_field(pbuf2d, m, tptr3d, (/1,1,n/),(/pcols,pver,1/))
          end do
       else
          call cnst_get_ind('CLDICE', ixcldice)
          call infld('CLDICE',fh_ini,dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
             tptr3d, found, grid_map='PHYS')
          if(found) then
             do n = 1, pbuf_times
                call pbuf_set_field(pbuf2d, m, tptr3d, (/1,1,n/),(/pcols,pver,1/))
             end do
          else
             call pbuf_set_field(pbuf2d, m, 0._r8)
          end if
          if (masterproc) then
             if (found) then
                write(iulog,*) trim(fieldname), ' initialized with CLDICE'
             else
                write(iulog,*) trim(fieldname), ' initialized to 0.0'
             end if
          end if
       end if
    end if

    fieldname = 'LCWAT'
    m = pbuf_get_index(fieldname,ierr)
    if (m > 0) then
       call infld(fieldname, fh_ini, dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
            tptr3d, found, grid_map='phys')
       if(found) then
          do n = 1, pbuf_times
             call pbuf_set_field(pbuf2d, m, tptr3d, (/1,1,n/),(/pcols,pver,1/))
          end do
       else
          allocate(tptr3d_2(pcols,pver,begchunk:endchunk))     
          call cnst_get_ind('CLDICE', ixcldice)
          call cnst_get_ind('CLDLIQ', ixcldliq)
          call infld('CLDICE',fh_ini,dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
               tptr3d, found, grid_map='PHYS')
          call infld('CLDLIQ',fh_ini,dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
               tptr3d_2, found2, grid_map='PHYS')
          if(found .and. found2) then
             tptr3d(:,:,:)=tptr3d(:,:,:)+tptr3d_2(:,:,:)
             if (masterproc) write(iulog,*) trim(fieldname), ' initialized with CLDICE + CLDLIQ'
          else if (found) then ! Data already loaded in tptr3d
             if (masterproc) write(iulog,*) trim(fieldname), ' initialized with CLDICE only'
          else if (found2) then
             tptr3d(:,:,:)=tptr3d_2(:,:,:)
             if (masterproc) write(iulog,*) trim(fieldname), ' initialized with CLDLIQ only'
          end if

          if (found .or. found2) then
             do n = 1, pbuf_times
                call pbuf_set_field(pbuf2d, m, tptr3d, (/1,1,n/),(/pcols,pver,1/))
             end do
             if(dycore_is('LR')) call polar_average(pver, tptr3d) 	
          else
             call pbuf_set_field(pbuf2d, m, 0._r8)
             if (masterproc)  write(iulog,*) trim(fieldname), ' initialized to 0.0'
          end if
          deallocate(tptr3d_2)
       end if
    end if

    deallocate(tptr3d)
    allocate(tptr3d(pcols,pver,begchunk:endchunk))

    fieldname = 'TCWAT'
    m = pbuf_get_index(fieldname,ierr)
    if (m > 0) then
       call infld(fieldname, fh_ini, dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
            tptr3d, found, grid_map='phys')
       if(.not.found) then
          call infld('T', fh_ini, dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
               tptr3d, found, grid_map='phys')
          if(dycore_is('LR')) call polar_average(pver, tptr3d) 	
          if (masterproc) write(iulog,*) trim(fieldname), ' initialized with T'
       end if
       do n = 1, pbuf_times
          call pbuf_set_field(pbuf2d, m, tptr3d, (/1,1,n/),(/pcols,pver,1/))
       end do
    end if

    deallocate(tptr3d)
    allocate(tptr3d(pcols,pverp,begchunk:endchunk))

    fieldname = 'TKE'
    m = pbuf_get_index( 'tke')
    call infld(fieldname, fh_ini, dim1name, 'ilev', 'lat', 1, pcols, 1, pverp, begchunk, endchunk, &
         tptr3d, found, grid_map='phys')
    if (found) then
       call pbuf_set_field(pbuf2d, m, tptr3d)
    else
       call pbuf_set_field(pbuf2d, m, 0.01_r8)
       if (masterproc) write(iulog,*) trim(fieldname), ' initialized to 0.01'
    end if


    fieldname = 'KVM'
    m = pbuf_get_index('kvm')
    call infld(fieldname, fh_ini, dim1name, 'ilev', 'lat', 1, pcols, 1, pverp, begchunk, endchunk, &
         tptr3d, found, grid_map='phys')
    if (found) then
       call pbuf_set_field(pbuf2d, m, tptr3d)
    else
       call pbuf_set_field(pbuf2d, m, 0._r8)
       if (masterproc) write(iulog,*) trim(fieldname), ' initialized to 0.'
    end if


    fieldname = 'KVH'
    m = pbuf_get_index('kvh')
    call infld(fieldname, fh_ini, dim1name, 'ilev', 'lat', 1, pcols, 1, pverp, begchunk, endchunk, &
         tptr3d, found, grid_map='phys')
    if (found) then
       call pbuf_set_field(pbuf2d, m, tptr3d)
    else
       call pbuf_set_field(pbuf2d, m, 0._r8)
       if (masterproc) write(iulog,*) trim(fieldname), ' initialized to 0.'
    end if

    deallocate(tptr3d)
    allocate(tptr3d(pcols,pver,begchunk:endchunk))

    fieldname = 'CONCLD'
    m = pbuf_get_index('CONCLD')
    call infld(fieldname, fh_ini, dim1name, 'lev', 'lat', 1, pcols, 1, pver, begchunk, endchunk, &
         tptr3d, found, grid_map='phys')
    if(found) then
       do n = 1, pbuf_times
          call pbuf_set_field(pbuf2d, m, tptr3d, (/1,1,n/),(/pcols,pver,1/))
       end do
    else
       call pbuf_set_field(pbuf2d, m, 0._r8)
       if (masterproc) write(iulog,*) trim(fieldname), ' initialized to 0.'
    end if

    deallocate (tptr3d)

    call initialize_short_lived_species(fh_ini, pbuf2d)
end subroutine phys_inidat


subroutine phys_init( phys_state, phys_tend, pbuf2d, cam_out )

    !----------------------------------------------------------------------- 
    ! 
    ! Initialization of physics package.
    ! 
    !-----------------------------------------------------------------------

    use physics_buffer,     only: physics_buffer_desc, pbuf_initialize, pbuf_get_index
    use physconst,          only: rair, cpair, cpwv, gravit, stebol, tmelt, &
                                  latvap, latice, rh2o, rhoh2o, pstd, zvir,         &
                                  karman, rhodair, physconst_init 
    use ref_pres,           only: pref_edge, pref_mid

    use aerosol_intr,       only: aerosol_init
    use carma_intr,         only: carma_init
    use cloud_rad_props,    only: cloud_rad_props_init
    use cam_control_mod,    only: nsrest  ! restart flag
    use check_energy,       only: check_energy_init
    use chemistry,          only: chem_init
    use prescribed_ozone,   only: prescribed_ozone_init
    use prescribed_ghg,     only: prescribed_ghg_init
    use prescribed_aero,    only: prescribed_aero_init
    use aerodep_flx,        only: aerodep_flx_init
    use aircraft_emit,      only: aircraft_emit_init
    use prescribed_volcaero,only: prescribed_volcaero_init
    use cloud_fraction,     only: cldfrc_init
    use co2_cycle,          only: co2_init, co2_transport
    use convect_deep,       only: convect_deep_init
    use convect_shallow,    only: convect_shallow_init
    use cam_diagnostics,    only: diag_init
    use gw_drag,            only: gw_inti
    use cam3_aero_data,     only: cam3_aero_data_on, cam3_aero_data_init
    use cam3_ozone_data,    only: cam3_ozone_data_on, cam3_ozone_data_init
    use radheat,            only: radheat_init
    use radiation,          only: radiation_init
    use cloud_diagnostics,  only: cloud_diagnostics_init
    use stratiform,         only: stratiform_init
    use phys_control,       only: phys_getopts, waccmx_is
    use wv_saturation,      only: wv_sat_init
    use microp_driver,      only: microp_driver_init
    use microp_aero,        only: microp_aero_init
    use macrop_driver,      only: macrop_driver_init
    use conv_water,         only: conv_water_init
    use tracers,            only: tracers_init
    use aoa_tracers,        only: aoa_tracers_init
    use rayleigh_friction,  only: rayleigh_friction_init
    use pbl_utils,          only: pbl_utils_init
    use vertical_diffusion, only: vertical_diffusion_init
    use dycore,             only: dycore_is
    use phys_debug_util,    only: phys_debug_init
    use rad_constituents,   only: rad_cnst_init
    use aer_rad_props,      only: aer_rad_props_init
#if ( defined WACCM_PHYS )
    use qbo,                only: qbo_init
    use iondrag,            only: iondrag_init
#endif
#if ( defined OFFLINE_DYN )
    use metdata,            only: metdata_phys_init
#endif
    use ionosphere,	   only: ionos_init  ! Initialization of ionosphere module (WACCM-X)
    use majorsp_diffusion,  only: mspd_init   ! Initialization of major species diffusion module (WACCM-X)
    use clubb_intr,         only: clubb_ini_cam
    use sslt_rebin,         only: sslt_rebin_init
    use tropopause,         only: tropopause_init
    use solar_data,         only: solar_data_init
    use rad_solar_var,      only: rad_solar_var_init
    ! +++ Nudging coe +++ !
    use nudging,            only: Nudge_Model,nudging_init
    ! ------------------- !

    ! Input/output arguments
    type(physics_state), pointer       :: phys_state(:)
    type(physics_tend ), pointer       :: phys_tend(:)
    type(physics_buffer_desc), pointer :: pbuf2d(:,:)

    type(cam_out_t),intent(inout)      :: cam_out(begchunk:endchunk)

    ! local variables
    integer :: lchnk

    character(len=16) :: microp_scheme 
    logical           :: do_clubb_sgs

    !-----------------------------------------------------------------------

    ! Get microphysics option
    call phys_getopts(microp_scheme_out = microp_scheme)
    call phys_getopts(do_clubb_sgs_out  = do_clubb_sgs )

    call physics_type_alloc(phys_state, phys_tend, begchunk, endchunk, pcols)

    do lchnk = begchunk, endchunk
       call physics_state_set_grid(lchnk, phys_state(lchnk))
    end do

    !-------------------------------------------------------------------------------------------
    ! Initialize any variables in physconst which are not temporally and/or spatially constant
    !------------------------------------------------------------------------------------------- 
    call physconst_init()

    ! Initialize debugging a physics column
    call phys_debug_init()

    call pbuf_initialize(pbuf2d)

    ! diag_init makes addfld calls for dynamics fields that are output from
    ! the physics decomposition
    call diag_init()

    call check_energy_init()

    call tracers_init()

    ! age of air tracers
    call aoa_tracers_init()

    teout_idx = pbuf_get_index( 'TEOUT')

    ! For adiabatic or ideal physics don't need to initialize any of the
    ! parameterizations below:
    if (adiabatic .or. ideal_phys) return

    if (nsrest .eq. 0) then
       call phys_inidat(cam_out, pbuf2d) 
    end if
    
    ! wv_saturation is relatively independent of everything else and
    ! low level, so init it early. Must at least do this before radiation.
    call wv_sat_init

    ! CAM3 prescribed aerosols
    if (cam3_aero_data_on) call cam3_aero_data_init(phys_state)

    ! Initialize rad constituents and their properties
    call rad_cnst_init()
    call aer_rad_props_init()
    call cloud_rad_props_init()

    ! Initialize some aerosol code
    call aerosol_init(pbuf2d)

    ! initialize carma
    call carma_init()

    ! solar irradiance data modules
    call solar_data_init()


    ! Prognostic chemistry.
    call chem_init(phys_state,pbuf2d)

    ! Prescribed tracers
    call prescribed_ozone_init()
    call prescribed_ghg_init()
    call prescribed_aero_init()
    call aerodep_flx_init()
    call aircraft_emit_init()
    call prescribed_volcaero_init()

    ! co2 cycle            
    if (co2_transport()) then
       call co2_init()
    end if

    ! CAM3 prescribed ozone
    if (cam3_ozone_data_on) call cam3_ozone_data_init(phys_state)

    call gw_inti(cpair, cpwv, gravit, rair, pref_edge)

    call rayleigh_friction_init()

    call pbl_utils_init(gravit, karman, cpair, rair, zvir)
    if (.not. do_clubb_sgs) call vertical_diffusion_init(pbuf2d)

    if ( waccmx_is('ionosphere') .or. waccmx_is('neutral') ) then
       call mspd_init ()
       ! Initialization of ionosphere module if mode set to ionosphere
       if( waccmx_is('ionosphere') ) then
          call ionos_init()
       endif
    endif

    call tsinti(tmelt, latvap, rair, stebol, latice)

    call radiation_init

    call rad_solar_var_init()

    call cloud_diagnostics_init

    call radheat_init(pref_mid)

    call convect_shallow_init(pref_edge)

    call cldfrc_init

    call convect_deep_init(pref_edge)

    if( microp_scheme == 'RK' ) then
       call stratiform_init()
    elseif( microp_scheme == 'MG' ) then 
       if (.not. do_clubb_sgs) call macrop_driver_init()
       call microp_aero_init()
       call microp_driver_init(pbuf2d)
       call conv_water_init
    end if

    ! initiate CLUBB within CAM
    if (do_clubb_sgs) call clubb_ini_cam(pbuf2d)

#if ( defined WACCM_PHYS )
    call iondrag_init(pref_mid)
    call qbo_init
#endif

#if ( defined OFFLINE_DYN )
    call metdata_phys_init()
#endif
    call sslt_rebin_init()
    call tropopause_init()

    prec_dp_idx  = pbuf_get_index('PREC_DP')
    snow_dp_idx  = pbuf_get_index('SNOW_DP')
    prec_sh_idx  = pbuf_get_index('PREC_SH')
    snow_sh_idx  = pbuf_get_index('SNOW_SH')

    ! +++ Nudging code +++ !
    ! Initialize Nudging Parameters
    !--------------------------------
    if(Nudge_Model) call nudging_init
    ! -------------------- !

end subroutine phys_init

  !
  !-----------------------------------------------------------------------
  !

subroutine phys_run1(phys_state, ztodt, phys_tend, pbuf2d,  cam_in, cam_out)
    !----------------------------------------------------------------------- 
    ! 
    ! Purpose: 
    ! First part of atmospheric physics package before updating of surface models
    ! 
    !-----------------------------------------------------------------------
    use time_manager,   only: get_nstep
    use cam_diagnostics,only: diag_allocate, diag_physvar_ic
    use check_energy,   only: check_energy_gmean

    use physics_buffer,         only: physics_buffer_desc, pbuf_get_chunk, pbuf_allocate
#if (defined BFB_CAM_SCAM_IOP )
    use cam_history,    only: outfld
#endif
    use comsrf,         only: fsns, fsnt, flns, sgh30, flnt, landm, fsds
    use abortutils,     only: endrun
#if ( defined OFFLINE_DYN )
     use metdata,       only: get_met_srf1
#endif
    !
    ! Input arguments
    !
    real(r8), intent(in) :: ztodt            ! physics time step unless nstep=0
    !
    ! Input/Output arguments
    !
    type(physics_state), intent(inout), dimension(begchunk:endchunk) :: phys_state
    type(physics_tend ), intent(inout), dimension(begchunk:endchunk) :: phys_tend

    type(physics_buffer_desc), pointer, dimension(:,:) :: pbuf2d
    type(cam_in_t),                     dimension(begchunk:endchunk) :: cam_in
    type(cam_out_t),                    dimension(begchunk:endchunk) :: cam_out
    !-----------------------------------------------------------------------
    !
    !---------------------------Local workspace-----------------------------
    !
    integer :: c                                 ! indices
    integer :: ncol                              ! number of columns
    integer :: nstep                             ! current timestep number
#if (! defined SPMD)
    integer  :: mpicom = 0
#endif
    type(physics_buffer_desc), pointer :: phys_buffer_chunk(:)

    call t_startf ('physpkg_st1')
    nstep = get_nstep()

#if ( defined OFFLINE_DYN )
    !
    ! if offline mode set SNOWH and TS for micro-phys
    !
    call get_met_srf1( cam_in )
#endif

    ! The following initialization depends on the import state (cam_in)
    ! being initialized.  This isn't true when cam_init is called, so need
    ! to postpone this initialization to here.
    if (nstep == 0 .and. phys_do_flux_avg()) call flux_avg_init(cam_in,  pbuf2d)

    ! Compute total energy of input state and previous output state
    call t_startf ('chk_en_gmean')
    call check_energy_gmean(phys_state, pbuf2d, ztodt, nstep)
    call t_stopf ('chk_en_gmean')

    call t_stopf ('physpkg_st1')

    if ( adiabatic .or. ideal_phys )then
       call t_startf ('bc_physics')
       call phys_run1_adiabatic_or_ideal(ztodt, phys_state, phys_tend,  pbuf2d)
       call t_stopf ('bc_physics')
    else
       call t_startf ('physpkg_st1')

       call pbuf_allocate(pbuf2d, 'physpkg')
       call diag_allocate()

       !-----------------------------------------------------------------------
       ! Advance time information
       !-----------------------------------------------------------------------

       call phys_timestep_init( phys_state, cam_out, pbuf2d)

       call t_stopf ('physpkg_st1')

#ifdef TRACER_CHECK
       call gmean_mass ('before tphysbc DRY', phys_state)
#endif


       !-----------------------------------------------------------------------
       ! Tendency physics before flux coupler invocation
       !-----------------------------------------------------------------------
       !

#if (defined BFB_CAM_SCAM_IOP )
       do c=begchunk, endchunk
          call outfld('Tg',cam_in(c)%ts,pcols   ,c     )
       end do
#endif

       call t_barrierf('sync_bc_physics', mpicom)
       call t_startf ('bc_physics')
       call t_adj_detailf(+1)

!$OMP PARALLEL DO PRIVATE (C, phys_buffer_chunk)
       do c=begchunk, endchunk
          !
          ! Output physics terms to IC file
          !
          phys_buffer_chunk => pbuf_get_chunk(pbuf2d, c)

          call t_startf ('diag_physvar_ic')
          call diag_physvar_ic ( c,  phys_buffer_chunk, cam_out(c), cam_in(c) )
          call t_stopf ('diag_physvar_ic')

          call tphysbc (ztodt, fsns(1,c), fsnt(1,c), flns(1,c), flnt(1,c), phys_state(c),        &
                       phys_tend(c), phys_buffer_chunk,  fsds(1,c), landm(1,c),          &
                       sgh30(1,c), cam_out(c), cam_in(c) )

       end do

       call t_adj_detailf(-1)
       call t_stopf ('bc_physics')

       ! Don't call the rest in CRM mode
       if(single_column.and.scm_crm_mode) return

#ifdef TRACER_CHECK
       call gmean_mass ('between DRY', phys_state)
#endif
    end if

end subroutine phys_run1

  !
  !-----------------------------------------------------------------------
  !

subroutine phys_run1_adiabatic_or_ideal(ztodt, phys_state, phys_tend,  pbuf2d)
    !----------------------------------------------------------------------- 
    ! 
    ! Purpose: 
    ! Physics for adiabatic or idealized physics case.
    ! 
    !-----------------------------------------------------------------------
    use physics_buffer, only : physics_buffer_desc, pbuf_set_field, pbuf_get_chunk, pbuf_old_tim_idx
    use time_manager,     only: get_nstep
    use cam_diagnostics,  only: diag_phys_writeout
    use check_energy,     only: check_energy_fix, check_energy_chng
    use dycore,           only: dycore_is

    !
    ! Input arguments
    !
    real(r8), intent(in) :: ztodt            ! physics time step unless nstep=0
    !
    ! Input/Output arguments
    !
    type(physics_state), intent(inout), dimension(begchunk:endchunk) :: phys_state
    type(physics_tend ), intent(inout), dimension(begchunk:endchunk) :: phys_tend

    type(physics_buffer_desc), pointer :: pbuf2d(:,:)
    !-----------------------------------------------------------------------
    !---------------------------Local workspace-----------------------------
    !
    integer             :: c               ! indices
    integer             :: nstep           ! current timestep number
    type(physics_ptend) :: ptend(begchunk:endchunk) ! indivdual parameterization tendencies
    real(r8)            :: flx_heat(pcols) ! effective sensible heat flux
    real(r8)            :: zero(pcols)     ! array of zeros

    ! physics buffer field for total energy
    integer itim
    real(r8), pointer, dimension(:) :: teout
    logical, SAVE :: first_exec_of_phys_run1_adiabatic_or_ideal  = .TRUE.
    !-----------------------------------------------------------------------

    nstep = get_nstep()
    zero  = 0._r8

    ! Associate pointers with physics buffer fields
    itim = pbuf_old_tim_idx()
    if (first_exec_of_phys_run1_adiabatic_or_ideal) then
       first_exec_of_phys_run1_adiabatic_or_ideal  = .FALSE.
    endif

!$OMP PARALLEL DO PRIVATE (C, FLX_HEAT)
    do c=begchunk, endchunk

       ! Initialize the physics tendencies to zero.
       call physics_tend_init(phys_tend(c))

       ! Dump dynamics variables to history buffers
       call diag_phys_writeout(phys_state(c))

       if (dycore_is('LR')) then
          call check_energy_fix(phys_state(c), ptend(c), nstep, flx_heat)
          call physics_update(phys_state(c), ptend(c), ztodt, phys_tend(c))
          call check_energy_chng(phys_state(c), phys_tend(c), "chkengyfix", nstep, ztodt, &
               zero, zero, zero, flx_heat)
          call physics_ptend_dealloc(ptend(c))
       end if

       if ( ideal_phys )then
          call t_startf('tphysidl')
          call tphysidl(ztodt, phys_state(c), phys_tend(c))
          call t_stopf('tphysidl')
       end if

       ! Save total enery after physics for energy conservation checks
       call pbuf_set_field(pbuf_get_chunk(pbuf2d, c), teout_idx, phys_state(c)%te_cur)


    end do

end subroutine phys_run1_adiabatic_or_ideal

  !
  !-----------------------------------------------------------------------
  !

subroutine phys_run2(phys_state, ztodt, phys_tend, pbuf2d,  cam_out, &
       cam_in )
    !----------------------------------------------------------------------- 
    ! 
    ! Purpose: 
    ! Second part of atmospheric physics package after updating of surface models
    ! 
    !-----------------------------------------------------------------------
    use physics_buffer,         only: physics_buffer_desc, pbuf_get_chunk, pbuf_deallocate, pbuf_update_tim_idx
    use mo_lightning,   only: lightning_no_prod


    use cam_diagnostics,only: diag_deallocate, diag_surf
    use comsrf,         only: trefmxav, trefmnav, sgh, sgh30, fsds 
    use physconst,      only: stebol, latvap
    use carma_intr,     only: carma_accumulate_stats
#if ( defined OFFLINE_DYN )
    use metdata,        only: get_met_srf2
#endif
    !
    ! Input arguments
    !
    real(r8), intent(in) :: ztodt                       ! physics time step unless nstep=0
    !
    ! Input/Output arguments
    !
    type(physics_state), intent(inout), dimension(begchunk:endchunk) :: phys_state
    type(physics_tend ), intent(inout), dimension(begchunk:endchunk) :: phys_tend
    type(physics_buffer_desc),pointer, dimension(:,:)     :: pbuf2d

    type(cam_out_t),     intent(inout), dimension(begchunk:endchunk) :: cam_out
    type(cam_in_t),      intent(inout), dimension(begchunk:endchunk) :: cam_in
    !
    !-----------------------------------------------------------------------
    !---------------------------Local workspace-----------------------------
    !
    integer :: c                                 ! chunk index
    integer :: ncol                              ! number of columns
#if (! defined SPMD)
    integer  :: mpicom = 0
#endif
    type(physics_buffer_desc),pointer, dimension(:)     :: phys_buffer_chunk
    !
    ! If exit condition just return
    !

    if(single_column.and.scm_crm_mode) return

    if ( adiabatic .or. ideal_phys ) return
    !-----------------------------------------------------------------------
    ! Tendency physics after coupler 
    ! Not necessary at terminal timestep.
    !-----------------------------------------------------------------------
    !
#if ( defined OFFLINE_DYN )
    !
    ! if offline mode set SHFLX QFLX TAUX TAUY for vert diffusion
    !
    call get_met_srf2( cam_in )
#endif
    ! Set lightning production of NO
    call t_startf ('lightning_no_prod')
    call lightning_no_prod( phys_state, pbuf2d,  cam_in )
    call t_stopf ('lightning_no_prod')

    call t_barrierf('sync_ac_physics', mpicom)
    call t_startf ('ac_physics')
    call t_adj_detailf(+1)

!$OMP PARALLEL DO PRIVATE (C, NCOL, phys_buffer_chunk)

    do c=begchunk,endchunk
       ncol = get_ncols_p(c)
       phys_buffer_chunk => pbuf_get_chunk(pbuf2d, c)
       !
       ! surface diagnostics for history files
       !
       call t_startf('diag_surf')
       call diag_surf(cam_in(c), cam_out(c), phys_state(c)%ps,trefmxav(1,c), trefmnav(1,c))
       call t_stopf('diag_surf')

       call tphysac(ztodt, cam_in(c),  &
            sgh(1,c), sgh30(1,c), cam_out(c),                              &
            phys_state(c), phys_tend(c), phys_buffer_chunk,&
            fsds(1,c))
    end do                    ! Chunk loop

    call t_adj_detailf(-1)
    call t_stopf('ac_physics')

#ifdef TRACER_CHECK
    call gmean_mass ('after tphysac FV:WET)', phys_state)
#endif

    call t_startf ('carma_accumulate_stats')
    call carma_accumulate_stats()
    call t_stopf ('carma_accumulate_stats')

    call t_startf ('physpkg_st2')
    call pbuf_deallocate(pbuf2d, 'physpkg')

    call pbuf_update_tim_idx()
    call diag_deallocate()
    call t_stopf ('physpkg_st2')

end subroutine phys_run2

  !
  !----------------------------------------------------------------------- 
  !

subroutine phys_final( phys_state, phys_tend, pbuf2d )
    use physics_buffer, only : physics_buffer_desc, pbuf_deallocate
    use chemistry, only : chem_final
    use carma_intr, only : carma_final
    use wv_saturation, only : wv_sat_final
    !----------------------------------------------------------------------- 
    ! 
    ! Purpose: 
    ! Finalization of physics package
    ! 
    !-----------------------------------------------------------------------
    ! Input/output arguments
    type(physics_state), pointer :: phys_state(:)
    type(physics_tend ), pointer :: phys_tend(:)
    type(physics_buffer_desc), pointer :: pbuf2d(:,:)

    if(associated(pbuf2d)) then
       call pbuf_deallocate(pbuf2d,'global')
       deallocate(pbuf2d)
    end if
    deallocate(phys_state)
    deallocate(phys_tend)
    call chem_final
    call carma_final
    call wv_sat_final

end subroutine phys_final


subroutine tphysac (ztodt,   cam_in,  &
       sgh,     sgh30,                                     &
       cam_out,  state,   tend,    pbuf,            &
       fsds    )
    !----------------------------------------------------------------------- 
    ! 
    ! Purpose: 
    ! Tendency physics after coupling to land, sea, and ice models.
    ! Computes the following:
    !   o Radon surface flux and decay (optional)
    !   o Vertical diffusion and planetary boundary layer
    !   o Multiple gravity wave drag
    ! 
    ! Method: 
    ! <Describe the algorithm(s) used in the routine.> 
    ! <Also include any applicable external references.> 
    ! 
    ! Author: CCM1, CMS Contact: J. Truesdale
    ! 
    !-----------------------------------------------------------------------
    use physics_buffer, only: physics_buffer_desc, pbuf_set_field, pbuf_get_index, pbuf_get_field, pbuf_old_tim_idx
    use shr_kind_mod,       only: r8 => shr_kind_r8
    use chemistry,          only: chem_is_active, chem_timestep_tend
    use cam_diagnostics,    only: diag_phys_tend_writeout
    use gw_drag,            only: gw_intr
    use vertical_diffusion, only: vertical_diffusion_tend
    use rayleigh_friction,  only: rayleigh_friction_tend
    use constituents,       only: cnst_get_ind
    use physics_types,      only: physics_state, physics_tend, physics_ptend, physics_update,    &
         physics_dme_adjust, set_dry_to_wet, physics_state_check
    use majorsp_diffusion,  only: mspd_intr  ! WACCM-X major diffusion
    use ionosphere,         only: ionos_intr ! WACCM-X ionosphere
    use phys_control,       only: phys_getopts
    use tracers,            only: tracers_timestep_tend
    use aoa_tracers,        only: aoa_tracers_timestep_tend
    use physconst,          only: rhoh2o, latvap,latice
    use aerosol_intr,       only: aerosol_emis_intr, aerosol_drydep_intr
    use carma_intr,         only: carma_emission_tend, carma_timestep_tend
    use carma_flags_mod,    only: carma_do_aerosol, carma_do_emission
    use check_energy,       only: check_energy_chng
    use check_energy,       only: check_tracers_data, check_tracers_init, check_tracers_chng
    use time_manager,       only: get_nstep
    use abortutils,         only: endrun
    use dycore,             only: dycore_is
    use cam_control_mod,    only: aqua_planet 
    use mo_gas_phase_chemdr,only: map2chm
    use clybry_fam,         only: clybry_fam_set
    use charge_neutrality,  only: charge_fix
#if ( defined WACCM_PHYS )
    use iondrag,            only: iondrag_calc, do_waccm_ions
    use qbo,                only: qbo_relax
#endif
    use clubb_intr,         only: clubb_surface
    use perf_mod
    use phys_control,       only: phys_do_flux_avg, waccmx_is
    use flux_avg,           only: flux_avg_run
    ! +++ Nudging code +++ !
    use nudging,            only: Nudge_Model,Nudge_ON,nudging_timestep_tend,nudging_diag,Nudge_Diag_Opt
    ! -------------------- !

    implicit none

    !
    ! Arguments
    !
    real(r8), intent(in) :: ztodt                  ! Two times model timestep (2 delta-t)
    real(r8), intent(in) :: fsds(pcols)            ! down solar flux
    real(r8), intent(in) :: sgh(pcols)             ! Std. deviation of orography for gwd
    real(r8), intent(in) :: sgh30(pcols)           ! Std. deviation of 30s orography for tms

    type(cam_in_t),      intent(inout) :: cam_in
    type(cam_out_t),     intent(inout) :: cam_out
    type(physics_state), intent(inout) :: state
    type(physics_tend ), intent(inout) :: tend
    type(physics_buffer_desc), pointer :: pbuf(:)


    type(check_tracers_data):: tracerint             ! tracer mass integrals and cummulative boundary fluxes

    !
    !---------------------------Local workspace-----------------------------
    !
    type(physics_ptend)     :: ptend               ! indivdual parameterization tendencies

    integer  :: nstep                              ! current timestep number
    real(r8) :: zero(pcols)                        ! array of zeros

    integer :: lchnk                                ! chunk identifier
    integer :: ncol                                 ! number of atmospheric columns
    integer i,k,m                 ! Longitude, level indices
    integer :: yr, mon, day, tod       ! components of a date
    integer :: ixcldice, ixcldliq      ! constituent indices for cloud liquid and ice water.

    logical :: labort                            ! abort flag

    real(r8) tvm(pcols,pver)           ! virtual temperature
    real(r8) prect(pcols)              ! total precipitation
    real(r8) surfric(pcols)            ! surface friction velocity
    real(r8) obklen(pcols)             ! Obukhov length
    real(r8) :: fh2o(pcols)            ! h2o flux to balance source from methane chemistry
    real(r8) :: tmp_q     (pcols,pver) ! tmp space
    real(r8) :: tmp_cldliq(pcols,pver) ! tmp space
    real(r8) :: tmp_cldice(pcols,pver) ! tmp space
    real(r8) :: tmp_t     (pcols,pver) ! tmp space

    ! physics buffer fields for total energy and mass adjustment
    integer itim, ifld

    real(r8), pointer, dimension(:,:) :: tini
    real(r8), pointer, dimension(:,:) :: cld
    real(r8), pointer, dimension(:,:) :: qini
    real(r8), pointer, dimension(:,:) :: cldliqini
    real(r8), pointer, dimension(:,:) :: cldiceini
    real(r8), pointer, dimension(:,:) :: dtcore
    real(r8), pointer, dimension(:,:) :: ast     ! relative humidity cloud fraction 

    logical :: do_clubb_sgs 

    ! Debug physics_state.
    logical :: state_debug_checks
    !
    !-----------------------------------------------------------------------
    !
    lchnk = state%lchnk
    ncol  = state%ncol

    nstep = get_nstep()
    
    call phys_getopts( do_clubb_sgs_out       = do_clubb_sgs, &
                       state_debug_checks_out = state_debug_checks)

    ! Adjust the surface fluxes to reduce instabilities in near sfc layer
    if (phys_do_flux_avg()) then 
       call flux_avg_run(state, cam_in,  pbuf, nstep, ztodt)
    endif

    ! Validate the physics state.
    if (state_debug_checks) &
         call physics_state_check(state, name="before tphysac")

    call t_startf('tphysac_init')
    ! Associate pointers with physics buffer fields
    itim = pbuf_old_tim_idx()


    ifld = pbuf_get_index('DTCORE')
    call pbuf_get_field(pbuf, ifld, dtcore, start=(/1,1,itim/), kount=(/pcols,pver,1/) )

    call pbuf_get_field(pbuf, tini_idx, tini)
    call pbuf_get_field(pbuf, qini_idx, qini)
    call pbuf_get_field(pbuf, cldliqini_idx, cldliqini)
    call pbuf_get_field(pbuf, cldiceini_idx, cldiceini)

    ifld = pbuf_get_index('CLD')
    call pbuf_get_field(pbuf, ifld, cld, start=(/1,1,itim/),kount=(/pcols,pver,1/))

    ifld = pbuf_get_index('AST')
    call pbuf_get_field(pbuf, ifld, ast, start=(/1,1,itim/), kount=(/pcols,pver,1/) )

    !
    ! accumulate fluxes into net flux array for spectral dycores
    ! jrm Include latent heat of fusion for snow
    !
    do i=1,ncol
       tend%flx_net(i) = tend%flx_net(i) + cam_in%shf(i) + (cam_out%precc(i) &
            + cam_out%precl(i))*latvap*rhoh2o &
            + (cam_out%precsc(i) + cam_out%precsl(i))*latice*rhoh2o
    end do

    ! emission of aerosols at surface
    call aerosol_emis_intr (state, cam_in)

    if (carma_do_emission) then
       ! carma emissions
       call carma_emission_tend (state, ptend, cam_in, ztodt)
       call physics_update(state, ptend, ztodt, tend)
    end if

    ! get nstep and zero array for energy checker
    zero = 0._r8
    nstep = get_nstep()
    call check_tracers_init(state, tracerint)

    ! Check if latent heat flux exceeds the total moisture content of the
    ! lowest model layer, thereby creating negative moisture.

    call qneg4('TPHYSAC '       ,lchnk               ,ncol  ,ztodt ,               &
         state%q(1,pver,1),state%rpdel(1,pver) ,cam_in%shf ,         &
         cam_in%lhf , cam_in%cflx )

    call t_stopf('tphysac_init')
    !===================================================
    ! Source/sink terms for advected tracers.
    !===================================================
    call t_startf('adv_tracer_src_snk')
    ! Test tracers

    call tracers_timestep_tend(state, ptend, cam_in%cflx, cam_in%landfrac, ztodt)      
    call physics_update(state, ptend, ztodt, tend)
    call check_tracers_chng(state, tracerint, "tracers_timestep_tend", nstep, ztodt,   &
         cam_in%cflx)

    call aoa_tracers_timestep_tend(state, ptend, cam_in%cflx, cam_in%landfrac, ztodt)      
    call physics_update(state, ptend, ztodt, tend)
    call check_tracers_chng(state, tracerint, "aoa_tracers_timestep_tend", nstep, ztodt,   &
         cam_in%cflx)

    ! Chemistry calculation
    if (chem_is_active()) then
       call chem_timestep_tend(state, ptend, cam_in, cam_out, ztodt, &
            pbuf,  fh2o, fsds)

       call physics_update(state, ptend, ztodt, tend)
       call check_energy_chng(state, tend, "chem", nstep, ztodt, fh2o, zero, zero, zero)
       call check_tracers_chng(state, tracerint, "chem_timestep_tend", nstep, ztodt, &
            cam_in%cflx)
    end if
    call t_stopf('adv_tracer_src_snk')

    !===================================================
    ! Vertical diffusion/pbl calculation
    ! Call vertical diffusion code (pbl, free atmosphere and molecular)
    !===================================================

    ! If CLUBB is called, do not call vertical diffusion, but obukov length and
    !   surface friction velocity still need to be computed.  In addition, 
    !   surface fluxes need to be updated here for constituents 
    if (do_clubb_sgs) then

       call clubb_surface ( state, ptend, ztodt, cam_in, surfric, obklen)
       
       ! Update surface flux constituents 
       call physics_update(state, ptend, ztodt, tend)

    else

       call t_startf('vertical_diffusion_tend')
       call vertical_diffusion_tend (ztodt ,state ,cam_in%wsx, cam_in%wsy,   &
            cam_in%shf     ,cam_in%cflx     ,surfric  ,obklen   ,ptend    ,ast    ,&
            cam_in%ocnfrac  , cam_in%landfrac ,        &
            sgh30    ,pbuf )

    !------------------------------------------
    ! Call major diffusion for extended model
    !------------------------------------------
    if ( waccmx_is('ionosphere') .or. waccmx_is('neutral') ) then
       call mspd_intr (ztodt    ,state    ,ptend)
    endif

       call physics_update(state, ptend, ztodt, tend)
       call t_stopf ('vertical_diffusion_tend')
    
    endif


    !===================================================
    ! Rayleigh friction calculation
    !===================================================
    call t_startf('rayleigh_friction')
    call rayleigh_friction_tend( ztodt, state, ptend)
    call physics_update(state, ptend, ztodt, tend)
    call t_stopf('rayleigh_friction')

    if (do_clubb_sgs) then
      call check_energy_chng(state, tend, "vdiff", nstep, ztodt, zero, zero, zero, zero)
    else
      call check_energy_chng(state, tend, "vdiff", nstep, ztodt, cam_in%cflx(:,1), zero, &
           zero, cam_in%shf)
    endif
    
    call check_tracers_chng(state, tracerint, "vdiff", nstep, ztodt, cam_in%cflx)

    !  aerosol dry deposition processes
    call t_startf('aero_drydep')
    call aerosol_drydep_intr (state, ptend, cam_in, cam_out, ztodt,  &
         fsds, obklen, surfric, prect, pbuf)
    call physics_update(state, ptend, ztodt, tend)
    call t_stopf('aero_drydep')

   ! CARMA microphysics
   !
   ! NOTE: This does both the timestep_tend for CARMA aerosols as well as doing the dry
   ! deposition for CARMA aerosols. It needs to follow vertical_diffusion_tend, so that
   ! obklen and surfric have been calculated. It needs to follow aerosol_drydep_intr, so
   ! that cam_out%xxxdryxxx fields have already been set for CAM aerosols and cam_out
   ! can be added to for CARMA aerosols.
   if (carma_do_aerosol) then
     call t_startf('carma_timestep_tend')
     call carma_timestep_tend(state, cam_in, cam_out, ptend, ztodt, pbuf, obklen=obklen, ustar=surfric)
     call physics_update(state, ptend, ztodt, tend)
   
     call check_energy_chng(state, tend, "carma_tend", nstep, ztodt, zero, zero, zero, zero)
     call t_stopf('carma_timestep_tend')
   end if


    !---------------------------------------------------------------------------------
    !	... enforce charge neutrality
    !---------------------------------------------------------------------------------
    if (do_waccm_phys()) call charge_fix( ncol, state%q(:,:,:) )

    !===================================================
    ! Gravity wave drag
    !===================================================
    call t_startf('gw_intr')

    call gw_intr(state, sgh, pbuf, ztodt, ptend, cam_in%landfrac)

    call physics_update(state, ptend, ztodt, tend)
    ! Check energy integrals
    call check_energy_chng(state, tend, "gwdrag", nstep, ztodt, zero, zero, zero, zero)
    call t_stopf('gw_intr')

#if ( defined WACCM_PHYS )

    ! QBO relaxation
    call qbo_relax(state, ptend)
    call physics_update(state, ptend, ztodt, tend)
    ! Check energy integrals
    call check_energy_chng(state, tend, "qborelax", nstep, ztodt, zero, zero, zero, zero)
    ! Ion drag calculation
    call t_startf ( 'iondrag' )

    if ( do_waccm_ions ) then
       call iondrag_calc( lchnk, ncol, state, ptend, pbuf,  ztodt )
    else
       call iondrag_calc( lchnk, ncol, state, ptend)
    endif
    !----------------------------------------------------------------------------
    ! Call ionosphere routines for extended model if mode is set to ionosphere
    !----------------------------------------------------------------------------
    if( waccmx_is('ionosphere') ) then
       call ionos_intr(state, ptend, pbuf, ztodt)
    endif

    call physics_update(state, ptend, ztodt, tend)
    ! Check energy integrals
    call check_energy_chng(state, tend, "iondrag", nstep, ztodt, zero, zero, zero, zero)
    call t_stopf  ( 'iondrag' )

#endif


    !-------------- Energy budget checks vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

    call pbuf_set_field(pbuf, teout_idx, state%te_cur, (/1,itim/),(/pcols,1/))       

    !*** BAB's FV heating kludge *** apply the heating as temperature tendency.
    !*** BAB's FV heating kludge *** modify the temperature in the state structure
    tmp_t(:ncol,:pver) = state%t(:ncol,:pver)
    state%t(:ncol,:pver) = tini(:ncol,:pver) + ztodt*tend%dtdt(:ncol,:pver)

    ! store dse after tphysac in buffer
    do k = 1,pver
       dtcore(:ncol,k) = state%t(:ncol,k)
    end do


    !
    ! FV: convert dry-type mixing ratios to moist here because physics_dme_adjust
    !     assumes moist. This is done in p_d_coupling for other dynamics. Bundy, Feb 2004.


    if ( dycore_is('LR') .or. dycore_is('SE')) call set_dry_to_wet(state)    ! Physics had dry, dynamics wants moist


    ! Scale dry mass and energy (does nothing if dycore is EUL or SLD)
    call cnst_get_ind('CLDLIQ', ixcldliq)
    call cnst_get_ind('CLDICE', ixcldice)
    tmp_q     (:ncol,:pver) = state%q(:ncol,:pver,1)
    tmp_cldliq(:ncol,:pver) = state%q(:ncol,:pver,ixcldliq)
    tmp_cldice(:ncol,:pver) = state%q(:ncol,:pver,ixcldice)
    call physics_dme_adjust(state, tend, qini, ztodt)
!!!   REMOVE THIS CALL, SINCE ONLY Q IS BEING ADJUSTED. WON'T BALANCE ENERGY. TE IS SAVED BEFORE THIS
!!!   call check_energy_chng(state, tend, "drymass", nstep, ztodt, zero, zero, zero, zero)

    !-------------- Energy budget checks ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    if (aqua_planet) then
       labort = .false.
       do i=1,ncol
          if (cam_in%ocnfrac(i) /= 1._r8) labort = .true.
       end do
       if (labort) then
          call endrun ('TPHYSAC error:  grid contains non-ocean point')
       endif
    endif
    ! +++ Nudging code +++ !
    !===================================================
    ! Update Nudging values, if needed
    !===================================================
    if((Nudge_Model).and.(Nudge_ON)) then
      call nudging_timestep_tend(state,ptend)
      call physics_update(state,ptend,ztodt,tend)
    endif
    ! ---------------------!

    call diag_phys_tend_writeout (state, pbuf,  tend, ztodt, tmp_q, tmp_cldliq, tmp_cldice, &
         tmp_t, qini, cldliqini, cldiceini)

    call clybry_fam_set( ncol, lchnk, map2chm, state%q, pbuf )

end subroutine tphysac

subroutine tphysbc (ztodt,               &
       fsns,    fsnt,    flns,    flnt,    state,   &
       tend,    pbuf,     fsds,    landm,            &
       sgh30, cam_out, cam_in )
    !----------------------------------------------------------------------- 
    ! 
    ! Purpose: 
    ! Evaluate and apply physical processes that are calculated BEFORE 
    ! coupling to land, sea, and ice models.  
    !
    ! Processes currently included are: 
    ! dry adjustment, moist convection, stratiform, wet deposition, radiation
    !
    ! Pass surface fields for separate surface flux calculations
    ! Dump appropriate fields to history file.
    ! 
    ! Method: 
    !
    ! Each parameterization should be implemented with this sequence of calls:
    !  1)  Call physics interface
    !  2)  Check energy
    !  3)  Call physics_update
    ! See Interface to Column Physics and Chemistry Packages 
    !   http://www.ccsm.ucar.edu/models/atm-cam/docs/phys-interface/index.html
    ! 
    ! Author: CCM1, CMS Contact: J. Truesdale
    !         modified by A. Gettelman and C. Craig Nov 2010 to separate micro/macro physics
    ! 
    !-----------------------------------------------------------------------

    use physics_buffer,          only : physics_buffer_desc, pbuf_get_field
    use physics_buffer,          only : pbuf_get_index, pbuf_old_tim_idx, pbuf_times
    use shr_kind_mod,    only: r8 => shr_kind_r8

    use stratiform,      only: stratiform_tend
    use phys_control,    only: phys_getopts
    use microp_driver,   only: microp_driver_tend
    use microp_aero,     only: microp_aero_run
    use macrop_driver,   only: macrop_driver_tend
    use physics_types,   only: physics_state, physics_tend, physics_ptend, physics_update, &
         physics_ptend_init, physics_ptend_sum, physics_state_check
    use cam_diagnostics, only: diag_conv_tend_ini, diag_phys_writeout, diag_conv, diag_export, diag_state_b4_phys_write
    use cam_history,     only: outfld
    use physconst,       only: cpair, latvap
    use constituents,    only: pcnst, qmin, cnst_get_ind
    use convect_deep,    only: convect_deep_tend, convect_deep_tend_2, deep_scheme_does_scav_trans
    use time_manager,    only: is_first_step, get_nstep
    use convect_shallow, only: convect_shallow_tend
    use check_energy,    only: check_energy_chng, check_energy_fix
    use check_energy,    only: check_tracers_data, check_tracers_init, check_tracers_chng
    use dycore,          only: dycore_is
    use aerosol_intr,    only: aerosol_wet_intr
    use carma_intr,      only: carma_wetdep_tend, carma_timestep_tend
    use carma_flags_mod, only: carma_do_detrain, carma_do_cldice, carma_do_cldliq,  carma_do_wetdep
    use radiation,       only: radiation_tend
    use cloud_diagnostics, only: cloud_diagnostics_calc
    use perf_mod
#ifdef MODAL_AERO
    use modal_aero_data, only: qneg3_worst_thresh_amode
#endif
    use mo_gas_phase_chemdr,only: map2chm
    use clybry_fam,         only: clybry_fam_adj
    use clubb_intr,      only: clubb_tend_cam
    use sslt_rebin,      only: sslt_rebin_adv
    use tropopause,      only: tropopause_output
    use abortutils,      only: endrun

    implicit none

    !
    ! Arguments
    !
    real(r8), intent(in) :: ztodt                          ! 2 delta t (model time increment)
    real(r8), intent(inout) :: fsns(pcols)                   ! Surface solar absorbed flux
    real(r8), intent(inout) :: fsnt(pcols)                   ! Net column abs solar flux at model top
    real(r8), intent(inout) :: flns(pcols)                   ! Srf longwave cooling (up-down) flux
    real(r8), intent(inout) :: flnt(pcols)                   ! Net outgoing lw flux at model top
    real(r8), intent(inout) :: fsds(pcols)                   ! Surface solar down flux
    real(r8), intent(in) :: landm(pcols)                   ! land fraction ramp
    real(r8), intent(in) :: sgh30(pcols)                   ! Std. deviation of 30 s orography for tms

    type(physics_state), intent(inout) :: state
    type(physics_tend ), intent(inout) :: tend
    type(physics_buffer_desc), pointer :: pbuf(:)

    type(cam_out_t),     intent(inout) :: cam_out
    type(cam_in_t),      intent(in)    :: cam_in


    !
    !---------------------------Local workspace-----------------------------
    !

    type(physics_ptend)   :: ptend            ! indivdual parameterization tendencies
    type(physics_state)   :: state_sc         ! state for sub-columns
    type(physics_ptend)   :: ptend_sc         ! ptend for sub-columns
    type(physics_ptend)   :: ptend_aero       ! ptend for microp_aero
    type(physics_tend)    :: tend_sc          ! tend for sub-columns

    integer :: nstep                          ! current timestep number

    real(r8) :: net_flx(pcols)

    real(r8) :: zdu(pcols,pver)               ! detraining mass flux from deep convection
    real(r8) :: cmfmc(pcols,pverp)            ! Convective mass flux--m sub c

    real(r8) cmfcme(pcols,pver)                ! cmf condensation - evaporation
    real(r8) cmfmc2(pcols,pverp)               ! Moist convection cloud mass flux
    real(r8) dlf(pcols,pver)                   ! Detraining cld H20 from shallow + deep convections
    real(r8) dlf2(pcols,pver)                  ! Detraining cld H20 from shallow convections
    real(r8) pflx(pcols,pverp)                 ! Conv rain flux thru out btm of lev
    real(r8) rtdt                              ! 1./ztodt

    integer lchnk                              ! chunk identifier
    integer ncol                               ! number of atmospheric columns
    integer ierr

    integer  i,k,m                             ! Longitude, level, constituent indices
    integer :: ixcldice, ixcldliq              ! constituent indices for cloud liquid and ice water.

    ! physics buffer fields to compute tendencies for stratiform package
    integer itim, ifld
    real(r8), pointer, dimension(:,:) :: cld        ! cloud fraction


    ! physics buffer fields for total energy and mass adjustment
    real(r8), pointer, dimension(:  ) :: teout
    real(r8), pointer, dimension(:,:) :: tini
    real(r8), pointer, dimension(:,:) :: qini
    real(r8), pointer, dimension(:,:) :: cldliqini
    real(r8), pointer, dimension(:,:) :: cldiceini
    real(r8), pointer, dimension(:,:) :: dtcore

    real(r8), pointer, dimension(:,:,:) :: fracis  ! fraction of transported species that are insoluble

    ! convective precipitation variables
    real(r8),pointer :: prec_dp(:)                ! total precipitation from ZM convection
    real(r8),pointer :: snow_dp(:)                ! snow from ZM convection
    real(r8),pointer :: prec_sh(:)                ! total precipitation from Hack convection
    real(r8),pointer :: snow_sh(:)                ! snow from Hack convection

    ! carma precipitation variables
    real(r8) :: prec_sed_carma(pcols)          ! total precip from cloud sedimentation (CARMA)
    real(r8) :: snow_sed_carma(pcols)          ! snow from cloud ice sedimentation (CARMA)

    ! stratiform precipitation variables
    real(r8),pointer :: prec_str(:)    ! sfc flux of precip from stratiform (m/s)
    real(r8),pointer :: snow_str(:)     ! sfc flux of snow from stratiform   (m/s)
    real(r8),pointer :: prec_pcw(:)     ! total precip from prognostic cloud scheme
    real(r8),pointer :: snow_pcw(:)     ! snow from prognostic cloud scheme
    real(r8),pointer :: prec_sed(:)     ! total precip from cloud sedimentation
    real(r8),pointer :: snow_sed(:)     ! snow from cloud ice sedimentation

    ! energy checking variables
    real(r8) :: zero(pcols)                    ! array of zeros
    real(r8) :: rliq(pcols)                    ! vertical integral of liquid not yet in q(ixcldliq)
    real(r8) :: rliq2(pcols)                   ! vertical integral of liquid from shallow scheme
    real(r8) :: det_s  (pcols)                 ! vertical integral of detrained static energy from ice
    real(r8) :: det_ice(pcols)                 ! vertical integral of detrained ice
    real(r8) :: flx_cnd(pcols)
    real(r8) :: flx_heat(pcols)
    type(check_tracers_data):: tracerint             ! energy integrals and cummulative boundary fluxes
    real(r8) :: zero_tracers(pcols,pcnst)

    logical   :: lq(pcnst)

    ! +++ ycw
    integer :: ideep(pcols)
    ! --- ycw

    !  pass macro to micro
    character(len=16) :: microp_scheme 
    character(len=16) :: macrop_scheme

    ! Debug physics_state.
    logical :: state_debug_checks

    call phys_getopts( microp_scheme_out      = microp_scheme, &
                       macrop_scheme_out      = macrop_scheme, &
                       state_debug_checks_out = state_debug_checks)
    
    !-----------------------------------------------------------------------
    call t_startf('bc_init')

    zero = 0._r8
    zero_tracers(:,:) = 0._r8

    lchnk = state%lchnk
    ncol  = state%ncol

    rtdt = 1._r8/ztodt

    nstep = get_nstep()


    ! Associate pointers with physics buffer fields
    itim = pbuf_old_tim_idx()
    ifld = pbuf_get_index('CLD')
    call pbuf_get_field(pbuf, ifld, cld, (/1,1,itim/),(/pcols,pver,1/))

    call pbuf_get_field(pbuf, teout_idx, teout, (/1,itim/), (/pcols,1/))

    call pbuf_get_field(pbuf, tini_idx, tini)
    call pbuf_get_field(pbuf, qini_idx, qini)
    call pbuf_get_field(pbuf, cldliqini_idx, cldliqini)
    call pbuf_get_field(pbuf, cldiceini_idx, cldiceini)

    ifld   =  pbuf_get_index('DTCORE')
    call pbuf_get_field(pbuf, ifld, dtcore, start=(/1,1,itim/), kount=(/pcols,pver,1/) )

    ifld    = pbuf_get_index('FRACIS')
    call pbuf_get_field(pbuf, ifld, fracis, start=(/1,1,1/), kount=(/pcols, pver, pcnst/)  )

    ! Set physics tendencies to 0
    tend %dTdt(:ncol,:pver)  = 0._r8
    tend %dudt(:ncol,:pver)  = 0._r8
    tend %dvdt(:ncol,:pver)  = 0._r8

    !
    ! Make sure that input tracers are all positive (otherwise,
    ! clybry_fam_adj will crash every few years).
    !

#ifdef MODAL_AERO
    call qneg3_modalx1( &
         'TPHYSBCb',lchnk  ,ncol    ,pcols   ,pver    , &
         1, pcnst, qmin  ,state%q, qneg3_worst_thresh_amode )
#else
    call qneg3('TPHYSBCb',lchnk  ,ncol    ,pcols   ,pver    , &
         1, pcnst, qmin  ,state%q )
#endif

    ! Validate state coming from the dynamics.
    if (state_debug_checks) &
         call physics_state_check(state, name="before tphysbc (dycore?)")

    call clybry_fam_adj( ncol, lchnk, map2chm, state%q, pbuf )

    ! Since clybry_fam_adj operates directly on the tracers, and has no
    ! physics_update call, re-run qneg3.

#ifdef MODAL_AERO
    call qneg3_modalx1( &
         'TPHYSBCc',lchnk  ,ncol    ,pcols   ,pver    , &
         1, pcnst, qmin  ,state%q, qneg3_worst_thresh_amode )
#else
    call qneg3('TPHYSBCc',lchnk  ,ncol    ,pcols   ,pver    , &
         1, pcnst, qmin  ,state%q )
#endif

    ! Validate output of clybry_fam_adj.
    if (state_debug_checks) &
         call physics_state_check(state, name="clybry_fam_adj")

    fracis (:ncol,:,1:pcnst) = 1._r8
    !
    ! Dump out "before physics" state
    !
    call diag_state_b4_phys_write (state)

    ! compute mass integrals of input tracers state
    call check_tracers_init(state, tracerint)

    call t_stopf('bc_init')

    !===================================================
    ! Global mean total energy fixer
    !===================================================
    call t_startf('energy_fixer')

    !*** BAB's FV heating kludge *** save the initial temperature
    tini(:ncol,:pver) = state%t(:ncol,:pver)
    if (dycore_is('LR')) then
       call check_energy_fix(state, ptend, nstep, flx_heat)
       call physics_update(state, ptend, ztodt, tend)
       call check_energy_chng(state, tend, "chkengyfix", nstep, ztodt, zero, zero, zero, flx_heat)
    end if
    ! Save state for convective tendency calculations.
    call diag_conv_tend_ini(state, pbuf)

    call cnst_get_ind('CLDLIQ', ixcldliq)
    call cnst_get_ind('CLDICE', ixcldice)
    qini     (:ncol,:pver) = state%q(:ncol,:pver,       1)
    cldliqini(:ncol,:pver) = state%q(:ncol,:pver,ixcldliq)
    cldiceini(:ncol,:pver) = state%q(:ncol,:pver,ixcldice)


    call outfld('TEOUT', teout       , pcols, lchnk   )
    call outfld('TEINP', state%te_ini, pcols, lchnk   )
    call outfld('TEFIX', state%te_cur, pcols, lchnk   )

    ! set and output the dse change due to dynpkg
    if( nstep > pbuf_times-1 ) then
       do k = 1,pver
          dtcore(:ncol,k) = (tini(:ncol,k) - dtcore(:ncol,k))/(ztodt) + tend%dTdt(:ncol,k)
       end do
       call outfld( 'DTCORE', dtcore, pcols, lchnk )
    end if

    call t_stopf('energy_fixer')
    !
    !===================================================
    ! Dry adjustment
    ! This code block is not a good example of interfacing a parameterization
    !===================================================
    call t_startf('dry_adjustment')

    ! Copy state info for input to dadadj
    ! This is a kludge, so that dadadj does not have to be correctly reformulated in dry static energy

    lq(:) = .FALSE.
    lq(1) = .TRUE.
    call physics_ptend_init(ptend, state%psetcols, 'dadadj', ls=.true., lq=lq)
    ptend%s(:ncol,:pver)   = state%t(:ncol,:pver)
    ptend%q(:ncol,:pver,1) = state%q(:ncol,:pver,1)

    call dadadj (lchnk, ncol, state%pmid,  state%pint,  state%pdel,  &
         ptend%s, ptend%q(1,1,1))
    ptend%s(:ncol,:)   = (ptend%s(:ncol,:)   - state%t(:ncol,:)  )/ztodt * cpair
    ptend%q(:ncol,:,1) = (ptend%q(:ncol,:,1) - state%q(:ncol,:,1))/ztodt
    call physics_update(state, ptend, ztodt, tend)

    call t_stopf('dry_adjustment')
    !
    !===================================================
    ! Moist convection
    !===================================================
    call t_startf('moist_convection')
    !
    ! Since the PBL doesn't pass constituent perturbations, they
    ! are zeroed here for input to the moist convection routine
    !
    call t_startf ('convect_deep_tend')
    call convect_deep_tend(  &
         cmfmc,      cmfcme,             &
         dlf,        pflx,    zdu,       &
         rliq,    &
         ztodt,   &
    ! +++ ycw
         state,   ptend, cam_in%landfrac, pbuf, ideep)
    !     state,   ptend, cam_in%landfrac, pbuf)  ! default
    ! --- ycw
    call t_stopf('convect_deep_tend')

    call physics_update(state, ptend, ztodt, tend)

    call pbuf_get_field(pbuf, prec_dp_idx, prec_dp )
    call pbuf_get_field(pbuf, snow_dp_idx, snow_dp )
    call pbuf_get_field(pbuf, prec_sh_idx, prec_sh )
    call pbuf_get_field(pbuf, snow_sh_idx, snow_sh )
    call pbuf_get_field(pbuf, prec_str_idx, prec_str )
    call pbuf_get_field(pbuf, snow_str_idx, snow_str )
    call pbuf_get_field(pbuf, prec_sed_idx, prec_sed )
    call pbuf_get_field(pbuf, snow_sed_idx, snow_sed )

    ! Check energy integrals, including "reserved liquid"
    flx_cnd(:ncol) = prec_dp(:ncol) + rliq(:ncol)
    call check_energy_chng(state, tend, "convect_deep", nstep, ztodt, zero, flx_cnd, snow_dp, zero)

    !
    ! Call Hack (1994) convection scheme to deal with shallow/mid-level convection
    !
    call t_startf ('convect_shallow_tend')

    ! +++ Yi-Chi : Oct 2014 ++++
    !call convect_shallow_tend (ztodt   , cmfmc,  cmfmc2  ,&
    !     dlf        , dlf2   ,  rliq   , rliq2, & 
    !     state      , ptend  ,  pbuf)
    call convect_shallow_tend (ztodt   , cmfmc,  cmfmc2  ,&
         dlf        , dlf2   ,  rliq   , rliq2, &
         state      , ptend  ,  pbuf, & !)
! cjshiu add three additional parameters needed by HP2011
         cam_in%landfrac, cam_in%shf, cam_in%cflx, ideep)
!cjshiu addEND
    ! ++++++++++++++++++++++++
    call t_stopf ('convect_shallow_tend')

    call physics_update(state, ptend, ztodt, tend)

    flx_cnd(:ncol) = prec_sh(:ncol) + rliq2(:ncol)
    call check_energy_chng(state, tend, "convect_shallow", nstep, ztodt, zero, flx_cnd, snow_sh, zero)

    call check_tracers_chng(state, tracerint, "convect_shallow", nstep, ztodt, zero_tracers)

    call t_stopf('moist_convection')

    ! Rebin the 4-bin version of sea salt into bins for coarse and accumulation
    ! modes that correspond to the available optics data.  This is only necessary
    ! for CAM-RT.  But it's done here so that the microphysics code which is called
    ! from the stratiform interface has access to the same aerosols as the radiation
    ! code.
    call sslt_rebin_adv(pbuf,  state)
    
    !===================================================
    ! Calculate tendencies from CARMA bin microphysics.
    !===================================================
    !
    ! If CARMA is doing detrainment, then on output, rliq no longer represents water reserved
    ! for detrainment, but instead represents potential snow fall. The mass and number of the
    ! snow are stored in the physics buffer and will be incorporated by the MG microphysics.
    !
    ! Currently CARMA cloud microphysics is only supported with the MG microphysics.
    call t_startf('carma_timestep_tend')

    if (carma_do_cldice .or. carma_do_cldliq) then
       call carma_timestep_tend(state, cam_in, cam_out, ptend, ztodt, pbuf, dlf=dlf, rliq=rliq, &
            prec_str=prec_str, snow_str=snow_str, prec_sed=prec_sed_carma, snow_sed=snow_sed_carma)
       call physics_update(state, ptend, ztodt, tend)

       ! Before the detrainment, the reserved condensate is all liquid, but if CARMA is doing
       ! detrainment, then the reserved condensate is snow.
       if (carma_do_detrain) then
          call check_energy_chng(state, tend, "carma_tend", nstep, ztodt, zero, prec_str+rliq, snow_str+rliq, zero)
       else
          call check_energy_chng(state, tend, "carma_tend", nstep, ztodt, zero, prec_str, snow_str, zero)
       end if
    end if

    call t_stopf('carma_timestep_tend')

    if( microp_scheme == 'RK' ) then

       !===================================================
       ! Calculate stratiform tendency (sedimentation, detrain, cloud fraction and microphysics )
       !===================================================
       call t_startf('stratiform_tend')

       call stratiform_tend(state, ptend, pbuf, ztodt, &
            cam_in%icefrac, cam_in%landfrac, cam_in%ocnfrac, &
            landm, cam_in%snowhland, & ! sediment
            dlf, dlf2, & ! detrain
            rliq  , & ! check energy after detrain
            cmfmc,   cmfmc2, &
            cam_in%ts,      cam_in%sst,        zdu)

       call physics_update(state, ptend, ztodt, tend)
       call check_energy_chng(state, tend, "cldwat_tend", nstep, ztodt, zero, prec_str, snow_str, zero)

       call t_stopf('stratiform_tend')

    elseif( microp_scheme == 'MG' ) then

       !===================================================
       ! Calculate macrophysical tendency (sedimentation, detrain, cloud fraction)
       !===================================================

       call t_startf('macrop_tend')

       ! don't call Park macrophysics if CLUBB is called
       if (macrop_scheme .ne. 'CLUBB_SGS') then

          call macrop_driver_tend(state, ptend, ztodt, &
               cam_in%landfrac, cam_in%ocnfrac, &
               cam_in%snowhland, & ! sediment
               dlf, dlf2, & ! detrain
               cmfmc,   cmfmc2, &
               cam_in%ts,      cam_in%sst, zdu,  pbuf, &
               det_s, det_ice)

          !  Since we "added" the reserved liquid back in this routine, we need 
	  !    to account for it in the energy checker
          flx_cnd(:ncol) = -1._r8*rliq(:ncol) 
	  flx_heat(:ncol) = det_s(:ncol)
          
          call physics_update(state, ptend, ztodt, tend)
          call check_energy_chng(state, tend, "macrop_tend", nstep, ztodt, zero, flx_cnd, det_ice, flx_heat)
       
       else ! Calculate CLUBB macrophysics

          ! =====================================================
          !    CLUBB call (PBL, shallow convection, macrophysics)
          ! =====================================================  
   
          call clubb_tend_cam(state,ptend,pbuf,1.0_r8*ztodt,&
             cmfmc, cmfmc2, cam_in, sgh30, dlf, det_s, det_ice)

          !  Since we "added" the reserved liquid back in this routine, we need 
	  !    to account for it in the energy checker
          flx_cnd(:ncol) = -1._r8*rliq(:ncol) 
	  flx_heat(:ncol) = cam_in%shf(:ncol) + det_s(:ncol)

          !    Update physics tendencies and copy state to state_eq, because that is 
          !      input for microphysics              
          call physics_update(state, ptend, ztodt, tend)
          call check_energy_chng(state, tend, "clubb_tend", nstep, ztodt, cam_in%lhf/latvap, flx_cnd, det_ice, flx_heat)
 
       endif 

       call t_stopf('macrop_tend') 

       !===================================================
       ! Calculate cloud microphysics 
       !===================================================

       call t_startf('microp_aero_run')
       call microp_aero_run(state, ptend_aero, ztodt, pbuf)
       call t_stopf('microp_aero_run')

       call t_startf('microp_tend')

       call microp_driver_tend( &
            state, ptend, ztodt, pbuf)

       ! combine aero and micro tendencies
       call physics_ptend_sum(ptend_aero, ptend, ncol)

       call physics_update(state, ptend, ztodt, tend)
       call check_energy_chng(state, tend, "microp_tend", nstep, ztodt, zero, prec_str, snow_str, zero)

       call physics_ptend_dealloc(ptend_aero)
       call t_stopf('microp_tend')

    endif

    ! Add the precipitation from CARMA to the precipitation from stratiform.
    if (carma_do_cldice .or. carma_do_cldliq) then
       prec_sed(:ncol) = prec_sed(:ncol) + prec_sed_carma(:ncol)
       snow_sed(:ncol) = snow_sed(:ncol) + snow_sed_carma(:ncol)
    end if

    if ( .not. deep_scheme_does_scav_trans() ) then

       !===================================================
       !  Aerosol wet chemistry determines scavenging fractions, and transformations
       !
       !
       !  Then do convective transport of all trace species except water vapor and
       !     cloud liquid and ice (we needed to do the scavenging first
       !     to determine the interstitial fraction) 
       !===================================================

       call t_startf('bc_aerosols')
       call aerosol_wet_intr (state, ptend, ztodt, pbuf,  cam_out, dlf)
       call physics_update(state, ptend, ztodt, tend)

       if (carma_do_wetdep) then
          ! CARMA wet deposition
          !
          ! NOTE: It needs to follow aerosol_drydep_intr, so that cam_out%xxxwetxxx
          ! fields have already been set for CAM aerosols and cam_out can be added
          ! to for CARMA aerosols.
          call t_startf ('carma_wetdep_tend')
          call carma_wetdep_tend(state, ptend, ztodt, pbuf, dlf, cam_out)
          call physics_update(state, ptend, ztodt, tend)
          call t_stopf ('carma_wetdep_tend')
       end if

       call t_startf ('convect_deep_tend2')
       call convect_deep_tend_2( state,   ptend,  ztodt,  pbuf ) 
       call t_stopf ('convect_deep_tend2')

       call physics_update(state, ptend, ztodt, tend)

       ! check tracer integrals
       call check_tracers_chng(state, tracerint, "cmfmca", nstep, ztodt,  zero_tracers)

       call t_stopf('bc_aerosols')

   endif

    !===================================================
    ! Moist physical parameteriztions complete: 
    ! send dynamical variables, and derived variables to history file
    !===================================================

    call t_startf('bc_history_write')
    call diag_phys_writeout(state, cam_out%psl)
    call diag_conv(state, ztodt, pbuf)

    call t_stopf('bc_history_write')

    !===================================================
    ! Write cloud diagnostics on history file
    !===================================================

    call t_startf('bc_cld_diag_history_write')

    call cloud_diagnostics_calc(state, pbuf)

    call t_stopf('bc_cld_diag_history_write')

    !===================================================
    ! Radiation computations
    !===================================================
    call t_startf('radiation')

    call radiation_tend(state,ptend, pbuf, &
         cam_out, cam_in, &
         cam_in%landfrac,landm,cam_in%icefrac, cam_in%snowhland, &
         fsns,    fsnt, flns,    flnt,  &
         fsds, net_flx)

    ! Set net flux used by spectral dycores
    do i=1,ncol
       tend%flx_net(i) = net_flx(i)
    end do
    call physics_update(state, ptend, ztodt, tend)
    call check_energy_chng(state, tend, "radheat", nstep, ztodt, zero, zero, zero, net_flx)

    call t_stopf('radiation')

    ! Diagnose the location of the tropopause and its location to the history file(s).
    call t_startf('tropopause')
    call tropopause_output(state)
    call t_stopf('tropopause')

    ! Save atmospheric fields to force surface models
    call t_startf('cam_export')
    call cam_export (state,cam_out,pbuf)
    call t_stopf('cam_export')

    ! Write export state to history file
    call t_startf('diag_export')
    call diag_export(cam_out)
    call t_stopf('diag_export')

end subroutine tphysbc

subroutine phys_timestep_init(phys_state, cam_out, pbuf2d)
!-----------------------------------------------------------------------------------
!
! Purpose: The place for parameterizations to call per timestep initializations.
!          Generally this is used to update time interpolated fields from boundary
!          datasets.
!
!-----------------------------------------------------------------------------------
  use shr_kind_mod,        only: r8 => shr_kind_r8
  use chemistry,           only: chem_timestep_init
  use chem_surfvals,       only: chem_surfvals_set
  use physics_types,       only: physics_state
  use physics_buffer,      only: physics_buffer_desc
  use carma_intr,          only: carma_timestep_init
  use ghg_data,            only: ghg_data_timestep_init
  use cam3_aero_data,      only: cam3_aero_data_on, cam3_aero_data_timestep_init
  use cam3_ozone_data,     only: cam3_ozone_data_on, cam3_ozone_data_timestep_init
  use radiation,           only: radiation_do
  use tracers,             only: tracers_timestep_init
  use aoa_tracers,         only: aoa_tracers_timestep_init
  use vertical_diffusion,  only: vertical_diffusion_ts_init
  use radheat,             only: radheat_timestep_init
  use solar_data,          only: solar_data_advance
  use efield,              only: get_efield
#if ( defined WACCM_PHYS )
  use iondrag,             only: do_waccm_ions
  use qbo,                 only: qbo_timestep_init
#endif
  use perf_mod

  use prescribed_ozone,    only: prescribed_ozone_adv
  use prescribed_ghg,      only: prescribed_ghg_adv
  use prescribed_aero,     only: prescribed_aero_adv
  use aerodep_flx,         only: aerodep_flx_adv
  use aircraft_emit,       only: aircraft_emit_adv
  use prescribed_volcaero, only: prescribed_volcaero_adv
  ! +++ Nudging +++ !
  use nudging,             only: Nudge_Model,nudging_timestep_init
  ! --------------- !

  implicit none

  type(physics_state), intent(inout), dimension(begchunk:endchunk) :: phys_state
  type(cam_out_t),     intent(inout), dimension(begchunk:endchunk) :: cam_out
  
  type(physics_buffer_desc), pointer                 :: pbuf2d(:,:)

  !-----------------------------------------------------------------------------

  ! Chemistry surface values
  call chem_surfvals_set(phys_state)

  ! Solar irradiance
  call solar_data_advance()

  ! Time interpolate for chemistry.
  call chem_timestep_init(phys_state, pbuf2d)

  ! Prescribed tracers
  call prescribed_ozone_adv(phys_state, pbuf2d)
  call prescribed_ghg_adv(phys_state, pbuf2d)
  call prescribed_aero_adv(phys_state, pbuf2d)
  call aircraft_emit_adv(phys_state, pbuf2d)
  call prescribed_volcaero_adv(phys_state, pbuf2d)

  ! prescribed aerosol deposition fluxes
  call aerodep_flx_adv(phys_state, pbuf2d, cam_out)

  ! CAM3 prescribed aerosol masses
  if (cam3_aero_data_on) call cam3_aero_data_timestep_init(pbuf2d,  phys_state)

  ! CAM3 prescribed ozone data
  if (cam3_ozone_data_on) call cam3_ozone_data_timestep_init(pbuf2d,  phys_state)

  ! Time interpolate data models of gasses in pbuf2d
  call ghg_data_timestep_init(pbuf2d,  phys_state)

  ! Upper atmosphere radiative processes
  call radheat_timestep_init(phys_state, pbuf2d)
 
  ! Time interpolate for vertical diffusion upper boundary condition
  call vertical_diffusion_ts_init(pbuf2d, phys_state)

#if ( defined WACCM_PHYS )
  if (do_waccm_ions) then
     ! Compute the electric field
     call t_startf ('efield')
     call get_efield
     call t_stopf ('efield')
  endif
  !----------------------------------------------------------------------
  ! update QBO data for this time step
  !----------------------------------------------------------------------
  call qbo_timestep_init
#endif

  call carma_timestep_init()

  ! Time interpolate for tracers, if appropriate
  call tracers_timestep_init(phys_state)

  ! age of air tracers
  call aoa_tracers_timestep_init(phys_state)

  ! +++ Nudging code +++ !
  ! Update Nudging values, if needed
  !----------------------------------
  if(Nudge_Model) call nudging_timestep_init(phys_state)
  ! -------------------- !

end subroutine phys_timestep_init

end module physpkg
                                                                                                                                                                                                                                                                                                                                                                                                                                                                           ././@LongLink                                                                                       0000000 0000000 0000000 00000000177 00000000000 011572  L                                                                                                    ustar   root                            root                                                                                                                                                                                                                   chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.cam/namelist_definition.xml                                                                                                                                                                                                                                                                                                                                                                                                  chia_cluster/home/ychwang/01-PROJ_CAUSE/Cases/f09.F2000C5.TaiESM.NUDGE.ICITM.UVonly/SourceMods/src.c0000644 0143640 0000777 00000621542 12573012446 030574  0                                                                                                    ustar   ychwang                         lccr                                                                                                                                                                                                                   <?xml version="1.0"?>

<?xml-stylesheet type="text/xsl" href="http://www.cgd.ucar.edu/~cam/namelist/namelist_definition_CAM.xsl"?>

<namelist_definition>

<!-- Each namelist variable is defined in an <entry> element.  The
     content of the element is the documentation of how the variable is
     used.  Other aspects of the variable's definition are expressed as
     attributes of the <entry> element.  Note that it is an XML requirement
     that the attribute values are enclosed in quotes.  The attributes are:

     id
          The variable's name.  *** N.B. *** The name must be lower case.
          The module convert all namelist variable names to lower case
          since Fortran is case insensitive.

     type
          An abbreviation of the fortran declaration for the variable.
	  Valid declarations are:

          char*n  
	  integer
	  logical
	  real

	  Any of these types may be followed by a comma separated list of
	  integers enclosed in parenthesis to indicate an array.

	  The current namelist validation code only distinquishes between
	  string and non-string types.

     input_pathname
          Only include this attribute to indicate that the variable
          contains the pathname of an input dataset that resides in the
          CCSM inputdata directory tree.  Note that the variables
          containing the names of restart files that are used in branch
          runs don't reside in the inputdata tree and should not be given
          this attribute.

	  The recognized values are "abs" to indicate that an absolute
          pathname is required, or "rel:var_name" to indicate that the
          pathname is relative and that the namelist variable "var_name"
          contains the absolute root directory.

     category
          A category assigned for organizing the documentation.

     group
          The namelist group that the variable is declared in.

     valid_values
          This is an optional attribute that is mainly useful for variables
          that have only a small number of allowed values.

                                                                        -->

<!-- Nudging Parameters -->

<entry id="Nudge_Model" type="logical" category="nudging"
       group="nudging_nl" valid_values="" >
       Toggle Model Nudging ON/OFF.
       Default: FALSE
       </entry>

<entry id="Nudge_Path" type="char*256" input_pathname="abs" category="nudging"
       group="nudging_nl" valid_values="" >
       Full pathname of analyses data to use for nudging.
       Default: none
       </entry>

<entry id="Nudge_File_Template" type="char*80" category="nudging"
       group="nudging_nl" valid_values="" >
       Template for Nudging analyses file names.
       Default: none
       </entry>

<entry id="Nudge_Force_Opt" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Select the form of nudging forcing.
       Default: none
       </entry>

<entry id="Nudge_Diag_Opt" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Select the nudging diagnostic output option.
       Default: none
       </entry>

<entry id="Nudge_Times_Per_Day" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Number of analyses files per day.
       Default: none
       </entry>

<entry id="Model_Times_Per_Day" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Number of time to update model data per day.
       Default: none
       </entry>

<entry id="Nudge_Uprof" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Profile index for U nudging.
       Default: none
       </entry>

<entry id="Nudge_Ucoef" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Coeffcient for U nudging.
       Default: none
       </entry>

<entry id="Nudge_Vprof" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Profile index for V nudging.
       Default: none
       </entry>

<entry id="Nudge_Vcoef" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Coeffcient for V nudging.
       Default: none
       </entry>

<entry id="Nudge_Tprof" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Profile index for T nudging.
       Default: none
       </entry>

<entry id="Nudge_Tcoef" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Coeffcient for T nudging.
       Default: none
       </entry>

<entry id="Nudge_Qprof" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Profile index for Q nudging.
       Default: none
       </entry>

<entry id="Nudge_Qcoef" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Coeffcient for Q nudging.
       Default: none
       </entry>

<entry id="Nudge_PSprof" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Profile index for PS nudging.
       Default: none
       </entry>

<entry id="Nudge_PScoef" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Coeffcient for PS nudging.
       Default: none
       </entry>

<entry id="Nudge_Beg_Year" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Year at which Nudging Begins.
       Default: none
       </entry>

<entry id="Nudge_Beg_Month" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Month at which Nudging Begins.
       Default: none
       </entry>

<entry id="Nudge_Beg_Day" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Day at which Nudging Begins.
       Default: none
       </entry>

<entry id="Nudge_End_Year" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Year at which Nudging Ends.
       Default: none
       </entry>

<entry id="Nudge_End_Month" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Month at which Nudging Ends.
       Default: none
       </entry>

<entry id="Nudge_End_Day" type="integer" category="nudging"
       group="nudging_nl" valid_values="" >
       Day at which Nudging Ends.
       Default: none
       </entry>

<entry id="Nudge_Hwin_lo" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       LOW Coeffcient for Horizontal Window.
       Default: none
       </entry>

<entry id="Nudge_Hwin_hi" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       HIGH Coeffcient for Horizontal Window.
       Default: none
       </entry>

<entry id="Nudge_Hwin_lat0" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       LAT0 of Horizonalt Window.
       Default: none
       </entry>

<entry id="Nudge_Hwin_latWidth" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Width of LAT Window.
       Default: none
       </entry>

<entry id="Nudge_Hwin_latDelta" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Steepness of LAT Window.
       Default: none
       </entry>

<entry id="Nudge_Hwin_lon0" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       LON0 of Horizontal Window.
       Default: none
       </entry>

<entry id="Nudge_Hwin_lonWidth" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Width of LON Window.
       Default: none
       </entry>

<entry id="Nudge_Hwin_lonDelta" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Steepness of LON Window.
       Default: none
       </entry>

<entry id="Nudge_Vwin_lo" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       LOW Coeffcient for Vertical Window.
       Default: none
       </entry>

<entry id="Nudge_Vwin_hi" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       HIGH Coeffcient for Vertical Window.
       Default: none
       </entry>


<entry id="Nudge_Vwin_Hindex" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       HIGH Level Index for Verical Window.
       Default: none
       </entry>

<entry id="Nudge_Vwin_Hdelta" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Steepness of HIGH end of Vertical Window.
       Default: none
       </entry>

<entry id="Nudge_Vwin_Lindex" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       LOW Level Index for Verical Window.
       Default: none
       </entry>

<entry id="Nudge_Vwin_Ldelta" type="real" category="nudging"
       group="nudging_nl" valid_values="" >
       Steepness of LOW end of Vertical Window.
       Default: none
       </entry>


<!-- Aerosols: Data (CAM version) -->

<entry id="bndtvaer" type="char*256" input_pathname="abs" category="aero_data_cam"
       group="cam3_aero_data_nl" valid_values="" >
Full pathname of time-variant boundary dataset for aerosol masses.
Default: set by build-namelist.
</entry>

<entry id="cam3_aero_data_on" type="logical" category="aero_data_cam"
       group="cam3_aero_data_nl" valid_values="" >
Add CAM3 prescribed aerosols to the physics buffer.
Default: FALSE
</entry>

<!-- Coupler between Physics and Dynamics -->

<entry id="phys_alltoall" type="integer"  category="perf_dp_coup"
       group="cam_inparm" valid_values="0,1,2,11,12,13">
Dynamics/physics transpose method for nonlocal load-balance.  0: use
mpi_alltoallv. 1: use point-to-point MPI-1 two-sided implementation. 2: use
point-to-point MPI-2 one-sided implementation if supported, otherwise use
MPI-1 implementation. 3: use Co-Array Fortran implementation if supported,
otherwise use MPI-1 implementation. 11-13: use mod_comm, choosing any of
several methods internal to mod_comm.  The method within mod_comm (denoted
mod_method) has possible values 0,1,2 and is set according to mod_method =
phys_alltoall - modmin_alltoall, where modmin_alltoall is 11. -1: use 
option 1 when each process communicates with less than half of the other 
processes, otherwise use option 0 (approx.).
Default: -1
</entry>

<entry id="phys_chnk_per_thd" type="integer"  category="perf_dp_coup"
       group="cam_inparm" valid_values="">
Select target number of chunks per thread.  Must be positive.
Default: 1
</entry>

<entry id="phys_loadbalance" type="integer"  category="perf_dp_coup"
       group="cam_inparm" valid_values="">
Physics grid decomposition options.
-1: each chunk is a dynamics block.
 0: chunk definitions and assignments do not require interprocess comm.
 1: chunk definitions and assignments do not require internode comm.
 2: optimal diurnal, seasonal, and latitude load-balanced chunk definition and assignments.
 3: chunk definitions and assignments only require communication with one other process.
 4: concatenated blocks, no load balancing, no interprocess communication.
Default: 0
</entry>

<entry id="phys_twin_algorithm" type="integer"  category="perf_dp_coup"
       group="cam_inparm" valid_values="">
Physics grid decomposition options.
 0: assign columns to chunks as single columns, wrap mapped across chunks
 1: use (day/night; north/south) twin algorithm to determine load-balanced pairs of
      columns and assign columns to chunks in pairs, wrap mapped
Default: 0 for unstructured grid dycores, 1 for lat/lon grid dycores
</entry>

<!-- Diagnostics -->

<entry id="history_amwg" type="logical"  category="diagnostics"
       group="phys_ctl_nl" valid_values="" >
Switch for diagnostic output of AMWG diag package variables
Default: .true.
</entry>

<entry id="diag_cnst_conv_tend" type="char*8"  category="diagnostics"
       group="cam_diag_opts" valid_values="none,q_only,all" >
Output constituent tendencies due to convection.  Set to
'none', 'q_only' or 'all'.
Default: 'q_only', but 'none' for WACCM configurations.
</entry>

<entry id="do_circulation_diags" type="logical"  category="diagnostics"
       group="circ_diag_nl" valid_values="" >
Turns on TEM circulation diagnostics history output.  Only valid for FV dycore.

Default: .true. for WACCM with interactive chemistry, otherwise .false.
</entry>

<entry id="print_energy_errors" type="logical"  category="diagnostics"
       group="cam_inparm" valid_values="" >
Turn on verbose output identifying columns that fail energy/water 
conservation checks.
Default: FALSE
</entry>

<!-- Dry Convective Adjustment -->

<entry id="nlvdry" type="integer"  category="dry_conv_adj"
       group="cam_inparm" valid_values="" >
Number of layers from the top of the model over which to do dry convective
adjustment. Must be less than plev (the number of vertical levels).
Default: 3
</entry>

<!-- Dynamics: Finite Volume -->

<entry id="ct_overlap" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="" >
Overlapping of trac2d and cd_core subcycles.
Default: 0
</entry>

<entry id="fft_flt" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="0,1" >
1 for FFT filter always, 0 for combined algebraic/FFT filter.  The value 0
is used for CAM3, otherwise it is using the value 1.  In the CAM3
version of the model it was necessary to build with the CPP
variable ALT_PFT defined to get the behavior now obtained by setting fft_flt=1.
Default: set by build-namelist
</entry>

<entry id="div24del2flag" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="2,4,42" >
Chooses type of divergence damping and velocity diffusion.
div24del2flag = 2 for ldiv2 (default),
              = 4 for ldiv4,
              = 42 for ldiv4 + ldel2
where
ldiv2: 2nd-order divergence damping everywhere and increasing in top layers
ldiv4: 4th-order divergence damping
ldel2: 2nd-order velocity-component damping targetted to top layers,
       with coefficient del2coef

Default: set by build-namelist
</entry>

<entry id="del2coef" type="real"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="" >
Chooses level of velocity diffusion.
Default: 3.0e5
</entry>

<entry id="filtcw" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="0,1" >
Enables optional filter for intermediate c-grid winds, (courtesy of Bill Putman).
Default: 0
</entry>

<entry id="force_2d" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Set to 1 to force the 2D transpose computation when a 1D decomposition is
used.  This is intended for debugging purposes only.
Default: 0
</entry>

<entry id="geopktrans" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="0,1,2" >
Geopotential method (routines geopk, geopk16, or geopk_d).
0 for transpose method, 1 for method using semi-global z communication 
with optional 16-byte arithmetic, 2 for method using local
z communication; method 0, method 1 with 16-byte arithmetic and method 2 
are all bit-for-bit across decompositions; method 0 scales better than 
method 1 with npr_z, and method 1 is superior to method 0 for small npr_z.
The optimum speed is attained using either method 1 with 8-byte 
arithmetic (standard for geopk16) or method 2 when utilizing the 
optimal value for the associated parameter geopkblocks; for the last 
two subcycles of a timestep, method 0 is automatically used; see 
geopk.F90 and cd_core.F90.

Default: 0
</entry>

<entry id="geopkblocks" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Geopotential method 2 pipeline parameter (routine geopk_d).
geopk_d implements a pipeline algorithm by dividing the 
information that must be moved between processes into blocks. geopkblocks
specifies the number of blocks to use. The larger the number of blocks,
the greater the opportunity for overlapping communication with computation
and for decreasing instantaneous bandwidth requirements. The smaller the
number of blocks, the fewer MPI messages sent, decreasing MPI total latency.
See geopk_d within geopk.F90.
Default: 1
</entry>

<entry id="modc_sw_dynrun" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Mod_comm irregular underlying communication method for dyn_run/misc.
0 for original mp_sendirr/mp_recvirr
1 for mp_swapirr and a point-to-point implementation of communication pattern
2 for mp_swapirr and a collective (MPI_Alltoallv) implementation of communication pattern
Default: 0
</entry>

<entry id="modc_hs_dynrun" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for mod_comm irregular communication handshaking for dyn_run/misc
Default: .true.
</entry>

<entry id="modc_send_dynrun" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for mod_comm irregular communication blocking send for dyn_run/misc,
false for nonblocking send
Default: .true.
</entry>

<entry id="modc_mxreq_dynrun" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Maximum number of outstanding nonblocking MPI requests to allow when
using mp_swapirr and point-to-point communications for dyn_run/misc. 
Setting this less than the maximum can improve robustness for large process 
count runs. If set to less than zero, then do not limit the number of
outstanding send/receive requests.
Default: -1 (so no limit)
</entry>

<entry id="modc_sw_cdcore" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Mod_comm irregular underlying communication method for cd_core/geopk
0 for original mp_sendirr/mp_recvirr
1 for mp_swapirr and a point-to-point implementation of communication pattern
2 for mp_swapirr and a collective (MPI_Alltoallv) implementation of communication pattern
Default: 0
</entry>

<entry id="modc_hs_cdcore" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for mod_comm irregular communication handshaking for cd_core/geopk
Default: .true.
</entry>

<entry id="modc_send_cdcore" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for geopk_d and mod_comm irregular communication blocking send for 
cd_core/geopk; false for nonblocking send.
Default: .true.
</entry>

<entry id="modc_mxreq_cdcore" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Maximum number of outstanding nonblocking MPI requests to allow when
using mp_swapirr and point-to-point communications for cd_core/geopk.
Setting this less than the maximum can improve robustness for large process 
count runs. If set to less than zero, then do not limit the number of
outstanding send/receive requests.
Default: -1 (so no limit)
</entry>

<entry id="modc_sw_gather" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Mod_comm irregular underlying communication method for gather
0 for original mp_sendirr/mp_recvirr
1 for mp_swapirr and a point-to-point implementation of communication pattern
2 for mp_swapirr and a collective (MPI_Alltoallv) implementation of communication pattern
Default: 0
</entry>

<entry id="modc_hs_gather" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for mod_comm irregular communication handshaking for gather
Default: .true.
</entry>

<entry id="modc_send_gather" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for mod_comm irregular communication blocking send for gather,
false for nonblocking send
Default: .true.
</entry>

<entry id="modc_mxreq_gather" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Maximum number of outstanding nonblocking MPI requests to allow when
using mp_swapirr and point-to-point communications for gather.
Setting this less than the maximum can improve robustness for large process 
count runs. If set to less than zero, then do not limit the number of
outstanding send/receive requests.
Default: -1 (so no limit)
</entry>

<entry id="modc_sw_scatter" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Mod_comm irregular underlying communication method for scatter
0 for original mp_sendirr/mp_recvirr
1 for mp_swapirr and a point-to-point implementation of communication pattern
2 for mp_swapirr and a collective (MPI_Alltoallv) implementation of communication pattern
Default: 0
</entry>

<entry id="modc_hs_scatter" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for mod_comm irregular communication handshaking for scatter
Default: .true.
</entry>

<entry id="modc_send_scatter" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for mod_comm irregular communication blocking send for scatter,
false for nonblocking send
Default: .true.
</entry>

<entry id="modc_mxreq_scatter" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Maximum number of outstanding nonblocking MPI requests to allow when
using mp_swapirr and point-to-point communications for scatter.
Setting this less than the maximum can improve robustness for large process 
count runs. If set to less than zero, then do not limit the number of
outstanding send/receive requests.
Default: -1 (so no limit)
</entry>

<entry id="modc_sw_tracer" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Mod_comm irregular underlying communication method for multiple tracers
0 for original mp_sendtrirr/mp_recvtrirr
1 for mp_swaptrirr and point-to-point communications
2 for mp_swaptrirr and all-to-all communications
Default: 0
</entry>

<entry id="modc_hs_tracer" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for mod_comm irregular communication handshaking for multiple tracers
Default: .true.
</entry>

<entry id="modc_send_tracer" type="logical"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
True for mod_comm irregular communication blocking send for multiple
tracers, false for nonblocking send
Default: .true.
</entry>

<entry id="modc_mxreq_tracer" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Maximum number of outstanding nonblocking MPI requests to allow when
using mp_swaptrirr and point-to-point communications for multiple tracers.
Setting this less than the maximum can improve robustness for large process 
count runs. If set to less than zero, then do not limit the number of
outstanding send/receive requests.
Default: -1 (so no limit)
</entry>

<entry id="modc_onetwo" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
One or two simultaneous mod_comm irregular communications (excl. tracers)
Default: 1
</entry>

<entry id="modc_tracers" type="integer"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
Max number of tracers for simultaneous mod_comm irregular communications
Default: 1
</entry>

<entry id="iord" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="" >
Order (mode) of X interpolation (1,..,6).
East-West transport scheme (used with Finite Volume dynamical core only).
Default: 4
</entry>

<entry id="jord" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="" >
Order (mode) of Y interpolation (1,..,6).
North-South transport scheme (used with Finite Volume dynamical core only).
Default: 4
</entry>

<entry id="kord" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="" >
Scheme to be used for vertical mapping.
Default: 4
</entry>

<entry id="modcomm_gatscat" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="0,1,2" >
For mod_comm gather/scatters, 0 for temporary contiguous buffers; 1 for mpi derived
types.
Default: 0
</entry>

<entry id="modcomm_geopk" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="0,1,2" >
For geopk (geopktrans=1) messages, 0 for temporary contiguous buffers; 1 for mpi derived
types.
Default: 0
</entry>

<entry id="modcomm_transpose" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="0,1,2" >
For mod_comm transposes, 0 for temporary contiguous buffers; 1 for mpi derived
types.
Default: 0
</entry>

<entry id="npr_yz" type="integer(4)"  category="dyn_fv"
       group="spmd_fv_inparm" valid_values="" >
A four element integer array which specifies the YZ and XY decompositions.
The first two elements are the number of Y subdomains and number of Z
subdomains in the YZ decomposition.  The second two elements are the number
of X subdomains and the number of Y subdomains in the XY decomposition.
Note that both the X and Y subdomains must contain at least 3 grid points.
For example, a grid with 96 latitudes can contain no more than 32 Y
subdomains.  There is no restriction on the number of grid points (levels)
in a Z subdomain, but note that the threading parallelism in the FV dycore
is over levels, so for parallel efficiency it is best to have at least the
number of levels in each Z subdomain as there are threads available.

There are a couple of rough rules of thumb to follow when setting the 2D
decompositions.  The first is that the number of Y subdomains in the YZ
decomposition should be the same as the number of Y subdomains in the XY
decomposition (npr_yz(1) == npr_yz(4)).  The second is that the total
number of YZ subdomains (npr_yz(1)*npr_yz(2)) should equal the total number
of XY subdomains (npr_yz(3)*npr_yz(4)).

Default: ntask,1,1,ntask where ntask is the number of MPI tasks.  This is a
1D decomposition in latitude.
</entry>

<entry id="nsplit" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="" >
Number of dynamics timesteps per physics timestep. If zero, a best-estimate
will be automatically calculated.
Default: 0
</entry>

<entry id="nspltrac" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="" >
Number of tracer advection timesteps per physics timestep.
Nsplit is partitioned into nspltrac and nsplit/nspltrac,
with the latter being the number of dynamics timesteps per
tracer timestep, possibly rounded upward; after initialization,
the code quantity nsplit is redefined to be the number of
dynamics timesteps per tracer timestep.
Default: 0
</entry>

<entry id="nspltvrm" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="" >
Number of vertical re-mapping timesteps per physics timestep.
Nspltrac is partitioned into nspltvrm and nspltrac/nspltvrm,
with the latter being the number of tracer timesteps per
re-mapping timestep, possibly rounded upward; after initialization,
the code quantity nspltrac is redefined to be the number of
tracer timesteps per re-mapping timestep.
Default: 0
</entry>

<entry id="trac_decomp" type="integer"  category="dyn_fv"
       group="dyn_fv_inparm" valid_values="" >
Size of tracer domain decomposition for trac2d.
Default: 1
</entry>


<!-- Dynamics: Finite Volume: Offline -->

<entry id="met_cell_wall_winds" type="logical"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
TRUE =&gt; the offline meteorology winds are defined on the model grid cell walls.
Default: FALSE
</entry>

<entry id="met_data_file" type="char*256" input_pathname="rel:met_data_path" category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
Name of file that contains the offline meteorology data.
Default: none
</entry>

<entry id="met_data_path" type="char*256" input_pathname="abs" category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
Name of directory that contains the offline meteorology data.
Default: none
</entry>

<entry id="met_filenames_list" type="char*256" input_pathname="abs" category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
Name of file that contains names of the offline meteorology data files.
Default: none
</entry>

<entry id="met_remove_file" type="logical"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
TRUE =&gt; the offline meteorology file will be removed from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="met_rlx_top" type="real"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
(km) top of relaxation region of winds for offline waccm
Default: 
</entry>

<entry id="met_rlx_bot" type="real"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
(km) bottom of relaxation region of winds for offline waccm
Default:
</entry>

<entry id="met_max_rlx" type="real"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
maximum of vertical relaxation function in bottom portion
Default: 1.0
</entry>

<entry id="met_fix_mass" type="logical"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
switch to turn on/off mass fixer for offline driver 
Default: true
</entry>

<entry id="met_shflx_name" type="char*16"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
srf heat flux field name in met data file
Default:
</entry>

<entry id="met_qflx_name" type="char*16"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
water vapor flux field name in met data file
Default:
</entry>

<entry id="met_shflx_factor" type="real"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
multiplication factor for srf heat flux
Default: 1.0
</entry>

<entry id="met_qflx_factor" type="real"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
multiplication factor for water vapor flux
Default: 1.0
</entry>

<entry id="met_snowh_factor" type="real"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
multiplication factor for snow hieght
Default: 1.0
</entry>

<entry id="met_srf_feedback" type="logical"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
if false then do not allow surface models feedbacks influence climate
Default: true
</entry>

<entry id="met_srf_nudge_flux" type="logical"  category="dyn_fv_off"
       group="metdata_nl" valid_values="" >
if true nudge meteorology surface fields TAUX, TAUY, SHFLX, QFLX rather than force
Default: true
</entry>

<!-- Dynamics: Spectral -->

<entry id="eul_nsplit" type="integer"  category="dyn_spectral"
       group="dyn_spectral_inparm" valid_values="" >
Number of dynamics timesteps per physics timestep. If zero, a best-estimate
will be automatically calculated.
Default: 1
</entry>

<entry id="dif2" type="real"  category="dyn_spectral"
       group="dyn_spectral_inparm" valid_values="" >
del^2 horizontal diffusion coefficient. Default: resolution dependent,
e.g. 2.5e5 for T42 EUL.
</entry>

<entry id="dif4" type="real"  category="dyn_spectral"
       group="dyn_spectral_inparm" valid_values="">
del^4 horizontal diffusion coefficient. Default: resolution dependent,
e.g. 1.0e16 for T42 EUL.
</entry>

<entry id="divdampn" type="real"  category="dyn_spectral"
       group="dyn_spectral_inparm" valid_values="">
Number of days (from timestep 0) to run divergence damper. Use only if spectral
model becomes dynamicallly unstable during initialization. Suggested value:
2. (Value must be &gt;= 0.)  Default: 0.
</entry>

<entry id="dyn_allgather" type="integer"  category="dyn_spectral"
       group="spmd_dyn_inparm" valid_values="">
Spectral dynamics gather option.
Default: 0
</entry>

<entry id="dyn_alltoall" type="integer"  category="dyn_spectral"
       group="spmd_dyn_inparm" valid_values="">
Spectral dynamics transpose option.
Default: 0
</entry>

<entry id="dyn_equi_by_col" type="logical"  category="dyn_spectral"
       group="spmd_dyn_inparm" valid_values="">
Flag indicating whether to assign latitudes to equidistribute columns or
latitudes. This only matters when using a reduced grid.
Default: TRUE
</entry>

<entry id="dyn_npes" type="integer"  category="dyn_spectral"
       group="spmd_dyn_inparm" valid_values="">
Number of processes assigned to dynamics (SE, EUL and SLD dycores).
Default: Total number of processes assigned to job.
</entry>

<entry id="dyn_npes_stride" type="integer"  category="dyn_spectral"
       group="spmd_dyn_inparm" valid_values="">
Stride for dynamics processes (EUL and SLD dycores).
E.g., if stride=2, assign every second process to the dynamics.
Default: 1
</entry>

<entry id="eps" type="real"  category="dyn_spectral"
       group="dyn_spectral_inparm" valid_values="">
Time filter coefficient.  Default: 0.06
</entry>

<entry id="kmxhdc" type="integer"  category="dyn_spectral"
       group="dyn_spectral_inparm" valid_values="">
Number of levels over which to apply Courant limiter, starting at top of
model.
Default: 5
</entry>

<!-- Gravity Wave Drag -->

<entry id="fcrit2" type="real"  category="gw_drag"
       group="gw_drag_nl" valid_values="" >
Critical Froude number squared.
Default: set by build-namelist.
</entry>

<!-- Greenhouse Gases: CO2, CH4, N2O, CFC11, CFC12 (original CAM versions) -->

<entry id="bndtvghg" type="char*256" input_pathname="abs" category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
Full pathname of time-variant boundary dataset for greenhouse gas surface
values.
Default: set by build-namelist.
</entry>

<entry id="ch4vmr" type="real"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
CH4 volume mixing ratio.  This is used as the time invariant surface value
of CH4 if no time varying values are specified.
Default: set by build-namelist.
</entry>

<entry id="co2vmr" type="real"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
CO2 volume mixing ratio.  This is used as the time invariant surface value
of CO2 if no time varying values are specified.
Default: set by build-namelist.
</entry>

<entry id="co2vmr_rad" type="real"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
User override for the prescribed CO2 volume mixing ratio used by the radiation
calculation.  Note however that the prescribed value of CO2 which is sent
to the surface models is still the one that is set using either the 
<varname>co2vmr</varname> or the <varname>scenario_ghg</varname> variables.
Default: not used
</entry>

<entry id="f11vmr" type="real"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
CFC11 volume mixing ratio adjusted to reflect contributions from many GHG
species.  This is used as the time invariant surface value of F11 if no
time varying values are specified.
Default: set by build-namelist.
</entry>

<entry id="f12vmr" type="real"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
CFC12 volume mixing ratio.  This is used as the time invariant surface value
of CFC12 if no time varying values are specified.
Default: set by build-namelist.
</entry>

<entry id="n2ovmr" type="real"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
N2O volume mixing ratio.  This is used as the time invariant surface value
of N2O if no time varying values are specified.
Default: 0.311e-6
</entry>

<entry id="ghg_yearstart_data" type="integer"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
Data start year.  Use in conjunction
with <varname>ghg_yearstart_model</varname>.
Default: 0
</entry>

<entry id="ghg_yearstart_model" type="integer"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
Model start year.  Use in conjunction
with <varname>ghg_yearstart_data</varname>.
Default: 0
</entry>

<entry id="ramp_co2_annual_rate" type="real"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
Amount of co2 ramping per year (percent).  Only used
if <varname>scenario_ghg</varname> = 'RAMP_CO2_ONLY'
Default: 1.0
</entry>

<entry id="ramp_co2_cap" type="real"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
CO2 cap if &gt; 0, floor otherwise.  Specified as multiple or fraction of
inital value; e.g., setting to 4.0 will cap at 4x initial CO2 setting.
Only used if <varname>scenario_ghg</varname> = 'RAMP_CO2_ONLY'
Default: boundless if <varname>ramp_co2_annual_rate</varname> &gt; 0, zero otherwise.
</entry>

<entry id="ramp_co2_start_ymd" type="integer"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
Date on which ramping of co2 begins.  The date is encoded as an integer in
the form YYYYMMDD.  Only used if <varname>scenario_ghg</varname> = 'RAMP_CO2_ONLY'
Default: 0
</entry>

<entry id="rampyear_ghg" type="integer"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="" >
If <varname>scenario_ghg</varname> is set to "RAMPED" then the greenhouse
gas surface values are interpolated between the annual average values 
read from the file specified by <varname>bndtvghg</varname>.
In that case, the value of this variable (&gt; 0) fixes the year of the
lower bounding value (i.e., the value for calendar day 1.0) used in the
interpolation.  For example, if rampyear_ghg = 1950, then the GHG surface
values will be the result of interpolating between the values for 1950 and
1951 from the dataset.
Default: 0
</entry>

<entry id="scenario_ghg" type="char*16"  category="ghg_cam"
       group="chem_surfvals_nl" valid_values="FIXED,RAMPED,RAMP_CO2_ONLY" >
Controls treatment of prescribed co2, ch4, n2o, cfc11, cfc12 volume mixing
ratios.  May be set to 'FIXED' or 'RAMPED' or 'RAMP_CO2_ONLY'.
FIXED =&gt; volume mixing ratios are fixed and have either default or namelist
         input values.
RAMPED =&gt; volume mixing ratios are time interpolated from the dataset
          specified by <varname>bndtvghg</varname>.
RAMP_CO2_ONLY =&gt; only co2 mixing ratios are ramped at a rate determined by
                 the variables <varname>ramp_co2_annual_rate</varname>, <varname>ramp_co2_cap</varname>,
                 and <varname>ramp_co2_start_ymd</varname>.
Default: FIXED
</entry>

<!-- Greenhouse Gases: prognostic CH4, N2O, CFC11, CFC12 (original CAM versions) -->

<entry id="bndtvg" type="char*256" input_pathname="abs" category="ghg_chem"
       group="chem_inparm" valid_values="" >
Full pathname of time-variant boundary dataset for greenhouse gas production/loss
rates.  Only used by the simple prognostic GHG chemistry scheme that is
enabled via the argument "-prog_species GHG" to configure.
Default: set by build-namelist.
</entry>

<entry id="ghg_chem" type="logical"  category="ghg_chem"
       group="chem_inparm" valid_values="" >
This variable should not be set by the user.  It is set by build-namelist
when the user specifies the argument "-prog_species GHG" to configure which
turns on a simple prognostic chemistry scheme for CH4, N2O, CFC11 and
CFC12.
Default: set by build-namelist
</entry>


<!-- CO2 cycle for BGC -->

<entry id="co2_cycle_rad_passive" type="logical" category="co2_cycle"
       group="camexp" valid_values="" >
Flag to set rad_climate variable so that the prognostic CO2 controlled by
the co2_cycle module is radiatively passive.
Default: FALSE
</entry>

<entry id="co2_flag" type="logical"  category="co2_cycle"
       group="co2_cycle_nl" valid_values="" >
If TRUE turn on CO2 code.
Default: FALSE
</entry>

<entry id="co2_readflux_fuel" type="logical"  category="co2_cycle"
       group="co2_cycle_nl" valid_values="" >
If TRUE read co2 flux from fuel.
Default: FALSE
</entry>

<entry id="co2_readflux_ocn" type="logical"  category="co2_cycle"
       group="co2_cycle_nl" valid_values="" >
If TRUE read co2 flux from ocn.
Default: FALSE
</entry>

<entry id="co2flux_ocn_file" type="char*256" input_pathname="abs" category="co2_cycle"
       group="co2_cycle_nl" valid_values="" >
Filepath for dataset containing CO2 flux from ocn.
Default: none
</entry>

<entry id="co2flux_fuel_file" type="char*256" input_pathname="abs" category="co2_cycle"
       group="co2_cycle_nl" valid_values="" >
Filepath for dataset containing CO2 flux from fossil fuel.
Default: none
</entry>

<!-- History and Initial Conditions Output -->

<entry id="avgflag_pertape" type="char*1(6)"  category="history"
       group="cam_inparm" valid_values="A,B,I,X,M" >
Sets the averaging flag for all variables on a particular history file
series. Valid values are:

 A ==&gt; Average
 B ==&gt; GMT 00:00:00 average
 I ==&gt; Instantaneous
 M ==&gt; Minimum
 X ==&gt; Maximum

The default is to use the averaging flags for each variable that are set in
the code via calls to subroutine addfld.

Defaults: set in code via the addfld and add_default subroutine calls.
</entry>

<entry id="empty_htapes" type="logical"  category="history"
       group="cam_inparm" valid_values="" >
If true don't put any of the variables on the history tapes by
default. Only output the variables that the user explicitly lists in
the <varname>fincl#</varname> namelist items.  Default: FALSE
</entry>

<entry id="fexcl1" type="char*24(750)"  category="history"
       group="cam_inparm" valid_values="" >
List of fields to exclude from the 1st history file (by default the name
of this file contains the string "h0").
Default: none
</entry>
<entry id="fexcl2" type="char*24(750)"  category="history"
       group="cam_inparm" valid_values="" >
List of fields to exclude from the 2nd history file (by default the name
of this file contains the string "h1").
Default: none
</entry>
<entry id="fexcl3" type="char*24(750)"  category="history"
       group="cam_inparm" valid_values="" >
List of fields to exclude from the 3rd history file (by default the name
of this file contains the string "h2").
Default: none
</entry>
<entry id="fexcl4" type="char*24(750)"  category="history"
       group="cam_inparm" valid_values="" >
List of fields to exclude from the 4th history file (by default the name
of this file contains the string "h3").
Default: none
</entry>
<entry id="fexcl5" type="char*24(750)"  category="history"
       group="cam_inparm" valid_values="" >
List of fields to exclude from the 5th history file (by default the name
of this file contains the string "h4").
Default: none
</entry>
<entry id="fexcl6" type="char*24(750)"  category="history"
       group="cam_inparm" valid_values="" >
List of fields to exclude from the 6th history file (by default the name
of this file contains the string "h5").
Default: none
</entry>

<entry id="fincl1" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
List of fields to include on the first history file (by default the name of
this file contains the string "h0").  The added fields must be in Master
Field List.  The averaging flag for the output field can be specified by
appending a ":" and a valid averaging flag to the field name.  Valid flags
are:

 A ==&gt; Average
 B ==&gt; GMT 00:00:00 average
 I ==&gt; Instantaneous
 M ==&gt; Minimum
 X ==&gt; Maximum

Default:  set in code via the addfld and add_default subroutine calls.
</entry>
<entry id="fincl2" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1</varname>, but for the 2nd history file (by default
the name of this file contains the string "h1").
Default: none.
</entry>
<entry id="fincl3" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1</varname>, but for the 3rd history file (by default
the name of this file contains the string "h2").
Default: none.
</entry>
<entry id="fincl4" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1</varname>, but for the 4th history file (by default
the name of this file contains the string "h3").
Default: none.
</entry>
<entry id="fincl5" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1</varname>, but for the 5th history file (by default
the name of this file contains the string "h4").
Default: none.
</entry>
<entry id="fincl6" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1</varname>, but for the 6th history file (by default
the name of this file contains the string "h5").
Default: none.
</entry>

<entry id="clubb_history" type="logical"  category="history"
       group="clubb_his_nl" valid_values="" >
if .true. then output CLUBBs history statistics
</entry>

<entry id="clubb_rad_history" type="logical"  category="history"
       group="clubb_his_nl" valid_values="" >
if .true. then output CLUBBs radiative history statistics
</entry>

<entry id="clubb_vars_zt" type="char*16(10000)"  category="history"
       group="clubb_stats_nl" valid_values="" >
Same as <varname>fincl1</varname>, but for CLUBB statistics on zt grid.
Default: none.
</entry>

<entry id="clubb_vars_zm" type="char*16(10000)"  category="history"
       group="clubb_stats_nl" valid_values="" >
Same as <varname>fincl1</varname>, but for CLUBB statistics on zm grid.
Default: none.
</entry>

<entry id="clubb_vars_rad_zt" type="char*16(10000)"  category="history"
       group="clubb_stats_nl" valid_values="" >
Same as <varname>fincl1</varname>, but for CLUBB statistics on radiation zt grid.
Default: none.
</entry>

<entry id="clubb_vars_rad_zm" type="char*16(10000)"  category="history"
       group="clubb_stats_nl" valid_values="" >
Same as <varname>fincl1</varname>, but for CLUBB statistics on radiation zm grid.
Default: none.
</entry>

<entry id="clubb_vars_sfc" type="char*16(10000)"  category="history"
       group="clubb_stats_nl" valid_values="" >
Same as <varname>fincl1</varname>, but for CLUBB statistics on surface.
Default: none.
</entry>

<entry id="clubb_iop_name" type="char*200"  category="history"
       group="scm_nl" valid_values="" >
Name of the IOP case so case specific adjustments can be made in CLUBB.  
Default: none.
</entry>

<entry id="collect_column_output" type="logical(6)" category="history"
   group="cam_inparm" valid_values="">
Collect all column data into a single field and output in ncol format,
much faster than default when you have a lot of columns.
</entry>

<entry id="fincl1lonlat" type="char*128(750)"  category="history"
       group="cam_inparm" valid_values="" >
List of columns or contiguous columns at which the fincl1 fields will be
output. Individual columns are specified as a string using a longitude
degree (greater or equal to 0.) followed by a single character
(e)ast/(w)est identifer, an underscore '_' , and a latitude degree followed
by a single character (n)orth/(s)outh identifier.  For example, '10e_20n'
would pick the model column closest to 10 degrees east longitude by 20
degrees north latitude.  A group of contiguous columns can be specified
using bounding latitudes and longitudes separated by a colon.  For example,
'10e:20e_15n:20n' would select the model columns which fall with in the
longitude range from 10 east to 20 east and the latitude range from 15
north to 20 north.
Default: none
</entry>
<entry id="fincl2lonlat" type="char*128(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1lonlat</varname>, but for 2nd history file.
</entry>
<entry id="fincl3lonlat" type="char*128(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1lonlat</varname>, but for 3rd history file.
</entry>
<entry id="fincl4lonlat" type="char*128(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1lonlat</varname>, but for 4th history file.
</entry>
<entry id="fincl5lonlat" type="char*128(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1lonlat</varname>, but for 5th history file.
</entry>
<entry id="fincl6lonlat" type="char*128(750)"  category="history"
       group="cam_inparm" valid_values="" >
Same as <varname>fincl1lonlat</varname>, but for 6th history file.
</entry>


<entry id="fwrtpr1" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Specific fields which will be written using the non-default precision on
the 1st history file.
Default: none
</entry>
<entry id="fwrtpr2" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Specific fields which will be written using the non-default precision on
the 2nd history file.
Default: none
</entry>
<entry id="fwrtpr3" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Specific fields which will be written using the non-default precision on
the 3rd history file.
Default: none
</entry>
<entry id="fwrtpr4" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Specific fields which will be written using the non-default precision on
the 4th history file.
Default: none
</entry>
<entry id="fwrtpr5" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Specific fields which will be written using the non-default precision on
the 5th history file.
Default: none
</entry>
<entry id="fwrtpr6" type="char*26(750)"  category="history"
       group="cam_inparm" valid_values="" >
Specific fields which will be written using the non-default precision on
the 6th history file.
Default: none
</entry>

<entry id="hfilename_spec" type="char*256(6)"  category="history"
       group="cam_inparm" valid_values="" >

Array of history filename specifiers.  The filenames of up to six history
output files can be controlled via this variable.  Filename specifiers give
generic formats for the filenames with specific date and time components,
file series number (0-5), and caseid, filled in when the files are
created. The following strings are expanded when the filename is created:
%c=caseid; %t=file series number (0-5); %y=year (normally 4 digits, more
digits if needed); %m=month; %d=day; %s=seconds into current day; %%=%
symbol.  Note that the caseid may be set using the namelist
variable <varname>case_name</varname>.

For example, for a simulation with caseid="test" and current date and time
of 0000-12-31 0:00UT, a filename specifier of "%c.cam2.h%t.%y-%m.nc" would
expand into "test.cam2.h0.0000-12.nc" for the first history file.  The
filename specifier "%c.cam2.h%t.%y-%m-%d-%s.nc" would expand to
"test.cam2.h1.0000-12-31-00000.nc" for the second history file. Spaces are
not allowed in filename specifiers. Although the character "/" is allowed
in the specifier, it will be interpreted as a directory name and the
corresponding directories will have to be created in the model execution
directory (directory given to configure with -cam_exedir option) before
model execution.  The first element is for the primary history file which
is output by default as a monthly history file.  Entries 2 through 6 are
user specified auxilliary output files.

Defaults: "%c.cam2.h0.%y-%m.nc", "%c.cam2.h1.%y-%m-%d-%s.nc", ...,
          "%c.cam2.h5.%y-%m-%d-%s.nc"
</entry>

<entry id="sathist_track_infile" type="char*256" input_pathname="abs" category="history"
       group="satellite_options_nl" valid_values="" >
Full pathname of the satellite track data used by the satellite track history 
output feature.
Default: none 
</entry>
<entry id="sathist_hfilename_spec" type="char*256"  category="history"
       group="satellite_options_nl" valid_values="" >
Satellite track history filename specifier.  See <varname>hfilename_spec</varname>
Default:  "%c.cam2.sat.%y-%m-%d-%s.nc"
</entry>
<entry id="sathist_fincl" type="char*18(750)"  category="history"
       group="satellite_options_nl" valid_values="" >
List of history fields to output along the satellite track specified by  <varname>sathist_track_infile</varname>
Default: none
</entry>
<entry id="sathist_mfilt" type="integer"  category="history"
       group="satellite_options_nl" valid_values="" >
Sets the number of observation columns written the satellite track history file
series. 
Default: 100000
</entry>

<entry id="sathist_nclosest" type="integer"  category="history"
       group="satellite_options_nl" valid_values="" >
Sets the number of columns closest to the observation that should be output. Setting
this to a number greater than 1 allows for spatial interpolation in the post processing.
Default: 1
</entry>

<entry id="sathist_ntimestep" type="integer"  category="history"
       group="satellite_options_nl" valid_values="" >
Sets the number of timesteps closest to the observation that should be output. Setting
this to a number greater than 1 allows for temporal interpolation in the post processing.
Default: 1
</entry>

<entry id="inithist" type="char*8"  category="history"
       group="cam_inparm" valid_values="NONE,6-HOURLY,DAILY,MONTHLY,YEARLY,CAMIOP,ENDOFRUN" >
Frequency that initial files will be output: 6-hourly, daily, monthly,
yearly, or never.  Valid values: 'NONE', '6-HOURLY', 'DAILY', 'MONTHLY',
'YEARLY', 'CAMIOP', 'ENDOFRUN'.
Default: 'YEARLY'
</entry>

<entry id="inithist_all" type="logical"  category="history"
       group="cam_inparm" valid_values="" >
If false then include only REQUIRED fields on IC file.  If true then
include required AND optional fields on IC file.  
Default: FALSE
</entry>

<entry id="mfilt" type="integer(6)"  category="history"
       group="cam_inparm" valid_values="" >
Array containing the maximum number of time samples written to a history
file.  The first value applies to the primary history file, the second
through sixth to the auxillary history files.
Default: 1,30,30,30,30,30
</entry>

<entry id="lcltod_start" type="integer(6)"  category="history"
       group="cam_inparm" valid_values="" >
Array containing the starting time of day for local time history averaging. 
Used in conjuction with lcltod_stop. If lcltod_stop is less than lcltod_start, 
then the time range wraps around 24 hours. The start time is included in the 
interval. Time is in seconds and defaults to 39600 (11:00 AM).  The first value 
applies to the primary hist. file, the second to the first aux. hist. file, etc.
Default: none
</entry>

<entry id="lcltod_stop" type="integer(6)"  category="history"
       group="cam_inparm" valid_values="" >
Array containing the stopping time of day for local time history averaging. 
Used in conjuction with lcltod_start. If lcltod_stop is less than lcltod_start, 
then the time range wraps around 24 hours. The stop time is not included in the 
interval. Time is in seconds and defaults to 0 (midnight).  The first value 
applies to the primary hist. file, the second to the first aux. hist. file, etc.
Default: none
</entry>

<entry id="ndens" type="integer(6)"  category="history"
       group="cam_inparm" valid_values="1,2" > 

Array specifying the precision of real data written to each history file
series. Valid values are 1 or 2. '1' implies output real values are 8-byte
and '2' implies output real values are 4-byte.

Default: 2,2,2,2,2,2
</entry>


<entry id="nhtfrq" type="integer(6)"  category="history"
       group="cam_inparm" valid_values="" > 

Array of write frequencies for each history file series.
If <varname>nhtfrq(1)</varname> = 0, the file will be a monthly average.
Only the first file series may be a monthly average.  If
<varname>nhtfrq(i)</varname> &gt; 0, frequency is specified as number of
timesteps.  If <varname>nhtfrq(i)</varname> &lt; 0, frequency is specified
as number of hours.

Default: 0,-24,-24,-24,-24,-24
</entry>

<!-- Initial Conditions -->

<entry id="ncdata" type="char*256" input_pathname="abs" category="initial_conditions"
       group="cam_inparm" valid_values="" >
Full pathname of initial atmospheric state dataset (NetCDF format).
Default: set by build-namelist.
</entry>

<entry id="pertlim" type="real"  category="initial_conditions"
       group="cam_inparm" valid_values="" >
Perturb the initial conditions for temperature randomly by up to the given
amount. Only applied for initial simulations.
Default: 0.0
</entry>

<entry id="readtrace" type="logical"  category="initial_conditions"
       group="cam_inparm" valid_values="" >
If TRUE, try to initialize data for all consituents by reading from the
initial conditions dataset. If variable not found then data will be
initialized using internally-specified default values.  If FALSE then don't
try reading constituent data from the IC file; just use the
internally-specified defaults.
Default: TRUE
</entry>

<entry id="use_64bit_nc" type="logical"  category="history"
       group="cam_inparm" valid_values="" >
Use 64-bit netCDF format for cam history files.
Default: TRUE
</entry>


<!-- COSP Cloud Simulator control LOGICALS -->

<entry id="docosp" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, the COSP cloud simulator is run.
Setting this namelist variable happens automatically if you compile with COSP.
COSP will not run unless this is set to .true. in the namelist!
Turn on the desired simulators using lXXX_sim namelist vars
If no specific simulators are specified, all of the simulators
are run on all columns and all output is saved. (useful for testing). 
COSP is available with CAM4 and CAM5 physics.
This default logical is set in cospsimulator_intr.F90.
Default: FALSE
</entry>

<entry id="cosp_amwg" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, COSP cloud simulators are run to produce 
all output required for the COSP plots in the AMWG diagnostics package.
sets cosp_ncolumns=10 and cosp_nradsteps=3 
(appropriate for COSP statistics derived from seasonal averages),
and runs MISR, ISCCP, MODIS, CloudSat radar and CALIPSO lidar simulators 
(cosp_lmisr_sim=.true.,cosp_lisccp_sim=.true.,
cosp_lmodis_sim=.true.,cosp_lradar_sim=.true.,cosp_llidar_sim=.true.).
This default logical is set in cospsimulator_intr.F90.
Default: TRUE
</entry>

<entry id="cosp_lite" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, the COSP cloud simulators are run to produce 
select output for the AMWG diagnostics package.
sets cosp_ncolumns=10 and cosp_nradsteps=3 
(appropriate for COSP statistics derived from seasonal averages),
and runs MISR, ISCCP, MODIS, and CALIPSO lidar simulators 
(cosp_lmisr_sim=.true.,cosp_lisccp_sim=.true.,
cosp_lmodis_sim=.true.,cosp_llidar_sim=.true.).
This default logical is set in cospsimulator_intr.F90.
Default: FALSE
</entry>

<entry id="cosp_passive" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, the passive COSP cloud simulators are run to produce 
select output for the AMWG diagnostics package.
sets cosp_ncolumns=10 and cosp_nradsteps=3 
(appropriate for COSP statistics derived from seasonal averages),
and runs MISR, ISCCP, and MODIS simulators 
(cosp_lmisr_sim=.true.,cosp_lisccp_sim=.true.,cosp_lmodis_sim=.true.).
This default logical is set in cospsimulator_intr.F90.
Default: FALSE
</entry>

<entry id="cosp_active" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, the active COSP cloud simulators are run to produce 
select output for the AMWG diagnostics package.
sets cosp_ncolumns=10 and cosp_nradsteps=3 
(appropriate for COSP statistics derived from seasonal averages),
and runs CloudSat radar and CALIPSO lidar simulators 
(cosp_lradar_sim=.true.,cosp_llidar_sim=.true.).
This default logical is set in cospsimulator_intr.F90.
Default: FALSE
</entry>

<entry id="cosp_isccp" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, the ISCCP cloud simulator is run to produce 
select output for the AMWG diagnostics package.
sets cosp_ncolumns=10 and cosp_nradsteps=3 
(appropriate for COSP statistics derived from seasonal averages),
and runs ISCCP simulator
(cosp_lmisr_sim=.false.,cosp_lisccp_sim=.true.,
cosp_lmodis_sim=.false.,cosp_lradar_sim=.false.,cosp_llidar_sim=.false.).
This default logical is set in cospsimulator_intr.F90.
1236: Default: FALSE
</entry>

<entry id="cosp_runall" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, run all simulators using the default values cosp_ncolumns=50 and
cosp_nradsteps=1.  This option is mainly intended for testing, but it also
must be used in order to output the input fields needed to run the
simulator in an offline mode (via setting cosp_histfile_aux=.true.).
Default: FALSE
</entry>

<entry id="cosp_lradar_sim" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, COSP radar simulator will be run and all non-subcolumn output 
will be saved.
Default: FALSE
</entry>

<entry id="cosp_llidar_sim" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, COSP lidar simulator will be run and all non-subcolumn output
will be saved
Default: FALSE
</entry>

<entry id="cosp_lisccp_sim" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, COSP ISCCP simulator will be run and all non-subcolumn output
will be saved.  ISCCP simulator is run on only daylight
columns.
Default: FALSE
</entry>

<entry id="cosp_lmisr_sim" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, MISR simulator will be run and all non-subcolumn output
will be saved.  MISR simulator is run on only daylight
columns.
Default: FALSE
</entry>

<entry id="cosp_lmodis_sim" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, MODIS simulator will be run and all non-subcolumn output
will be saved.

Default: FALSE
</entry>

<!-- COSP CFMIP Cloud Simulator LOGICALS -->

<entry id="cosp_cfmip_3hr" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, the COSP cloud simulator is run for CFMIP 3-hourly 
experiments.
This default logical is set in cospsimulator_intr.F90
Default: FALSE
</entry>

<entry id="cosp_cfmip_da" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, the COSP cloud simulator is run for CFMIP daily 
experiments.
This default logical is set in cospsimulator_intr.F90
Default: FALSE
</entry>

<entry id="cosp_cfmip_off" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, the COSP cloud simulator is run for CFMIP off-line  
monthly experiments.
This default logical is set in cospsimulator_intr.F90
Default: FALSE
</entry>

<entry id="cosp_cfmip_mon" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, the COSP cloud simulator is run for CFMIP monthly
experiments.
This default logical is set in cospsimulator_intr.F90
Default: FALSE
</entry>

<!-- COSP input control parameters -->

<entry id="cosp_ncolumns" type="integer"  category="cosp"
       group="cospsimulator_nl" valid_values="">
Number of subcolumns in SCOPS
This default logical is set in cospsimulator_intr.F90
Default: 50
</entry>

<!-- COSP sampling parameters -->

<entry id="cosp_sample_atrain" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
Turns on sampling along a-train orbit for radar and lidar simulators.
This default logical is set in cospsimulator_intr.F90
Default: FALSE
</entry>

<entry id="cosp_atrainorbitdata" type="char*256"  category="cosp"
       group="cospsimulator_nl" valid_values="">
Path for the Atrain orbit data file provided by CFMIP.
There is no default for this, but sample_atrain = .true. will not work 
if this namelist variable is undefined.
currently /project/cms/jenkay/SCAM/repository/cloudsat_orbit_08921_14250.nc
Default: no default set now, need to specify in namelist
</entry>

<!-- COSP output parameters -->

<entry id="cosp_histfile_num" type="integer"  category="cosp"
       group="cospsimulator_nl" valid_values="">
This specifies the CAM history tape where COSP diagnostics will be written.
Ignored/not used if any of the cosp_cfmip_* namelist variables are invoked.

This default is set in cospsimulator_intr.F90
Default: 1
</entry>
<entry id="cosp_histfile_aux" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
If true, additional output is added to make it possible to
run COSP off-line.

This default is set in cospsimulator_intr.F90
Default: FALSE
</entry>
<entry id="cosp_histfile_aux_num" type="integer"  category="cosp"
       group="cospsimulator_nl" valid_values="">
This specifies the CAM history tape where extra COSP diagnostics will be written.

This default is set in cospsimulator_intr.F90
Default: 2
</entry>

<entry id="cosp_nradsteps" type="integer"  category="cosp"
       group="cospsimulator_nl" valid_values="">
This specifies the frequency at which is COSP is called, 
every cosp_nradsteps radiation timestep.

This default is set in cospsimulator_intr.F90
Default: 1
</entry>

<entry id="cosp_lfrac_out" type="logical"  category="cosp"
       group="cospsimulator_nl" valid_values="">
Turns on sub-column output from COSP.
If both the isccp/misr simulators and the lidar/radar simulators
are run, lfrac_out is from the isccp/misr simulators columns.
This default logical is set in cospsimulator_intr.F90
Default: FALSE
</entry>

<!-- Cldwat -->
<entry id="cldwat_icritc" type="real" category="conv"
       group="cldwat_nl" valid_values="" >
Threshold for autoconversion of cold ice in RK microphysics scheme.
Default: set by build-namelist
</entry>

<entry id="cldwat_icritw" type="real" category="conv"
       group="cldwat_nl" valid_values="" >
Threshold for autoconversion of warm ice in RK microphysics scheme.
Default: set by build-namelist
</entry>

<entry id="cldwat_conke" type="real" category="conv"
       group="cldwat_nl" valid_values="" >
Tunable constant for evaporation of precip in RK microphysics scheme.
Default: set by build-namelist
</entry>

<entry id="cldwat_r3lcrit" type="real" category="conv"
       group="cldwat_nl" valid_values="" >
Critical radius at which autoconversion become efficient in RK microphysics
scheme.
Default: set by build-namelist
</entry>

<!-- macro_park -->
<entry id="macro_park_do_cldice" type="logical" category="conv"
       group="macro_park_nl" valid_values="" >
Switch to control whether Park macrophysics should prognose
cloud ice (cldice).
Default: .true.
</entry>

<entry id="macro_park_do_cldliq" type="logical" category="conv"
       group="macro_park_nl" valid_values="" >
Switch to control whether Park macrophysics should prognose
cloud liquid (cldliq).
Default: .true.
</entry>

<entry id="macro_park_do_detrain" type="logical" category="conv"
       group="macro_park_nl" valid_values="" >
Switch to control whether Park macrophysics should perform
detrainment into the stratiform cloud scheme.
Default: .true.
</entry>

<!-- micro_mg -->
<entry id="micro_mg_version" type="integer" category="microphys"
       group="micro_mg_nl" valid_values="" >
Version number for MG microphysics
Default: 1
</entry>

<entry id="micro_mg_sub_version" type="integer" category="microphys"
       group="micro_mg_nl" valid_values="" >
Sub-version number for MG microphysics
Default: 0
</entry>

<entry id="micro_mg_do_cldice" type="logical" category="microphys"
       group="micro_mg_nl" valid_values="" >
Switch to control whether MG microphysics should prognose
cloud ice (cldice).
Default: .true.
</entry>

<entry id="micro_mg_do_cldliq" type="logical" category="microphys"
       group="micro_mg_nl" valid_values="" >
Switch to control whether MG microphysics should prognose
cloud liquid (cldliq).
Default: .true.
</entry>

<!-- micro_aero -->
<entry id="microp_aero_bulk_scale" type="real" category="conv"
       group="microp_aero_nl" valid_values="" >
prescribed aerosol bulk sulfur scale factor
Default: 2 
</entry>

<!-- hkconv Moist Convection -->
<entry id="hkconv_cmftau" type="real" category="conv"
       group="hkconv_nl" valid_values="" >
Characteristic adjustment time scale for Hack shallow scheme.
Default: set by build-namelist
</entry>

<entry id="hkconv_c0" type="real" category="conv"
       group="hkconv_nl" valid_values="" >
Rain water autoconversion coefficient for Hack shallow scheme.
Default: set by build-namelist
</entry>

<!-- uwshcu Moist Convection -->
<entry id="uwshcu_rpen" type="real" category="conv"
       group="uwshcu_nl" valid_values="">
Penetrative entrainment efficiency in UW shallow scheme.
Default: set by build-namelist
</entry>

<!-- Cloud fraction -->

<entry id="cldfrc_freeze_dry" type="logical" category="cldfrc"
       group="cldfrc_nl" valid_values="" >
Switch for Vavrus "freeze dry" adjustment in cloud fraction.  Set to FALSE to
turn the adjustment off.
Default: set by build-namelist
</entry>

<entry id="cldfrc_ice" type="logical" category="cldfrc"
       group="cldfrc_nl" valid_values="" >
Switch for ice cloud fraction calculation.
Default: set by build-namelist
</entry>

<entry id="cldfrc_rhminl" type="real" category="cldfrc"
       group="cldfrc_nl" valid_values="" >
Minimum rh for low stable clouds.
Default: set by build-namelist
</entry>

<entry id="cldfrc_rhminl_adj_land" type="real" category="conv"
       group="cldfrc_nl" valid_values="" >
Adjustment to rhminl for land without snow cover.
Default: 0.10
</entry>

<entry id="cldfrc_rhminh" type="real" category="cldfrc"
       group="cldfrc_nl" valid_values="" >
Minimum rh for high stable clouds.
Default: set by build-namelist
</entry>

<entry id="cldfrc_sh1" type="real" category="cldfrc"
       group="cldfrc_nl" valid_values="" >
parameter for shallow convection cloud fraction.
Default: set by build-namelist
</entry>

<entry id="cldfrc_sh2" type="real" category="cldfrc"
       group="cldfrc_nl" valid_values="" >
parameter for shallow convection cloud fraction.
Default: set by build-namelist
</entry>

<entry id="cldfrc_dp1" type="real" category="cldfrc"
       group="cldfrc_nl" valid_values="" >
parameter for deep convection cloud fraction.
Default: set by build-namelist
</entry>

<entry id="cldfrc_dp2" type="real" category="cldfrc"
       group="cldfrc_nl" valid_values="" >
parameter for deep convection cloud fraction.
Default: set by build-namelist
</entry>

<entry id="cldfrc_premit" type="real" category="cldfrc"
       group="cldfrc_nl" valid_values="" >
top pressure bound for mid level cloud.
Default: set by build-namelist
</entry>

<entry id="cldfrc_premib" type="real" category="conv"
       group="cldfrc_nl" valid_values="" >
Bottom height (Pa) for mid-level liquid stratus fraction.
Default: 700.e2
</entry>

<entry id="cldfrc_iceopt" type="integer" category="conv"
       group="cldfrc_nl" valid_values="" >
Scheme for ice cloud fraction: 1=wang & sassen, 2=schiller (iciwc),  
3=wood & field, 4=Wilson (based on smith), 5=modified slingo (ssat & empyt cloud)
Default: 5
</entry>

<entry id="cldfrc_icecrit" type="real" category="conv"
       group="cldfrc_nl" valid_values="" >
Critical RH for ice clouds (Wilson & Ballard scheme).
Default: 0.93
</entry>

<!-- condensate to rain autoconversion coefficient -->
<entry id="zmconv_c0_lnd" type="real" category="conv"
       group="zmconv_nl" valid_values="" >
Autoconversion coefficient over land in ZM deep convection scheme.
Default: set by build-namelist
</entry>

<entry id="zmconv_c0_ocn" type="real" category="conv"
       group="zmconv_nl" valid_values="" >
Autoconversion coefficient over ocean in ZM deep convection scheme.
Default: set by build-namelist
</entry>

<entry id="zmconv_ke" type="real" category="conv"
       group="zmconv_nl" valid_values="" >
Tunable evaporation efficiency in ZM deep convection scheme.
Default: set by build-namelist
</entry>


<!-- Cloud sedimentation -->

<entry id="cldsed_ice_stokes_fac" type="real" category="cldsed"
       group="cldsed_nl" valid_values="" >
Factor applied to the ice fall velocity computed from 
Stokes terminal velocity.
Default: set by build-namelist
</entry>

<!-- Water Vapor Saturation -->

<entry id="wv_sat_scheme" type="char*16" category="wv_sat"
       group="wv_sat_nl" valid_values="GoffGratch,MurphyKoop" >
Type of water vapor saturation vapor pressure scheme employed.  'GoffGratch' for
Goff and Gratch (1946); 'MurphyKoop' for Murphy & Koop (2005)
Default: GoffGratch
</entry>

<!-- Physics sub-column switches -->

<entry id="use_subcol_microp" type="logical" category="conv"
       group="phys_ctl_nl" valid_values="" >
Control use of sub-columns within microphysics;
'false' for no subcolumns.
Default: 'false'
</entry>

<!-- Moist Convection and Microphysics -->

<!-- Yi-Chi: add SAS and ZMMOD -->
<entry id="deep_scheme" type="char*16" category="conv"
       group="phys_ctl_nl" valid_values="ZM,ZMMOD,SAS,off" >
Type of deep convection scheme employed.  'ZM' for Zhang-McFarlane;
'SAS' for Simplified Arakawa Schubert scheme;
'ZMMOD' for modified Zhang-McFarlane scheme; 'off' for none.
Default: 'ZM'
</entry>

<entry id="microp_scheme" type="char*16" category="conv"
       group="phys_ctl_nl" valid_values="RK,MG" >
Type of microphysics scheme employed.  'RK' for Rasch and Kristjansson
(1998); 'MG' for Morrison and Gettelman (2008), Gettelman et al (2010)
two moment scheme for CAM5.1
Default: set by build-namelist (depends on value set in configure).
</entry>

<entry id="macrop_scheme" type="char*16" category="conv"
       group="phys_ctl_nl" valid_values="park,RK,CLUBB_SGS,updf,tpdf" >
Type of macrophysics scheme employed.  'park' for Park
(1998); 'RK' for Rasch and Kristjansson (1998); 'CLUBB_SGS' clubb;
'updf' for uniform probability distribution function.
Default: 'park'
</entry>

<entry id="do_clubb_sgs" type="logical" category="conv"
       group="phys_ctl_nl" valid_values="" >
Switch for CLUBB_SGS
Default: FALSE
</entry>

<!-- Yi-Chi: add HP -->
<entry id="shallow_scheme" type="char*16" category="conv"
       group="phys_ctl_nl" valid_values="Hack,UW,HP,CLUBB_SGS" >
Type of shallow convection scheme employed.  'Hack' for Hack shallow convection;
'UW' for original McCaa UW pbl scheme, modified by Sungsu Park; 'CLUBB_SGS'
for CLUBB_SGS. And 'HP' for Han and Pan 2011 scheme.
Default: set by build-namelist (depends on <varname>eddy_scheme</varname>).
</entry>

<entry id="do_tms" type="logical" category="pbl"
       group="phys_ctl_nl" valid_values="" >
Logical switch to turn on turbulent mountain stress calculation in 
vertical diffusion routine.
Default: set by build-namelist
</entry>

<entry id="eddy_lbulk_max" type="real" category="conv"
       group="vert_diff_nl" valid_values="" >
Maximum master length scale designed to address issues in diag_TKE outside the
boundary layer.
In order not to disturb turbulence characteristics in the lower troposphere,
this should be set at least larger than a few km. However, this does not
significantly improve the values outside of the boundary layer. Smaller values
make some improvement, but it is also noisy. Better results are seen using
eddy_leng_max or kv_freetrop_scale.
Default: 40.e3 (m)
</entry>

<entry id="eddy_leng_max" type="real" category="conv"
       group="vert_diff_nl" valid_values="" >
Maximum dissipation length scale designed to address issues with diag_TKE outside
the boundary layer, where the default value generates large diffusivities. A value
of 30 m is consistent with the length scales used in the HB scheme; however, this
will also reduce value in the boundary layer.
Default: 40.e3 (m)
</entry>

<entry id="eddy_max_bot_pressure" type="real" category="conv"
       group="vert_diff_nl" valid_values="" >
Bottom pressure level at which namelist values for eddy_leng_max and 
eddy_lbulk_max are applied. Default values are used at lower levels (i.e. the 
boundary layer).
Default: 100.e3 (hPa)
</entry>

<entry id="kv_top_pressure" type="real" category="conv"
       group="vert_diff_nl" valid_values="" >
Pressure (Pa) that defined the upper atmosphere for adjustment of
eddy diffusivities from diag_TKE using kv_top_scale.
Default: 0.
</entry>

<entry id="kv_top_scale" type="real" category="conv"
       group="vert_diff_nl" valid_values="" >
Scaling factor that is applied (multiplied) to the eddy diffusivities
in the upper atmosphere (see kv_top_pressure).
Default: 1.0
</entry>

<entry id="kv_freetrop_scale" type="real" category="conv"
       group="vert_diff_nl" valid_values="" >
Scaling factor that is applied (multiplied) to the eddy diffusivities
in the free troposphere (boundary layer to kv_top_pressure)
Default: 1.0
</entry>

<entry id="diff_cnsrv_mass_check" type="logical" category="conv"
       group="vert_diff_nl" valid_values="" >
Perform mass conservation check on eddy diffusion operation.
Default: FALSE
</entry>

<entry id="do_iss" type="logical" category="pbl"
       group="vert_diff_nl" valid_values="" >
Logical switch to turn on implicit turbulent surface stress calculation in
diffusion solver routine.
Default: set by build-namelist
</entry>

<!-- CARMA Sectional Microphysics -->

<entry id="carma_model" type="char*32" category="carma"
       group="carma_nl" valid_values="" >
The name of the active CARMA microphysics model or none when CARMA
is not active.
Default: none
</entry>

<entry id="carma_conmax" type="real" category="carma"
       group="carma_nl" valid_values="" >
A fraction that scales how tight the convergence criteria are to
determine that the substepping has resulted in a valid solution.
Smaller values will force more substepping.
CARMA particles.
Default: 0.1
</entry>

<entry id="carma_dt_threshold" type="real" category="carma"
       group="carma_nl" valid_values="" >
When non-zero, the largest change in temperature (K)
allowed per substep.
Default: 0.
</entry>

<entry id="carma_do_aerosol" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that the CARMA model is an aerosol model, and
should be called in tphysac.
Default: TRUE
</entry>

<entry id="carma_do_cldice" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that CARMA is a cloud ice model and should
be called in tphysbc.
Default: FALSE
</entry>

<entry id="carma_do_cldliq" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that CARMA is a cloud liquid model and should
be called in tphysbc.
Default: FALSE
</entry>

<entry id="carma_do_clearsky" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that CARMA should do clear sky calculations for
particles that are not part of a cloud in addition to doing a
separate calculation for incloud particles. Only valid when
carma_do_incloud is true.
Default: FALSE
</entry>

<entry id="carma_do_coag" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating whether the coagulation process is enabled for
CARMA particles.
Default: FALSE
</entry>

<entry id="carma_do_detrain" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that CARMA is responsible for detrain condensate
from convection into the model.
Default: FALSE
</entry>

<entry id="carma_do_drydep" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that the dry deposition process is enabled for
CARMA particles.
Default: FALSE
</entry>

<entry id="carma_do_emission" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that the emission of particles is enabled for
CARMA.
Default: FALSE
</entry>

<entry id="carma_do_explised" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that sedimentation should be calculated using an
explicit technique where the substepping is used to keep the CFL
condition from being violated rather than the default PPM scheme.
Default: FALSE
</entry>

<entry id="carma_do_fixedinit" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating CARMA coefficients should only be initialized once from
a fixed temperature profile rather than recomputed for each column. This
improves performance, but reduces accuracy. By default the temperature
profile used is calculated as the average of the initial condition file,
but a predefined profile can be provided.
Default: FALSE
</entry>

<entry id="carma_do_grow" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that the condensational growth process is enabled for
CARMA particles.
Default: FALSE
</entry>

<entry id="carma_do_hetchem" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that CARMA sulfate surface area density will be used
in heterogeneous chemistry rate calculation.
Default: FALSE
</entry>

<entry id="carma_do_incloud" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that CARMA should treat cloud particles as incloud
rather than gridbox average calculations.
Default: FALSE
</entry>

<entry id="carma_do_optics" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that carma should generate optical properties files
for the CAM radiation code.
Default: FALSE
</entry>

<entry id="carma_do_pheat" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that particle heating will be used for the condensational
growth process.
Default: FALSE
</entry>

<entry id="carma_do_pheatatm" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that particle heating will affect the atmospheric
temperature.
Default: FALSE
</entry>

<entry id="carma_do_substep" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that substepping will be used for the condensational
growth process.
Default: FALSE
</entry>

<entry id="carma_do_thermo" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that changes in heating will be calculated as a result
CARMA processes and will affect the CAM heating tendency.
Default: FALSE
</entry>

<entry id="carma_do_wetdep" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that the wet deposition process is enabled for
CARMA particles.
Default: FALSE
</entry>

<entry id="carma_do_vdiff" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that the effect of Brownian diffusion will be calculated for
CARMA particles. NOTE: This needs to be used in conjunction with CARMA
sedimentation.
Default: FALSE
</entry>

<entry id="carma_do_vtran" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating that the sedimentation process is enabled for
CARMA particles.
Default: FALSE
</entry>

<entry id="carma_flag" type="logical" category="carma"
       group="carma_nl" valid_values="" >
Flag indicating whether CARMA is enabled. If CARMA has been included
in the build (configure -carma with something other than none), then
this will cause all of the CARMA constituents and field names to be
registered, but no other CARMA process will be preformed. This overrides
the individual CARMA process flags.
Default: FALSE
</entry>

<entry id="carma_maxretries" type="integer" category="carma"
       group="carma_nl" valid_values="" >
Specifies the maximum number of retry attempts to be used when 
condensational growth requires substepping, but the original estimate
for the amount of substepping was insufficient.
Default: 8
</entry>

<entry id="carma_maxsubsteps" type="integer" category="carma"
       group="carma_nl" valid_values="" >
Specifies the maximum number of substeps that could be used for the
first guess when condensational growth requires substepping.
Default: 1
</entry>

<entry id="carma_reftfile" type="char*256" category="carma"
       group="carma_nl" valid_values="" >
Specifies the name of the reference temperature file that will be
used (and created if necessary)  for initialization of CARMA to a
fixed temperature profile.
Default: carma_reft.nc
</entry>

<entry id="carma_cstick" type="real" category="carma"
       group="carma_nl" valid_values="" >
Accommodation coefficient for coagulation.
Default: 1.0
</entry>

<entry id="carma_gsticki" type="real" category="carma"
       group="carma_nl" valid_values="" >
Accommodation coefficient for growth with ice.
Default: 0.93
</entry>

<entry id="carma_gstickl" type="real" category="carma"
       group="carma_nl" valid_values="" >
Accommodation coefficient for growth with liquid.
Default: 1.0
</entry>

<entry id="carma_tstick" type="real" category="carma"
       group="carma_nl" valid_values="" >
Accommodation coefficient for temperature.
Default: 1.0
</entry>

<entry id="carma_rhcrit" type="real" category="carma"
       group="carma_nl" valid_values="" >
Critical relative humidity for liquid cloud formation, used
for sub-grid scale in-cloud saturation.
Default: 1.0
</entry>


<!-- CARMA model - meteor smoke & pmc -->

<entry id="carma_do_escale" type="logical" category="carma_model"
       group="carma_model_nl" valid_values="" >
Flag indicating that meteor smoke emission will be scaled by a
global relative flux based upon the carma_escale_file.
Default: FALSE
</entry>

<entry id="carma_emis_total" type="real" category="carma_model"
       group="carma_model_nl" valid_values="" >
The total meteor smoke emission rate in kt/year. The flux will be
scaled to total that value.
Default: 16.0
</entry>

<entry id="carma_emis_file" type="char*256" input_pathname="abs" category="carma_model"
       group="carma_model_nl" valid_values="" >
Specifies the name of the file containing the meteor smoke emission
(ablation) profile.
Default: set by build-namelist.
</entry>

<entry id="carma_escale_file" type="char*256" input_pathname="abs" category="carma_model"
       group="carma_model_nl" valid_values="" >
Specifies the name of the file containing the global realtive flux
specification.
Default: set by build-namelist.
</entry>

<entry id="carma_launch_doy" type="integer" category="carma_model"
       group="carma_model_nl" valid_values="" >
Specifies the day of year when tracers will start being emitted for the tracer test.
Default: 1
</entry>

<entry id="carma_emission_rate" type="real" category="carma_model"
       group="carma_model_nl" valid_values="" >
The emission rate of inert tracers used in the test. A positive value indicates that
the rate is a column mass (kg/m2/s) and a negative value indicate that it is a mass
mixing ratio (kg/kg/s).
Default: 1e-9
</entry>

<!-- CARMA model - cirrus -->

<entry id="carma_sulfate_method" type="char*32" category="carma_model"
       group="carma_model_nl" valid_values="bulk,carma,fixed,modal" >
Specifies the method to use to get the prescribed sulfate aerosols for use with nucleation
of cirrus clouds. This can be different than the sulfate aerosols that are used with the
climate.
Default: fixed
</entry>

<!-- CARMA model - cirrus & pmc -->

<entry id="carma_mice_file" type="char*256" input_pathname="abs" category="carma_model"
       group="carma_model_nl" valid_values="" >
Specifies the name of the file containing ice refrative indicies as a function of wavelength
used for the particle heating calculation.
Default: set by build-namelist.
</entry>

<!-- CARMA model - dust -->

<entry id="carma_soilerosion_file" type="char*256" input_pathname="abs" category="carma_model"
       group="carma_model_nl" valid_values="" >
Specifies the name of the file containing soil erosion factors. This is used by
the dust model.
Default: set by build-namelist.
</entry>


<!-- CARMA model - sea salt -->

<entry id="carma_do_WeibullK" type="logical" category="carma_model"
       group="carma_model_nl" valid_values="" >
Flag indicating that a calculated Weibull K should be used.
Default: FALSE
</entry>

<entry id="carma_seasalt_emis" type="char*32" category="carma_model"
       group="carma_model_nl" valid_values="" >
Specifies the name of the sea salt emission parameterization.
Default: Gong
</entry>


=======
<!-- Ozone: Data (original CAM version) -->

<entry id="bndtvo" type="char*256" input_pathname="abs" category="o3_data_cam"
       group="cam3_ozone_data_nl" valid_values="" >
Full pathname of time-variant ozone mixing ratio boundary dataset.
Default: set by build-namelist.
</entry>

<entry id="cam3_ozone_data_on" type="logical"  category="o3_data_cam"
       group="cam3_ozone_data_nl" valid_values="" >
Add CAM3 prescribed ozone to the physics buffer.
Default: FALSE
</entry>

<entry id="ozncyc" type="logical"  category="o3_data_cam"
       group="cam3_ozone_data_nl" valid_values="" >
Flag for yearly cycling of ozone data. If set to FALSE, a multi-year
dataset is assumed, otherwise a single-year dataset is assumed, and ozone
will be cycled over the 12 monthly averages in the file.
Default: TRUE
</entry>

<!-- Performance Tuning and Profiling -->

<entry id="papi_ctr1_str" type="char*16"  category="performance"
       group="papi_inparm" valid_values="">
String identifying a hardware counter to the papi library.
Default: PAPI_TOT_CYC
</entry>

<entry id="papi_ctr2_str" type="char*16"  category="performance"
       group="papi_inparm" valid_values="">
String identifying a hardware counter to the papi library.
Default: PAPI_FP_OPS
</entry>

<entry id="papi_ctr3_str" type="char*16"  category="performance"
       group="papi_inparm" valid_values="">
String identifying a hardware counter to the papi library.
Default: PAPI_FP_INS
</entry>

<entry id="papi_ctr4_str" type="char*16"  category="performance"
       group="papi_inparm" valid_values="">
String identifying a hardware counter to the papi library.
Default: PAPI_NO_CTR
</entry>

<entry id="print_step_cost" type="logical"  category="performance"
       group="cam_inparm" valid_values="">
If TRUE, print CPU timing per model timestep. 
Default: FALSE
</entry>

<entry id="profile_barrier" type="logical"  category="performance"
       group="prof_inparm" valid_values="">
Flag indicating whether the mpi_barrier in t_barrierf should be called.
Default: FALSE
</entry>

<entry id="profile_depth_limit" type="integer"  category="performance"
       group="prof_inparm" valid_values="">
Maximum number of levels of timer nesting .
Default: 99999
</entry>

<entry id="profile_detail_limit" type="integer"  category="performance"
       group="prof_inparm" valid_values="">
Maximum detail level to profile.
Default: 1
</entry>

<entry id="profile_disable" type="logical"  category="performance"
       group="prof_inparm" valid_values="">
Flag indicating whether timers are disabled.
Default: FALSE
</entry>

<entry id="profile_global_stats" type="logical"  category="performance"
       group="prof_inparm" valid_values="">
Collect and print out global performance statistics (for this component communicator).
Default: FALSE
</entry>

<entry id="profile_outpe_num" type="integer"  category="performance"
       group="prof_inparm" valid_values="">
Maximum number of processes writing out timing data (for this component communicator).
Default: -1
</entry>

<entry id="profile_outpe_stride" type="integer"  category="performance"
       group="prof_inparm" valid_values="">
Separation between process ids for processes that are writing out timing data 
(for this component communicator).
Default: 1
</entry>

<entry id="profile_papi_enable" type="logical"  category="performance"
       group="prof_inparm" valid_values="">
Flag indicating whether the PAPI namelist should be read and HW performance counters
used in profiling.
Default: FALSE
</entry>

<entry id="profile_single_file" type="logical"  category="performance"
       group="prof_inparm" valid_values="">
Flag indicating whether the performance timer output should be written to a
single file (per component communicator) or to a separate file for each
process.
Default: TRUE
</entry>

<entry id="profile_timer" type="integer"  category="performance"
       group="prof_inparm" valid_values="">
Initialization of GPTL timing library.
Default: GPTLmpiwtime
</entry>

<entry id="swap_comm_protocol" type="integer"  category="performance"
       group="spmd_utils_nl" valid_values="">
Swap communication protocol option (reduced set):
 3, 5:                  nonblocking send
 2, 3, 4, 5:            nonblocking receive
 4, 5:                  ready send
Default: 4
</entry>

<entry id="swap_comm_maxreq" type="integer"  category="performance"
       group="spmd_utils_nl" valid_values="">
Swap communication maximum request count:
 &lt;=0: do not limit number of outstanding send/receive requests
  &gt;0: do not allow more than swap_comm_maxreq outstanding
      nonblocking send requests or nonblocking receive requests
Default: 128
</entry>

<entry id="fc_gather_flow_cntl" type="integer"  category="performance"
       group="spmd_utils_nl" valid_values="">
fc_gather flow control option:
 &lt; 0 : use MPI_Gather
 &gt;= 0: use point-to-point with handshaking messages and preposting 
       receive requests up to 
         max(min(1,fc_gather_flow_cntl),max_gather_block_size) 
       ahead. Default value is defined by private parameter 
       max_gather_block_size, which is currently set to 64.
Default: 64
</entry>

<!-- Physics Buffer -->

<entry id="pbuf_global_allocate" type="logical" category="pbuf"
       group="cam_inparm" valid_values="" >
Allocate all buffers as global.  This is a performance optimization on
machines for which allocation/deallocation of physpkg scope buffers on
every timestep was slow (Cray-X1).
Default: TRUE
</entry>

<!-- Physics control -->

<entry id="cam_physpkg" type="char*16" category="build"
       group="phys_ctl_nl" valid_values="cam3,cam4,cam5,ideal,adiabatic" >
Name of the CAM physics package.  N.B. this variable may not be set by
the user.  It is set by build-namelist via information in the configure
cache file to be consistent with how CAM was built.
Default: set by build-namelist
</entry>

<entry id="cam_chempkg" type="char*16" category="build"
       group="phys_ctl_nl" valid_values="waccm_mozart,waccm_ghg,trop_mozart,
                                         trop_ghg,trop_bam,trop_mam3,trop_mam7,
                                         super_fast_llnl,super_fast_llnl_mam3,none " >
Name of the CAM chemistry package.  N.B. this variable may not be set by
the user.  It is set by build-namelist via information in the configure
cache file to be consistent with how CAM was built.
Default: set by build-namelist
</entry>

<entry id="waccmx_opt" type="char*16" category="waccm"
       group="phys_ctl_nl" valid_values="ionosphere,neutral,off" >
Runtime options of upper thermosphere WACCM-X.  'ionosphere' for 
full ionopshere and neutral thermosphere, 'neutral' for just 
neutral thermosphere, and off for no WACCM-X.
Default: 'off'
</entry>

<!-- Reference Pressures -->

<entry id="trop_cloud_top_press" type="real" category="press_lim"
       group="ref_pres_nl" valid_values="" >
Troposphere cloud physics will be done only below the top defined
by this pressure (Pa).
Default: set by build-namelist
</entry>

<entry id="clim_modal_aero_top_press" type="real" category="press_lim"
       group="ref_pres_nl" valid_values="" >
MAM affects climate only below the top defined by this pressure (Pa).
Default: 0 for non-MAM cases, otherwise set by build-namelist
</entry>

<!-- Physics Debugging -->

<entry id="phys_debug_lat" type="real"  category="phys_debug"
       group="phys_debug_nl" valid_values="">
Use this variable to specify the latitude (in degrees) of a column to
debug.  The closest column in the physics grid will be used.
Default: none
</entry>

<entry id="phys_debug_lon" type="real"  category="phys_debug"
       group="phys_debug_nl" valid_values="">
Use this variable to specify the longitude (in degrees) of a column to
debug.  The closest column in the physics grid will be used.
Default: none
</entry>

<entry id="state_debug_checks" type="logical"  category="phys_debug"
       group="phys_ctl_nl" valid_values="">
If set to .true., turns on extra validation of physics_state objects
in physics_update. Used mainly to track down which package is the
source of invalid data in state.
Default: .false.
</entry>


<!-- Planetary Boundary Layer and Vertical Diffusion -->

<entry id="srf_flux_avg" type="integer" category="pbl"
       group="phys_ctl_nl" valid_values="0,1" >
Switch to turn on adjustment of the surface fluxes to reduce instabilities
in the surface layer.  Set to 1 to turn on the adjustments.
Default: 0 if <varname>eddy_scheme</varname> is 'HB', 1 otherwise.
</entry>

<!-- Yi-Chi: add HBGFS-->
<entry id="eddy_scheme" type="char*16" category="pbl"
       group="phys_ctl_nl" valid_values="HB,diag_TKE,HBR,CLUBB_SGS,HBGFS" >
Type of eddy scheme employed by the vertical diffusion package.  'HB' for
Holtslag and Boville; 'diag_TKE' for diagnostic tke version of Grenier and
Bretherton; 'HBR' for Rasch modified version of 'HB'. 'HBGFS' for HB + GFS cloudtop diffusion.
Default: 'HB'
</entry>

<!-- Diagnostics -->

<entry id="history_aerosol" type="logical"  category="diagnostics"
       group="phys_ctl_nl" valid_values="" >
Switch for diagnostic output of the aerosol tendencies
Default: .false.
</entry>

<entry id="history_aero_optics" type="logical"  category="diagnostics"
       group="phys_ctl_nl" valid_values="" >
Switch for diagnostic output of the aerosol optics
Default: .false.
</entry>

<entry id="history_eddy" type="logical"  category="diagnostics"
       group="phys_ctl_nl" valid_values="" >
Switch for diagnostic output of eddy variables 
Default: .false.
</entry>

<entry id="history_budget" type="logical"  category="diagnostics"
       group="phys_ctl_nl" valid_values="" >
Switch for cam4 T/Q budget diagnostic output
Default: .false.
</entry>

<entry id="history_budget_histfile_num" type="integer"  category="diagnostics"
       group="phys_ctl_nl" valid_values="1,2,3,4,5,6" >
History tape number T/Q budget output is written to.
Default: 1
</entry>

<!-- Radiation -->
<entry id="radiation_scheme" type="char*16" category="radiation"
       group="phys_ctl_nl" valid_values="rrtmg,camrt" >
Type of radiation scheme employed. 
Default: set by build-namelist
</entry>

<entry id="conv_water_in_rad" type="integer" category="radiation"
       group="phys_ctl_nl" valid_values="0,1,2" >
Convective water used in radiation?
0 ==> No
1 ==> Yes - Arithmetic average.
2 ==> Yes - Average in emissivity.
Default: set by build-namelist
</entry>

<entry id="absems_data" type="char*256" input_pathname="abs" category="radiation"
       group="cam_inparm" valid_values="" >
Full pathname of absorption/emission dataset.
It consists of terms used for determining the absorptivity and
emissivity of water vapor in the longwave parameterization of radiation.
Default: set by build-namelist.
</entry>

<entry id="iradae" type="integer"  category="radiation"
       group="cam_inparm" valid_values="">
Interval between absorptivity/emissivity calculations in time steps (if
positive) or model hours (if negative).  To avoid having the abs/ems values
saved on the restart output, make sure that the interval of the abs/ems
calculation evenly divides the restart interval.
Default: -12
</entry>

<entry id="iradlw" type="integer"  category="radiation"
       group="cam_inparm" valid_values="">
Interval of long-wave radiation calculation in timesteps (if positive) or
model hours (if negative).
Default: -1
</entry>

<entry id="iradsw" type="integer"  category="radiation"
       group="cam_inparm" valid_values="">
Interval of short-wave radiation calculation in timesteps (if positive) or
model hours (if negative).
Default: -1
</entry>

<entry id="irad_always" type="integer"  category="radiation"
       group="cam_inparm" valid_values="">
Specifies length of time in timesteps (positive) or hours (negative) SW/LW
radiation will be run for every timestep from the start of an initial run.
Default: 0
</entry>

<entry id="spectralflux" type="logical"  category="radiation"
       group="cam_inparm" valid_values="" >
Return fluxes per band in addition to the total fluxes.
Default: FALSE
</entry>

<entry id="mode_defs" type="char*256(60)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Definitions for the aerosol modes that may be used in the rad_climate and
rad_diag_* variables.
Default: set by build-namelist
</entry>

<entry id="rad_climate" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
A list of the radiatively active species, i.e., species that affect the
climate simulation via the radiative heating rate calculation.
Default: set by build-namelist
</entry>

<entry id="rad_diag_1" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
A list of species to be used in the first diagnostic radiative heating rate
calculation.  These species are not the ones affecting the climate
simulation.  This is a hook for performing radiative forcing calculations.
Default: none
</entry>

<entry id="rad_diag_2" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Analogous to rad_diag_1, but for the 2nd diagnostic calculation.
Default: none
</entry>

<entry id="rad_diag_3" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Analogous to rad_diag_1, but for the 3rd diagnostic calculation.
Default: none
</entry>

<entry id="rad_diag_4" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Analogous to rad_diag_1, but for the 4th diagnostic calculation.
Default: none
</entry>

<entry id="rad_diag_5" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Analogous to rad_diag_1, but for the 5th diagnostic calculation.
Default: none
</entry>

<entry id="rad_diag_6" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Analogous to rad_diag_1, but for the 6th diagnostic calculation.
Default: none
</entry>

<entry id="rad_diag_7" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Analogous to rad_diag_1, but for the 7th diagnostic calculation.
Default: none
</entry>

<entry id="rad_diag_8" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Analogous to rad_diag_1, but for the 8th diagnostic calculation.
Default: none
</entry>

<entry id="rad_diag_9" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Analogous to rad_diag_1, but for the 9th diagnostic calculation.
Default: none
</entry>

<entry id="rad_diag_10" type="char*256(30)"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
Analogous to rad_diag_1, but for the 10th diagnostic calculation.
Default: none
</entry>

<entry id="aer_drydep_list" type="char*16(1000)" category="cam_chem"
       group="chem_inparm" valid_values="" >
List of aerosol species that undergo dry deposition.
Default: set by build-namelist.
</entry>

<entry id="rad_data_output" type="logical"   category="radiation"
       group="rad_data_nl" valid_values="" >
output data needed for off-line radiation calculations
Default: FALSE
</entry>

<entry id="rad_data_histfile_num" type="integer"   category="radiation"
       group="rad_data_nl" valid_values="" >
History tape number radiation driver output data is written to.
Default: 0
</entry>

<entry id="rad_data_avgflag" type="char*1"   category="radiation"
       group="rad_data_nl" valid_values="" >
Averaging flag for adiation driver output data.
Default: 'A'
</entry>

<!-- Aerosol and cloud optics -->

<entry id="water_refindex_file" type="char*256" input_pathname="abs" category="radiation"
       group="modal_aer_opt_nl" valid_values="" >
Full pathname of dataset for water refractive indices used in modal aerosol optics
Default: none
</entry>


<entry id="drydep_srf_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="">
Dry deposition surface values interpolated to model grid, required for unstructured atmospheric grids
with modal chemistry.
Default: none
</entry>

<entry id="oldcldoptics" type="logical"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
filepath and name for ice optics data for rrtmg
Default: none
</entry>

<entry id="liqcldoptics" type="char*32"  category="radiation"
       group="rad_cnst_nl" valid_values="slingo,gammadist" >
filepath and name for ice optics data for rrtmg
Default: none
</entry>

<entry id="icecldoptics" type="char*32"  category="radiation"
       group="rad_cnst_nl" valid_values="ebertcurry,mitchell" >
filepath and name for ice optics data for rrtmg
Default: none
</entry>

<entry id="iceopticsfile" type="char*256" input_pathname="abs"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
filepath and name for ice optics data for rrtmg
Default: none
</entry>

<entry id="liqopticsfile" type="char*256" input_pathname="abs"  category="radiation"
       group="rad_cnst_nl" valid_values="" >
filepath and name for liquid cloud (gamma distributed) optics data for rrtmg
Default: none
</entry>


<!-- Rayleigh Friction Parameterization -->

<entry id="rayk0" type="integer" category="rayleigh_friction"
       group="cam_inparm" valid_values="">
Variable to specify the vertical index at which the
Rayleigh friction term is centered (the peak value).
Default: 2
</entry>

<entry id="raykrange" type="real" category="rayleigh_friction"
       group="cam_inparm" valid_values="">
Rayleigh friction parameter to determine the width of the profile.  If set
to 0 then a width is chosen by the algorithm (see rayleigh_friction.F90).
Default: 0.
</entry>

<entry id="raytau0" type="real" category="rayleigh_friction"
       group="cam_inparm" valid_values="">
Rayleigh friction parameter to determine the approximate value of the decay
time (days) at model top.  If 0.0 then no Rayleigh friction is applied.
Default: 0.
</entry>


<!-- Restart (Continuation and Branch) Runs -->

<entry id="cam_branch_file" type="char*256" category="restart"
       group="cam_inparm" valid_values="">
Full pathname of master restart file from which to branch. Setting is
Required for branch run.
Default: none
</entry>


<!-- Single column mode -->

<entry id="iopfile" type="char*128" input_pathname="abs" category="scam"
       group="cam_inparm" valid_values="" >
Full pathname of IOP dataset.
Default: set by build-namelist.
</entry>

<entry id="scm_crm_mode" type="logical" category="scam"
       group="cam_inparm" valid_values="">
Column radiation mode.
Default: FALSE
</entry>

<entry id="scm_diurnal_avg" type="logical" category="scam"
       group="cam_inparm" valid_values="">
If using diurnal averaging or not.
Default: FALSE
</entry>

<entry id="scm_iop_srf_prop" type="logical" category="scam"
       group="cam_inparm" valid_values="">
Use the specified surface properties.
Default: FALSE
</entry>

<entry id="scm_clubb_iop_name" type="char*200" category="scam"
       group="cam_inparm" valid_values="">
IOP name for CLUBB running in single column mode
Default: ""
</entry>

<entry id="scm_relaxation" type="logical" category="scam"
       group="cam_inparm" valid_values="">
Use relaxation.
Default: FALSE
</entry>

<!-- Solar Parameters -->

<entry id="solar_const" type="real" category="solar"
       group="solar_inparm" valid_values="">
Total solar irradiance (W/m2).
Default: set by build-namelist
</entry>

<entry id="solar_data_file" type="char*256" input_pathname="abs" category="solar"
       group="solar_inparm" valid_values="" >
Full pathname of dataset for file that contains the solar photon enerspectra or TSI data 
as a time series
Default: none
</entry>

<entry id="solar_data_type" type="char*8" category="solar"
       group="solar_inparm" valid_values="FIXED,SERIAL" >
Type of time interpolation for data in <varname>solar_data_file</varname>.
Can be set to "FIXED" or "SERIAL".
Default: SERIAL
</entry>

<entry id="solar_data_ymd" type="integer"  category="solar"
       group="solar_inparm" valid_values="" >
If <varname>solar_data_type</varname> is "FIXED" then solar_data_ymd
is the date the solar data is fixed to.  If <varname>solar_data_type</varname> 
is "SERIAL" the solar_data_ymd is the start date of the time series
of solar data.
Format: YYYYMMDD
Default: none
</entry>

<entry id="solar_data_tod" type="integer"  category="solar"
       group="solar_inparm" valid_values="" >
Seconds of the day corresponding to <varname>solar_data_ymd</varname>
Default: current model time of day
</entry>

<entry id="solar_htng_spctrl_scl" type="logical"  category="solar"
       group="solar_inparm" valid_values="" >
Use spectral scaling in the radiation heating 
Default: false
</entry>

<!-- Test Tracers -->

<entry id="tracers_flag" type="logical" category="test_tracers"
       group="cam_inparm" valid_values="" >
This variable should not be set by the user.  If configure has been invoked
with the '-nadv_tt N' option then build-namelist will set this flag to true
which turns on the test tracer code.  Also, if the user invokes configure
with the option '-nadv N', and N is larger than the number of advected
constituents requested by all other physics and chemistry
parameterizations, then the number of test tracers is chosen
dynamically to fill the available slots in the constituents array up to the
total number requested by the -nadv option.
Default: set by configure
</entry>

<entry id="aoa_tracers_flag" type="logical" category="test_tracers"
       group="aoa_tracers_nl" valid_values="" >
If true age of air tracers are included.  This variable should not be set
by the user.  It will be set by build-namelist to be consistent with the
'-age_of_air_trcs' argument specified to configure.
Default: set by configure
</entry>

<entry id="aoa_read_from_ic_file" type="logical" category="test_tracers"
       group="aoa_tracers_nl" valid_values="" >
If true age of air tracers are read from the initial conditions file.
If this is not specified then they are not read from IC file.
Default: TRUE
</entry>

<!-- Time step -->

<entry id="dtime" type="real"  category="time_mgr"
       group="cam_inparm" valid_values="">
The length (in seconds) of the coupling interval between the dynamics and
physics.  Changing this variable directly impacts the physical
parameterizations in the model and may impact the climate.  Changing
resolution usually requires a change in <varname>dtime</varname>.  
Default: is resolution and dycore dependent and is set by build-namelist.
</entry>

<!-- Topography -->

<entry id="bnd_topo" type="char*256" input_pathname="abs" category="topo"
       group="cam_inparm" valid_values="" >
Full pathname of time-invariant boundary dataset for topography fields.
Default: set by build-namelist.
</entry>

<!-- Tropopause -->

<entry id="tropopause_climo_file" type="char*256" input_pathname="abs" category="tropo"
       group="tropopause_nl" valid_values="" >
Full pathname of boundary dataset for tropopause climatology.
Default: set by build-namelist.
</entry>

<!-- CAM-CHEM -->

<entry id="ipcc_aircraft_emis" type="logical" category="cam_chem"
       group="camexp" valid_values="" >
Flag to tell build-namelist to use time-dependent external forcing
files for the aircraft emissions.
Default: FALSE
</entry>

<entry id="chem_rad_passive" type="logical" category="cam_chem"
       group="chem_inparm" valid_values="" >
Flag to set rad_climate variable so that the chemical tracers are
radiatively passive.
Default: FALSE
</entry>

<entry id="gas_wetdep_method" type="char*3" category="cam_chem"
       group="wetdep_inparm" valid_values="MOZ,NEU" >
Wet depostion method used
  MOZ --> mozart scheme is used
  NEU --> J Neu's scheme is used
Default: MOZ
</entry>

<entry id="gas_wetdep_list" type="char*16(1000)" category="cam_chem"
       group="wetdep_inparm" valid_values="" >
List of gas-phase species that undergo wet deposition via the wet deposition scheme.
Default: NONE
</entry>

<entry id="aer_wetdep_list" type="char*16(1000)" category="cam_chem"
       group="chem_inparm" valid_values="" >
List of aerosol species that undergo wet deposition.
Default: set by build-namelist.
</entry>

<entry id="sol_facti_cloud_borne" type="real" category="cam_chem"
       group="chem_inparm" valid_values="" >
In-cloud scav for cloud-borne aerosol tuning factor
Default: set by build-namelist.
</entry>

<entry id="airpl_emis_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of boundary dataset for airplane emissions.
Default: set by build-namelist.
</entry>

<entry id="clim_soilw_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset containing soil moisture fraction information used in 'xactive_atm' 
method of calculating dry deposition of chemical tracers.
Default: set by build-namelist.
</entry>

<entry id="depvel_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset which contains the prescribed deposition velocities used 
in the 'table' method of calculating dry deposition  of chemical tracers.
Default: set by build-namelist.
</entry>

<entry id="depvel_lnd_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset which contains land vegitation information used in 'xactive_atm' 
method of calculating dry deposition of chemical tracers.
Default: set by build-namelist.
</entry>

<entry id="season_wes_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset which contains season information used in 'xactive_atm' 
method of calculating dry deposition of chemical tracers.
Default: set by build-namelist.
</entry>

<entry id="dust_emis_fact" type="real" category="cam_chem"
       group="aerosol_nl" valid_values="" >
Tuning parameter for dust emissions.
Default: set by build-namelist.
</entry>

<entry id="efield_hflux_file" type="char*256" input_pathname="abs" category="waccm_phys"
       group="cam_inparm" valid_values="" >
Full pathname of dataset for coefficient data used in WACCM to calculate ion drag 
for high solar fluxes from the Scherliess low latitude electric potential model.
Default: set by build-namelist.
</entry>

<entry id="efield_lflux_file" type="char*256" input_pathname="abs" category="waccm_phys"
       group="cam_inparm" valid_values="" >
Full pathname of dataset for coefficient data used in WACCM to calculate ion drag 
for low solar fluxes from the Scherliess low latitude electric potential model.
Default: set by build-namelist.
</entry>

<entry id="efield_wei96_file" type="char*256" input_pathname="abs" category="waccm_phys"
       group="cam_inparm" valid_values="" >
Full pathname of dataset for coefficient data used in WACCM to calculate ion drag 
from the Weimer96 high latitude electric potential model.
Default: set by build-namelist.
</entry>

<entry id="electron_file" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for the neutral species absorption cross sections for EUV 
photo reactions producing electrons.
Default: set by build-namelist.
</entry>

<entry id="srf_emis_type" type="char*32" category="cam_chem"
       group="chem_inparm" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation of emission datasets specified.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
by <varname>srf_emis_specifier</varname>. 
Default: 'CYCLICAL'
</entry>

<entry id="srf_emis_cycle_yr" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The  cycle year of the surface emissions data
if <varname>srf_emis_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="srf_emis_fixed_ymd" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The date at which the surface emissions are fixed
if <varname>srf_emis_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="srf_emis_fixed_tod" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The time of day (seconds) corresponding to <varname>srf_emis_fixed_ymd</varname>
at which the surface emissions are fixed
if <varname>srf_emis_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="euvac_file" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for EUVAC solar EUV model (0.05-121nm).
Default: set by build-namelist.
</entry>

<entry id="euvacdat_file" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for variables used to compute the solar flux in the EUV 
wavelength regime.  Used to compute EUV photorates and heating from EUV photolysis.
Default: set by build-namelist.
</entry>

<entry id="ext_frc_cycle_yr" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The  cycle year of the external forcings (3D emissions) data
if <varname>ext_frc_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="ext_frc_fixed_ymd" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
Default: current model date
The date at which the external forcings are fixed
if <varname>ext_frc_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="ext_frc_fixed_tod" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The time of day (seconds) corresponding to <varname>ext_frc_fixed_ymd</varname>
at which the external forcings are fixed
if <varname>ext_frc_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="ext_frc_specifier" type="char*256(1000)" category="cam_chem"
       group="chem_inparm" valid_values="" >
List of full pathnames of elevated emission (or external chemical forcings) datasets.

The chemistry package reads in elevated emission data from a set of netcdf files in
units of "molecules/cm3/s".  Each tracer species emissions is read from its
own file as directed by the namelist variable <varname>ext_frc_specifier</varname>.  The
<varname>ext_frc_specifier</varname> variable tells the model which species have elevated
emissions and the file path for the corresponding species.  That is, the
<varname>ext_frc_specifier</varname> variable is set something like:

 ext_frc_specifier = 'SO2 -> /path/vrt.emis.so2.nc',
                     'SO4 -> /path/vrt.emis.so4.nc', etc...

Each emission file can have more than one source.  When the emission are
read in the sources are summed to give a total emission field for the
corresponding species.  The emission can be read in as time series of data,
cycle over a given year, or be fixed to a given date.

The vertical coordinate in these emissions files should be 'altitude' (km) so that the 
vertical redistribution to the model layers is done using a mass conserving method.  
If the vertical coordinate is altitude then data needs to be ordered from the
surface to the top (increasing altitude).

Default: set by build-namelist.
</entry>

<entry id="ext_frc_type" type="char*32" category="cam_chem"
       group="chem_inparm" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for fixed lower boundary data.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
Default: 'CYCLICAL'
</entry>

<entry id="flbc_cycle_yr" type="integer" category="cam_chem"
       group="chem_surfvals_nl" valid_values="" >
The cycle year of the fixed lower boundary data
if <varname>flbc_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>
<entry id="flbc_fixed_ymd" type="integer" category="cam_chem"
       group="chem_surfvals_nl" valid_values="" >
The date at which the fixed lower boundary data is fixed
if <varname>flbc_type</varname> is 'FIXED'..
Format: YYYYMMDD
Default: 0
</entry>
<entry id="flbc_fixed_tod" type="integer" category="cam_chem"
       group="chem_surfvals_nl" valid_values="" >
The time of day (seconds) corresponding to <varname>flbc_fixed_ymd</varname>
at which the fixed lower boundary data is fixed
if <varname>flbc_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="flbc_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_surfvals_nl" valid_values="" >
Full pathname of dataset for fixed lower boundary conditions.
Default: set by build-namelist.
</entry>

<entry id="flbc_list" type="char*16(1000)" category="cam_chem"
       group="chem_surfvals_nl" valid_values="" >
List of species that are fixed at the lower boundary.
Default: set by build-namelist.
</entry>

<entry id="flbc_type" type="char*8" category="cam_chem"
       group="chem_surfvals_nl" valid_values="CYCLICAL,SERIAL,FIXED" >
Type of time interpolation for fixed lower boundary data.
Default: 'CYCLICAL'
</entry>

<entry id="fstrat_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for chemical tracers constrained  in the stratosphere
Default: set by build-namelist.
</entry>

<entry id="fstrat_list" type="char*16(1000)" category="cam_chem"
       group="chem_inparm" valid_values="" >
List of species that are constrained in the stratosphere.
Default: set by build-namelist.
</entry>

<entry id="lght_landmask_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for land mask applied to the lighting NOx production  
Default: set by build-namelist.
</entry>

<entry id="lght_no_prd_factor" type="real" category="cam_chem"
       group="chem_inparm" valid_values="" >
Multiplication factor  applied to the lighting NOx production  
Default: 1.0.
</entry>

<entry id="no_xfac_ubc" type="real" category="waccm"
       group="chem_inparm" valid_values="" >
Multiplication factor applied to the upper boundary NO mass mixing ratio. 
Default: 1.0
</entry>

<entry id="photon_file" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for the neutral species absorption cross sections.
Default: set by build-namelist.
</entry>

<entry id="tuv_xsect_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for fast-tuv photolysis cross sections
Default: set by build-namelist.
</entry>

<entry id="o2_xsect_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset of O2 cross sections for fast-tuv photolysis 
Default: set by build-namelist.
</entry>

<entry id="exo_coldens_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset of O2 and 03 column densities above the model for look-up-table photolysis 
Default: set by build-namelist.
</entry>

<entry id="aircraft_specifier" type="char*256(100)" category="cam_chem"
       group="aircraft_emit_nl" valid_values="" >
Full pathname of the aircraft input file list
Default: none
</entry>

<entry id="aircraft_type" type="char*32" category="cam_chem"
       group="aircraft_emit_nl" valid_values="CYCLICAL_LIST" >
Type of time interpolation for data in aircraft aerosol files.
Default: 'CYCLICAL_LIST'
</entry>

<entry id="prescribed_aero_datapath" type="char*256" input_pathname="abs" category="cam_chem"
       group="prescribed_aero_nl" valid_values="" >
Full pathname of the directory that contains the files specified in
<varname>prescribed_aero_filelist</varname>.
Default: set by build-namelist.
</entry>

<entry id="prescribed_aero_model" type="char*5" category="cam_chem"
       group="camexp" valid_values="bulk,modal" >
Switch used to indicate which type of aerosols are prescribed -- bulk or modal.
This is used to set the default <varname>prescribed_aero_specifier</varname> and 
<varname>aerodep_flx_specifier</varname> namelist variables.
Default: bulk
</entry>

<entry id="prescribed_aero_file" type="char*256" input_pathname="rel:prescribed_aero_datapath" category="cam_chem"
       group="prescribed_aero_nl" valid_values="" >
Filename of dataset for prescribed aerosols.
Default: set by build-namelist.
</entry>

<entry id="prescribed_aero_filelist" type="char*256" input_pathname="rel:prescribed_aero_datapath" category="cam_chem"
       group="prescribed_aero_nl" valid_values="" >
Filename of file that contains a sequence of filenames for prescribed
aerosols.  The filenames in this file are relative to the directory specied
by <varname>prescribed_aero_datapath</varname>.
Default: set by build-namelist.
</entry>

<entry id="prescribed_aero_rmfile" type="logical" category="cam_chem"
       group="prescribed_aero_nl" valid_values="" >
Remove the file containing prescribed aerosol concentrations from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="prescribed_aero_specifier" type="char*32(50)" category="cam_chem"
       group="prescribed_aero_nl" valid_values="" >
A list of variable names of the concentration fields in the prescribed aerosol datasets
and corresponding names used in the physics buffer seperated by colons.  For example:

 prescribed_aero_specifier = 'pbuf_name1:ncdf_fld_name1','pbuf_name2:ncdf_fld_name2', ...

If there is no colon seperater then the specified name is used as both the pbuf_name and ncdf_fld_name,

Default: none
</entry>

<entry id="prescribed_aero_type" type="char*32" category="cam_chem"
       group="prescribed_aero_nl" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for data in prescribed_aero files.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
Default: 'SERIAL'
</entry>

<entry id="prescribed_aero_cycle_yr" type="integer" category="cam_chem"
       group="prescribed_aero_nl" valid_values="" >
The  cycle year of the prescribed aerosol data
if <varname>prescribed_aero_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="prescribed_aero_fixed_ymd" type="integer" category="cam_chem"
       group="prescribed_aero_nl" valid_values="" >
The date at which the prescribed aerosol data is fixed
if <varname>prescribed_aero_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="prescribed_aero_fixed_tod" type="integer" category="cam_chem"
       group="prescribed_aero_nl" valid_values="" >
The time of day (seconds) corresponding to <varname>prescribed_aero_fixed_ymd</varname>
at which the prescribed aerosol data is fixed
if <varname>prescribed_aero_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="aerodep_flx_datapath" type="char*256" input_pathname="abs" category="cam_chem"
       group="aerodep_flx_nl" valid_values="" >
Full pathname of the directory that contains the files specified in
<varname>aerodep_flx_filelist</varname>.
Default: set by build-namelist.
</entry>

<entry id="aerodep_flx_file" type="char*256" input_pathname="rel:aerodep_flx_datapath" category="cam_chem"
       group="aerodep_flx_nl" valid_values="" >
Filename of dataset for prescribed aerosols.
Default: set by build-namelist.
</entry>

<entry id="aerodep_flx_filelist" type="char*256" input_pathname="rel:aerodep_flx_datapath" category="cam_chem"
       group="aerodep_flx_nl" valid_values="" >
Filename of file that contains a sequence of filenames for prescribed
aerosols.  The filenames in this file are relative to the directory specied
by <varname>aerodep_flx_datapath</varname>.
Default: set by build-namelist.
</entry>

<entry id="aerodep_flx_rmfile" type="logical" category="cam_chem"
       group="aerodep_flx_nl" valid_values="" >
Remove the file containing prescribed aerosol deposition fluxes from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="aerodep_flx_specifier" type="char*32(22)" category="cam_chem"
       group="aerodep_flx_nl" valid_values="" >
Names of variables containing aerosol data in the prescribed aerosol datasets.
Default: none
</entry>

<entry id="aerodep_flx_type" type="char*32" category="cam_chem"
       group="aerodep_flx_nl" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for data in aerodep_flx files.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
Default: 'SERIAL'
</entry>

<entry id="aerodep_flx_cycle_yr" type="integer" category="cam_chem"
       group="aerodep_flx_nl" valid_values="" >
The  cycle year of the prescribed aerosol flux data
if <varname>aerodep_flx_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="aerodep_flx_fixed_ymd" type="integer" category="cam_chem"
       group="aerodep_flx_nl" valid_values="" >
The date at which the prescribed aerosol flux data is fixed
if <varname>aerodep_flx_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="aerodep_flx_fixed_tod" type="integer" category="cam_chem"
       group="aerodep_flx_nl" valid_values="" >
The time of day (seconds) corresponding to <varname>ssaerodep_flx_fixed_ymd</varname>
at which the prescribed aerosol flux data is fixed
if <varname>saerodep_flx_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="prescribed_ghg_datapath" type="char*256" input_pathname="abs" category="cam_chem"
       group="prescribed_ghg_nl" valid_values="" >
Full pathname of the directory that contains the files specified in
<varname>prescribed_ghg_filelist</varname>.
Default: set by build-namelist.
</entry>

<entry id="prescribed_ghg_file" type="char*256" input_pathname="rel:prescribed_ghg_datapath" category="cam_chem"
       group="prescribed_ghg_nl" valid_values="" >
Filename of dataset for prescribed GHGs.
Default: set by build-namelist.
</entry>

<entry id="prescribed_ghg_filelist" type="char*256" input_pathname="rel:prescribed_ghg_datapath" category="cam_chem"
       group="prescribed_ghg_nl" valid_values="" >
Filename of file that contains a sequence of filenames for prescribed
GHGs.  The filenames in this file are relative to the directory specied
by <varname>prescribed_ghg_datapath</varname>.
Default: set by build-namelist.
</entry>

<entry id="prescribed_ghg_rmfile" type="logical" category="cam_chem"
       group="prescribed_ghg_nl" valid_values="" >
Remove the file containing prescribed green house gas concentrations from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="prescribed_ghg_specifier" type="char*16(100)" category="cam_chem"
       group="prescribed_ghg_nl" valid_values="" >
Names of variables containing GHG data in the prescribed GHG datasets.
Default: none
</entry>

<entry id="prescribed_ghg_type" type="char*32" category="cam_chem"
       group="prescribed_ghg_nl" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for data in prescribed_ghg files.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
Default: 'SERIAL'
</entry>

<entry id="prescribed_ghg_cycle_yr" type="integer" category="cam_chem"
       group="prescribed_ghg_nl" valid_values="" >
The  cycle year of the prescribed green house gas data
if <varname>prescribed_ghg_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="prescribed_ghg_fixed_ymd" type="integer" category="cam_chem"
       group="prescribed_ghg_nl" valid_values="" >
The date at which the prescribed green house gas data  is fixed
if <varname>prescribed_ghg_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="prescribed_ghg_fixed_tod" type="integer" category="cam_chem"
       group="prescribed_ghg_nl" valid_values="" >
The time of day (seconds) corresponding to <varname>prescribed_ghg_fixed_ymd</varname>
at which the prescribed green house gas data is fixed
if <varname>prescribed_ghg_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="prescribed_ozone_datapath" type="char*256" input_pathname="abs" category="cam_chem"
       group="prescribed_ozone_nl" valid_values="" >
Full pathname of the directory that contains the files specified in
<varname>prescribed_ozone_filelist</varname>.
Default: set by build-namelist.
</entry>

<entry id="prescribed_ozone_file" type="char*256" input_pathname="rel:prescribed_ozone_datapath" category="cam_chem"
       group="prescribed_ozone_nl" valid_values="" >
Filename of dataset for prescribed ozone.
Default: set by build-namelist.
</entry>

<entry id="prescribed_ozone_filelist" type="char*256" input_pathname="rel:prescribed_ozone_datapath" category="cam_chem"
       group="prescribed_ozone_nl" valid_values="" >
Filename of file that contains a sequence of filenames for prescribed
ozone.  The filenames in this file are relative to the directory specied
by <varname>prescribed_ozone_datapath</varname>.
Default: set by build-namelist.
</entry>

<entry id="prescribed_ozone_name" type="char*16" category="cam_chem"
       group="prescribed_ozone_nl" valid_values="" >
Name of variable containing ozone data in the prescribed ozone datasets.
Default: 'ozone'
</entry>

<entry id="prescribed_ozone_rmfile" type="logical" category="cam_chem"
       group="prescribed_ozone_nl" valid_values="" >
Remove the file containing prescribed ozone concentrations from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="prescribed_ozone_type" type="char*32" category="cam_chem"
       group="prescribed_ozone_nl" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for data in prescribed_ozone files.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
Default: 'SERIAL'
</entry>

<entry id="prescribed_ozone_cycle_yr" type="integer" category="cam_chem"
       group="prescribed_ozone_nl" valid_values="" >
The  cycle year of the prescribed ozone data
if <varname>prescribed_ozone_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="prescribed_ozone_fixed_ymd" type="integer" category="cam_chem"
       group="prescribed_ozone_nl" valid_values="" >
The date at which the prescribed ozone data is fixed
if <varname>prescribed_ozone_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="prescribed_ozone_fixed_tod" type="integer" category="cam_chem"
       group="prescribed_ozone_nl" valid_values="" >
The time of day (seconds) corresponding to <varname>prescribed_ozone_fixed_ymd</varname>
at which the prescribed ozone data is fixed
if <varname>prescribed_ozone_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="prescribed_volcaero_datapath" type="char*256" input_pathname="abs" category="cam_chem"
       group="prescribed_volcaero_nl" valid_values="" >
Full pathname of the directory that contains the files specified in
<varname>prescribed_volcaero_filelist</varname>.
Default: set by build-namelist.
</entry>

<entry id="prescribed_volcaero_file" type="char*256" input_pathname="rel:prescribed_volcaero_datapath" category="cam_chem"
       group="prescribed_volcaero_nl" valid_values="" >
Filename of dataset for prescribed volcaero.
Default: set by build-namelist.
</entry>

<entry id="prescribed_volcaero_filelist" type="char*256" input_pathname="rel:prescribed_volcaero_datapath" category="cam_chem"
       group="prescribed_volcaero_nl" valid_values="" >
Filename of file that contains a sequence of filenames for prescribed
volcaero.  The filenames in this file are relative to the directory specied
by <varname>prescribed_volcaero_datapath</varname>.
Default: set by build-namelist.
</entry>

<entry id="prescribed_volcaero_name" type="char*16" category="cam_chem"
       group="prescribed_volcaero_nl" valid_values="" >
Name of variable containing volcaero data in the prescribed volcaero datasets.
Default: 'MMRVOLC'
</entry>

<entry id="prescribed_volcaero_rmfile" type="logical" category="cam_chem"
       group="prescribed_volcaero_nl" valid_values="" >
Remove the file containing prescribed volcanic aerosol concentrations from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="prescribed_volcaero_type" type="char*32" category="cam_chem"
       group="prescribed_volcaero_nl" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for data in prescribed_volcaero files.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
Default: 'SERIAL'
</entry>

<entry id="prescribed_volcaero_cycle_yr" type="integer" category="cam_chem"
       group="prescribed_volcaero_nl" valid_values="" >
The  cycle year of the prescribed volcanic aerosol data
if <varname>prescribed_volcaero_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="prescribed_volcaero_fixed_ymd" type="integer" category="cam_chem"
       group="prescribed_volcaero_nl" valid_values="" >
The date at which the prescribed volcanic aerosol data  is fixed
if <varname>prescribed_volcaero_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="prescribed_volcaero_fixed_tod" type="integer" category="cam_chem"
       group="prescribed_volcaero_nl" valid_values="" >
The time of day (seconds) corresponding to <varname>prescribed_volcaero_fixed_ymd</varname>
at which the prescribed volcanic aerosol data is fixed
if <varname>prescribed_volcaero_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="rsf_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for radiative source function used in look up table photloysis
Default: set by build-namelist.
</entry>

<entry id="sad_file" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for stratospheric aerosol densities
Default: set by build-namelist.
</entry>

<entry id="sad_cycle_yr" type="integer" category="waccm"
       group="chem_inparm" valid_values="" >
The cycle year of the stratospheric aerosol data
if <varname>sad_cycle_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>
<entry id="sad_fixed_ymd" type="integer" category="waccm"
       group="chem_inparm" valid_values="" >
The date at which the stratospheric aerosol data is fixed
if <varname>sad_type</varname> is 'FIXED'..
Format: YYYYMMDD
Default: 0
</entry>
<entry id="sad_fixed_tod" type="integer" category="waccm"
       group="chem_inparm" valid_values="" >
The time of day (seconds) corresponding to <varname>sad_fixed_ymd</varname>
at which the stratospheric aerosol data is fixed
if <varname>sad_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="sad_type" type="char*16" category="waccm"
       group="chem_inparm" valid_values="FIXED,SERIAL,CYCLICAL" >
Type of time interpolation for stratospheric aerosol density data.
Can be set to 'CYCLICAL', 'SERIAL', or 'FIXED'.
Default: 'CYCLICAL'
</entry>

<entry id="snoe_ubc_file" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for the coefficients of the NOEM nitric oxide model used 
to calculate its upper boundary concentration.
Default: set by build-namelist.
</entry>

<entry id="soil_erod" type="char*256" input_pathname="abs" category="cam_chem"
       group="aerosol_nl" valid_values="" >
Full pathname of boundary dataset for soil erodibility factors.
Default: set by build-namelist.
</entry>

<entry id="solar_parms_file" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Full pathname of time-variant boundary dataset for the time-dependent proxies for 
solar and geomagnetic activity( F10.7, F10.7a, Kp, Ap ).
Default: set by build-namelist.
</entry>

<entry id="gw_drag_file" type="char*256" input_pathname="abs" category="waccm_phys"
       group="gw_drag_nl" valid_values="" >
Full pathname of Bers lookup table data file for gravity waves.
Default: set by build-namelist.
</entry>

<entry id="srf_emis_specifier" type="char*256(1000)" category="cam_chem"
       group="chem_inparm" valid_values="" >
List of full pathnames of surface emission datasets.

The chemistry package reads in emission data from a set of netcdf files in
units of "molecules/cm2/s".  Each tracer species emissions is read from its
own file as directed by the namelist variable <varname>srf_emis_specifier</varname>.  The
<varname>srf_emis_specifier</varname> variable tells the model which species have emissions
and the file path for the corresponding species.  That is, the
<varname>srf_emis_specifier</varname> variable is set something like:

 srf_emis_specifier = 'CH4 -> /path/emis.ch4.nc',
                      'CO  -> /path/emis.co.nc', etc...

Each emission file can have more than one source.  When the emission are
read in the sources are summed to give a total emission field for the
corresponding species.  The emission can be read in as time series of data,
cycle over a given year, or be fixed to a given date.

Default: set by build-namelist.
</entry>

<entry id="sulf_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset containing tropopheric sulfate aerosols
Default: set by build-namelist.
</entry>

<entry id="tgcm_ubc_file" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for TGCM upper boundary
Default: set by build-namelist.
</entry>
<entry id="tgcm_ubc_data_type" type="char*32" category="waccm"
       group="chem_inparm" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for data in TGCM upper boundary file.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
Default: 'SERIAL'
</entry>

<entry id="tgcm_ubc_cycle_yr" type="integer" category="waccm"
       group="chem_inparm" valid_values="" >
The cycle year of the TGCM upper boundary data
if <varname>tgcm_ubc_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="tgcm_ubc_fixed_ymd" type="integer" category="waccm"
       group="chem_inparm" valid_values="" >
The date at which the TGCM upper boundary data is fixed
if <varname>tgcm_ubc_type</varname> is 'FIXED'.
Format: YYYY
Default: 0
</entry>

<entry id="tgcm_ubc_fixed_tod" type="integer" category="waccm"
       group="chem_inparm" valid_values="" >
The time of day (seconds) corresponding to <varname>tgcm_ubc_fixed_ymd</varname>
at which the TGCM upper boundary data is fixed
if <varname>tgcm_ubc_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="t_pert_ubc" type="real" category="waccm"
       group="chem_inparm" valid_values="" >
Perturbation applied to the upper boundary temperature.
Default: 0.0
</entry>

<entry id="chem_freq" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
Frequency in time steps at which the chemical equations are solved.
Default: 1
</entry>

<entry id="chlorine_loading_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Filename of dataset for linoz cholirine loading.
Default: none.
</entry>
<entry id="chlorine_loading_type" type="char*8" category="cam_chem"
       group="chem_inparm" valid_values="SERIAL,FIXED" >
Type of time interpolation type for data in  <varname>chlorine_loading_file</varname>
Default: 'SERIAL'
</entry>
<entry id="chlorine_loading_fixed_tod" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The time of day (seconds) corresponding to <varname>chlorine_loading_fixed_ymd</varname>
at which the chlorine loading data is fixed
if <varname>chlorine_loading_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>
<entry id="chlorine_loading_fixed_ymd" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The date at which the chlorine loading data is fixed
if <varname>chlorine_loading_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>


<entry id="linoz_data_path" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of the directory that contains the files specified in
<varname>linoz_data_filelist</varname>.
Default: none.
</entry>

<entry id="linoz_data_file" type="char*256" input_pathname="rel:linoz_data_path" category="cam_chem"
       group="chem_inparm" valid_values="" >
Filename of dataset for LINOZ data.
Default: none.
</entry>

<entry id="linoz_data_filelist" type="char*256" input_pathname="rel:linoz_data_datapath" category="cam_chem"
       group="chem_inparm" valid_values="" >
Filename of file that contains a sequence of filenames of the linoz data.  
The filenames in this file are relative to the directory specied
by <varname>linoz_data_datapath</varname>.
Default: set by build-namelist.
</entry>

<entry id="linoz_data_type" type="char*24" category="cam_chem"
       group="chem_inparm" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for data in linoz_data files.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
Default: 'SERIAL'
</entry>

<entry id="linoz_data_rmfile" type="logical" category="cam_chem"
       group="chem_inparm" valid_values="TRUE,FALSE" >
Remove the file containing LINOZ data from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="linoz_data_cycle_yr" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The  cycle year of the LINOZ data
if <varname>linoz_data_type</varname> is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="linoz_data_fixed_ymd" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The date at which the LINOZ data  is fixed
if <varname>linoz_data_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="linoz_data_fixed_tod" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The time of day (seconds) corresponding to <varname>linoz_data_fixed_ymd</varname>
at which the LINOZ data is fixed
if <varname>linoz_data_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="tracer_cnst_datapath" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of the directory that contains the files specified in
<varname>tracer_cnst_filelist</varname>.
Default: set by build-namelist.
</entry>

<entry id="tracer_cnst_file" type="char*256" input_pathname="rel:tracer_cnst_datapath" category="cam_chem"
       group="chem_inparm" valid_values="" >
Filename of dataset for the prescribed chemical constituents.
Default: set by build-namelist.
</entry>

<entry id="tracer_cnst_filelist" type="char*256" input_pathname="rel:tracer_cnst_datapath" category="cam_chem"
       group="chem_inparm" valid_values="" >
Filename of file that contains a sequence of filenames for the prescribed chemical constituents.  
The filenames in this file are relative to the directory specied
by <varname>tracer_cnst_datapath</varname>.
Default: set by build-namelist.
</entry>

<entry id="tracer_cnst_rmfile" type="logical" category="cam_chem"
       group="chem_inparm" valid_values="" >
Remove the file containing prescribed chemical constituents from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="tracer_cnst_specifier" type="char*256(100)" category="cam_chem"
       group="chem_inparm" valid_values="" >
List of prescribed chemical constituents.
Default: set by build-namelist.
</entry>

<entry id="tracer_cnst_type" type="char*24" category="cam_chem"
       group="chem_inparm" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for data in tracer_cnst files.
Default: 'SERIAL'
</entry>

<entry id="tracer_cnst_cycle_yr" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The  cycle year of the prescribed chemical constituents data
if <varname>tracer_cnst_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="tracer_cnst_fixed_ymd" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The date at which the chemical constituents data is fixed
if <varname>tracer_cnst_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="tracer_cnst_fixed_tod" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The time of day (seconds) corresponding to <varname>tracer_cnst_fixed_ymd</varname>
at which the chemical constituents data is fixed
if <varname>tracer_cnst_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="tracer_srcs_datapath" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of the directory that contains the files specified in
<varname>tracer_srcs_filelist</varname>.
Default: set by build-namelist.
</entry>

<entry id="tracer_srcs_file" type="char*256" input_pathname="rel:tracer_srcs_datapath" category="cam_chem"
       group="chem_inparm" valid_values="" >
Filename of dataset for the prescribed chemical sources.
Default: set by build-namelist.
</entry>

<entry id="tracer_srcs_filelist" type="char*256" input_pathname="rel:tracer_srcs_datapath" category="cam_chem"
       group="chem_inparm" valid_values="" >
Filename of file that contains a sequence of datasets for the prescribed chemical sources.
The filenames in this file are relative to the directory specied
by <varname>tracer_srcs_datapath</varname>.
Default: set by build-namelist.
</entry>

<entry id="tracer_srcs_rmfile" type="logical" category="cam_chem"
       group="chem_inparm" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Remove the file containing prescribed chemical sources from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="tracer_srcs_specifier" type="char*256(100)" category="cam_chem"
       group="chem_inparm" valid_values="" >
List of prescribed chemical sources
Default: set by build-namelist.
</entry>

<entry id="tracer_srcs_type" type="char*24" category="cam_chem"
       group="chem_inparm" valid_values="" >
Type of time interpolation for data in tracer_srcs files.
Default: 'SERIAL'
</entry>

<entry id="tracer_srcs_cycle_yr" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The  cycle year of the prescribed chemical sources data
if <varname>tracer_srcs_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="tracer_srcs_fixed_ymd" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The date at which the chemical sources data is fixed
if <varname>tracer_srcs_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="tracer_srcs_fixed_tod" type="integer" category="cam_chem"
       group="chem_inparm" valid_values="" >
The time of day (seconds) corresponding to <varname>tracer_srcs_fixed_ymd</varname>
at which the chemical sources data is fixed
if <varname>tracer_srcs_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="use_cam_sulfchem" type="logical"  category="cam_chem"
       group="chem_inparm" valid_values="" >
If TRUE use CAM sulfur chemistry driver rather than mo_setsox.
Default: FALSE
</entry>

<entry id="xactive_prates" type="logical" category="cam_chem"
       group="chem_inparm" valid_values="" >
If TRUE then use the FTUV method to calculate the photolysis reactions rates,
otherwise use the look up table method.
Default: FALSE
</entry>

<entry id="xs_coef_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of dataset for  Chebyshev polynomial Coeff data used for photolysis
cross sections.
Default: set by build-namelist.
</entry>

<entry id="xs_long_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of cross section dataset for long wavelengh photolysis
Default: set by build-namelist.
</entry>

<entry id="xs_short_file" type="char*256" input_pathname="abs" category="cam_chem"
       group="chem_inparm" valid_values="" >
Full pathname of cross section dataset for short wavelengh photolysis
Default: set by build-namelist.
</entry>

<!-- Namelist read by seq_drydep_mod and shared by CAM and CLM -->

<entry id="drydep_list" type="char*16(1000)" category="dry_deposition"
       group="drydep_inparm" valid_values="" >
List of species that undergo dry deposition.
Default: set by build-namelist.
</entry>

<entry id="drydep_method" type="char*16" category="dry_deposition"
       group="drydep_inparm" valid_values="xactive_atm,xactive_lnd,table" >
Dry deposition method used.  This specifies the method used to calculate dry
deposition velocities of gas-phase chemical species.  The available methods 
are:
 'table'       - prescribed method in CAM
 'xactive_atm' - interactive method in CAM
 'xactive_lnd' - interactive method in CLM
Default: set by build-namelist
</entry>

<entry id="megan_factors_file" type="char*256" input_pathname="abs" category="VOC_emissions"
       group="megan_emis_nl" valid_values="" >
File containing MEGAN emissions factors.
Default: set by build-namelist.
</entry>

<entry id="megan_specifier" type="char*1024(100)" category="VOC_emissions"
       group="megan_emis_nl" valid_values="" >
MEGAN specifier.
Default: set by build-namelist.
</entry>

<entry id="megan_mapped_emisfctrs" type="logical" category="VOC_emissions"
       group="megan_emis_nl" valid_values=".true.,.false." >
MEGAN mapped isoprene emissions facters switch
If true then use mapped MEGAN emissions facters for isoprene.
Default: .false.
</entry>

<entry id="carma_fields" type="char*256" category="carma"
       group="carma_inparm" valid_values="" >
List of fluxes needed by the CARMA model, from CLM to CAM.
Default: set by build-namelist.
</entry>

<!-- WACCM_GHG Chemistry -->

<entry id="waccm_forcing_file" type="char*256" input_pathname="rel:waccm_forcing_datapath" category="waccm_ghg"
       group="waccm_forcing_nl" valid_values="" >
Filename of the prescribed waccm forcing data used with waccm_ghg chemistry.
This contains prescribed constituents for non-LTE calculations and heating rates 
for wavelengths less than 200 nm.
Default: set by build-namelist.
</entry>

<entry id="waccm_forcing_datapath" type="char*256" input_pathname="abs" category="waccm_ghg"
       group="waccm_forcing_nl" valid_values="" >
Full pathname of the directory that contains the files specified in
<varname>waccm_forcing_filelist</varname>.
Default: set by build-namelist.
</entry>

<entry id="waccm_forcing_filelist" type="char*256" input_pathname="rel:waccm_forcing_datapath" category="waccm_ghg"
       group="waccm_forcing_nl" valid_values="" >
A file that contains a sequence of filenames for prescribed waccm forcing data.  
The filenames in this file are relative to the directory specied 
by <varname>waccm_forcing_datapath</varname>.
Default: set by build-namelist.
</entry>

<entry id="waccm_forcing_rmfile" type="logical" category="waccm_ghg"
       group="waccm_forcing_nl" valid_values="" >
Remove the file containing prescribed waccm forcing data from local disk when no longer needed.
Default: FALSE
</entry>

<entry id="waccm_forcing_specifier" type="char*16(100)" category="waccm_ghg"
       group="waccm_forcing_nl" valid_values="" >
Names of variables containing concentrations and heating rate in the prescribed waccm forcing datasets.
Default: none
</entry>

<entry id="waccm_forcing_type" type="char*32" category="waccm_ghg"
       group="waccm_forcing_nl" valid_values="CYCLICAL,SERIAL,INTERP_MISSING_MONTHS,FIXED" >
Type of time interpolation for data in waccm_forcing files.
Can be set to 'CYCLICAL', 'SERIAL', 'INTERP_MISSING_MONTHS', or 'FIXED'.
Default: 'CYCLICAL'
</entry>

<entry id="waccm_forcing_cycle_yr" type="integer" category="waccm_ghg"
       group="waccm_forcing_nl" valid_values="" >
The  cycle year of the prescribed waccm forcing data
if <varname>waccm_forcing_type</varname>  is 'CYCLICAL'.
Format: YYYY
Default: 0
</entry>

<entry id="waccm_forcing_fixed_ymd" type="integer" category="waccm_ghg"
       group="waccm_forcing_nl" valid_values="" >
The date at which the prescribed waccm forcing data is fixed
if <varname>waccm_forcing_type</varname> is 'FIXED'.
Format: YYYYMMDD
Default: 0
</entry>

<entry id="waccm_forcing_fixed_tod" type="integer" category="waccm_ghg"
       group="waccm_forcing_nl" valid_values="" >
The time of day (seconds) corresponding to <varname>waccm_forcing_fixed_ymd</varname>
at which the prescribed waccm forcing data is fixed
if <varname>waccm_forcing_type</varname> is 'FIXED'.
Default: 0 seconds
</entry>

<entry id="h2orates" type="char*256" input_pathname="abs" category="waccm_ghg"
       group="chem_inparm" valid_values="" >
Full pathname of time-variant boundary dataset for H2O production/loss rates.
Default: set by build-namelist.
</entry>

<!-- WACCM -->

<entry id="strat_aero_feedback" type="logical" category="waccm"
       group="chem_inparm" valid_values="" >
 true =&gt; radiation feed backs from strat sulfur aerosol
Default: false
</entry>

<entry id="nlte_use_mo" type="logical" category="waccm_phys"
       group="cam_inparm" valid_values="" >
Determines which constituents are used from NLTE calculations.
TRUE implies use prognostic constituents.
FALSE implies use constituents from dataset specified by <varname>waccm_forcing_file</varname>.
Default: TRUE for full WACCM code; FALSE for WACCM_GHG.
</entry>

<entry id="qbo_cyclic" type="logical" category="waccm_phys"
       group="cam_inparm" valid_values="" >
TRUE implies assume cyclic qbo data.
Default: FALSE
</entry>

<entry id="qbo_forcing_file" type="char*256" input_pathname="abs" category="waccm_phys"
       group="cam_inparm" valid_values="" >
Filepath for qbo forcing dataset.
Default: Set by build-namelist.
</entry>

<entry id="qbo_use_forcing" type="logical" category="waccm_phys"
       group="cam_inparm" valid_values="" >
TRUE implies qbo package is active.
Default: FALSE
</entry>

<entry id="spe_data_file" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Filepath for time-variant solar proton ionization dataset.
Default: Set by build-namelist.
</entry>

<entry id="spe_filenames_list" type="char*256" input_pathname="abs" category="waccm"
       group="chem_inparm" valid_values="" >
Filepath for file that lists a series of solar proton ionization dataset files.
Default: Set by build-namelist.
</entry>

<entry id="spe_remove_file" type="logical" category="waccm"
       group="chem_inparm" valid_values="" >
TRUE implies the offline solar proton ionization data file will be deleted when 
finished with it.
Default: FALSE
</entry>

<entry id="spe_restart" type="logical" category="waccm"
       group="chem_inparm" valid_values="" >
TRUE implies restart (branch) from a previous run with solar proton events.
Default: TRUE
</entry>



<!-- SE dycore -->

<entry id="interpolate_analysis" type="logical(6)" category="se"
    group="analysis_nl" valid_values="">
If interpolate_analysis(k) = .true., then the k'th history file will be
interpolated to a lat/lon grid before output.
Default: Set by build-namelist (probably all .false.).
</entry>

<entry id="interp_nlat" type="integer" category="se"
    group="analysis_nl" valid_values="">
Latitude dimension of grid for interpolated output.
If interp_nlat and interp_nlon are zero, reasonable values will be chosen
based on the cubed-sphere resolution.
Default: Set by build-namelist.
</entry>

<entry id="interp_nlon" type="integer" category="se"
    group="analysis_nl" valid_values="">
Longitude dimension of grid for interpolated output.
If interp_nlat and interp_nlon are zero, reasonable values will be chosen
based on the cubed-sphere resolution.
Default: Set by build-namelist.
</entry>

<entry id="interp_type" type="integer" category="se"
    group="analysis_nl" valid_values="0,1">
Selects interpolation method for output on lat/lon grid.
0: Use SE's native high-order method.
1: Use a bilinear method.
Default: Set by build-namelist.
</entry>

<entry id="interp_gridtype" type="integer" category="se"
    group="analysis_nl" valid_values="1,2,3">
Selects output grid type for lat/lon interpolated output.
1: Equally spaced, including poles (FV scalars output grid).
2: Gauss grid (CAM Eulerian).
3: Equally spaced, no poles (FV staggered velocity).
Default: Set by build-namelist.
</entry>

<entry id="se_nsplit" type="integer" category="se"
       group="ctl_nl" valid_values="" >
Number of dynamics steps per physics timestep.
Default: Set by build-namelist.
</entry>

<entry id="se_phys_tscale" type="integer" category="se"
       group="ctl_nl" valid_values="" >
Physics timescale (in seconds) used to compute physics tendencies
If 0, feature is disabled (use dtime).
Default: Set by build-namelist. 
</entry>

<entry id="se_limiter_option" type="integer" category="se"
       group="ctl_nl" valid_values="0,4,8" >
Limiter used for horizontal tracer advection:
0: None
4: Sign-preserving limiter.
8: Monotone limiter.
Default: Set by build-namelist (probably 8).
</entry>

<entry id="vert_remap_q_alg" type="integer" category="se"
    group="ctl_nl" valid_values="0,1,2">
CAM-SE vertical remap algorithm
0: default value, Zerroukat monotonic splines
1: PPM vertical remap with mirroring at the boundaries
   (solid wall bc's, high-order throughout)
2: PPM vertical remap without mirroring at the boundaries
   (no bc's enforced, first-order at two cells bordering top and bottom
   boundaries)
Default: Set by build-namelist.
</entry>

<entry id="se_ftype" type="integer" category="se"
       group="ctl_nl" valid_values="0,1,2" >
CAM physics forcing option:
0: tendencies
1: adjustments
2: hybrid
Default: Set by build-namelist.
</entry>

<entry id="integration" type="char*80" category="se"
       group="ctl_nl" valid_values="explicit,semi_implicit" >
Time integration method.
Default: Set by build-namelist ("explicit").
</entry>

<entry id="se_ne" type="integer" category="se"
       group="ctl_nl" valid_values="" >
Element width of resolution.
Must match value of grid. Do NOT set this yourself.
Default: Set by build-namelist.
</entry>

<entry id="qsplit" type="integer" category="se"
       group="ctl_nl" valid_values="" >
Tracer advection is done every qsplit dynamics timesteps.
Default: Set by build-namelist.
</entry>

<entry id="rsplit" type="integer" category="se"
       group="ctl_nl" valid_values="" >
Vertically lagrangian code updates every rsplit tracer timesteps.
If rsplit=0, vertically lagrangian code is off.
Default: Set by build-namelist.
</entry>

<entry id="hypervis_order" type="integer" category="se"
       group="ctl_nl" valid_values="2" >
Hyperviscosity operator is the Laplacian^hypervis_order.
The only supported value in CAM is "2".
Default: Set by build-namelist.
</entry>

<entry id="hypervis_subcycle" type="integer" category="se"
       group="ctl_nl" valid_values="" >
Number of hyperviscosity subcycles per dynamics timestep.
Default: Set by build-namelist (probably 2).
</entry>

<entry id="hypervis_subcycle_q" type="integer" category="se"
       group="ctl_nl" valid_values="1" >
Number of hyperviscosity subcycles done in tracer advection code.
The only supported value in CAM is 1.
Default: Set by build-namelist.
</entry>

<entry id="energy_fixer" type="integer" category="se"
       group="ctl_nl" valid_values="-1,1,4" >
Energy fixer mode.
-1: Disabled.
 1: Enable energy fixer.
 4: Deprecated option to enable (for backwards compatibility).
Default: Set by build-namelist (probably -1).
</entry>

<entry id="nu" type="real" category="se"
       group="ctl_nl" valid_values="" >
Dynamics hyperviscosity [m^4/s].
Default: Set by build-namelist.
</entry>

<entry id="nu_div" type="real" category="se"
       group="ctl_nl" valid_values="" >
Weighting of divergence component when applying hyperviscosity.
If < 0, uses nu.
Default: Set by build-namelist.
</entry>

<entry id="nu_p" type="real" category="se"
       group="ctl_nl" valid_values="" >
Hyperviscosity applied to dp3d (layer thickness when running
vertically lagrangian dynamics) [m^4/s].
Default: Set by build-namelist.
</entry>

<entry id="nu_q" type="real" category="se"
       group="ctl_nl" valid_values="" >
Hyperviscosity applied during tracer advection [m^4/s].
If < 0, uses nu.
Default: Set by build-namelist.
</entry>

<entry id="nu_top" type="real" category="se"
       group="ctl_nl" valid_values="" >
Second-order viscosity applied only near the model top [m^2/s].
Default: Set by build-namelist.
</entry>

<entry id="se_partmethod" type="integer" category="se"
       group="ctl_nl" valid_values="4" >
Mesh partitioning method (METIS).
The only supported value in CAM is 4 (space-filling).
Default: Set by build-namelist.
</entry>

<entry id="statefreq" type="integer" category="se"
       group="ctl_nl" valid_values="" >
Frequency with which diagnostic output is written to log (output every
statefreq dynamics timesteps).
Default: Set by build-namelist.
</entry>

<entry id="se_topology" type="char*80" category="se"
       group="ctl_nl" valid_values="cube" >
SE's topology.
Only "cube" is supported in CAM.
Default: Set by build-namelist.
</entry>

<!-- CAM I/O  -->

<entry id="pio_stride" type="integer" category="pio"
       group="pio_default_inparm" valid_values="" >
Default: 4
</entry>
<entry id="pio_numiotasks" type="integer" category="pio"
       group="pio_default_inparm" valid_values="" >
Default: -1
</entry>
<entry id="pio_typename" type="char*80" category="pio"
       group="pio_default_inparm" valid_values="netcdf,pnetcdf,netcdf4p,netcdf4c" >
Default: "netcdf"
</entry>
<entry id="pio_root" type="integer" category="pio"
       group="pio_default_inparm" valid_values="" >
Default: 1
<entry id="pio_debug_level" type="integer" category="pio"
       group="pio_default_inparm" valid_values="" >
Default: 0
</entry>
<entry id="pio_blocksize" type="integer" category="pio"
       group="pio_default_inparm" valid_values="" >
Default: -1
</entry>
<entry id="pio_buffer_size_limit" type="integer" category="pio"
       group="pio_default_inparm" valid_values="" >
Default: 0
</entry>
<entry id="pio_async_interface" type="logical" category="pio"
       group="pio_default_inparm" valid_values="" >
Default: .false.
</entry>


<!-- DOCN -->

<entry id="restfilm" type="char*256" input_pathname="abs" category="ocn"
       group="docn_nml" valid_values="" >
Full pathname of docn restart file.
Default: set by build-namelist.
</entry>

<entry id="ocn_in" type="char*24" category="ocn"
       group="docn_nml" valid_values="" >
Full pathname of docn restart file.
Default: set by build-namelist.
</entry>

<entry id="decomp" type="char*24" category="ocn"
       group="docn_nml" valid_values="" >
Full pathname of docn restart file.
Default: set by build-namelist.
</entry>

<!-- Backwards compatibility options: support for old DOM, CSIM4 -->
<!-- SST Data -->

<entry id="bndtvs" type="char*256" input_pathname="abs" category="ocn"
       group="camexp" valid_values="" >
Full pathname of time-variant sea-surface temperature and sea-ice
concentration boundary dataset.
Default: set by build-namelist.
</entry>

<entry id="focndomain" type="char*256" input_pathname="abs" category="ocn"
       group="camexp" valid_values="" >
Full pathname of 
Default: set by build-namelist.
</entry>

<entry id="bndtvs_domain" type="char*256" input_pathname="abs" category="ocn"
       group="camexp" valid_values="" >
Full pathname of grid file for time-variant sea-surface temperature and sea-ice
concentration boundary dataset.
Default: set by build-namelist.
</entry>

<entry id="sstcyc" type="logical" category="ocn"
       group="camexp" valid_values="" >
Flag for yearly cycling of SST data. If set to FALSE, a multi-year dataset
is assumed, otherwise a single-year dataset is assumed, and SSTs will be
cycled over the first 12 values in the file.  Not used if running with
CCSM.
Default: TRUE
</entry>

<!-- CICE: These variables are passed through to the CICE build-namelist.   -->
<!--       They are provided here for convenience in setting up AMIP runs.  -->

<entry id="stream_year_first" type="integer" category="ice"
       group="camexp" valid_values="" >
The first year of the multi-year SST dataset which is read by CICE for
the prescribed ice fraction.  This needs to be set for AMIP simulations.
Default: 0
</entry>

<entry id="stream_year_last" type="integer" category="ice"
       group="camexp" valid_values="" >
The last year of the multi-year SST dataset which is read by CICE for
the prescribed ice fraction.  This needs to be set for AMIP simulations.
Default: 0
</entry>

<!-- DOM (CAM version) -->

<entry id="dom_branch_file" type="char*256" category="restart"
       group="dom_inparm" valid_values="">
Full pathname of master restart file from which to branch. Setting is
Required for branch run.
Default: none
</entry>

<!-- CSIM (CAM version) -->

<entry id="ice_conschk_frq" type="integer" category="csim"
       group="csim_inparm" valid_values="" >
This is only used when running as part of CCSM. If n &gt; 0 then sea
ice global energy checking will be done every n timesteps. If n &lt; 0 then
sea ice global energy checking will be done every n days.
</entry>

<entry id="csim_branch_file" type="char*256" category="restart"
       group="csim_inparm" valid_values="">
Full pathname of master restart file from which to branch. Setting is
Required for branch run.
Default: none
</entry>

<entry id="prognostic_icesnow" type="logical" category="csim"
       group="csim_inparm" valid_values="">
Prognostic snow over ice, currently limited to 0.5m.
If this is false then a snow climatology is used.
Default: TRUE
</entry>

<entry id="reset_csim_iceprops" type="logical" category="csim"
       group="csim_inparm" valid_values="">
If true =&gt; resets the csim ice properties to base state, i.e.,
no snow cover, TSICE and TS[1-4] are all set to
freezing.
The csim is sensitive to imbalances between the
surface temperature and ice temperatures. When
using an initial conditions dataset interpolated
from a different resolution you may have to set this
to true to get csim to run.  If set to true you will
have to allow time for the ice to spin up.
Default: FALSE
</entry>

<!-- ========================================================================================  -->
<!-- Rename component log files.  shr_file_mod::shr_file_setIO reads
     namelist /modelio/.  These variables in group camexp are treated
     specially in build-namelist, where they are put into the modelio
     namelist group in files with specific names that are read by each
     component.  --> 

<entry id="atm_logfile" type="char*256" category="driver"
       group="camexp" valid_values="">
Name of file that the atmosphere component log messages will be written to.  By
default all log messages are written to stdout.
Default: ""
</entry>

<entry id="atm_logfile_diro" type="char*256" category="driver"
       group="camexp" valid_values="">
Absolute pathname of directory that the file specified by <varname>atm_logfile</varname>
will be written to.
Default: "."
</entry>

<entry id="cpl_logfile" type="char*256" category="driver"
       group="camexp" valid_values="">
Name of file that the driver component log messages will be written to.  By
default all log messages are written to stdout.
Default: ""
</entry>

<entry id="cpl_logfile_diro" type="char*256" category="driver"
       group="camexp" valid_values="">
Absolute pathname of directory that the file specified by <varname>cpl_logfile</varname>
will be written to.
Default: "."
</entry>

<entry id="lnd_logfile" type="char*256" category="driver"
       group="camexp" valid_values="">
Name of file that the land component log messages will be written to.  By
default all log messages are written to stdout.
Default: ""
</entry>

<entry id="lnd_logfile_diro" type="char*256" category="driver"
       group="camexp" valid_values="">
Absolute pathname of directory that the file specified by <varname>lnd_logfile</varname>
will be written to.
Default: "."
</entry>

<entry id="rof_logfile" type="char*256" category="driver"
       group="camexp" valid_values="">
Name of file that the runoff component log messages will be written to.  By
default all log messages are written to stdout.
Default: ""
</entry>

<entry id="rof_logfile_diro" type="char*256" category="driver"
       group="camexp" valid_values="">
Absolute pathname of directory that the file specified by <varname>rof_logfile</varname>
will be written to.
Default: "."
</entry>


<!-- ========================================================================================  -->
<!-- CPL7 Driver -->

<!-- coupler fields -->

<entry id="flds_co2a" type="logical"  category="driver"
       group="seq_cplflds_inparm" valid_values="" >
Default: FALSE
</entry>
<entry id="flds_co2b" type="logical"  category="driver"
       group="seq_cplflds_inparm" valid_values="" >
Default: FALSE
</entry>
<entry id="flds_co2c" type="logical"  category="driver"
       group="seq_cplflds_inparm" valid_values="" >
Default: FALSE
</entry>
<entry id="flds_co2_dmsa" type="logical"  category="driver"
       group="seq_cplflds_inparm" valid_values="" >
Default: FALSE
</entry>
<entry id="cplflds_custom" type="char*80"  category="driver"
       group="seq_cplflds_userspec" valid_values="" >
Default: 
</entry>

<!-- Task/Thread layouts -->

<entry id="atm_pestride" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Stride used in selecting the processes in the atm communicator group.
Default: 1
</entry>

<entry id="atm_rootpe" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Root process of the atm communicator group.
Default: 0
</entry>

<entry id="atm_ntasks" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of atm tasks.
Default: total number of tasks assigned to job.
</entry>

<entry id="atm_nthreads" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of threads in each atm task.
Default: 1
</entry>

<entry id="lnd_pestride" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Stride used in selecting the processes in the lnd communicator group.
Default: 1
</entry>

<entry id="lnd_rootpe" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Root process of the lnd communicator group.
Default: 0
</entry>

<entry id="lnd_ntasks" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of lnd tasks.
Default: total number of tasks assigned to job.
</entry>

<entry id="lnd_nthreads" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of threads in each lnd task.
Default: 1
</entry>

<entry id="ice_pestride" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Stride used in selecting the processes in the ice communicator group.
Default: 1
</entry>

<entry id="ice_rootpe" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Root process of the ice communicator group.
Default: 0
</entry>

<entry id="ice_ntasks" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of ice tasks.
Default: total number of tasks assigned to job.
</entry>

<entry id="ice_nthreads" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of threads in each ice task.
Default: 1
</entry>

<entry id="ocn_pestride" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Stride used in selecting the processes in the ocn communicator group.
Default: 1
</entry>

<entry id="ocn_rootpe" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Root process of the ocn communicator group.
Default: 0
</entry>

<entry id="ocn_ntasks" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of ocn tasks.
Default: total number of tasks assigned to job.
</entry>

<entry id="ocn_nthreads" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of threads in each ocn task.
Default: 1
</entry>

<entry id="rof_pestride" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Stride used in selecting the processes in the rof communicator group.
Default: 1
</entry>

<entry id="rof_rootpe" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Root process of the rof communicator group.
Default: 0
</entry>

<entry id="rof_ntasks" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of rof tasks.
Default: total number of tasks assigned to job.
</entry>

<entry id="rof_nthreads" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of threads in each rof task.
Default: 1
</entry>

<entry id="cpl_pestride" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Stride used in selecting the processes in the cpl communicator group.
Default: 1
</entry>

<entry id="cpl_rootpe" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Root process of the cpl communicator group.
Default: 0
</entry>

<entry id="cpl_ntasks" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of cpl tasks.
Default: total number of tasks assigned to job.
</entry>

<entry id="cpl_nthreads" type="integer"  category="driver"
       group="ccsm_pes" valid_values="" >
Number of threads in each cpl task.
Default: 1
</entry>

<!-- Control info -->

<entry id="aqua_planet" type="logical"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
If true, run model in "aqua planet" mode. Only one of
<varname>atm_adiabatic</varname>, <varname>atm_ideal_phys</varname>, or
<varname>aqua_planet</varname> can be true.
Default: FALSE
</entry>

<entry id="aqua_planet_sst" type="integer"  category="driver"
       group="seq_infodata_inparm" valid_values="1" >
Set the sst to a particular analytic solution.  **Not currently
functional** The type of analytic solution is currently hardcoded with a
parameter in ocn_comp.F90.
Default: 1
</entry>

<entry id="atm_adiabatic" type="logical"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
If TRUE, do not run model physics, only run the dynamical core.
Only one of
<varname>atm_adiabatic</varname>, <varname>atm_ideal_phys</varname>, or
<varname>aqua_planet</varname> can be true.
Default: FALSE
</entry>

<entry id="atm_dep_flux" type="logical" category="driver"
       group="phys_ctl_nl" valid_values="" >
If FALSE then CAM will set the deposition fluxes to zero before sending
them to the coupler.  A side effect of setting the
variable <varname>chem_rad_passive</varname> to TRUE is that this variable
will be set to FALSE (the deposition fluxes must be set to zero in order
for the chemistry not to impact the climate).
Default: TRUE
</entry>

<entry id="atm_ideal_phys" type="logical"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
If TRUE run the idealized Held&amp;Suarez physics package.
Only one of
<varname>atm_adiabatic</varname>, <varname>atm_ideal_phys</varname>, or
<varname>aqua_planet</varname> can be true.
Default: FALSE
</entry>

<entry id="bfbflag" type="logical"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
bit for bit flag
Default: FALSE
</entry>

<entry id="brnch_retain_casename" type="logical"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
If TRUE, use the pre-existing case name for a branch run.
Default: FALSE
</entry>

<entry id="budget_ann" type="integer" category="driver"
       group="seq_infodata_inparm" valid_values="" >
annual budget level
Default: 1
</entry>

<entry id="budget_daily" type="integer" category="driver"
       group="seq_infodata_inparm" valid_values="" >
daily budget level
Default: 0
</entry>

<entry id="budget_inst" type="integer" category="driver"
       group="seq_infodata_inparm" valid_values="" >
instantaneous budget level
Default: 0
</entry>

<entry id="budget_ltann" type="integer" category="driver"
       group="seq_infodata_inparm" valid_values="" >
long term budget level written at end of year
Default: 1
</entry>

<entry id="budget_ltend" type="integer" category="driver"
       group="seq_infodata_inparm" valid_values="" >
long term budget level written at end of run
Default: 0
</entry>

<entry id="budget_month" type="integer" category="driver"
       group="seq_infodata_inparm" valid_values="" >
monthly budget level
Default: 1
</entry>

<entry id="case_desc" type="char*256"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Case title.
Default: none.
</entry>

<entry id="case_name" type="char*80"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Case identifier.  The value of <varname>case_name</varname> is used in the
default filenames of both the history and restart files (see
the <varname>hfilename_spec</varname> namelist option).  The "%c" string in
the <varname>hfilename_spec</varname> templates are expanded using the
value of <varname>case_name</varname> when history filenames are created.
Default: set by build-namelist. 
</entry>

<entry id="cpl_cdf64" type="logical"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Use netcdf 64 bit offset, large file support.
Default: FALSE
</entry>

<entry id="do_budgets" type="logical" category="driver"
       group="seq_infodata_inparm" valid_values="" >
T =&gt; do heat/water budget diagnostics
Default: FALSE
</entry>

<entry id="drv_threading" type="logical" category="driver"
       group="seq_infodata_inparm" valid_values="" >
T =&gt; enable run time setting of thread count for each component
Default: FALSE
</entry>

<entry id="flux_albav" type="logical" category="driver"
       group="seq_infodata_inparm" valid_values="" >
T =&gt; no diurnal cycle in ocn albedos.
Default: FALSE
</entry>

<entry id="flux_epbal" type="char*256" category="driver"
       group="seq_infodata_inparm" valid_values="" >
Selects E,P,R adjustment technique.
Default: 'off'
</entry>

<entry id="hostname" type="char*80"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Current machine.
Default: 'unknown'
</entry>

<entry id="info_debug" type="integer" category="driver"
       group="seq_infodata_inparm" valid_values="" >
Debug flag.
Default: 1
</entry>

<entry id="logfilepostfix" type="char*80" category="driver"
       group="seq_infodata_inparm" valid_values="" >
Postfix for output log files.
Default: '.log'
</entry>

<entry id="model_version" type="char*256"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Model version.
Default: 'unknown'
</entry>

<entry id="ocean_tight_coupling" type="logical"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Couple ocean on atm timestep.
Default: TRUE
</entry>

<entry id="orb_eccen" type="real"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Earth's eccentricity of orbit. (unitless: typically 0. to 0.1). Setting is
Required if <varname>orb_iyear</varname> not set.  Not used when running
as part of CCSM.
Default: none
</entry>

<entry id="orb_mode" type="char*256"  category="driver"
       group="seq_infodata_inparm" valid_values="fixed_year,variable_year,fixed_parameters" >
Mode to specify how orbital parameters are to be set.
Not used when running as part of CCSM.
Default: fixed_year
</entry>

<entry id="orb_iyear" type="integer"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Year (AD) used to compute earth's orbital parameters. If not set, then use
the values from
the <varname>orb_eccen</varname>, <varname>orb_mvelp</varname>,
and <varname>orb_obliq</varname> namelist parameters.  If only
<varname>orb_iyear</varname> is set, orbital parameters will be computed
automatically (based on Berger, 1977).  If one
of <varname>orb_eccen</varname>, <varname>orb_mvelp</varname>, or
<varname>orb_obliq</varname> is set, all three must be set.  If all four of
the above are set by the user, <varname>orb_iyear</varname> takes
precedence.  Setting is Required
unless <varname>orb_eccen</varname>, <varname>orb_mvelp</varname>,
and <varname>orb_obliq</varname> are set.  Not used when running as part of
CCSM.
Default: 1990.
</entry>

<entry id="orb_mvelp" type="real"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Earth's moving vernal equinox at perihelion (degrees: 0. to 360.0).
Setting is Required if <varname>orb_iyear</varname> not set.  Not used
when running as part of CCSM.
Default: none
</entry>

<entry id="orb_obliq" type="real"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Earth's orbital  angle of obliquity  (degrees: -90. to +90., typically 22. to 26.).
Setting is Required if <varname>orb_iyear</varname> not set.  Not used
when running as part of CCSM.
Default: none
</entry>

<entry id="outpathroot" type="char*256" category="driver"
       group="seq_infodata_inparm" valid_values="" >
Root output files
Default: './'
</entry>

<entry id="perpetual" type="logical"  category="time_mgr"
       group="seq_infodata_inparm" valid_values="" >
Set to TRUE to specify that the run will use a perpetual calendar, i.e., a
diurnal cycle will be present for the fixed calendar day specified
by <varname>perpetual_ymd</varname>.
Default: FALSE
</entry>

<entry id="perpetual_ymd" type="integer"  category="time_mgr"
       group="seq_infodata_inparm" valid_values="" >
Perpetual date encoded in an integer as (year*1000 + month*100 + day).
If <varname>aqua_planet</varname> = .true. then perpetual_ymd is ignored
and the perpetual date is set to 321.
Default: none.
</entry>

<entry id="restart_file" type="char*256" category="driver"
       group="seq_infodata_inparm" valid_values="" >
Restart filename.
Default: none
</entry>

<entry id="restart_file_override" type="char*256" category="driver"
       group="seq_infodata_inparm" valid_values="" >
List of namelist variables that may be overridden on a restart run.
Default: none
</entry>

<entry id="restart_pfile" type="char*256" category="driver"
       group="seq_infodata_inparm" valid_values="" >
Restart pointer filename.
Default: 'rpointer.drv'
</entry>

<entry id="samegrid" type="logical" category="driver"
       group="seq_infodata_inparm" valid_values="">
are ocean and ice grids same lat/lon/size
Default: TRUE
</entry>

<entry id="scmlat" type="real" category="scam"
       group="seq_infodata_inparm" valid_values="">
Latitude value of single column.
Default: none.
</entry>

<entry id="scmlon" type="real" category="scam"
       group="seq_infodata_inparm" valid_values="">
Longitude value of single column.
Default: none.
</entry>

<entry id="single_column" type="logical" category="scam"
       group="seq_infodata_inparm" valid_values="">
Set to TRUE to turn on single column mode.
Default: FALSE
</entry>

<entry id="start_type" type="char*8"  category="driver"
       group="seq_infodata_inparm" valid_values="startup,continue,branch" >
Run type.  'startup' is an initial run.  'continue' is a restart run.
'branch' is a restart run in which properties of the output history files
may be changed.
Default: 'startup'
</entry>

<entry id="username" type="char*80"  category="driver"
       group="seq_infodata_inparm" valid_values="" >
Current user.
Default: 'unknown'
</entry>

<entry id="vect_map" type="char*8"  category="driver"
       group="seq_infodata_inparm" valid_values="none,npfix,cart3d,cart3d_diag,cart3d_uvw,cart3d_uvw_diag" >
Invoke vector mapping option
Default: 'npfix'
</entry>

<!-- Reproducible Distributed Sum Calculation -->

<entry id="reprosum_use_ddpdd" type="logical"  category="reprosum"
       group="seq_infodata_inparm" valid_values="">
Flag to indicate whether to use the double-double distributed sum algorithm
rather than the (almost) infinite precision reproducible distributed sum algorithm.
Default: FALSE
</entry>

<entry id="reprosum_recompute" type="logical"  category="reprosum"
       group="seq_infodata_inparm" valid_values="">
Flag to indicate whether a distributed sum that violates the difference 
tolerance specified by reprosum_diffmax should be recomputed using 
a floating point-based (but nonscalable) reproducible algorithm.
Default: FALSE
</entry>

<entry id="reprosum_diffmax" type="real"  category="reprosum"
       group="seq_infodata_inparm" valid_values="">
Relative difference between repro and nonrepro algorithms that will 
generate a warning. This will also force a recompute using a nonscalable 
algorithm if reprosum_recompute is true. If less than zero, then
the difference will not be evaluated (and the nonrepro algorithm will not 
be computed).
Default: -1.0
</entry>

<!-- Time Manager -->

<entry id="atm_cpl_dt" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Coupling interval between the atmosphere and other system components.  This
is how frequently information can be communicated between the atmosphere
and the surface models.
Default: set by build-namelist.
</entry>

<entry id="atm_cpl_offset" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Default: 
</entry>

<entry id="calendar" type="char*80"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="NO_LEAP,GREGORIAN" >
Calendar type "NO_LEAP" for consistent 365-days per year or "GREGORIAN" to
include leap-years. Note that if "GREGORIAN" is selected
leap-years will be used in the time manager, but the calculation of the
earth's orbit still assumes 365 day years.  Valid values are "NO_LEAP" or
"GREGORIAN".
Default: "NO_LEAP"
</entry>

<entry id="end_restart" type="logical"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Write restart at end of run.
Default: TRUE
</entry>

<entry id="ice_cpl_dt" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Default: set by build-namelist.
</entry>

<entry id="ice_cpl_offset" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Default: 
</entry>

<entry id="lnd_cpl_dt" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Default: set by build-namelist.
</entry>

<entry id="lnd_cpl_offset" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Default: 
</entry>

<entry id="ocn_cpl_dt" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Default: set by build-namelist.
</entry>

<entry id="ocn_cpl_offset" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Default: 
</entry>

<entry id="rof_cpl_dt" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Default: set by build-namelist.
</entry>

<entry id="rof_cpl_offset" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Default: 
</entry>

<entry id="ref_tod" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Reference time-of-day expressed as seconds past midnight.  Used in
conjuction with <varname>ref_ymd</varname> to set the reference time.
Default: set to <varname>start_tod</varname>.
</entry>

<entry id="ref_ymd" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Reference date encoded in an integer as (year*1000 + month*100 + day).
Used in
conjuction with <varname>ref_tod</varname> to set the reference time which
is used to define a time coordinate for the output history files.  The
convention for the unit string of a time coordinate is of the form
"time-unit since reference-time", for example, "days since 1990-01-01
00:00:00".  The reference-time part of this string is specified by the
<varname>ref_ymd</varname> and <varname>ref_tod</varname> variables.

Default: set to <varname>start_ymd</varname>.
</entry>

<entry id="restart_n" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Set the restart interval as a number of elapsed time units which are specified
by <varname>restart_option</varname>.
Default: 1
</entry>

<entry id="restart_option" type="char*8"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="none,nsteps,ndays,nmonths,nyears,monthly,yearly,end" >
Set the interval between writing restart files
using one of the options 'nsteps',
'ndays', 'nmonths', or 'nyears', in conjuction
with <varname>stop_n</varname> to set the number of time units.
A convenience option allows specifying that restart files be written at the
end of each month or at the end of each year by using the options
'monthly' or 'yearly' respectively.  It is also possible to request that no
restart files be written via the option 'none', or that restart files be
written only at the end of the run via the option 'end'.
Default: 'monthly'
</entry>

<entry id="start_tod" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Start time-of-day expressed as seconds past midnight.  Used in
conjuction with <varname>start_ymd</varname> to set the start time.
Default: 0.
</entry>

<entry id="start_ymd" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Start date encoded in an integer as (year*1000 + month*100 + day).
Used in
conjuction with <varname>start_tod</varname> to set the start date of
the simulation.
Default: set by build-namelist.
</entry>

<entry id="stop_n" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Set the length of run as a number of elapsed time units which are specified
by <varname>stop_option</varname>.
Default: 1
</entry>

<entry id="stop_option" type="char*8"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="nsteps,ndays,nmonths,nyears,date" >
Set the length of run as an elapsed time using one of the options 'nsteps',
'ndays', 'nmonths', or 'nyears', in conjuction
with <varname>stop_n</varname> to set the number of elapsed time units.
Alternatively, set the final simulation time in absolute terms by using the
option 'date' in conjuction with <varname>stop_ymd</varname>,
and <varname>stop_tod</varname> to specify a date and time of day at which
the simulation should stop.
Default: 'ndays'
</entry>

<entry id="stop_tod" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Stop time-of-day expressed as seconds past midnight.  Used in
conjuction with <varname>stop_ymd</varname> to set the stop time.
Default: 0.
</entry>

<entry id="stop_ymd" type="integer"  category="time_mgr"
       group="seq_timemgr_inparm" valid_values="" >
Stop date encoded in an integer as (year*1000 + month*100 + day).
Used in
conjuction with <varname>stop_tod</varname> to set the stop date of
the simulation.
Default: none.
</entry>


<!-- ========================================================================================  -->
<!-- CLM -->

<entry id="clump_pproc" type="integer" category="clm"
       group="clm_inparm" valid_values="" >
Clumps per processor.
Default: Number of threads per process; or 1 if no OMP.
</entry>

<entry id="co2_ppmv" type="real" category="clm"
       group="clm_inparm" valid_values="" >

Default: 355.
</entry>

<entry id="co2_type" type="char*16" category="clm"
       group="clm_inparm" valid_values="constant,prognostic,diagnostic" >
Type of CO2 feedback.
Default: 'constant' for BGC mode
</entry>

<entry id="create_crop_landunit" type="logical" category="clm"
       group="clm_inparm" valid_values="" >
on if to create crop as separate landunits
Default: FALSE
</entry>

<entry id="fatmlndfrc" type="char*256" input_pathname="abs" category="clm"
       group="clm_inparm" valid_values="" >
Full pathname of grid/landfrac data file (on atm grid).
Default: set by build-namelist.
</entry>

<entry id="fatmtopo" type="char*256" input_pathname="abs" category="clm"
       group="clm_inparm" valid_values="" >
Full pathname of atmosphere topography data file (on atm grid).
Default: set by build-namelist.
</entry>

<entry id="finidat" type="char*256" input_pathname="abs" category="clm"
       group="clm_inparm" valid_values="" >
Full pathname of initial conditions file.
Default: set by build-namelist.
</entry>

<entry id="flndtopo" type="char*256" input_pathname="abs" category="clm"
       group="clm_inparm" valid_values="" >
Full pathname of land topography file.
Default: set by build-namelist.
</entry>

<entry id="fpftcon" type="char*256" input_pathname="abs" category="clm"
       group="clm_inparm" valid_values="" >
Full pathname of PFT data file.
Default: set by build-namelist.
</entry>

<entry id="fpftdyn" type="char*256" input_pathname="abs" category="clm"
       group="clm_inparm" valid_values="" >
Full pathname of time varying PFT data file.
Default: set by build-namelist.
</entry>

<entry id="frivinp_rtm" type="char*256" input_pathname="abs" category="clm"
       group="clm_inparm" valid_values="" >
Full pathname of input datafile for rtm.
Default: set by build-namelist.
</entry>

<entry id="fsurdat" type="char*256" input_pathname="abs" category="clm"
       group="clm_inparm" valid_values="" >
Full pathname of surface data file.
Default: set by build-namelist.
</entry>

<entry id="fsnowoptics" type="char*256"  input_pathname="abs" category="clm" 
       group="clm_inparm" valid_values="" >
SNICAR (SNow, ICe, and Aerosol Radiative model) optical data file name
</entry>

<entry id="fsnowaging" type="char*256"  input_pathname="abs" category="clm" 
       group="clm_inparm" valid_values="" >
SNICAR (SNow, ICe, and Aerosol Radiative model) snow aging data file name
</entry>

<entry id="hist_avgflag_pertape" type="char*1(6)" category="clm"
       group="clm_inparm" valid_values="" >
Per file averaging flag.
Default: ' ',' ',' ',' ',' ',' '
</entry>

<entry id="hist_dov2xy" type="logical(6)" category="clm"
       group="clm_inparm" valid_values="" >
TRUE implies do grid averaging.  One value for each output history file.
Default: All TRUE.
</entry>

<entry id="hist_empty_htapes" type="logical" category="clm"
       group="clm_inparm" valid_values="" >
TRUE indicates no default history fields.
Default: FALSE
</entry>

<entry id="hist_fexcl1" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to exclude from history file 1.
Default: none.
</entry>

<entry id="hist_fexcl2" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to exclude from history file 2.
Default: none.
</entry>

<entry id="hist_fexcl3" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to exclude from history file 3.
Default: none.
</entry>

<entry id="hist_fexcl4" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to exclude from history file 4.
Default: none.
</entry>

<entry id="hist_fexcl5" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to exclude from history file 5.
Default: none.
</entry>

<entry id="hist_fexcl6" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to exclude from history file 6.
Default: none.
</entry>

<entry id="hist_fincl1" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to add to history file 1.
Default: none.
</entry>

<entry id="hist_fincl2" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to add to history file 2.
Default: none.
</entry>

<entry id="hist_fincl3" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to add to history file 3.
Default: none.
</entry>

<entry id="hist_fincl4" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to add to history file 4.
Default: none.
</entry>

<entry id="hist_fincl5" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to add to history file 5.
Default: none.
</entry>

<entry id="hist_fincl6" type="char*34(1000)" category="clm"
       group="clm_inparm" valid_values="" >
Fields to add to history file 6.
Default: none.
</entry>

<entry id="hist_mfilt" type="integer(6)" category="clm"
       group="clm_inparm" valid_values="" >
Per file maximum number of time samples.
Default: 30,30,30,30,30,30
</entry>

<entry id="hist_ndens" type="integer(6)" category="clm"
       group="clm_inparm" valid_values="1,2" >
Per file history output precision.
Default: 2,2,2,2,2,2
</entry>

<entry id="hist_nhtfrq" type="integer(6)" category="clm"
       group="clm_inparm" valid_values="" >
Per file history write frequency (0=monthly)
Default: 0,-24,-24,-24,-24,-24
</entry>

<entry id="hist_type1d_pertape" type="char*32(6)" category="clm"
       group="clm_inparm" valid_values="" >
Per file type1d
Default: ' ',' ',' ',' ',' ',' '
</entry>

<entry id="nrevsn" type="char*256" category="clm"
       group="clm_inparm" valid_values="" >
Full pathname of master restart file for branch run.
Default: none.
</entry>

<entry id="nsegspc" type="integer" category="clm"
       group="clm_inparm" valid_values="" >
number of segments per clump for decomposition
Default: 20
</entry>

<entry id="outnc_large_files" type="logical" category="clm"
       group="clm_inparm" valid_values="" >
on to output NetCDF files in large-file format
<default>Default: FALSE</default>
</entry>

<entry id="rest_flag" type="logical" category="clm"
       group="clm_inparm" valid_values="" >
FALSE implies don't write any restart files.
Default: TRUE
</entry>

<entry id="rtm_nsteps" type="integer" category="clm"
       group="clm_inparm" valid_values="" >
If greater than one, average rtm over rtm_nsteps time steps
</entry>

<entry id="sim_year" type="char*9" category="clm"
       group="camexp" valid_values="1850,2000,1850-2000">
This varible is only used internally by build-namelist to determine correct
defaults for datasets such as surface datasets, initial conditions, dynamic
PFT, aerosol-deposition, Nitrogen deposition rates etc.
Default: set by build-namelist.
</entry> 

<entry id="urban_hac" type="char*16" category="clm"
       group="clm_inparm" valid_values="OFF,ON,ON_WASTEHEAT" >
Urban air conditioning/heating and wasteheat
<default>Default: 'off'</default>
</entry>

<entry id="urban_traffic" type="logical" category="clm"
       group="clm_inparm" valid_values="" >
TRUE if want urban traffic flux
<default>Default: FALSE</default>
</entry>

<entry id="wrtdia" type="logical" category="clm"
       group="clm_inparm" valid_values="" >
true if want output written
Default: FALSE
</entry>

<!-- ========================================================================================  -->
<!-- RTM -->

<entry id="rtm_mode" type="logical" category="rtm"
       group="rtm_inparm" valid_values="">
River runoff
Default: NULL
</entry>

<!-- ========================================================================================  -->
<!-- physical constants: -->

<entry id="sday" type="real" category="physconst"
       group="physconst_nl" valid_values="" >
Length of siderial day [seconds].
Default: set to shr_const value
</entry>

<entry id="rearth" type="real" category="physconst"
       group="physconst_nl" valid_values="" >
Radius of Earth [m].
Default: set to shr_const value
</entry>

<entry id="gravit" type="real" category="physconst"
       group="physconst_nl" valid_values="" >
Acceleration of gravity [m/s**2].
Default: set to shr_const value
</entry>

<entry id="mwdry" type="real" category="physconst"
       group="physconst_nl" valid_values="" >
Molecular weight of dry air [g/mol]
Default: set to shr_const value
</entry>

<entry id="mwh2o" type="real" category="physconst"
       group="physconst_nl" valid_values="" >
Molecular weight of water [g/mol].
Default: set to shr_const value
</entry>

<entry id="cpwv" type="real" category="physconst"
       group="physconst_nl" valid_values="" >
Heat capacity of water vapor at constant pressure [J/kg/K].
Default: set to shr_const value
</entry>

<entry id="tmelt" type="real" category="physconst"
       group="physconst_nl" valid_values="" >
Freezing point of water [K].
Default: set to shr_const value
</entry>

<entry id="tms_orocnst" type="real" category="physconst"
       group="physconst_nl" valid_values="" >
Turbulent mountain stress parameter used when turbulent mountain stress calculation 
is turned on. See <varname>do_tms</varname>.
Default: 1.0 for CAM, set by build-namelist for WACCM, T31
</entry>

<entry id="tms_z0fac" type="real" category="physconst"
       group="physconst_nl" valid_values="" >
Factor determining z_0 from orographic standard deviation [ no unit ] 
Used when turbulent mountain stress calc is turned on. See <varname>do_tms</varname>.
set by build-namelist for WACCM, T31
</entry>

<!-- for offine unit drivers -->

<entry id="offline_driver_infile" type="char*256" input_pathname="abs" category="offline_unit_driver"
       group="offline_driver_nl" valid_values="" >
Filepath for dataset for offline unit driver.
Default: none
</entry>

<entry id="offline_driver_fileslist" type="char*256" input_pathname="abs" category="offline_unit_driver"
       group="offline_driver_nl" valid_values="" >
List of filepaths for dataset for offline unit driver.
Default: none
</entry>

<entry id="offline_driver_do_fdh" type="logical"  category="offline_unit_driver"
       group="offline_driver_nl" valid_values="" >
Switch to turn on Fixed Dynamical Heating in the offline radiation tool (PORT).
This is implemented for CAMRT only.
Default: false
</entry>

</namelist_definition>
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              