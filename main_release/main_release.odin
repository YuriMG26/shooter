package main_release

import game ".."

main :: proc()
{
  game.game_init_window()
  game.game_init()
  window_open := true
  for window_open {
    window_open = game.game_update()
  }

  game.game_shutdown()
}
