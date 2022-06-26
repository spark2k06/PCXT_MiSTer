REM FW3.BAT
REM Fool Microsoft's Windows 3.x into starting, even though all files are high

REM This batch file is for MS-DOS version 3.x only, and is only required
REM for versions higher then 3.31.  For DOS 4.x and DOS 5.x use FW4&5.BAT

set W1=CON 567890123456789012345678901234567890123456789
set W2=CON 567890123456789012345678901234567890123456789
set W3=CON 5
win %1 %2 %3 %4 %5 %6 %7 %8 %9
