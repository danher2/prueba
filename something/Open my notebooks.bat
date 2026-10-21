@echo off
setlocal
cd /d "%~dp0"
set "SRC=%~1"
if "%SRC%"=="" (
  echo.
  echo  OneNote Viewer
  echo  --------------
  echo  Drag your notebooks folder onto this file, or paste its path below.
  echo  Example: C:\Users\you\Documents\OneNote Notebooks
  echo.
  set /p "SRC=Folder with your notebooks: "
)
set "SRC=%SRC:"=%"
if "%SRC%"=="" goto :eof
where py >nul 2>nul && (set "PY=py -3") || (set "PY=python")
%PY% "%~dp0onenote_viewer.py" "%SRC%"
echo.
pause
