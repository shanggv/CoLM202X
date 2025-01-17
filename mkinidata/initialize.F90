#include <define.h>

SUBROUTINE initialize (casename, dir_landdata, dir_restart, &
      idate, greenwich)

   ! ======================================================================
   ! initialization routine for land surface model.
   !
   ! Created by Yongjiu Dai, 09/15/1999
   ! Revised by Yongjiu Dai, 08/30/2002
   ! Revised by Yongjiu Dai, 03/2014
   !             
   ! ======================================================================
   use precision
   USE GlobalVars
   use mod_namelist
   use spmd_task
   use mod_pixel
   use mod_landpatch
   use PhysicalConstants
   use MOD_TimeInvariants
   use MOD_TimeVariables
#ifdef PFT_CLASSIFICATION
   USE mod_landpft
   USE MOD_PFTimeInvars
   USE MOD_PFTimeVars
#endif
#ifdef PC_CLASSIFICATION
   USE mod_landpc
   USE MOD_PCTimeInvars
   USE MOD_PCTimeVars
#endif
   USE LC_Const
   USE PFT_Const
   use timemanager

   use mod_grid
   use mod_data_type
!   use mod_mapping_grid2pset
   use ncio_serial
   use ncio_block
#ifdef CLMDEBUG 
   use mod_colm_debug
#endif
#ifdef vanGenuchten_Mualem_SOIL_MODEL
   USE mod_soil_function
#endif

   IMPLICIT NONE

   ! ----------------------------------------------------------------------
   character(len=*), intent(in) :: casename      ! case name
   character(len=*), intent(in) :: dir_landdata
   character(len=*), intent(in) :: dir_restart
   integer, intent(inout) :: idate(3)   ! year, julian day, seconds of the starting time
   logical, intent(in)    :: greenwich  ! true: greenwich time, false: local time

   ! ------------------------ local variables -----------------------------
   real(r8) :: rlon, rlat

#if(defined SOILINI)
   character(len=256) :: fsoildat

   type(grid_type) :: gsoil
   type(mapping_grid2pset_type) :: ms2p

   integer :: nl_soil_ini
   
   real(r8), allocatable :: soil_z(:)
   
   type(block_data_real8_2d) :: snow_d_grid
   type(block_data_real8_3d) :: soil_t_grid
   type(block_data_real8_3d) :: soil_w_grid

   real(r8), allocatable :: snow_d(:)
   real(r8), allocatable :: soil_t(:,:)
   real(r8), allocatable :: soil_w(:,:)
#endif

   ! CLM soil layer thickiness and depths
   real(r8), allocatable :: z_soisno (:,:)
   real(r8), allocatable :: dz_soisno(:,:)

   real(r8) :: calday                    ! Julian cal day (1.xx to 365.xx)
   INTEGER  :: idate0(3)
   integer  :: year, jday                ! Julian day and seconds
   INTEGER  :: month, mday

   integer  :: i,j,ipatch,nsl,ps,pe,ivt,m  ! indices
   INTEGER  :: hs, he

   integer :: Julian_8day
   integer :: ltyp

   real(r8), external :: orb_coszen     ! cosine of the solar zenith angle

#ifdef BGC
   real(r8) f_s1s2 (1:nl_soil)
   real(r8) f_s1s3 (1:nl_soil)
   real(r8) rf_s1s2(1:nl_soil)
   real(r8) rf_s1s3(1:nl_soil)
   real(r8) f_s2s1
   real(r8) f_s2s3
   real(r8) t
#endif


   ! --------------------------------------------------------------------
   ! Allocates memory for CLM 1d [numpatch] variables
   ! --------------------------------------------------------------------

   CALL allocate_TimeInvariants 
   CALL allocate_TimeVariables  

   ! ---------------------------------------------------------------
   ! 1. INITIALIZE TIME INVARIANT VARIABLES
   ! ---------------------------------------------------------------

   if (p_is_worker) then
      
      patchclass = landpatch%settyp

      DO ipatch = 1, numpatch
         patchtype(ipatch) = patchtypes(patchclass(ipatch))
      ENDDO

      call landpatch%get_lonlat_radian (patchlonr, patchlatr)

#ifdef PFT_CLASSIFICATION
      pftclass = landpft%settyp
#endif
   
   ENDIF

#if (defined PFT_CLASSIFICATION || defined PC_CLASSIFICATION)
   CALL pct_readin (dir_landdata)
#endif
   
   ! ------------------------------------------
   ! 1.1 Ponding water
   ! ------------------------------------------
#ifdef USE_DEPTH_TO_BEDROCK
   CALL dbedrock_readin (dir_landdata)
#endif

   IF (p_is_worker) THEN
      IF (numpatch > 0) THEN
         dpond(:) = 0._r8
      ENDIF
   ENDIF
   ! ------------------------------------------
   ! 1.2 Lake depth and layers' thickness
   ! ------------------------------------------
   CALL lakedepth_readin (dir_landdata)

   ! ...............................................................
   ! 1.3 Read in the soil parameters of the patches of the gridcells
   ! ...............................................................

   CALL soil_parameters_readin (dir_landdata)

#ifdef vanGenuchten_Mualem_SOIL_MODEL
   IF (p_is_worker) THEN
      IF (numpatch > 0) THEN

         psi0(:,:) = -1.0

         DO ipatch = 1, numpatch
            DO i = 1, nl_soil
               CALL get_derived_parameters_vGM ( &
                  psi0(i,ipatch), alpha_vgm(i,ipatch), n_vgm(i,ipatch), &
                  sc_vgm(i,ipatch), fc_vgm(i,ipatch))
            ENDDO 
         ENDDO 
      ENDIF 
   ENDIF  
#endif

   ! ...............................................................
   ! 1.4 Plant time-invariant variables (based on the look-up tables) 
   ! ...............................................................

   ! read global tree top height from nc file
   CALL HTOP_readin (dir_landdata)

   ! ................................
   ! 1.5 Initialize TUNABLE constants
   ! ................................
   zlnd   = 0.01    !Roughness length for soil [m]
   zsno   = 0.0024  !Roughness length for snow [m]
   csoilc = 0.004   !Drag coefficient for soil under canopy [-]
   dewmx  = 0.1     !maximum dew
   wtfact = 0.38    !Maximum saturated fraction (global mean; see Niu et al., 2005)
   capr   = 0.34    !Tuning factor to turn first layer T into surface T
   cnfac  = 0.5     !Crank Nicholson factor between 0 and 1
   ssi    = 0.033   !Irreducible water saturation of snow
   wimp   = 0.05    !Water impremeable if porosity less than wimp
   pondmx = 10.0    !Ponding depth (mm)
   smpmax = -1.5e5  !Wilting point potential in mm
   smpmin = -1.e8   !Restriction for min of soil poten. (mm)
   trsmx0 = 2.e-4   !Max transpiration for moist soil+100% veg. [mm/s]
   tcrit  = 2.5     !critical temp. to determine rain or snow

#ifdef BGC
! bgc constant
   i_met_lit = 1
   i_cel_lit = 2
   i_lig_lit = 3
   i_cwd     = 4
   i_soil1   = 5
   i_soil2   = 6
   i_soil3   = 7
   i_atm     = 0

   donor_pool    = (/i_met_lit, i_cel_lit, i_lig_lit, i_soil1, i_cwd    , i_cwd    , i_soil1, i_soil2, i_soil2, i_soil3/)
   receiver_pool = (/i_soil1  , i_soil1  , i_soil2  , i_soil2, i_cel_lit, i_lig_lit, i_soil3, i_soil1, i_soil3, i_soil1/)
   am = 0.02_r8
   floating_cn_ratio = (/.true., .true., .true., .true., .false. ,.false., .false./)
   initial_cn_ratio  = (/90._r8, 90._r8, 90._r8, 90._r8,    8._r8, 11._r8,  11._r8/)      ! 1:ndecomp_pools

   f_s2s1 = 0.42_r8/(0.45_r8)
   f_s2s3 = 0.03_r8/(0.45_r8)
   if (p_is_worker) THEN
      if(numpatch > 0)then
         do j=1,nl_soil
            do i = 1, numpatch
!         t = 0.85_r8 - 0.68_r8 * 0.01_r8 * (100._r8 - wf_sand(j))
               t = 0.85_r8 - 0.68_r8 * 0.01_r8 * (100._r8 - 50._r8)
               f_s1s2 (j) = 1._r8 - .004_r8 / (1._r8 - t)
               f_s1s3 (j) = .004_r8 / (1._r8 - t)
               rf_s1s2(j) = t
               rf_s1s3(j) = t
               rf_decomp(j,:,i)  = (/0.55_r8, 0.5_r8, 0.5_r8, rf_s1s2(j), 0._r8  , 0._r8  , rf_s1s3(j), 0.55_r8, 0.55_r8, 0.55_r8/)
               pathfrac_decomp(j,:,i) = (/1.0_r8 ,1.0_r8 , 1.0_r8, f_s1s2(j) , 0.76_r8, 0.24_r8, f_s1s3(j) , f_s2s1 , f_s2s3 , 1._r8/)
            end do
         end do
      end if
   end if

   is_cwd            = (/.false.,.false.,.false.,.true. ,.false.,.false.,.false./)
   is_litter         = (/.true. ,.true. ,.true. ,.false.,.false.,.false.,.false./)
   is_soil           = (/.false.,.false.,.false.,.false.,.true. ,.true. ,.true./)
   
!   gdp_lf (:)    = 0._r8
!   abm_lf (:)    = 0._r8
!   peatf_lf (:)  = 0._r8
   cmb_cmplt_fact = (/0.5_r8,0.25_r8/)

   nitrif_n2o_loss_frac = 6.e-4 !fraction of N lost as N2O in nitrification (Li et al., 2000)
   dnp    = 0.01_r8
   bdnr   = 0.5_r8
   compet_plant_no3 = 1._r8
   compet_plant_nh4 = 1._r8
   compet_decomp_no3 = 1._r8
   compet_decomp_nh4 = 1._r8
   compet_denit = 1._r8
   compet_nit = 1._r8
   surface_tension_water = 0.073
   rij_kro_a     = 1.5e-10_r8
   rij_kro_alpha = 1.26_r8
   rij_kro_beta  = 0.6_r8
   rij_kro_gamma = 0.6_r8
   rij_kro_delta = 0.85_r8
#ifdef NITRIF
   nfix_timeconst = 10._r8
#else
   nfix_timeconst = 0._r8
#endif
   organic_max        = 130
   d_con_g21          = 0.1759_r8
   d_con_g22          = 0.00117_r8
   d_con_w21          = 1.172_r8
   d_con_w22          = 0.03443_r8
   d_con_w23          = 0.0005048_r8
   denit_resp_coef    = 0.1_r8
   denit_resp_exp     = 1.3_r8
   denit_nitrate_coef = 1.15_r8
   denit_nitrate_exp  = 0.57_r8
   k_nitr_max         = 1.1574074e-06_r8
   Q10       = 1.5_r8
   froz_q10  = 1.5_r8
   tau_l1    = 1._r8/18.5_r8
   tau_l2_l3 = 1._r8/4.9_r8
   tau_s1    = 1._r8/7.3_r8
   tau_s2    = 1._r8/0.2_r8
   tau_s3    = 1._r8/.0045_r8
   tau_cwd   = 1._r8/0.3_r8
   lwtop     = 0.7_r8/31536000.0_r8

   som_adv_flux               = 0._r8
   som_diffus                 = 3.170979198376459e-12_r8
   cryoturb_diffusion_k       = 1.585489599188229e-11_r8
   max_altdepth_cryoturbation = 2._r8
   max_depth_cryoturb         = 3._r8

   br              = 2.525e-6_r8
   br_root         = 0.83e-6_r8

   fstor2tran      = 0.5
   ndays_on        = 30
   ndays_off       = 15
   crit_dayl       = 39300
   crit_onset_fdd  = 15
   crit_onset_swi  = 15
   crit_offset_fdd = 15
   crit_offset_swi = 15
   soilpsi_on      = -0.6
   soilpsi_off     = -0.8

! constant for fire module
   occur_hi_gdp_tree        = 0.39_r8
   lfuel                    = 75._r8
   ufuel                    = 650._r8
   cropfire_a1              = 0.3_r8
   borealat                 = 40._r8/(4.*atan(1.))
   troplat                  = 23.5_r8/(4.*atan(1.))
   non_boreal_peatfire_c    = 0.001_r8
   boreal_peatfire_c        = 4.2e-5_r8
   rh_low                   = 30.0_r8
   rh_hgh                   = 80.0_r8
   bt_min                   = 0.3_r8
   bt_max                   = 0.7_r8
   pot_hmn_ign_counts_alpha = 0.0035_r8
   g0                       = 0.05_r8

   sf     = 0.1_r8
   sf_no3 = 1._r8
#endif

   ! ...............................................
   ! 1.6 Write out as a restart file [histTimeConst]
   ! ...............................................

#ifdef CLMDEBUG 
   call check_TimeInvariants ()
#endif

   CALL WRITE_TimeInvariants (casename, dir_restart)

#ifdef USEMPI
   call mpi_barrier (p_comm_glb, p_err)
#endif

   if (p_is_master) write (6,*) ('Successfully Initialize the Land Time-Invariants')

   ! ----------------------------------------------------------------------
   ! [2] INITIALIZE TIME-VARYING VARIABLES 
   ! as subgrid vectors of length [numpatch]
   ! initial run: create the time-varying variables based on :
   !              i) observation (NOT CODING CURRENTLY), or
   !             ii) some already-known information (NO CODING CURRENTLY), or
   !            iii) arbitrarily 
   ! continuation run: time-varying data read in from restart file 
   ! ----------------------------------------------------------------------

   ! 2.1 current time of model run
   ! ............................

   call initimetype(greenwich)
      
   IF (p_is_master) THEN
      IF(.not. greenwich)THEN
         print *, ".........greenwich false"
      ENDIF
   ENDIF


   ! ................................
   ! 2.2 cosine of solar zenith angle 
   ! ................................
   calday = calendarday(idate)
   if (p_is_worker) then
      do i = 1, numpatch
         coszen(i) = orb_coszen(calday, patchlonr(i), patchlatr(i))
      enddo
   end if

   ! ...........................................
   !2.3 READ in or GUSSES land state information
   ! ...........................................

#if(defined SOILINI)
   fsoildat = DEF_file_soil_init

   call gsoil%define_from_file (fsoildat)
   call ms2p%build (gsoil, landpatch)

   call ncio_read_bcast_serial (fsoildat, 'soil_z', soil_z)
   nl_soil_ini = size(soil_z)

   if (p_is_io) then

      call allocate_block_data (gsoil, snow_d_grid)
      call allocate_block_data (gsoil, soil_t_grid, nl_soil_ini)
      call allocate_block_data (gsoil, soil_w_grid, nl_soil_ini)

      call ncio_read_block (fsoildat, 'soil_t', gsoil, nl_soil_ini, soil_t_grid)  ! soil layer temperature (K)
      call ncio_read_block (fsoildat, 'soil_w', gsoil, nl_soil_ini, soil_w_grid)  ! soil layer wetness (-)
      call ncio_read_block (fsoildat, 'snow_d', gsoil, snow_d_grid)  ! snow depth (m)              

   end if

   if (p_is_worker) then

      allocate (snow_d(numpatch))
      allocate (soil_t(nl_soil_ini,numpatch))
      allocate (soil_w(nl_soil_ini,numpatch))

   end if

   call ms2p%map_aweighted (soil_t_grid, nl_soil_ini, soil_t)
   call ms2p%map_aweighted (soil_w_grid, nl_soil_ini, soil_w)
   call ms2p%map_aweighted (snow_d_grid, snow_d)
   
#endif

   ! ...................
   ! 2.4 LEAF area index
   ! ...................
#if(defined DYN_PHENOLOGY)
   ! CREAT fraction of vegetation cover, greenness, leaf area index, stem index
   if (p_is_worker) then
      
      do i = 1, numpatch
#if(defined SOILINI)
         do nsl = 1, nl_soil
            t_soisno(nsl,i) = soil_t(min(nl_soil_ini,nsl),i)
         enddo
#else
         t_soisno(1:,i) = 283.
#endif
      enddo

      tlai(:)=0.0; tsai(:)=0.0; green(:)=0.0; fveg(:)=0.0
      do i = 1, numpatch
         ! Call Ecological Model() 
         ltyp = patchtype(i)
         if(ltyp > 0) then
            call lai_empirical(ltyp, nl_soil,rootfr(1:,i), t_soisno(1:,i),tlai(i),tsai(i),fveg(i),green(i))
         endif
      enddo

   end if
#else

   idate0 = idate
   CALL adj2begin(idate0)
   year = idate0(1)
   jday = idate0(2)

   IF (DEF_LAI_CLIM) then
      ! yuan, 08/03/2019: read global LAI/SAI data
      CALL julian2monthday (year, jday, month, mday)
      CALL LAI_readin (year, month, dir_landdata)
   ELSE
      Julian_8day = int(calendarday(idate0)-1)/8*8 + 1
      CALL LAI_readin (year, Julian_8day, dir_landdata)
   ENDIF
#ifdef CLMDEBUG
   CALL check_vector_data ('LAI ', tlai)
   CALL check_vector_data ('SAI ', tsai)
#endif

#ifdef BGC
      CALL NDEP_readin(year, dir_landdata, .true., .false.)
      print*,'after NDEP readin'
#ifdef NITRIF
      CALL NITRIF_readin (month, dir_landdata)
      print*,'after NITRIF readin'
#endif

#ifdef CROP
      CALL CROP_readin (dir_landdata)
      print*,'after CROP readin'
      if (p_is_worker) then
         do i = 1, numpatch
            if(patchtype(i) .eq.  0)then
               ps = patch_pft_s(i)
               pe = patch_pft_e(i)
               do m = ps, pe
                  ivt = pftclass(m)
                  if(ivt >= npcropmin)then
                    leafc_p (m) = 0._r8
                    frootc_p(m) = 0._r8
                    tlai    (i) = 0._r8
                    tsai    (i) = 0._r8
                    tlai_p  (m) = 0._r8
                    tsai_p  (m) = 0._r8
                  end if 
               end do
            end if
         end do
      end if
#endif
#endif
#endif
#ifdef Fire
      CALL Fire_readin (year,dir_landdata)
      print*,'after Fire readin'
#endif

   ! ..............................................................................
   ! 2.5 initialize time-varying variables, as subgrid vectors of length [numpatch]
   ! ..............................................................................
   if (p_is_worker) then
      
      allocate ( z_soisno (maxsnl+1:nl_soil,numpatch) )
      allocate ( dz_soisno(maxsnl+1:nl_soil,numpatch) )

      do i = 1, numpatch
         z_soisno (1:nl_soil ,i) = z_soi (1:nl_soil)
         dz_soisno(1:nl_soil ,i) = dz_soi(1:nl_soil)
      enddo

      do i = 1, numpatch
         m = patchclass(i)
         print*,'before IniTimeVar',i
         CALL iniTimeVar(i, patchtype(i)&
            ,porsl(1:,i),psi0(1:,i),hksati(1:,i)&
            ,soil_s_v_alb(i),soil_d_v_alb(i),soil_s_n_alb(i),soil_d_n_alb(i)&
            ,z0m(i),zlnd,chil(m),rho(1:,1:,m),tau(1:,1:,m)&
            ,z_soisno(maxsnl+1:,i),dz_soisno(maxsnl+1:,i)&
            ,t_soisno(maxsnl+1:,i),wliq_soisno(maxsnl+1:,i),wice_soisno(maxsnl+1:,i)&
            ,smp(1:,i),hk(1:,i),zwt(i),wa(i)&
#ifdef PLANT_HYDRAULIC_STRESS
            ,vegwp(1:,i),gs0sun(i),gs0sha(i)&
#endif
            ,t_grnd(i),tleaf(i),ldew(i),ldew_rain(i),ldew_snow(i),sag(i),scv(i)&
            ,snowdp(i),fveg(i),fsno(i),sigf(i),green(i),lai(i),sai(i),coszen(i)&
            ,snw_rds(:,i),mss_bcpho(:,i),mss_bcphi(:,i),mss_ocpho(:,i),mss_ocphi(:,i)&
            ,mss_dst1(:,i),mss_dst2(:,i),mss_dst3(:,i),mss_dst4(:,i)&
            ,alb(1:,1:,i),ssun(1:,1:,i),ssha(1:,1:,i),ssno(1:,1:,:,i)&
            ,thermk(i),extkb(i),extkd(i)&
            ,trad(i),tref(i),qref(i),rst(i),emis(i),zol(i),rib(i)&
            ,ustar(i),qstar(i),tstar(i),fm(i),fh(i),fq(i)&
#ifdef BGC
            ,totlitc(i), totsomc(i), totcwdc(i), decomp_cpools(:,i), decomp_cpools_vr(:,:,i) &
            ,ctrunc_veg(i), ctrunc_soil(i), ctrunc_vr(:,i) &
            ,totlitn(i), totsomn(i), totcwdn(i), decomp_npools(:,i), decomp_npools_vr(:,:,i) &
            ,ntrunc_veg(i), ntrunc_soil(i), ntrunc_vr(:,i) &
            ,totvegc(i), totvegn(i), totcolc(i), totcoln(i), col_endcb(i), col_begcb(i), col_endnb(i), col_begnb(i) &
            ,col_vegendcb(i), col_vegbegcb(i), col_soilendcb(i), col_soilbegcb(i) &
            ,col_vegendnb(i), col_vegbegnb(i), col_soilendnb(i), col_soilbegnb(i) &
            ,col_sminnendnb(i), col_sminnbegnb(i) &
            ,altmax(i) , altmax_lastyear(i), altmax_lastyear_indx(i), lag_npp(i) &
            ,sminn_vr(:,i), sminn(i), smin_no3_vr  (:,i), smin_nh4_vr       (:,i)&
            ,prec10(i), prec60(i), prec365 (i), prec_today(i), prec_daily(:,i), tsoi17(i), rh30(i), accumnstep(i) , skip_balance_check(i) &
#ifdef SASU
!------------------------SASU variables-----------------------
            ,decomp0_cpools_vr        (:,:,i), decomp0_npools_vr        (:,:,i) &
            ,I_met_c_vr_acc             (:,i), I_cel_c_vr_acc             (:,i), I_lig_c_vr_acc             (:,i), I_cwd_c_vr_acc             (:,i) &
            ,AKX_met_to_soil1_c_vr_acc  (:,i), AKX_cel_to_soil1_c_vr_acc  (:,i), AKX_lig_to_soil2_c_vr_acc  (:,i), AKX_soil1_to_soil2_c_vr_acc(:,i) &
            ,AKX_cwd_to_cel_c_vr_acc    (:,i), AKX_cwd_to_lig_c_vr_acc    (:,i), AKX_soil1_to_soil3_c_vr_acc(:,i), AKX_soil2_to_soil1_c_vr_acc(:,i) &
            ,AKX_soil2_to_soil3_c_vr_acc(:,i), AKX_soil3_to_soil1_c_vr_acc(:,i) &
            ,AKX_met_exit_c_vr_acc      (:,i), AKX_cel_exit_c_vr_acc      (:,i), AKX_lig_exit_c_vr_acc      (:,i), AKX_cwd_exit_c_vr_acc      (:,i) &
            ,AKX_soil1_exit_c_vr_acc    (:,i), AKX_soil2_exit_c_vr_acc    (:,i), AKX_soil3_exit_c_vr_acc    (:,i) &
            ,diagVX_c_vr_acc          (:,:,i), upperVX_c_vr_acc         (:,:,i), lowerVX_c_vr_acc         (:,:,i) &
            ,I_met_n_vr_acc             (:,i), I_cel_n_vr_acc             (:,i), I_lig_n_vr_acc             (:,i), I_cwd_n_vr_acc             (:,i) &
            ,AKX_met_to_soil1_n_vr_acc  (:,i), AKX_cel_to_soil1_n_vr_acc  (:,i), AKX_lig_to_soil2_n_vr_acc  (:,i), AKX_soil1_to_soil2_n_vr_acc(:,i) &
            ,AKX_cwd_to_cel_n_vr_acc    (:,i), AKX_cwd_to_lig_n_vr_acc    (:,i), AKX_soil1_to_soil3_n_vr_acc(:,i), AKX_soil2_to_soil1_n_vr_acc(:,i) &
            ,AKX_soil2_to_soil3_n_vr_acc(:,i), AKX_soil3_to_soil1_n_vr_acc(:,i) &
            ,AKX_met_exit_n_vr_acc      (:,i), AKX_cel_exit_n_vr_acc      (:,i), AKX_lig_exit_n_vr_acc      (:,i), AKX_cwd_exit_n_vr_acc      (:,i) &
            ,AKX_soil1_exit_n_vr_acc    (:,i), AKX_soil2_exit_n_vr_acc    (:,i), AKX_soil3_exit_n_vr_acc    (:,i) &
            ,diagVX_n_vr_acc          (:,:,i), upperVX_n_vr_acc         (:,:,i), lowerVX_n_vr_acc         (:,:,i) &
#endif
!------------------------------------------------------------
#endif
#if(defined SOILINI)
            ,nl_soil_ini,soil_z,soil_t(1:,i),soil_w(1:,i),snow_d(i))
#else
          )
#endif
            print*,'after IniTimeVar',i
      enddo

      do i = 1, numpatch
         z_sno (maxsnl+1:0,i) = z_soisno (maxsnl+1:0,i)
         dz_sno(maxsnl+1:0,i) = dz_soisno(maxsnl+1:0,i)
      end do

   end if

   ! ------------------------------------------
   ! PLEASE  
   ! PLEASE UPDATE
   ! PLEASE UPDATE when have the observed lake status
   if (p_is_worker) then

      t_lake      (:,:) = 285.
      lake_icefrac(:,:) = 0.
      savedtke1   (:)   = tkwat

   end if
   ! ------------------------------------------

   ! ...............................................................
   ! 2.6 Write out the model variables for restart run [histTimeVar]
   ! ...............................................................
   
#ifdef CLMDEBUG 
   call check_TimeVariables ()
#endif

   CALL WRITE_TimeVariables (idate, casename, dir_restart)

#ifdef USEMPI
   call mpi_barrier (p_comm_glb, p_err)
#endif

   if (p_is_master) write (6,*) ('Successfully Initialize the Land Time-Vraying Variables')


   ! --------------------------------------------------
   ! Deallocates memory for CLM 1d [numpatch] variables
   ! --------------------------------------------------

   CALL deallocate_TimeInvariants
   CALL deallocate_TimeVariables 

   IF (allocated(z_soisno )) deallocate (z_soisno )
   IF (allocated(dz_soisno)) deallocate (dz_soisno)

#if(defined SOILINI)
   IF (allocated(soil_z)) deallocate (soil_z)
   IF (allocated(snow_d)) deallocate (snow_d)
   IF (allocated(soil_t)) deallocate (soil_t)
   IF (allocated(soil_w)) deallocate (soil_w)
#endif

END SUBROUTINE initialize
! --------------------------------------------------
! EOP
