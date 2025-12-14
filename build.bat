@echo off
echo ========================================
echo   Compile STAR-CAR...
echo ========================================
echo.

wla-z80 -o star-car.asm star-car.o
if errorlevel 1 goto error

wlalink -drvs linkfile star-car.sms
if errorlevel 1 goto error

echo.
echo ========================================
echo   ROM create: star-car.sms
echo ========================================
goto end

:error
echo.
echo ========================================
echo   ERROR compilation!
echo ========================================

:end
pause
