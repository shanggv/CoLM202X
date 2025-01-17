#include <define.h>

MODULE mod_pixelset

   USE precision
   USE mod_data_type
   IMPLICIT NONE

   ! ---- data types ----
   TYPE :: vec_gather_scatter_type
      
      ! for worker and io
      INTEGER, allocatable :: vlen(:,:)

      ! for worker
      INTEGER, allocatable :: vstt(:,:)
      INTEGER, allocatable :: vend(:,:)

      ! for io
      INTEGER, allocatable :: vcnt(:,:,:)
      INTEGER, allocatable :: vdsp(:,:,:)

   CONTAINS
      final  :: vec_gather_scatter_free_mem

   END TYPE vec_gather_scatter_type

   ! ---- data types ----
   TYPE :: pixelset_type
     
      INTEGER :: nset

      INTEGER, allocatable :: eindex(:)
      INTEGER, allocatable :: ipxstt(:)
      INTEGER, allocatable :: ipxend(:)
      INTEGER, allocatable :: settyp(:)

      INTEGER, allocatable :: ielm(:)

      INTEGER :: nblkgrp
      INTEGER, allocatable :: xblkgrp (:) 
      INTEGER, allocatable :: yblkgrp (:) 

      TYPE(vec_gather_scatter_type) :: vecgs

   CONTAINS 
      procedure, PUBLIC :: set_vecgs         => vec_gather_scatter_set
      procedure, PUBLIC :: get_lonlat_radian => pixelset_get_lonlat_radian
      procedure, PUBLIC :: pset_pack         => pixelset_pack

      final :: pixelset_free_mem

   END TYPE pixelset_type
   
   ! ---- data types ----
   TYPE :: subset_type
      
      INTEGER,  allocatable :: substt(:)
      INTEGER,  allocatable :: subend(:)
      REAL(r8), allocatable :: subfrc(:)

   CONTAINS
      procedure, PUBLIC :: build => subset_build
      final :: subset_free_mem

   END TYPE subset_type

   ! ---- data types ----
   TYPE :: superset_type
      
      INTEGER,  allocatable :: sup(:)

   CONTAINS
      procedure, PUBLIC :: build => superset_build
      final :: superset_free_mem

   END TYPE superset_type

CONTAINS
   
   ! --------------------------------
   SUBROUTINE pixelset_get_lonlat_radian (this, rlon, rlat)

      USE precision
      USE mod_utils
      USE mod_pixel
      USE mod_mesh

      IMPLICIT NONE
      CLASS(pixelset_type) :: this

      REAL(r8), intent(inout) :: rlon(:), rlat(:)

      ! Local Variables
      INTEGER :: iset, ie, ipxstt, ipxend, npxl, ipxl
      REAL(r8), allocatable :: area(:)

      DO iset = 1, this%nset

         ie = this%ielm(iset)

         ipxstt = this%ipxstt (iset)
         ipxend = this%ipxend (iset)

         allocate (area (ipxstt:ipxend))
         DO ipxl = ipxstt, ipxend 
            area(ipxl) = areaquad (&
               pixel%lat_s(mesh(ie)%ilat(ipxl)), &
               pixel%lat_n(mesh(ie)%ilat(ipxl)), &
               pixel%lon_w(mesh(ie)%ilon(ipxl)), &
               pixel%lon_e(mesh(ie)%ilon(ipxl)) )
         ENDDO

         npxl = ipxend - ipxstt + 1
         rlat(iset) = get_pixelset_rlat ( &
            npxl, mesh(ie)%ilat(ipxstt:ipxend), area)
         rlon(iset) = get_pixelset_rlon ( &
            npxl, mesh(ie)%ilon(ipxstt:ipxend), area)

         deallocate (area)

      ENDDO

   END SUBROUTINE pixelset_get_lonlat_radian 

   ! --------------------------------
   FUNCTION get_pixelset_rlat (npxl, ilat, area) result(rlat)

      USE precision
      USE MathConstants, only : pi
      USE mod_pixel
      IMPLICIT NONE
      
      REAL(r8) :: rlat

      INTEGER,  intent(in) :: npxl
      INTEGER,  intent(in) :: ilat(npxl)
      REAL(r8), intent(in) :: area(npxl)

      ! Local variables
      INTEGER :: ipxl

      rlat = 0.0
      DO ipxl = 1, npxl
         rlat = rlat + (pixel%lat_s(ilat(ipxl)) + pixel%lat_n(ilat(ipxl))) * 0.5 * area(ipxl)
      ENDDO
      rlat = rlat / sum(area) * pi/180.0

   END FUNCTION get_pixelset_rlat

   ! --------------------------------
   FUNCTION get_pixelset_rlon (npxl, ilon, area) result(rlon)

      USE precision
      USE mod_utils
      USE MathConstants, only : pi
      USE mod_pixel
      IMPLICIT NONE

      REAL(r8) :: rlon

      INTEGER,  intent(in) :: npxl
      INTEGER,  intent(in) :: ilon(npxl)
      REAL(r8), intent(in) :: area(npxl)

      ! Local variables
      INTEGER  :: ipxl
      REAL(r8) :: lon, lon0, area_done

      lon = 0.0
      area_done = 0.0
      DO ipxl = 1, npxl

         IF (pixel%lon_w(ilon(ipxl)) > pixel%lon_e(ilon(ipxl))) THEN
            lon0 = (pixel%lon_w(ilon(ipxl)) + pixel%lon_e(ilon(ipxl)) + 360.0) * 0.5 
         ELSE
            lon0 = (pixel%lon_w(ilon(ipxl)) + pixel%lon_e(ilon(ipxl))) * 0.5
         ENDIF
          
         CALL normalize_longitude (lon0)

         IF (lon - lon0 > 180._r8) THEN
            lon = lon * area_done + (lon0 + 360._r8) * area(ipxl)
         ELSEIF (lon - lon0 < -180._r8) THEN
            lon = lon * area_done + (lon0 - 360._r8) * area(ipxl)
         ELSE
            lon = lon * area_done + lon0 * area(ipxl)
         ENDIF

         area_done = area_done + area(ipxl)
         lon = lon / area_done

         CALL normalize_longitude(lon)
            
      ENDDO

      rlon = lon * pi/180.0

   END FUNCTION get_pixelset_rlon

   ! --------------------------------
   SUBROUTINE pixelset_free_mem (this)
      
      IMPLICIT NONE
      TYPE (pixelset_type) :: this

      IF (allocated(this%eindex)) deallocate(this%eindex)
      IF (allocated(this%ipxstt)) deallocate(this%ipxstt)
      IF (allocated(this%ipxend)) deallocate(this%ipxend)
      IF (allocated(this%settyp)) deallocate(this%settyp)
      
      IF (allocated(this%ielm  )) deallocate(this%ielm  )
      
      IF (allocated(this%xblkgrp)) deallocate(this%xblkgrp)
      IF (allocated(this%yblkgrp)) deallocate(this%yblkgrp)

   END SUBROUTINE pixelset_free_mem
   
   ! --------------------------------
   SUBROUTINE vec_gather_scatter_set (this)

      USE mod_block
      USE spmd_task
      USE mod_mesh
      IMPLICIT NONE

      class(pixelset_type)  :: this

      ! Local variables
      INTEGER :: iproc
      INTEGER :: iset, ie, xblk, yblk, iblk, jblk, scnt, iblkgrp
      LOGICAL, allocatable :: nonzero(:,:)
      
#ifdef USEMPI
      CALL mpi_barrier (p_comm_glb, p_err)
#endif
         
      IF (.not. allocated (this%vecgs%vlen)) THEN
         allocate (this%vecgs%vlen (gblock%nxblk, gblock%nyblk))
         this%vecgs%vlen(:,:) = 0
      ENDIF

      IF (p_is_worker) THEN

         IF (.not. allocated (this%vecgs%vstt)) THEN
            allocate (this%vecgs%vstt (gblock%nxblk, gblock%nyblk))
            allocate (this%vecgs%vend (gblock%nxblk, gblock%nyblk))
         ENDIF

         this%vecgs%vstt(:,:) = 0
         this%vecgs%vend(:,:) = -1

         ie = 1
         xblk = 0
         yblk = 0
         DO iset = 1, this%nset 
            DO WHILE (this%eindex(iset) /= mesh(ie)%indx)
               ie = ie + 1
            ENDDO 

            IF ((mesh(ie)%xblk /= xblk) .or. (mesh(ie)%yblk /= yblk)) THEN
               xblk = mesh(ie)%xblk
               yblk = mesh(ie)%yblk
               this%vecgs%vstt(xblk,yblk) = iset
            ENDIF

            this%vecgs%vend(xblk,yblk) = iset
         ENDDO

         this%vecgs%vlen = this%vecgs%vend - this%vecgs%vstt + 1

#ifdef USEMPI
         DO jblk = 1, gblock%nyblk
            DO iblk = 1, gblock%nxblk
               IF (gblock%pio(iblk,jblk) == p_address_io(p_my_group)) THEN

                  scnt = this%vecgs%vlen(iblk,jblk)
                  CALL mpi_gather (scnt, 1, MPI_INTEGER, &
                     MPI_INULL_P, 1, MPI_INTEGER, p_root, p_comm_group, p_err)

               ENDIF
            ENDDO
         ENDDO
#endif
      ENDIF

#ifdef USEMPI
      IF (p_is_io) THEN
      
         IF (.not. allocated(this%vecgs%vcnt)) THEN
            allocate (this%vecgs%vcnt (0:p_np_group-1,gblock%nxblk,gblock%nyblk))
            allocate (this%vecgs%vdsp (0:p_np_group-1,gblock%nxblk,gblock%nyblk))
         ENDIF
      
         this%vecgs%vcnt(:,:,:) = 0
         DO jblk = 1, gblock%nyblk
            DO iblk = 1, gblock%nxblk
               IF (gblock%pio(iblk,jblk) == p_iam_glb) THEN

                  scnt = 0
                  CALL mpi_gather (scnt, 1, MPI_INTEGER, &
                     this%vecgs%vcnt(:,iblk,jblk), 1, MPI_INTEGER, &
                     p_root, p_comm_group, p_err)

                  this%vecgs%vdsp(0,iblk,jblk) = 0
                  DO iproc = 1, p_np_group-1
                     this%vecgs%vdsp(iproc,iblk,jblk) = &
                        this%vecgs%vdsp(iproc-1,iblk,jblk) + this%vecgs%vcnt(iproc-1,iblk,jblk)
                  ENDDO

                  this%vecgs%vlen(iblk,jblk) = sum(this%vecgs%vcnt(:,iblk,jblk))

               ENDIF
            ENDDO
         ENDDO
      ENDIF
#endif

      IF (p_is_io .or. p_is_worker) THEN
         allocate (nonzero (gblock%nxblk,gblock%nyblk))

         nonzero = this%vecgs%vlen > 0
#ifdef USEMPI
         CALL mpi_allreduce (MPI_IN_PLACE, nonzero, gblock%nxblk * gblock%nyblk, &
            MPI_LOGICAL, MPI_LOR, p_comm_group, p_err)
#endif

         this%nblkgrp = count(nonzero)
         IF (allocated(this%xblkgrp)) deallocate(this%xblkgrp)
         IF (allocated(this%yblkgrp)) deallocate(this%yblkgrp)
         allocate (this%xblkgrp (this%nblkgrp))
         allocate (this%yblkgrp (this%nblkgrp))

         iblkgrp = 0
         DO jblk = 1, gblock%nyblk
            DO iblk = 1, gblock%nxblk
               IF (nonzero(iblk,jblk)) THEN
                  iblkgrp = iblkgrp + 1
                  this%xblkgrp(iblkgrp) = iblk
                  this%yblkgrp(iblkgrp) = jblk
               ENDIF
            ENDDO
         ENDDO

         deallocate(nonzero)
      ENDIF

   END SUBROUTINE vec_gather_scatter_set 
   
   ! --------------------------------
   SUBROUTINE pixelset_pack (this, mask, nset_packed)

      USE spmd_task
      IMPLICIT NONE
      class(pixelset_type) :: this
      LOGICAL, intent(in)  :: mask(:)
      INTEGER, intent(out) :: nset_packed

      INTEGER, allocatable :: eindex1(:)
      INTEGER, allocatable :: ipxstt1(:)
      INTEGER, allocatable :: ipxend1(:)
      INTEGER, allocatable :: settyp1(:)
      INTEGER, allocatable :: ielm1  (:)

      IF (p_is_worker) THEN 
      
         IF (count(mask) < this%nset) THEN

            allocate (eindex1(this%nset))
            allocate (ipxstt1(this%nset))
            allocate (ipxend1(this%nset))
            allocate (settyp1(this%nset))
            allocate (ielm1  (this%nset))

            eindex1 = this%eindex
            ipxstt1 = this%ipxstt
            ipxend1 = this%ipxend
            settyp1 = this%settyp
            ielm1   = this%ielm

            deallocate (this%eindex)
            deallocate (this%ipxstt)
            deallocate (this%ipxend)
            deallocate (this%settyp)
            deallocate (this%ielm  )

            this%nset = count(mask)

            IF (this%nset > 0) THEN

               allocate (this%eindex(this%nset))
               allocate (this%ipxstt(this%nset))
               allocate (this%ipxend(this%nset))
               allocate (this%settyp(this%nset))
               allocate (this%ielm  (this%nset))

               this%eindex = pack(eindex1, mask)
               this%ipxstt = pack(ipxstt1, mask)
               this%ipxend = pack(ipxend1, mask)
               this%settyp = pack(settyp1, mask)
               this%ielm   = pack(ielm1  , mask)

            ENDIF

            deallocate (eindex1)
            deallocate (ipxstt1)
            deallocate (ipxend1)
            deallocate (settyp1)
            deallocate (ielm1  )

         ENDIF
      
      ENDIF
         
      CALL this%set_vecgs

      nset_packed = this%nset

   END SUBROUTINE pixelset_pack

   ! --------------------------------
   SUBROUTINE vec_gather_scatter_free_mem (this)
      
      IMPLICIT NONE
      TYPE (vec_gather_scatter_type) :: this

      IF (allocated(this%vlen))  deallocate (this%vlen)
      IF (allocated(this%vstt))  deallocate (this%vstt)
      IF (allocated(this%vend))  deallocate (this%vend)
      IF (allocated(this%vcnt))  deallocate (this%vcnt)
      IF (allocated(this%vdsp))  deallocate (this%vdsp)
   
   END SUBROUTINE vec_gather_scatter_free_mem

   ! --------------------------------
   SUBROUTINE subset_build (this, superset, subset, use_frac, shadowfrac)
      
      USE mod_mesh
      USE mod_pixel
      USE mod_utils
      IMPLICIT NONE
      
      CLASS(subset_type) :: this
      
      TYPE (pixelset_type), intent(in) :: superset
      TYPE (pixelset_type), intent(in) :: subset
      LOGICAL, intent(in) :: use_frac
      REAL(r8), intent(in), optional :: shadowfrac (:)

      ! Local Variables
      INTEGER :: isuperset, isubset, ielm, ipxl, istt, iend

      IF (superset%nset <= 0) RETURN

      IF (allocated(this%substt)) deallocate(this%substt)
      IF (allocated(this%subend)) deallocate(this%subend)

      allocate (this%substt (superset%nset))
      allocate (this%subend (superset%nset))

      this%substt =  0
      this%subend = -1

      isuperset = 1
      isubset   = 1
      DO WHILE (isubset <= subset%nset)
         IF (     (subset%eindex(isubset) == superset%eindex(isuperset)) &
            .and. (subset%ipxstt(isubset) >= superset%ipxstt(isuperset)) &
            .and. (subset%ipxend(isubset) <= superset%ipxend(isuperset))) then

            IF (this%substt(isuperset) == 0) THEN
               this%substt(isuperset) = isubset
            ENDIF

            this%subend(isuperset) = isubset

            isubset = isubset + 1
         ELSE
            isuperset = isuperset + 1
         ENDIF
      ENDDO

      IF (use_frac) THEN

         IF (allocated(this%subfrc)) deallocate(this%subfrc)

         IF (subset%nset <= 0) RETURN
         
         allocate (this%subfrc (subset%nset))

         DO isubset = 1, subset%nset
            ielm = subset%ielm(isubset)
            this%subfrc(isubset) = 0
            DO ipxl = subset%ipxstt(isubset), subset%ipxend(isubset) 
               this%subfrc(isubset) = this%subfrc(isubset) & 
                  + areaquad (&
                  pixel%lat_s(mesh(ielm)%ilat(ipxl)), &
                  pixel%lat_n(mesh(ielm)%ilat(ipxl)), &
                  pixel%lon_w(mesh(ielm)%ilon(ipxl)), &
                  pixel%lon_e(mesh(ielm)%ilon(ipxl)) )
            ENDDO
            IF (present(shadowfrac)) THEN
               this%subfrc(isubset) = this%subfrc(isubset) * shadowfrac(isubset)
            ENDIF
         ENDDO

         DO isuperset = 1, superset%nset
            IF (this%substt(isuperset) /= 0) THEN
               istt = this%substt(isuperset)
               iend = this%subend(isuperset)
               this%subfrc(istt:iend) = this%subfrc(istt:iend) / sum(this%subfrc(istt:iend))
            ENDIF
         ENDDO

      ENDIF

   END SUBROUTINE subset_build

   ! --------------------------------
   SUBROUTINE subset_free_mem (this)
      
      IMPLICIT NONE
      TYPE (subset_type) :: this

      IF (allocated(this%substt))  deallocate (this%substt)
      IF (allocated(this%subend))  deallocate (this%subend)
      IF (allocated(this%subfrc))  deallocate (this%subfrc)
   
   END SUBROUTINE subset_free_mem

   ! --------------------------------
   SUBROUTINE superset_build (this, superset, subset)
      
      IMPLICIT NONE
      
      CLASS(superset_type) :: this
      
      TYPE (pixelset_type), intent(in) :: superset
      TYPE (pixelset_type), intent(in) :: subset

      ! Local Variables
      INTEGER :: isuperset, isubset

      IF (subset%nset <= 0) RETURN

      IF (allocated(this%sup)) deallocate(this%sup)

      allocate (this%sup (subset%nset))

      isuperset = 1
      isubset   = 1
      DO WHILE (isubset <= subset%nset)
         IF (     (subset%eindex(isubset) == superset%eindex(isuperset)) &
            .and. (subset%ipxstt(isubset) >= superset%ipxstt(isuperset)) &
            .and. (subset%ipxend(isubset) <= superset%ipxend(isuperset))) then

            this%sup(isubset) = isuperset

            isubset = isubset + 1
         ELSE
            isuperset = isuperset + 1
         ENDIF
      ENDDO

   END SUBROUTINE superset_build

   ! --------------------------------
   SUBROUTINE superset_free_mem (this)
      
      IMPLICIT NONE
      TYPE (superset_type) :: this

      IF (allocated(this%sup))  deallocate (this%sup)
   
   END SUBROUTINE superset_free_mem

END MODULE mod_pixelset
