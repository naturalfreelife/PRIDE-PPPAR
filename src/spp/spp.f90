
! Main function entry -------------------------------------------------------
program spp
implicit none
include 'file_para.h'
integer*4 argc, i
character(1024), pointer :: argv(:)
argc=iargc()
allocate(argv(argc))
do i=1,argc
    call getarg(i,argv(i))
enddo
call rnx2rtkp(argc,argv)
deallocate(argv)
end program spp

! rnx2rtkp ------------------------------------------------------------------
subroutine rnx2rtkp(argcIn, argvIn)
implicit none
include 'file_para.h'
integer*4, intent(in) :: argcIn
character(*), intent(in) :: argvIn(argcIn)  !argvIn(:)
type(prcopt_t) prcopt
type(solopt_t) solopt
type(gtime_t) ts, te, tc, epoch2time  ! current time
real*8 :: tint, es(6), ee(6), timediff
integer*4 :: i, n, ret
integer*4 :: irnxo, irnxn
integer*4 :: nrnxo, nrnxn
character(1024) :: infile(MAXFILE),outfile, buff(6), flntmp, flntmp2
character(1024) :: rnxobslist(flnumlim),rnxnavlist(flnumlim), obsdir, navdir
integer*4 argc, info, nsize, getrnxtyp, postpos, flexist  ! flnumlim
character(1024), pointer :: argv(:)
logical*1 :: isexceed, isnext, IsDayRight, IsTimeRight
external :: epoch2time, getrnxtyp, postpos, flexist, timediff, IsDayRight, IsTimeRight
integer*4 :: mjd_s, ymd2mjd
real*8 :: sod
call InitGlobal()

prcopt=prcopt_default; solopt=solopt_default
ts=gtime_t(0,0.d0); te=gtime_t(0,0.d0); tc=gtime_t(0,0.d0)
tint=0.d0; es=(/2000,1,1,0,0,0/); ee=(/2000,12,31,23,59,59/)
i=0; n=0; ret=0;  ! flnumlim=200
infile=''; outfile=''; flntmp=""; flntmp2=""
rnxobslist=""; rnxnavlist=""; obsdir=""; navdir=""

argc=argcIn
allocate(argv(argc))
argv(1:argc)=argvIn(1:argc)
!write(unit=6,fmt="('argc =',I2)") argc
!do i=1,argc
!    write(unit=6,fmt="(I2,' ',A)") i, argv(i)
!enddo
!print*

if(argc==0)then
    call printhelp(); call exit(0)
endif

do i=1,argc
    if(argv(i)=='-?'.or.argv(i)=='-h')then
        call printhelp(); call exit(0)
    endif
enddo

n=0; i=1
do while(i<=argc)
    if(argv(i)=='-o'.and.(i+1)<=argc)then
        outfile=argv(i+1); i=i+1
    elseif(argv(i)=='-ts'.and.(i+2)<=argc)then
        call string_split(argv(i+1),'/',buff(1:3),3)
        call string_split(argv(i+2),':',buff(4:6),3)
        read(buff(1:3),*,iostat=info) es(1),es(2),es(3)
        mjd_s=ymd2mjd(int(es(1:3)))
        if(mjd_s<=51666) prcopt%lsa=.true.
        read(buff(4:6),*,iostat=info) es(4),es(5),es(6); i=i+2
        if(.not.IsDayRight (int(es(1)),int(es(2)),int(es(3)))) call exit(3)
        if(.not.IsTimeRight(int(es(4)),int(es(5)),es(6))) call exit(3)
        ts=epoch2time(es)
    elseif(argv(i)=='-te'.and.(i+2)<=argc)then
        call string_split(argv(i+1),'/',buff(1:3),3)
        call string_split(argv(i+2),':',buff(4:6),3)
        read(buff(1:3),*,iostat=info) ee(1),ee(2),ee(3)
        read(buff(4:6),*,iostat=info) ee(4),ee(5),ee(6); i=i+2
        if(.not.IsDayRight (int(ee(1)),int(ee(2)),int(ee(3)))) call exit(3)
        if(.not.IsTimeRight(int(ee(4)),int(ee(5)),ee(6))) call exit(3)
        te=epoch2time(ee)
    elseif(argv(i)=='-ti'.and.(i+1)<=argc)then
        read(argv(i+1),*,iostat=info) tint; i=i+1
    elseif(argv(i)=='-k'.and.(i+1)<=argc)then
        i=i+2; cycle
!   elseif(argv(i)=='-s')then
!       solopt%issingle=1
    elseif(argv(i)=='-trop'.and.(i+1)<=argc)then
        if(argv(i+1)=='non')  prcopt%tropopt=0
        if(argv(i+1)=='saas') prcopt%tropopt=1
        i=i+1
    elseif(argv(i)=='-c'.and.(i+1)<=argc)then
        clkfile_=argv(i+1); i=i+1
    elseif(argv(i)=='-elev'.and.(i+1)<=argc)then
        read(argv(i+1),*,iostat=info) prcopt%elmin
        prcopt%elmin=prcopt%elmin*D2R; i=i+1
    elseif(n<MAXFILE)then
        n=n+1; infile(n)=argv(i)
    endif
    i=i+1
enddo
deallocate(argv);

if(n/=2)then  ! custom execution format
    if(n<=0) write(*,*) 'error : no input file'
    call exit(2)
endif

do i=1,2
    call getfname(infile(i),flntmp)
    info=getrnxtyp(flntmp)
    if(info==1 .or. info==3) rnxnavlist(1)=infile(i)  ! assuming the time is consistent
    if(info==2 .or. info==4) rnxobslist(1)=infile(i)
enddo

isnext=.true.
if (.not. isnext .or. (rnxobslist(1) .eq. "" .and. rnxnavlist(1) .eq. "")) then
    ret=postpos(ts,te,tint,0.d0,prcopt,solopt,infile,n,outfile,'','')  ! 0-error, 1-right
    call printresult(solopt,ret)  ! print the final result
else
    ! get rnx_obs_list
    if (rnxobslist(1) .ne. "") then
        nrnxo = 1
        call getfdir(rnxobslist(1),obsdir)
        call getfname(rnxobslist(1),flntmp)
        do i=1,flnumlim-1
            call getrnx_nname(flntmp,flntmp2,i)
            if(flexist(trim(obsdir)//flntmp2)==1)then
                rnxobslist(i+1)=trim(obsdir)//flntmp2
                nrnxo = nrnxo + 1
            else
                exit
            endif
        enddo
        if (rnxnavlist(1) .eq. "") then
            nrnxn = 1
            if (rnxobslist(1) .eq. infile(1)) rnxnavlist(1) = infile(2)
            if (rnxobslist(1) .eq. infile(2)) rnxnavlist(1) = infile(1)
        endif
    endif
    ! get rnx_nav_list
    if (rnxnavlist(1) .ne. "") then
        nrnxn = 1
        call getfdir(rnxnavlist(1),navdir)
        call getfname(rnxnavlist(1),flntmp)
        do i=1,flnumlim-1
            call getrnx_nname(flntmp,flntmp2,i)
            if(flexist(trim(navdir)//flntmp2)==1)then
                rnxnavlist(i+1)=trim(navdir)//flntmp2
                nrnxn = nrnxn + 1
            else
                exit
            endif
        enddo
        if (rnxobslist(1) .eq. "") then
            nrnxo = 1
            if (rnxnavlist(1) .eq. infile(1)) rnxobslist(1) = infile(2)
            if (rnxnavlist(1) .eq. infile(2)) rnxobslist(1) = infile(1)
        endif
    endif
    ! cycle calculation
    irnxo = 0
    irnxn = 0
    do i=1,flnumlim
        ! compare time
        isexceed=.false.; tc=gtime_t(0,0.d0)
        if(solindex_>0) tc=allsol_(solindex_)%time
        if(timediff(te,gtime_t(0,0.d0))>0.0 .and. dabs(timediff(tc,te))<=60.0) isexceed=.true.
        if (i .gt. nrnxo .and. i .gt. nrnxn) isexceed=.true.
        if (nrnxo .gt. 1) then
            irnxo = irnxo + 1
        else
            irnxo = 1
        endif
        if (nrnxn .gt. 1) then
            irnxn = irnxn + 1
        else
            irnxn = 1
        endif
        infile(1)=rnxobslist(irnxo)
        infile(2)=rnxnavlist(irnxn)
        if(infile(1) .eq. "" .or. infile(2) .eq. "" .or. isexceed) exit
        ret=postpos(ts,te,tint,0.d0,prcopt,solopt,infile,n,outfile,'','')  ! 0-error, 1-right
        if(ret==0) exit
    enddo
    ! print the final result
    call printresult(solopt,ret)
endif

if(ret==0)then
    write(unit=6,fmt="(A40)") ''; call exit(1)
endif
if(ret==1) call exit(0)
end subroutine
