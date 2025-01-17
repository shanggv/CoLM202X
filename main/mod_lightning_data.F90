#include <define.h>

MODULE mod_lightning_data
#ifdef Fire
   USE mod_grid
   USE mod_data_type
   USE mod_mapping_grid2pset
   use MOD_BGCTimeVars, only: lnfm
   IMPLICIT NONE

   CHARACTER(len=256) :: file_lightning
   TYPE(grid_type) :: grid_lightning

   TYPE(block_data_real8_2d) :: f_lnfm
   
   type (mapping_grid2pset_type) :: mg2p_lnfm

CONTAINS

   ! ----------
   SUBROUTINE init_lightning_data (time, idate)
      
      USE spmd_task
      USE mod_namelist
      USE timemanager
      USE mod_grid
      USE ncio_serial
      USE ncio_block
      USE mod_landpatch
      USE mod_colm_debug
      IMPLICIT NONE
      
      type(timestamp), intent(in) :: time
      integer,         intent(in) :: idate(3)

      ! Local Variables
      REAL(r8), allocatable :: lat(:), lon(:)
      INTEGER :: itime

      file_lightning = trim(DEF_dir_rawdata) // '/fire/clmforc.Li_2012_climo1995-2011.T62.lnfm_Total_c140423.nc'

      CALL ncio_read_bcast_serial (file_lightning, 'lat', lat)
      CALL ncio_read_bcast_serial (file_lightning, 'lon', lon)

      CALL grid_lightning%define_by_center (lat, lon)
      
      CALL allocate_block_data (grid_lightning, f_lnfm)  
      
      call mg2p_lnfm%build (grid_lightning, landpatch)

      itime = (idate(2)-1)*8 + min(idate(3)/10800+1,8)

      CALL ncio_read_block_time (file_lightning, 'lnfm', grid_lightning, itime, f_lnfm)
#ifdef CLMDEBUG
      CALL check_block_data ('lightning', f_lnfm)
#endif

!      IF (p_is_worker) THEN
!         IF (numpatch > 0) THEN
!            allocate (lnfm (numpatch))
!         ENDIF
!      ENDIF

   END SUBROUTINE init_lightning_data 

   ! ----------
   SUBROUTINE update_lightning_data (time, deltim)
      
      USE timemanager
      USE ncio_block
      USE mod_colm_debug
      IMPLICIT NONE
      
      type(timestamp), intent(in) :: time
      REAL(r8), intent(in) :: deltim

      ! Local Variables
      type(timestamp) :: time_next
      INTEGER :: itime, itime_next

      itime = (time%day-1)*8 + min(time%sec/10800+1,8)
      IF (mod(time%sec,10800) == 0) itime = itime - 1

      time_next = time + int(deltim)
      itime_next = (time_next%day-1)*8 + max(0,time_next%sec-1)/10800+1

      IF (itime_next /= itime) THEN
         itime_next = min(itime_next,2920)
         CALL ncio_read_block_time (file_lightning, 'lnfm', grid_lightning, itime_next, f_lnfm)
#ifdef CLMDEBUG
         CALL check_block_data ('lightning', f_lnfm)
#endif
      
         call mg2p_lnfm%map_aweighted (f_lnfm, lnfm) 
#ifdef CLMDEBUG
         call check_vector_data ('lightning', lnfm)
#endif
      ENDIF

   END SUBROUTINE update_lightning_data 

#endif
END MODULE mod_lightning_data
