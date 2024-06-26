MODULE mode_unwrap
!
!**********************************************************************************
!*  MODE_UNWRAP                                                                   *
!**********************************************************************************
!* This module reads two files, a "reference" and a "configuration",              *
!* and attempts to unwrap the atoms in the "configuration".                       *
!* Whether an atom must be "unwrapped" is decided by the difference of its        *
!* position between the "reference" and the "configuration": displacements        *
!* vector that are not between -0.5 and +0.5 the size of the box are shifted      *
!* until they end up in that limit. Finally the unwrapped coordinates of the      *
!* "configuration" are written.                                                   *
!**********************************************************************************
!* (C) Sep. 2011 - Pierre Hirel                                                   *
!*     Université de Lille, Sciences et Technologies                              *
!*     UMR CNRS 8207, UMET - C6, F-59655 Villeneuve D'Ascq, France                *
!*     pierre.hirel@univ-lille.fr                                                 *
!* Last modification: P. Hirel - 16 April 2024                                    *
!**********************************************************************************
!* This program is free software: you can redistribute it and/or modify           *
!* it under the terms of the GNU General Public License as published by           *
!* the Free Software Foundation, either version 3 of the License, or              *
!* (at your option) any later version.                                            *
!*                                                                                *
!* This program is distributed in the hope that it will be useful,                *
!* but WITHOUT ANY WARRANTY; without even the implied warranty of                 *
!* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                  *
!* GNU General Public License for more details.                                   *
!*                                                                                *
!* You should have received a copy of the GNU General Public License              *
!* along with this program.  If not, see <http://www.gnu.org/licenses/>.          *
!**********************************************************************************
!
!Load modules
USE comv
USE constants
USE messages
USE files
USE subroutines
!
!Module for reading and writing files
USE readin
USE writeout
!Module for applying options
USE options
!
!
CONTAINS
!
SUBROUTINE UNWRAP_XYZ(filefirst,filesecond,options_array,outputfile,outfileformats)
!
!Declare variables
IMPLICIT NONE
CHARACTER(LEN=*),INTENT(IN):: filefirst, filesecond
CHARACTER(LEN=5),DIMENSION(:),ALLOCATABLE:: outfileformats !list of formats to output
CHARACTER(LEN=128):: msg
CHARACTER(LEN=4096):: outputfile
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE:: AUXNAMES      !names of auxiliary properties
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE:: newAUXNAMES   !names of auxiliary properties
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE:: commentfirst, commentsecond !comments
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE:: options_array !options and their parameters
LOGICAL,DIMENSION(:),ALLOCATABLE:: SELECT  !mask for atom list
INTEGER:: i, j, k
INTEGER:: Nunwrap !number of atoms unwrapped
INTEGER:: coluw   !index of column in AUX containing "unwrapped" property
REAL(dp):: distance
REAL(dp),DIMENSION(3,3):: Huc    !Base vectors of unit cell (unknown, set to 0 here)
REAL(dp),DIMENSION(3,3):: H   !Base vectors of the supercell
REAL(dp),DIMENSION(3,3):: ORIENT  !crystal orientation
REAL(dp),DIMENSION(9,9):: C_tensor  !elastic tensor
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: Pfirst  !positions of "reference"
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: Psecond !positions of "configuration"
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: S       !positions of shells in "configuration"
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: AUX     !auxiliary properties
!
coluw = 0
ORIENT(:,:) = 0.d0
 C_tensor(:,:) = 0.d0
!
!
msg = 'ENTERING UNWRAP_XYZ...'
CALL ATOMSK_MSG(999,(/TRIM(msg)/),(/0.d0/))
!
CALL ATOMSK_MSG(4046,(/TRIM(msg)/),(/0.d0/))
!
!Initialize variables
IF(ALLOCATED(newAUXNAMES)) DEALLOCATE(newAUXNAMES)
IF(ALLOCATED(SELECT)) DEALLOCATE(SELECT)
Nunwrap=0
distance=0.d0
!
!
!
100 CONTINUE
CALL CHECKFILE(filefirst,'read')
CALL CHECKFILE(filesecond,'read')
!
!Read first file
CALL READ_AFF(filefirst,H,Pfirst,S,commentfirst,AUXNAMES,AUX)
IF(nerr>0 .OR. .NOT.ALLOCATED(Pfirst)) GOTO 1000
CALL OPTIONS_AFF(options_array,Huc,H,Pfirst,S,AUXNAMES,AUX,ORIENT,SELECT,C_tensor)
!Ignore S, AUXNAMES, AUX, SELECT from "reference"
IF(ALLOCATED(S)) DEALLOCATE(S)
IF(ALLOCATED(AUX)) DEALLOCATE(AUX)
IF(ALLOCATED(AUXNAMES)) DEALLOCATE(AUXNAMES)
IF(ALLOCATED(SELECT)) DEALLOCATE(SELECT)
IF(nerr>=1) GOTO 1000
!
!Read second file
CALL READ_AFF(filesecond,H,Psecond,S,commentsecond,AUXNAMES,AUX)
IF(nerr>0 .OR. .NOT.ALLOCATED(Psecond)) GOTO 1000
CALL OPTIONS_AFF(options_array,Huc,H,Psecond,S,AUXNAMES,AUX,ORIENT,SELECT,C_tensor)
IF(nerr>=1) GOTO 1000
!
!!Determine if the cell vectors were found or not
IF( VECLENGTH(H(1,:))==0.d0 .OR. VECLENGTH(H(2,:))==0.d0 &
  & .OR. VECLENGTH(H(3,:))==0.d0 ) THEN
  !!If basis vectors H were not found in the input file, then compute them
  ! (this does not work perfectly yet, see determine_H.f90)
  CALL ATOMSK_MSG(4701,(/''/),(/0.d0/))
  !
  CALL DETERMINE_H(H,Pfirst)
  !
ENDIF
!
!If both systems don't have the same size we are in trouble
IF( SIZE(Pfirst,1).NE.SIZE(Psecond,1) ) THEN
  CALL ATOMSK_MSG(4810,(/''/), &
       & (/ DBLE(SIZE(Pfirst(:,1))), DBLE(SIZE(Psecond(:,1))) /))
  nerr = nerr+1
  GOTO 1000
ENDIF
!
!Add new auxiliary property "unwrapped_atom"
IF( ALLOCATED(AUX) ) THEN
  coluw = SIZE(AUX,2) + 1
  CALL RESIZE_DBLEARRAY2(AUX,SIZE(AUX,1),SIZE(AUX,2)+1,i)
  AUX(:,coluw) = 0.d0
  ALLOCATE(newAUXNAMES(SIZE(AUXNAMES)+1))
  newAUXNAMES(1:SIZE(AUXNAMES)) = AUXNAMES(:)
  DEALLOCATE(AUXNAMES)
  ALLOCATE(AUXNAMES(SIZE(newAUXNAMES)))
  AUXNAMES(:) = newAUXNAMES(:)
  DEALLOCATE(newAUXNAMES)
ELSE
  ALLOCATE(AUX(SIZE(Pfirst,1),1))
  AUX(:,:) = 0.d0
  ALLOCATE(AUXNAMES(1))
  coluw = 1
ENDIF
AUXNAMES(coluw) = "unwrapped_atom"
!
!Convert positions to reduced coordinates
CALL CART2FRAC(Pfirst,H)
CALL CART2FRAC(Psecond,H)
!
k=0
DO i=1,SIZE(Pfirst,1)
  DO j=1,3
    distance = Psecond(i,j)-Pfirst(i,j)
    DO WHILE( distance<=-0.5d0 .OR. distance>0.5d0 )
      IF(distance<=-0.5d0) Psecond(i,j) = Psecond(i,j)+1.d0
      IF(distance>0.5d0)  Psecond(i,j) = Psecond(i,j)-1.d0
      distance = Psecond(i,j)-Pfirst(i,j)
      !Count this atom as unwrapped
      IF(k.NE.i) THEN
        k=i
        AUX(i,coluw) = 1.d0
        Nunwrap=Nunwrap+1
      ENDIF
    ENDDO
  ENDDO
ENDDO
!
!
!
200 CONTINUE
!Convert coordinates back to cartesian
CALL FRAC2CART(Pfirst,H)
CALL FRAC2CART(Psecond,H)
!
CALL ATOMSK_MSG(4047,(/""/),(/DBLE(Nunwrap)/))
!
!
!
300 CONTINUE
!If user did not provide output file name, set a default one
IF( LEN_TRIM(outputfile)<=0 ) THEN
  outputfile = filesecond
  i = SCAN(outputfile,".",BACK=.TRUE.)
  IF(i==0) i=LEN_TRIM(outputfile)+1
  outputfile = TRIM(ADJUSTL(outputfile(1:i-1)))//"_unwrap.cfg"
  IF( .NOT.ALLOCATED(outfileformats) .OR. SIZE(outfileformats)<=0 ) THEN
    IF(ALLOCATED(outfileformats)) DEALLOCATE(outfileformats)
    ALLOCATE(outfileformats(1))
    outfileformats(1) = "cfg"
  ENDIF
ENDIF
!Write unwrapped coordinates to output file(s)
CALL WRITE_AFF(outputfile,outfileformats,H,Psecond,S,commentfirst,AUXNAMES,AUX)
!
!
!
1000 CONTINUE
!
!
END SUBROUTINE UNWRAP_XYZ
!
!
END MODULE mode_unwrap
