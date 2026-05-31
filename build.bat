@echo off
echo Building Mouse Control binaries...

set COMPILER="C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
set BASE_BIN="C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

if not exist %COMPILER% (
    echo Ahk2Exe not found at %COMPILER%. Please make sure AutoHotkey v2 is installed correctly.
    pause
    exit /b 1
)

if not exist %BASE_BIN% (
    echo Base 64-bit binary not found at %BASE_BIN%.
    pause
    exit /b 1
)

if not exist "dist" (
    mkdir "dist"
)

echo Compiling main executable (mouse_ctrl.exe)...
%COMPILER% /in "src\mouse_ctrl.ahk" /out "dist\mouse_ctrl.exe" /icon "src\mouse_ctrl.ico" /base %BASE_BIN%

echo Compiling worker daemon (myHardwareWorker.exe)...
%COMPILER% /in "src\myHardwareWorker.ahk" /out "dist\myHardwareWorker.exe" /icon "src\mouse_ctrl.ico" /base %BASE_BIN%

echo.
echo Build complete! Both .exe files have been generated in the "dist" directory.
pause