PROGRAM p124      
!-------------------------------------------------------------------------
!     program 12.4 three dimensional transient analysis of heat conduction 
!     equation using 8-node hexahedral elements; parallel pcg version
!     implicit; integration in time using 'theta' method 
!-------------------------------------------------------------------------
 USE precision; USE global_variables; USE mp_interface; USE input
 USE output; USE loading; USE timing; USE maths; USE gather_scatter
 USE geometry; USE new_library; IMPLICIT NONE
! neq,ntot are now global variables - not declared
 INTEGER, PARAMETER::ndim=3,nodof=1,nprops=5
 INTEGER::nod,nn,nr,nip,i,j,k,l,iters,limit,iel,nstep,npri,nres,it,is,   &
   nlen,node_end,node_start,nodes_pp,loaded_freedoms,fixed_freedoms,     &
   loaded_nodes,fixed_freedoms_pp,fixed_freedoms_start,                  &
   loaded_freedoms_pp,loaded_freedoms_start,nels,ndof,ielpe,npes_pp,     &
   meshgen,partitioner,np_types,prog,tz
 REAL(iwp)::kx,ky,kz,det,theta,dtim,real_time,tol,alpha,beta,up,big,q,   &
   rho,cp,val0
 REAL(iwp),PARAMETER::zero=0.0_iwp,penalty=1.e20_iwp,t0=0.0_iwp
 CHARACTER(LEN=15)::element; CHARACTER(LEN=50)::argv,fname
 LOGICAL::converged=.false.
 REAL(iwp),ALLOCATABLE::loads_pp(:),u_pp(:),p_pp(:),points(:,:),kay(:,:),&
   coord(:,:),fun(:),jac(:,:),der(:,:),deriv(:,:),weights(:),d_pp(:),    &
   kc(:,:),pm(:,:),funny(:,:),p_g_co_pp(:,:,:),storka_pp(:,:,:),         &
   storkb_pp(:,:,:),x_pp(:),xnew_pp(:),pmul_pp(:,:),utemp_pp(:,:),       &
   diag_precon_pp(:),diag_precon_tmp(:,:),g_coord_pp(:,:,:),timest(:),   &
   disp_pp(:),eld_pp(:,:),val(:,:),val_f(:),store_pp(:),r_pp(:),         &
   kcx(:,:),kcy(:,:),kcz(:,:),eld(:),col(:,:),row(:,:),storkc_pp(:,:,:), &
   prop(:,:)
 INTEGER,ALLOCATABLE::rest(:,:),g(:),num(:),g_num_pp(:,:),g_g_pp(:,:),   &
   no(:),no_pp(:),no_f_pp(:),no_pp_temp(:),sense(:),node(:),etype_pp(:)
!--------------------------input and initialisation-----------------------
 ALLOCATE(timest(20)); timest=zero; timest(1)=elap_time()
 CALL find_pe_procs(numpe,npes); CALL getname(argv,nlen)
 CALL read_p124(argv,numpe,dtim,element,fixed_freedoms,limit,            &
   loaded_nodes,meshgen,nels,nip,nn,nod,npri,nr,nstep,partitioner,theta, &
   tol,np_types,val0)
 CALL calc_nels_pp(argv,nels,npes,numpe,partitioner,nels_pp)
 ndof=nod*nodof; ntot=ndof
 ALLOCATE(g_num_pp(nod,nels_pp),g_coord_pp(nod,ndim,nels_pp),            &
   etype_pp(nels_pp),prop(nprops,np_types)) 
 g_num_pp=0; g_coord_pp=zero; etype_pp=0; prop=zero
 IF (nr>0) THEN; ALLOCATE(rest(nr,nodof+1)); rest=0; END IF
 CALL read_elements(argv,iel_start,nn,npes,numpe,etype_pp,g_num_pp)
 IF(meshgen==2) CALL abaqus2sg(element,g_num_pp)
 CALL read_g_coord_pp(job_name,g_num_pp,nn,npes,numpe,g_coord_pp)
 IF (nr>0) CALL read_rest(job_name,numpe,rest)
 fname=argv(1:INDEX(job_name, " ")-1) // ".mat"  
 CALL read_materialValue(prop,fname,numpe,npes)
 ALLOCATE (points(nip,ndim),weights(nip),kay(ndim,ndim),coord(nod,ndim), &
   fun(nod),jac(ndim,ndim),der(ndim,nod),g(ntot),deriv(ndim,nod),        &
   pm(ntot,ntot),kc(ntot,ntot),funny(1,nod),num(nod),                    &
   g_g_pp(ntot,nels_pp),storka_pp(ntot,ntot,nels_pp),                    &
   utemp_pp(ntot,nels_pp),storkb_pp(ntot,ntot,nels_pp),                  &
   pmul_pp(ntot,nels_pp),(kcx(ntot,ntot),kcy(ntot,ntot),kcz(ntot,ntot),  &                     &
   eld(ntot),col(ntot,1),row(1,ntot),storkc_pp(ntot,ntot,nels_pp))
!----------  find the steering array and equations per process -----------
 timest(2)=elap_time()
 g_g_pp=0; neq=0
 IF(nr>0) THEN; CALL rearrange_2(rest)
   elements_1: DO iel = 1, nels_pp
     CALL find_g4(g_num_pp(:,iel),g_g_pp(:,iel),rest)
   END DO elements_1
 ELSE
   g_g_pp=g_num_pp  !When nr = 0, g_num_pp and g_g_pp are identical
 END IF
 neq=MAXVAL(g_g_pp); neq=max_p(neq); CALL calc_neq_pp
 CALL calc_npes_pp(npes,npes_pp); CALL make_ggl(npes_pp,npes,g_g_pp)
 DO i=1,neq_pp;IF(nres==ieq_start+i-1)THEN;it=numpe;is=i;END IF;END DO
 IF(numpe==it)THEN
   OPEN(11,FILE=argv(1:nlen)//'.res',STATUS='REPLACE',ACTION='WRITE') 
   WRITE(11,'(A,I5,A)')"This job ran on ", npes,"  processes"
   WRITE(11,'(A,3(I7,A))')"There are ",nn," nodes",nr,                   &
     " restrained and   ",neq," equations"
   WRITE(11,'(A,F10.4)')"Time after setup is ",elap_time()-timest(1)
 END IF
 ALLOCATE(loads_pp(neq_pp),diag_precon_pp(neq_pp),u_pp(neq_pp),          &
   d_pp(neq_pp),p_pp(neq_pp),x_pp(neq_pp),xnew_pp(neq_pp),r_pp(neq_pp))
 loads_pp=zero; diag_precon_pp=zero; u_pp=zero; r_pp=zero; d_pp=zero
 p_pp=zero; x_pp=zero; xnew_pp=zero
!-------------- element stiffness integration and storage ----------------
 CALL sample(element,points,weights); storka_pp=zero; storkb_pp=zero
 elements_3: DO iel=1,nels_pp
   kay=zero; kc=zero; pm=zero; kay(1,1)=prop(1,etype_pp(iel))                       
   kay(2,2)=prop(2,etype_pp(iel)); kay(3,3)=prop(3,etype_pp(iel)) 
   rho=prop(4,etype_pp(iel)); cp=prop(5,etype_pp(iel))
   gauss_pts: DO i=1,nip
     CALL shape_der(der,points,i); CALL shape_fun(fun,points,i)
     funny(1,:)=fun(:); jac=MATMUL(der,g_coord_pp(:,:,iel))
     det=determinant(jac); CALL invert(jac); deriv=MATMUL(jac,der)
     kc=kc+MATMUL(MATMUL(TRANSPOSE(deriv),kay),deriv)*det*weights(i)
     pm=pm+MATMUL(TRANSPOSE(funny),funny)*det*weights(i)*rho*cp
   END DO gauss_pts
   storka_pp(:,:,iel)=pm+kc*theta*dtim
   storkb_pp(:,:,iel)=pm-kc*(1._iwp-theta)*dtim
 END DO elements_3
!------------------ build the diagonal preconditioner --------------------
 ALLOCATE(diag_precon_tmp(ntot,nels_pp)); diag_precon_tmp = zero
 elements_4: DO iel = 1,nels_pp 
   DO k=1,ntot
     diag_precon_tmp(k,iel)=diag_precon_tmp(k,iel)+storka_pp(k,k,iel)
   END DO
 END DO elements_4; CALL scatter(diag_precon_pp,diag_precon_tmp)
 DEALLOCATE(diag_precon_tmp)  
!------------- read in fixed freedoms and assign to equations ------------
 IF(fixed_freedoms > 0) THEN
   ALLOCATE(node(fixed_freedoms),no(fixed_freedoms),                         &
     no_pp_temp(fixed_freedoms),sense(fixed_freedoms),                  &
     val_f(fixed_freedoms))
   node=0; no=0; no_pp_temp=0; sense=0; val_f = zero
   CALL read_fixed(job_name,numpe,node,sense,val_f)
   CALL find_no2(g_g_pp,g_num_pp,node,sense,no)
   CALL reindex(ieq_start,no,no_pp_temp,fixed_freedoms_pp,              &
     fixed_freedoms_start,neq_pp)
   ALLOCATE(no_f_pp(fixed_freedoms_pp),store_pp(fixed_freedoms_pp))
   no_f_pp=0; store_pp=zero; no_f_pp=no_pp_temp(1:fixed_freedoms_pp)
   DEALLOCATE(node,no,sense,no_pp_temp)
 END IF
 IF(fixed_freedoms == 0) fixed_freedoms_pp = 0
!-------------------------- invert preconditioner ------------------------
 IF(fixed_freedoms_pp > 0) THEN
   DO i=1,fixed_freedoms_pp
     l=no_f_pp(i)-ieq_start+1
     diag_precon_pp(l)=diag_precon_pp(l)+penalty
     store_pp(i)=diag_precon_pp(l)
   END DO
 END IF
 diag_precon_pp=1._iwp/diag_precon_pp
!--------------- read in loaded nodes and get starting r_pp --------------
 loaded_freedoms=loaded_nodes ! hack
   IF(loaded_freedoms>0) THEN
     ALLOCATE(node(loaded_freedoms),val(nodof,loaded_freedoms)           &
       no_pp_temp(loaded_freedoms)); val=zero; node=0; no_pp_temp=0
     CALL read_loads(job_name,numpe,node,val)
     CALL reindex(ieq_start,node,no_pp_temp,loaded_freedoms_pp,          &
       loaded_freedoms_start,neq_pp); ALLOCATE(no_pp(loaded_freedoms_pp))
     no_pp=0; no_pp=no_pp_temp(1:loaded_freedoms_pp)
     DEALLOCATE(no_pp_temp,node)
    END IF
!------------------------- start time stepping loop ----------------------
 CALL calc_nodes_pp(nn,npes,numpe,node_end,node_start,nodes_pp)
 ALLOCATE(ttr_pp(nodes_pp),(eld_pp(ntot,nels_pp))
 ttr_pp=zero; eld_pp=zero
 IF(numpe==it) THEN
   WRITE(11,'(A)') " Time  Temperature Iterations "

! IF(numpe==1) THEN
!   fname   = job_name(1:INDEX(job_name, " ")-1)//".ttr"
!   OPEN(24, file=fname, status='replace', action='write')
!   fname   = job_name(1:INDEX(job_name, " ")-1)//".ttrb"
!   OPEN(25, file=fname, status='replace', action='write',                    &
!        access='sequential', form='unformatted')
!   fname   = job_name(1:INDEX(job_name, " ")-1)//".npp"
!   OPEN(26, file=fname, status='replace', action='write')
!   label   = "*TEMPERATURE"  
!   WRITE(26,*) nn
!   WRITE(26,*) nstep/npri
!   WRITE(26,*) npes
! END IF

 timesteps: DO j=1,nstep
    real_time=j*dtim
!---- apply loads (sources and/or sinks) supplied as a boundary value ----
    loads_pp=zero
    DO i = 1, loaded_freedoms_pp
      loads_pp(no_pp(i)-ieq_start+1)=val(loaded_freedoms_start+i-1,1)*dtim
    END DO;  q=q+SUM_P(loads_pp)
!- compute RHS of time stepping equation, using storkb_pp, add to loads --
    u_pp=zero; pmul_pp=zero; utemp_pp=zero
    IF(j/=1) THEN
      CALL gather(xnew_pp,pmul_pp)
      elements_2a: DO iel=1,nels_pp
        utemp_pp(:,iel)=MATMUL(storkb_pp(:,:,iel),pmul_pp(:,iel))
      END DO elements_2a; CALL scatter(u_pp,utemp_pp)
      IF(fixed_freedoms_pp>0) THEN
        DO i=1,fixed_freedoms_pp
          l=no_f_pp(i)-ieq_start+1; k=fixed_freedoms_start+i-1
          u_pp(l)=store_pp(i)*val_f(k)
        END DO
      END IF; loads_pp = loads_pp+u_pp
    ELSE
!------------------------ set initial temperature ------------------------
      x_pp=val0
      IF(fixed_freedoms_pp>0) THEN
        DO i=1,fixed_freedoms_pp; l=no_f_pp(i)-ieq_start+1
          k=fixed_freedoms_start+i-1; x_pp(l)=val_f(k)
        END DO
      END IF
      CALL gather(x_pp,pmul_pp)
      elements_2c: DO iel=1,nels_pp
        utemp_pp(:,iel)=MATMUL(storka_pp(:,:,iel),pmul_pp(:,iel))
      END DO elements_2c; CALL scatter(u_pp,utemp_pp)
      loads_pp=loads_pp+u_pp
!----------------------- output "results" at t=0 -------------------------
      tz=0
      IF(numpe==1)THEN; WRITE(ch,'(I6.6)') tz
        OPEN(12,file=argv(1:nlen)//".ensi.NDPTL-"//ch,status='replace',       &
          action='write')
        WRITE(12,'(A)')                                                  &
          "Alya Ensight Gold --- Scalar per-node variable file"
        WRITE(12,'(A/A/A)') "part", "    1","coordinates"
      END IF
      eld_pp=zero; disp_pp=zero; CALL gather(x_pp(1:),eld_pp)
      CALL scatter_nodes(npes,nn,nels_pp,g_num_pp,nod,nodof,nodes_pp,         &
        node_start,node_end,eld_pp,ttr_pp,1)
      CALL dismsh_ensi_p(12,1,nodes_pp,npes,numpe,1,ttr_pp)
!     CALL write_nodal_variable_binary(label,25,tz,nodes_pp,npes,numpe,nodof, &
!       ttr_pp)
    END IF
!----- when x=0. p and r are just loads but in general p=r=loads-A*x ----------  
    r_pp=zero; pmul_pp=zero; utemp_pp=zero; x_pp=zero
    CALL gather(x_pp,pmul_pp)
    elements_2b: DO iel=1,nels_pp
      utemp_pp(:,iel)=MATMUL(storka_pp(:,:,iel),pmul_pp(:,iel))
    END DO elements_2b; CALL scatter(r_pp,utemp_pp)
    IF(fixed_freedoms_pp>0) THEN
      DO i=1,fixed_freedoms_pp; l=no_f_pp(i)-ieq_start+1
        k=fixed_freedoms_start+i-1; r_pp(l)=store_pp(i)*val_f(k)
      END DO
    END IF
    r_pp=loads_pp-r_pp; d_pp=diag_precon_pp*r_pp; p_pp=d_pp
!---------------- solve simultaneous equations by pcg --------------------
    iters=0
    iterations: DO
      iters=iters+1; u_pp=zero; pmul_pp=zero; utemp_pp=zero
      CALL gather(p_pp,pmul_pp)
      elements_6: DO iel=1,nels_pp
        utemp_pp(:,iel)=MATMUL(storka_pp(:,:,iel),pmul_pp(:,iel))
      END DO elements_6; CALL scatter(u_pp,utemp_pp)
      IF(fixed_freedoms_pp>0) THEN; DO i=1,fixed_freedoms_pp
          l=no_f_pp(i)-ieq_start+1; u_pp(l)=p_pp(l)*store_pp(i)
      END DO; END IF
      up=DOT_PRODUCT_P(r_pp,d_pp); alpha=up/DOT_PRODUCT_P(p_pp,u_pp)
      xnew_pp=x_pp+p_pp*alpha; r_pp=r_pp-u_pp*alpha
      d_pp=diag_precon_pp*r_pp; beta=DOT_PRODUCT_P(r_pp,d_pp)/up
      p_pp=d_pp+p_pp*beta
      CALL checon_par(xnew_pp,tol,converged,x_pp)
      IF(converged.OR.iters==limit)EXIT
    END DO iterations
    IF(j/npri*npri==j)THEN
      IF(numpe==1)THEN; WRITE(ch,'(I6.6)') numpe
        OPEN(12,file=argv(1:nlen)//".ensi.NDTTR-"//ch,status='replace',       &
          action='write')
        WRITE(12,'(A)')                                                  &
          "Alya Ensight Gold --- Scalar per-node variable file"
        WRITE(12,'(A/A/A)') "part", "    1","coordinates"
      END IF; eld_pp=zero; ttr_pp=zero; CALL gather(xnew_pp(1:),eld_pp)
      CALL scatter_nodes(npes,nn,nels_pp,g_num_pp,nod,nodof,nodes_pp,    &
        node_start,node_end,eld_pp,ttr_pp,1)
      CALL dismsh_ensi_p(12,1,nodes_pp,npes,numpe,1,ptl_pp)
      IF(numpe==1) CLOSE(12)
!     CALL write_nodal_variable_binary(label,25,j,nodes_pp,npes,numpe,   &
!       nodof,ttr_pp)
      IF(numpe==it) WRITE(11,'(2E12.4,I5)') real_time, xnew_pp(is), iters
    END IF
  END DO timesteps
  IF(numpe==it) THEN
    WRITE(11,'(A,F10.4)' "This analysis took ",elap_time()-timest(1)
    CLOSE(11)
  END IF
  CALL shutdown()
END PROGRAM p124
