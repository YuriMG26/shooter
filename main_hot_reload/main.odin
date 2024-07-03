package collision_test

import "core:math"
import rand "core:math/rand"

import "core:dynlib"
import "core:fmt"
import "core:c/libc"
import "core:os"

import rl "vendor:raylib"

GameAPI :: struct
{
  lib: dynlib.Library,
  init_window: proc(), 
  init: proc(),
  update: proc() -> bool,
  memory: proc() -> rawptr,
  memory_size: proc() -> int,
  hot_reloaded: proc(mem: rawptr),
  shutdown: proc(),
  force_reload: proc() -> bool,
  force_restart: proc() -> bool,
  modification_time: os.File_Time,
  api_version: int
}

main :: proc()
{
  game_api_version := 0
  game_api, game_api_ok := load_game_api(game_api_version)

  if !game_api_ok {
    fmt.println("Failed to load Game API")
    return
  }

  game_api_version += 1
  game_api.init_window()
  game_api.init()

  old_game_apis := make([dynamic]GameAPI)

  window_open := true
  for window_open {
    window_open = game_api.update()
    game_dll_mod, game_dll_mod_err := os.last_write_time_by_name("game.dll")
    force_reload := game_api.force_reload()
    force_restart := game_api.force_restart()
    reload := force_reload || force_restart

    if game_dll_mod_err == os.ERROR_NONE && game_api.modification_time != game_dll_mod {
      reload = true
    }

    if reload {
      new_game_api, new_game_api_ok := load_game_api(game_api_version)

      if new_game_api_ok {
        if game_api.memory_size() != new_game_api.memory_size() || force_restart {
          // handle restart
          game_api.shutdown()
          for &g in old_game_apis do unload_game_api(&g)
          clear(&old_game_apis)
          unload_game_api(&game_api)
          game_api = new_game_api
          game_api.init()
        }
        else {
          append(&old_game_apis, game_api)
          game_memory := game_api.memory()
          game_api = new_game_api
          game_api.hot_reloaded(game_memory)
        }

        game_api_version += 1
      }
    }
  }

  for &g in old_game_apis do unload_game_api(&g)
  unload_game_api(&game_api)
  delete(old_game_apis)
}

load_game_api :: proc(api_version: int) -> (api: GameAPI, ok: bool)
{
  mod_time, mod_time_error := os.last_write_time_by_name("game.dll")
  if mod_time_error != os.ERROR_NONE {
    fmt.printfln("Faield getting last write time of game.dll, error code: {1}", mod_time_error)
    return
  }

  game_dll_name := fmt.tprintf("game_{0}.dll", api_version)

  if libc.system(fmt.ctprintf("copy game.dll {0}", game_dll_name)) != 0 {
    fmt.println("Failed to copy game.dll to {0}", game_dll_name)
    return
  }

  _, ok = dynlib.initialize_symbols(&api, game_dll_name, "game_", "lib")
  if !ok {
    fmt.printfln("Failed initializing symbols {0}", dynlib.last_error())
    return {}, false
  }

  api.api_version = api_version
  api.modification_time = mod_time
  ok = true

  return
}

unload_game_api :: proc(api: ^GameAPI)
{
  if api.lib != nil {
    dynlib.unload_library(api.lib)
  }

  if libc.system(fmt.ctprintf("del game_{0}.dll", api.api_version)) != 0 {
    fmt.println("Failed to remove game_{0}.dll copy", api.api_version)
  }
}
