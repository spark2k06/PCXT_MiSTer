REM FW4-6.BAT
REM Fool Microsoft's Windows 3.x into starting, even though all files are high

REM This batch file is for MS-DOS version 4.x and higher only.  For MS-DOS
REM version 3.x use FW3.BAT

set W1=CON 567890123456789012345678901234567890123456789012345
set W2=CON 567890123456789012345678901234567890123456789012345
set W3=CON 5
win %1 %2 %3 %4 %5 %6 %7 %8 %9
