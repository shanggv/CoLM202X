#include <define.h>
#ifdef BGC

module bgc_SoilBiogeochemNStateUpdate1Mod
use precision
use MOD_BGCTimeInvars, only: &
  ! bgc constants
    i_met_lit, i_cel_lit, i_lig_lit, i_cwd, i_soil1, i_soil2, i_soil3
use MOD_BGCTimeInvars, only: &
    receiver_pool, donor_pool, nitrif_n2o_loss_frac

use MOD_BGCTimeVars, only: &
    ! Mineral nitrogen pools (inout)
    sminn_vr                   , smin_nh4_vr                , smin_no3_vr              , &
    ndep_prof                  , nfixation_prof             , &
    AKX_met_to_soil1_n_vr_acc  , AKX_cel_to_soil1_n_vr_acc  , AKX_lig_to_soil2_n_vr_acc  , AKX_soil1_to_soil2_n_vr_acc, &
    AKX_cwd_to_cel_n_vr_acc    , AKX_cwd_to_lig_n_vr_acc    , AKX_soil1_to_soil3_n_vr_acc, AKX_soil2_to_soil1_n_vr_acc, &
    AKX_soil2_to_soil3_n_vr_acc, AKX_soil3_to_soil1_n_vr_acc, &
    AKX_met_exit_n_vr_acc      , AKX_cel_exit_n_vr_acc      , AKX_lig_exit_n_vr_acc      , AKX_cwd_exit_n_vr_acc      , &
    AKX_soil1_exit_n_vr_acc    , AKX_soil2_exit_n_vr_acc    , AKX_soil3_exit_n_vr_acc 

use MOD_1D_BGCFluxes, only: &
    ! Decomposition fluxes variables (inout)
           decomp_npools_sourcesink, decomp_ntransfer_vr      , decomp_sminn_flux_vr     , sminn_to_denit_decomp_vr, &
           gross_nmin_vr           , actual_immob_nh4_vr      , actual_immob_no3_vr      , &
           sminn_to_plant_vr       , smin_nh4_to_plant_vr     , smin_no3_to_plant_vr     , supplement_to_sminn_vr, &
           sminn_to_plant_fun_vr   , sminn_to_plant_fun_nh4_vr, sminn_to_plant_fun_no3_vr, &
           sminn_to_denit_excess_vr, f_nit_vr                 , f_denit_vr               , soyfixn_to_sminn, &
           ndep_to_sminn           , ffix_to_sminn            , nfix_to_sminn            , fert_to_sminn
   use spmd_task

implicit none

public SoilBiogeochemNStateUpdate1

contains

subroutine SoilBiogeochemNStateUpdate1(i,deltim,nl_soil,ndecomp_transitions,dz_soi)

integer ,intent(in) :: i
real(r8),intent(in) :: deltim
integer ,intent(in) :: nl_soil
integer ,intent(in) :: ndecomp_transitions
real(r8),intent(iN) :: dz_soi(1:nl_soil)

integer j,k
real(r8):: sminflux,minerflux

      do j = 1, nl_soil
#ifdef FUN
               ! N deposition and fixation (put all into NH4 pool)
               smin_nh4_vr(j,i) = smin_nh4_vr(j,i) + ndep_to_sminn(i)*deltim * ndep_prof(j,i)
               smin_nh4_vr(j,i) = smin_nh4_vr(j,i) + ffix_to_sminn(i)*deltim * nfixation_prof(j,i)
#else
#ifndef NITRIF
               ! N deposition and fixation
               sminn_vr(j,i) = sminn_vr(j,i) + ndep_to_sminn(i)*deltim * ndep_prof(j,i)
               sminn_vr(j,i) = sminn_vr(j,i) + nfix_to_sminn(i)*deltim * nfixation_prof(j,i)
#else
               ! N deposition and fixation (put all into NH4 pool)
               smin_nh4_vr(j,i) = smin_nh4_vr(j,i) + ndep_to_sminn(i)*deltim * ndep_prof(j,i)
               smin_nh4_vr(j,i) = smin_nh4_vr(j,i) + nfix_to_sminn(i)*deltim * nfixation_prof(j,i)
                       
#endif
#endif
      end do

!      ! repeating N dep and fixation for crops
#ifdef CROP
      do j = 1, nl_soil

            ! column loop
#ifndef NITRIF
                  ! N deposition and fixation
         sminn_vr(j,i) = sminn_vr(j,i) &
                     + fert_to_sminn(i) * deltim * ndep_prof(j,i)
#ifdef CNSOYFIXN
         sminn_vr(j,i) = sminn_vr(j,i) &
                     + soyfixn_to_sminn(i) * deltim * nfixation_prof(j,i)
#endif
#else
                  ! N deposition and fixation (put all into NH4 pool)
         smin_nh4_vr(j,i) = smin_nh4_vr(j,i) &
                        + fert_to_sminn(i) * deltim * ndep_prof(j,i)
#ifdef CNSOYFIXN
         smin_nh4_vr(j,i) = smin_nh4_vr(j,i) &
                        + soyfixn_to_sminn(i) * deltim * nfixation_prof(j,i)
#endif
#endif
      end do
#endif

      ! decomposition fluxes
      do k = 1, ndecomp_transitions
         do j = 1, nl_soil

               decomp_npools_sourcesink(j,donor_pool(k),i) = &
                    decomp_npools_sourcesink(j,donor_pool(k),i) - &
                    decomp_ntransfer_vr(j,k,i) * deltim
         end do
      end do


      do k = 1, ndecomp_transitions
         if ( receiver_pool(k) /= 0 ) then  ! skip terminal transitions
            do j = 1, nl_soil

                  decomp_npools_sourcesink(j,receiver_pool(k),i) = &
                       decomp_npools_sourcesink(j,receiver_pool(k),i) + &
                       (decomp_ntransfer_vr(j,k,i) + &
                        decomp_sminn_flux_vr(j,k,i)) * deltim
            end do
         else  ! terminal transitions
            do j = 1, nl_soil
                  decomp_npools_sourcesink(j,donor_pool(k),i) = &
                       decomp_npools_sourcesink(j,donor_pool(k),i) - &
                       decomp_sminn_flux_vr(j,k,i) * deltim
            end do
         end if
      end do

#ifdef SASU
   do j = 1, nl_soil
      AKX_met_to_soil1_n_vr_acc  (j,i) = AKX_met_to_soil1_n_vr_acc  (j,i) + (decomp_ntransfer_vr(j, 1,i) + decomp_sminn_flux_vr(j, 1,i)) * deltim
      AKX_cel_to_soil1_n_vr_acc  (j,i) = AKX_cel_to_soil1_n_vr_acc  (j,i) + (decomp_ntransfer_vr(j, 2,i) + decomp_sminn_flux_vr(j, 2,i)) * deltim
      AKX_lig_to_soil2_n_vr_acc  (j,i) = AKX_lig_to_soil2_n_vr_acc  (j,i) + (decomp_ntransfer_vr(j, 3,i) + decomp_sminn_flux_vr(j, 3,i)) * deltim
      AKX_soil1_to_soil2_n_vr_acc(j,i) = AKX_soil1_to_soil2_n_vr_acc(j,i) + (decomp_ntransfer_vr(j, 4,i) + decomp_sminn_flux_vr(j, 4,i)) * deltim
      AKX_cwd_to_cel_n_vr_acc    (j,i) = AKX_cwd_to_cel_n_vr_acc    (j,i) + (decomp_ntransfer_vr(j, 5,i) + decomp_sminn_flux_vr(j, 5,i)) * deltim
      AKX_cwd_to_lig_n_vr_acc    (j,i) = AKX_cwd_to_lig_n_vr_acc    (j,i) + (decomp_ntransfer_vr(j, 6,i) + decomp_sminn_flux_vr(j, 6,i)) * deltim
      AKX_soil1_to_soil3_n_vr_acc(j,i) = AKX_soil1_to_soil3_n_vr_acc(j,i) + (decomp_ntransfer_vr(j, 7,i) + decomp_sminn_flux_vr(j, 7,i)) * deltim
      AKX_soil2_to_soil1_n_vr_acc(j,i) = AKX_soil2_to_soil1_n_vr_acc(j,i) + (decomp_ntransfer_vr(j, 8,i) + decomp_sminn_flux_vr(j, 8,i)) * deltim
      AKX_soil2_to_soil3_n_vr_acc(j,i) = AKX_soil2_to_soil3_n_vr_acc(j,i) + (decomp_ntransfer_vr(j, 9,i) + decomp_sminn_flux_vr(j, 9,i)) * deltim
      AKX_soil3_to_soil1_n_vr_acc(j,i) = AKX_soil3_to_soil1_n_vr_acc(j,i) + (decomp_ntransfer_vr(j,10,i) + decomp_sminn_flux_vr(j,10,i)) * deltim

      AKX_met_exit_n_vr_acc      (j,i) = AKX_met_exit_n_vr_acc      (j,i) + decomp_ntransfer_vr(j, 1,i) * deltim
      AKX_cel_exit_n_vr_acc      (j,i) = AKX_cel_exit_n_vr_acc      (j,i) + decomp_ntransfer_vr(j, 2,i) * deltim
      AKX_lig_exit_n_vr_acc      (j,i) = AKX_lig_exit_n_vr_acc      (j,i) + decomp_ntransfer_vr(j, 3,i) * deltim
      AKX_soil1_exit_n_vr_acc    (j,i) = AKX_soil1_exit_n_vr_acc    (j,i) + decomp_ntransfer_vr(j, 4,i) * deltim
      AKX_cwd_exit_n_vr_acc      (j,i) = AKX_cwd_exit_n_vr_acc      (j,i) + decomp_ntransfer_vr(j, 5,i) * deltim
      AKX_cwd_exit_n_vr_acc      (j,i) = AKX_cwd_exit_n_vr_acc      (j,i) + decomp_ntransfer_vr(j, 6,i) * deltim
      AKX_soil1_exit_n_vr_acc    (j,i) = AKX_soil1_exit_n_vr_acc    (j,i) + decomp_ntransfer_vr(j, 7,i) * deltim
      AKX_soil2_exit_n_vr_acc    (j,i) = AKX_soil2_exit_n_vr_acc    (j,i) + decomp_ntransfer_vr(j, 8,i) * deltim
      AKX_soil2_exit_n_vr_acc    (j,i) = AKX_soil2_exit_n_vr_acc    (j,i) + decomp_ntransfer_vr(j, 9,i) * deltim
      AKX_soil3_exit_n_vr_acc    (j,i) = AKX_soil3_exit_n_vr_acc    (j,i) + decomp_ntransfer_vr(j,10,i) * deltim
   end do
#endif

#ifndef NITRIF

         !--------------------------------------------------------
         !-------------    NITRIF_DENITRIF OFF -------------------
         !--------------------------------------------------------

         ! immobilization/mineralization in litter-to-SOM and SOM-to-SOM fluxes and denitrification fluxes
         do k = 1, ndecomp_transitions
            if ( receiver_pool(k) /= 0 ) then  ! skip terminal transitions
               do j = 1, nl_soil
                     sminn_vr(j,i)  = sminn_vr(j,i) - &
                          (sminn_to_denit_decomp_vr(j,k,i) + &
                          decomp_sminn_flux_vr(j,k,i))* deltim
               end do
            else
               do j = 1, nl_soil
                     sminn_vr(j,i)  = sminn_vr(j,i) - &
                          sminn_to_denit_decomp_vr(j,k,i)* deltim

                     sminn_vr(j,i)  = sminn_vr(j,i) + &
                          decomp_sminn_flux_vr(j,k,i)* deltim

               end do
            endif
         end do
                     

         do j = 1, nl_soil
               ! "bulk denitrification"
               sminn_vr(j,i) = sminn_vr(j,i) - sminn_to_denit_excess_vr(j,i) * deltim

               ! total plant uptake from mineral N
#if !defined(FUN)
                  sminn_vr(j,i) = sminn_vr(j,i) - sminn_to_plant_vr(j,i)*deltim
#else
                  sminn_vr(j,i) = sminn_vr(j,i) - sminn_to_plant_fun_vr(j,i)*deltim
#endif
               ! flux that prevents N limitation (when Carbon_only is set)
               sminn_vr(j,i) = sminn_vr(j,i) + supplement_to_sminn_vr(j,i)*deltim
         end do
               
#else

         !--------------------------------------------------------
         !-------------    NITRIF_DENITRIF ON --------------------
         !--------------------------------------------------------

         do j = 1, nl_soil

               ! mineralization fluxes (divert a fraction of this stream to nitrification flux, add the rest to NH4 pool)
               smin_nh4_vr(j,i) = smin_nh4_vr(j,i) + gross_nmin_vr(j,i)*deltim

               ! immobilization fluxes
               smin_nh4_vr(j,i) = smin_nh4_vr(j,i) - actual_immob_nh4_vr(j,i)*deltim

               smin_no3_vr(j,i) = smin_no3_vr(j,i) - actual_immob_no3_vr(j,i)*deltim

               ! plant uptake fluxes
#if !defined(FUN)
                  smin_nh4_vr(j,i) = smin_nh4_vr(j,i) - smin_nh4_to_plant_vr(j,i)*deltim

                  smin_no3_vr(j,i) = smin_no3_vr(j,i) - smin_no3_to_plant_vr(j,i)*deltim
#else
                  smin_nh4_vr(j,i) = smin_nh4_vr(j,i) -  sminn_to_plant_fun_nh4_vr(j,i)*deltim

                  smin_no3_vr(j,i) = smin_no3_vr(j,i) -  sminn_to_plant_fun_no3_vr(j,i)*deltim
#endif
             

               ! Account for nitrification fluxes
               smin_nh4_vr(j,i) = smin_nh4_vr(j,i) - f_nit_vr(j,i) * deltim

               smin_no3_vr(j,i) = smin_no3_vr(j,i) + f_nit_vr(j,i) * deltim &
                    * (1._r8 - nitrif_n2o_loss_frac)

               ! Account for denitrification fluxes
               smin_no3_vr(j,i) = smin_no3_vr(j,i) - f_denit_vr(j,i) * deltim

               ! flux that prevents N limitation (when Carbon_only is set; put all into NH4)
               smin_nh4_vr(j,i) = smin_nh4_vr(j,i) + supplement_to_sminn_vr(j,i)*deltim

               ! update diagnostic total
               sminn_vr(j,i) = smin_nh4_vr(j,i) + smin_no3_vr(j,i)
               
         end do
              
#endif

end subroutine SoilBiogeochemNStateUpdate1

end module bgc_SoilBiogeochemNStateUpdate1Mod
#endif
