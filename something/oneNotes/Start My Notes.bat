@echo off
cd /d "%~dp0"
where java >nul 2>nul
if errorlevel 1 goto nojava

if exist "%~dp0MyNotes.jar" (
  where javaw >nul 2>nul
  if not errorlevel 1 (
    start "" javaw -jar "%~dp0MyNotes.jar"
    exit /b
  )
  echo Starting My Notes... keep this window open while you use it.
  java -jar "%~dp0MyNotes.jar"
  pause
  exit /b
)

rem No MyNotes.jar: run straight from NotesApp.java (needs Java 11 or newer)
echo Starting My Notes... keep this window open while you use it.
java NotesApp.java
echo.
echo My Notes stopped. If you see an error above, your Java may be older than version 11.
pause
exit /b

:nojava
echo Java was not found on this computer.
echo Open a Command Prompt and type:  java -version
echo If that fails, ask IT to install Java (version 11 or newer).
pause
