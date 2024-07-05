@echo off
odin build main_release -define:RAYLIB_SHARED=false -out:shooter_game.exe -no-bounds-check -o:speed --debug -subsystem:windows
