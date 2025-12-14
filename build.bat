@echo off
echo ========================================
echo   Compiling STAR-CAR...
echo ========================================
echo.

wla-z80 -o build\star-car.o src\star-car.asm
if errorlevel 1 goto error

wlalink linkfile build\star-car.sms
if errorlevel 1 goto error

echo.
echo ========================================
echo   ROM created: build\star-car.sms
echo ========================================
echo.
echo File size:
dir build\star-car.sms | find "star-car.sms"
goto end

:error
echo.
echo ========================================
echo   COMPILATION ERROR!
echo ========================================

:end
pause
