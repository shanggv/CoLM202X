#include <define.h>

#ifdef USE_DEPTH_TO_BEDROCK

subroutine dbedrock_readin (dir_landdata)

   use precision
   use spmd_task
   USE mod_namelist
   use mod_landpatch
   use ncio_vector
   USE GlobalVars, only : nl_soil, dz_soi
   use MOD_TimeInvariants, only : dbedrock, ibedrock
#ifdef SinglePoint
   USE mod_single_srfdata
#endif

   IMPLICIT NONE

   character(LEN=256), INTENT(in) :: dir_landdata

   ! Local Variables
   character(len=256) :: lndname
   integer  :: ipatch, L

#ifdef SinglePoint
   dbedrock(:) = SITE_dbedrock
#else
   lndname = trim(dir_landdata)//'/dbedrock/dbedrock_patches.nc'
   call ncio_read_vector (lndname, 'dbedrock_patches', landpatch, dbedrock) 
#endif

   if (p_is_worker) then

      do ipatch = 1, numpatch

         L = landpatch%settyp(ipatch)

         if (L == 0) then
            ibedrock(ipatch) = 0
         else
            
            dbedrock(ipatch) = dbedrock(ipatch) / 100.0 ! from cm to meter
            dbedrock(ipatch) = max(dbedrock(ipatch), dz_soi(1))
            
            IF (dbedrock(ipatch) > zi_soi(1)) THEN
               ibedrock(ipatch) = findloc(dbedrock(ipatch)>zi_soi, .true., back=.true., dim=1) + 1
            ELSE
               ibedrock(ipatch) = 1
            ENDIF

         end if

      end do

   end if

end subroutine dbedrock_readin

#endif
