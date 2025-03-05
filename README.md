# "Ashes With No Nation" source code (Temporary name)
This game is being developed using the [Odin Programming Language](https://odin-lang.org/) and [Raylib](https://github.com/raysan5/raylib/), a game programming library developed in C.
The goal is a fast-paced top-down shooter game reminiscent of [Hotline Miami](https://store.steampowered.com/app/219150/Hotline_Miami/), with an impactful story and compelling characters.
## Disclaimer:
The game is **by now** contained to a single .odin file called "game.odin". Better code architecture **will** be employed soon, but in a fast iterative step of development (trying to find the footing in the basic gameplay systems), this actually is helpful.
## Features implemented so far:
- [x] Hot-reloading: while the game is running, we can recompile the source code as a dynamic library (dll on Windows) and it is automatically loaded by the executable. This way, gameplay loops can be tweaked much easier and results in a generally more pleasant programming experience.
- [x] Different types of guns:
  - [x] Semi-auto pistols with customizable cooldowns and rate of fire.
  - [x] Shotguns with random tweakable bullet spread.
  - [x] Automatic weapons with customizable bullet speed and rate of fire.
- [x] Basic collision: we have rudimentary circle-aabb collision resolution with normal/depth calculations, such as found in the [Real-Time Collision Detection](https://realtimecollisiondetection.net/) book.
- [x] Very simple state-machine AI, with raycasting for wall occlusion.

## Features to be implemented:
- [ ] Basic pathfinding for enemies
- [ ] Better space division for efficient collision checking
- [ ] Sprite-based animation system
- [ ] Sound effects
