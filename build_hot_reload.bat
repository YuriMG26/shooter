@echo off

odin build . -show-timings -use-separate-modules -define:RAYLIB_SHARED=true -build-mode:dll -out:game.dll -debug

set EXE=shooter_game.exe
FOR /F %%x IN ('tasklist /NH /FI "IMAGENAME eq %EXE%"') DO IF %%x == %EXE% exit /b 1

odin build main_hot_reload -use-separate-modules -out:shooter_game.exe -debug
