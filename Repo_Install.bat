@echo off
setlocal enabledelayedexpansion

set "RepositoryRoot=%~1"

if "%RepositoryRoot%"=="" (
    set /p "RepositoryRoot=Please enter the Repository Root folder path: "
)

if not defined RepositoryRoot (
    echo No valid repository root was provided.
    exit /b 1
)

if not exist "%RepositoryRoot%\" (
    echo "%RepositoryRoot%" does not exist. Please create it and restart Repo_Install.bat.
    exit /b 1
)

echo.
echo Installing File Repository Service in: "%RepositoryRoot%"
pause

set "TASK_NAME=FileRepositoryService"
set "SCRIPT_PATH=%RepositoryRoot%\FileServerApp.py"
set "WORK_DIR=%RepositoryRoot%"

echo [1/3] Checking for Python installation...

call :FIND_PYTHON
if defined PYTHON_EXE goto :PYTHON_FOUND

echo Python was not found on this system.
echo [2/3] Installing Python automatically...

where winget >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Installing Python via winget...
    winget install --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements
    if errorlevel 1 (
        echo Winget Python installation failed.
        pause
        exit /b 1
    )
    refreshenv >nul 2>nul
) else (
    echo Downloading Python installer...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.11.8/python-3.11.8-amd64.exe' -OutFile '%TEMP%\python_installer.exe'"
    if not exist "%TEMP%\python_installer.exe" (
        echo ERROR: Failed to download Python installer.
        pause
        exit /b 1
    )

    echo Running silent Python installation...
    "%TEMP%\python_installer.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1
    if errorlevel 1 (
        echo ERROR: Python installation failed.
        del "%TEMP%\python_installer.exe" 2>nul
        pause
        exit /b 1
    )
    del "%TEMP%\python_installer.exe" 2>nul
)

call :FIND_PYTHON
if defined PYTHON_EXE goto :PYTHON_FOUND

echo ERROR: Automatic Python installation failed. Please install Python manually.
pause
exit /b 1

:PYTHON_FOUND
echo Python found at: "%PYTHON_EXE%"

"%PYTHON_EXE%" -m pip --version >nul 2>nul
if errorlevel 1 (
    echo Python pip was not found. Attempting to enable pip...
    "%PYTHON_EXE%" -m ensurepip --upgrade
    if errorlevel 1 (
        echo ERROR: Could not enable pip for the selected Python interpreter.
        pause
        exit /b 1
    )
)

echo Installing Flask for the selected Python interpreter...
"%PYTHON_EXE%" -m pip install Flask
if errorlevel 1 (
    echo ERROR: Flask installation failed.
    pause
    exit /b 1
)

"%PYTHON_EXE%" -c "import flask" >nul 2>nul
if errorlevel 1 (
    echo ERROR: Flask could not be imported by the selected Python interpreter.
    pause
    exit /b 1
)

copy /Y ".\FileServerApp.py" "%RepositoryRoot%\" >nul
copy /Y ".\index.html" "%RepositoryRoot%\" >nul
copy /Y ".\uninstall.bat" "%RepositoryRoot%\" >nul

mkdir "%RepositoryRoot%\shared_files" >nul
copy /Y ".\favicon.png" "%RepositoryRoot%\shared_files" >nul

set "TASK_WRAPPER=%RepositoryRoot%\Run_FileRepository.cmd"
> "%TASK_WRAPPER%" (
    echo @echo off
    echo cd /d "%WORK_DIR%"
    echo "%PYTHON_EXE%" "%SCRIPT_PATH%"
)

echo [3/3] Creating Scheduled Task '%TASK_NAME%'...

schtasks /Create ^
    /TN "%TASK_NAME%" ^
    /TR "\"%TASK_WRAPPER%\"" ^
    /SC ONLOGON ^
    /F

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Task successfully created!
    echo Script will launch using "%PYTHON_EXE%" at user login.

    set "local_ip="
    for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
        set "local_ip=%%a"
    )

    if defined local_ip (
        set "local_ip=!local_ip:~1!"
        set "local_ip=!local_ip: =!"
    )

    echo ===============================================================================
    if defined local_ip (
        echo Your Local IP Address is: !local_ip!
        echo To access your File Repository Service, point your browser to http://!local_ip!:5000
    ) else (
        echo No IPv4 address was found. Check the network connection and run ipconfig.
    )
    echo You may have to check if port 5000 is open in your firewall.
    echo ===============================================================================
) else (
    echo.
    echo Failed to create scheduled task. Please right-click this script and select "Run as administrator".
)

pause
exit /b 0

:FIND_PYTHON
set "PYTHON_EXE="

rem Ignore Windows 11 App Execution Alias stubs and accept only interpreters that run.
for /f "delims=" %%i in ('where python 2^>nul') do (
    echo(%%i| findstr /i /c:"\WindowsApps\" >nul
    if errorlevel 1 (
        "%%i" -c "import sys" >nul 2>nul
        if not errorlevel 1 (
            set "PYTHON_EXE=%%i"
            goto :eof
        )
    )
)

rem The Python Launcher can find installations that were not added to this process's PATH.
for /f "delims=" %%i in ('py -3 -c "import sys; print(sys.executable)" 2^>nul') do (
    set "PYTHON_EXE=%%i"
    goto :eof
)

for %%i in ("C:\Python310\python.exe" "C:\Python311\python.exe" "C:\Program Files\Python311\python.exe") do (
    if exist "%%~i" (
        "%%~i" -c "import sys" >nul 2>nul
        if not errorlevel 1 (
            set "PYTHON_EXE=%%~i"
            goto :eof
        )
    )
)
exit /b 0
