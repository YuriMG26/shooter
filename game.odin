package game

import      "core:strconv"
import      "base:intrinsics"
import rl   "vendor:raylib"
import      "core:math"
import rand "core:math/rand"
import      "core:fmt"
import      "core:math/linalg"
import      "core:log"
import      "core:os"

FLAT_GREEN :: rl.Color { 0xAC, 0xFB, 0xC5, 0xFF }

// global constants
player_default_size :: 80
dash_duration       :: 0.1
default_enemy_size  :: 150
default_bullet_size :: 8

GunType :: enum
{
  SemiAuto,
  Burst,
  Auto
}

Gun :: struct
{
  type            : GunType,
  rpm             : int,
  spread          : f64,
  bullet_speed    : f64,

  last_shoot_time : f64,
  next_shoot_time : f64,
}

Bullet :: struct
{
  x, y        : f32,
  direction   : [2]f32,
  time_to_live: f64,
  spawned_in  : f64,
  speed       : f64,
  type        : f64,
}

Enemy :: struct
{
  x, y           : f32,
  starting_health: f32,
  health         : f32,
  speed          : f32,
  starting_speed : f32,
}

Arguments :: struct
{
  width   : int,
  height  : int,
  msaa    : bool,
  fullscreen    : bool,
}

GameMemory :: struct
{
// TODO Default Values
  player_pos                 : [2]f32,
  player_size                : [2]f32,
  player_rotation            : f32,
  player_health              : f32, // default = 100
  player_gun                 : Gun,
  delta_time                 : f32,
  dash_timestamp             : f64,
  dash_cooldown              : f32,
  is_dash_cooldown           : bool, // default = false
  dash_begin_position        : rl.Vector2,
  normalized_player_direction: rl.Vector2,
  player_dash_target         : rl.Vector2,
  player_direction           : rl.Vector2,
  dash_vector                : rl.Vector2,
  screen_width               : f32,
  screen_height              : f32,
  game_camera                : rl.Camera2D,
  mouse_position             : rl.Vector2,
  // camera
  camera_state               : int,
  target_zoom                : f32,

  background                 : rl.Texture,
  
  horizontal_padding         : f32, // 0.4
  vertical_padding           : f32, // 0.3
  scroll_bounds_a            : [2]f32,
  scroll_bounds_b            : [2]f32,
  scroll_bounds              : rl.Rectangle,

  hide_cursor                : bool,
  cursor_texture             : rl.Texture2D,

  bullets                    : [dynamic]Bullet,
  enemies                    : [dynamic]Enemy,
}

g_mem: ^GameMemory

move_player :: proc()
{
  using g_mem
  player_direction = 0
  if is_dash_cooldown {
    dash_cooldown -= rl.GetFrameTime()
    if dash_cooldown <= 0 do is_dash_cooldown = false
    if dash_duration + dash_timestamp > rl.GetTime() {
      player_direction += dash_vector * (rl.GetFrameTime() / dash_duration)
    }
  }

  if rl.IsKeyDown(.W) do player_direction.y -= 600 * delta_time
  if rl.IsKeyDown(.S) do player_direction.y += 600 * delta_time
  if rl.IsKeyDown(.A) do player_direction.x -= 600 * delta_time
  if rl.IsKeyDown(.D) do player_direction.x += 600 * delta_time

  normalized_player_direction = rl.Vector2Normalize(player_direction)

  if !is_dash_cooldown && rl.IsKeyPressed(.SPACE) && normalized_player_direction != rl.Vector2(0) {
    // begin dash state
    player_dash_target = player_pos + normalized_player_direction * 400
    dash_timestamp = rl.GetTime()
    is_dash_cooldown = true 
    dash_cooldown = 3.0
    dash_begin_position = player_pos
    dash_vector = player_dash_target - dash_begin_position
  }

  player_pos += player_direction
}


window_is_resized :: proc()
{
  using g_mem
  screen_width  = f32(rl.GetScreenWidth())
  screen_height = f32(rl.GetScreenHeight())
  game_camera.offset = rl.Vector2{ screen_width / 2, screen_height / 2 }
}


spawn_enemy_random :: proc()
{
  using g_mem
  x := rand.float32_range(0, screen_width)
  y := rand.float32_range(0, screen_height)
  speed := rand.float32_range(0, 200)
  enemy_to_spawn := Enemy {
    x = x, y = y, health = 100, speed = speed,
    starting_health = 100, starting_speed = speed,
  }
  append(&enemies, enemy_to_spawn)
}

spawn_enemy :: proc(x, y, health, speed: f32)
{
  using g_mem
  enemy_to_spawn := Enemy {
    x = x, y = y, health = health, speed = speed,
    starting_health = health, starting_speed = speed,
  }
  append(&enemies, enemy_to_spawn)
}

simulate_enemies :: proc()
{
  using g_mem
  for &enemy, index in enemies {
    if enemy.health <= enemy.starting_health / 2 do enemy.speed = enemy.starting_speed / 2
    if enemy.health <= 0 do unordered_remove(&enemies, index)
    direction := rl.Vector2Normalize(rl.Vector2{player_pos.x - enemy.x, player_pos.y - enemy.y})
    enemy.x += direction.x * delta_time * enemy.speed
    enemy.y += direction.y * delta_time * enemy.speed
  }
}

draw_enemies :: proc()
{
  using g_mem
  default_color :: rl.YELLOW
  enemy_max_health :: 100
  for enemy, index in enemies {
    // TODO: rotation is being calculated here but should be doing this in simulate_enemies()
    rotation := math.to_degrees(math.atan2(enemy.x - player_pos.x, player_pos.y - enemy.y))
    color := default_color
    health_factor := enemy.health / enemy_max_health
    color.g = u8(255 * health_factor)
    rl.DrawRectanglePro(rl.Rectangle{enemy.x, enemy.y, default_enemy_size, default_enemy_size}, rl.Vector2{default_enemy_size / 2, default_enemy_size / 2}, rotation, color)
  }
}

simulate_player_gun :: proc(mouse_direction: [2]f32)
{
  using g_mem

  // TODO: better logic for dispatch
  func := rl.IsMouseButtonDown
  #partial switch player_gun.type
  {
    case .Auto: {
      func = rl.IsMouseButtonDown
    }
    case .SemiAuto: {
      func = rl.IsMouseButtonPressed
    }
    
  }
  if func(.LEFT) {
    gun := &player_gun
    inv_rpm := f64(60.0) / f64(gun.rpm)

    if rl.GetTime() > gun.next_shoot_time {
      x := player_pos.x + (mouse_direction.x * ((player_default_size / 2) + 15))
      y := player_pos.y + (mouse_direction.y * ((player_default_size / 2) + 15))
      spawn_bullet(x, y, player_rotation, {mouse_direction.x, mouse_direction.y}, gun.bullet_speed)
      fmt.printfln("gun.next_shoot_time = {0} + {1} = {2}", rl.GetTime(), inv_rpm, rl.GetTime() + inv_rpm)
      gun.next_shoot_time = rl.GetTime() + inv_rpm
    }
  }
}

spawn_bullet :: proc(x, y, rotation: f32, direction: [2]f32, speed: f64)
{
  using g_mem
  bullet_to_spawn := Bullet {
    x = x, y = y,
    direction = direction,
    time_to_live = 3.0,
    spawned_in = rl.GetTime(), // TODO: game timer
    speed = speed,
    type = 1
  }
  append(&bullets, bullet_to_spawn)
  fmt.printfln("Spawning bullet \t bullet size: {0} \t container: %p", len(bullets), &bullets) 
}

simulate_bullets :: proc()
{
  using g_mem
  // first check if any died
  for &bullet, index in bullets {
    // maybe needs two loops so it doesn't get any inconsistencies.
    if bullet.time_to_live + bullet.spawned_in < rl.GetTime() {
      fmt.printfln("Removing bullet {0} \t bullet size: {1} \t container: %p", index, len(bullets), &bullets) 
      unordered_remove(&bullets, index)
      continue
    }
    bullet.x += bullet.direction.x * delta_time * auto_cast bullet.speed
    bullet.y += bullet.direction.y * delta_time * auto_cast bullet.speed
  }
}

draw_bullets :: proc()
{
  using g_mem
  for bullet in bullets {
    rl.DrawRectanglePro(rl.Rectangle{bullet.x, bullet.y, default_bullet_size, default_bullet_size}, rl.Vector2{default_bullet_size / 2, default_bullet_size / 2}, 0, rl.RED)
  }
}

check_collision :: proc()
{
  using g_mem
  for &bullet, bullet_index in bullets {
    bullet_removed := false
    for &enemy, enemy_index in enemies {
      if rl.CheckCollisionCircles(rl.Vector2{bullet.x, bullet.y}, default_bullet_size / 2, rl.Vector2{enemy.x, enemy.y}, default_enemy_size / 2) {
        fmt.printfln("Bullet %d collided with enemy %d", bullet_index, enemy_index)
        bullet_removed = true
        unordered_remove(&bullets, bullet_index)
        enemy.health -= 50
        break
      }
    }
    if !bullet_removed && rl.CheckCollisionCircles(rl.Vector2{bullet.x, bullet.y}, default_bullet_size / 2, player_pos, player_default_size / 2) {
      unordered_remove(&bullets, bullet_index)
      player_health -= 30
    }
  }
}

draw_shadowed_text :: proc(str: cstring, x, y, size: i32, color: rl.Color)
{
  rl.DrawText(str, x + 2, y + 2, size, rl.BLACK)
  rl.DrawText(str, x, y, size, color)
}

rectangle_from_points :: #force_inline proc(a, b: [2]f32) -> rl.Rectangle
{
  return rl.Rectangle {
    a.x, a.y,
    b.x - a.x, b.y - a.y 
  }
}

update_and_render :: proc() -> bool
{
  using g_mem

  if rl.IsKeyPressed(.SCROLL_LOCK) {
    if hide_cursor {
      hide_cursor = false
      rl.ShowCursor()
    } else {
      hide_cursor = true
      rl.HideCursor()
    }
  }
  // TODO: remove
  horizontal_padding = f32(0.45)
  vertical_padding = f32(0.45)
  scroll_bounds_a = {screen_width * horizontal_padding, screen_height * vertical_padding}
  scroll_bounds_b = {screen_width - (screen_width * horizontal_padding), screen_height - (screen_height * vertical_padding)}
  scroll_bounds = rectangle_from_points(scroll_bounds_a, scroll_bounds_b)
  if rl.IsWindowResized() {
    window_is_resized()
  }
  delta_time = rl.GetFrameTime()

  player_rotation = math.atan2(player_pos.x - mouse_position.x, mouse_position.y - player_pos.y) 
  player_rotation = math.to_degrees(player_rotation)

  if rl.IsKeyPressed(.SIX) do camera_state = 0
  else if rl.IsKeyPressed(.SEVEN) do camera_state = 1

  rl.BeginDrawing()
  rl.ClearBackground(rl.SKYBLUE)

  simulate_bullets()
  simulate_enemies()

  // game_camera.target = rl.Vector2{ player_pos.x, player_pos.y }
  player_screen_position := rl.GetWorldToScreen2D(player_pos, game_camera)

  target_zoom += rl.GetMouseWheelMove() * 0.05;

  if rl.IsKeyPressed(.MINUS) do target_zoom -= 0.5 
  if rl.IsKeyPressed(.EQUAL) do target_zoom += 0.5 
  if rl.IsKeyPressed(.NINE) do spawn_enemy_random() 

  target_zoom = rl.Clamp(target_zoom, 0.1, 10)
  game_camera.zoom = rl.Lerp(game_camera.zoom, target_zoom, 0.1)
  mouse_position = rl.GetScreenToWorld2D(rl.GetMousePosition(), game_camera)

  check_collision()

  mouse_direction: rl.Vector2 = mouse_position - player_pos
  mouse_direction = rl.Vector2Normalize(mouse_direction)

  move_player()

  simulate_player_gun(mouse_direction)

  if player_health <= 0 {
    return false
  }

  rl.BeginMode2D(game_camera)

  rl.DrawTextureEx(background, rl.Vector2{-1000, -1000}, 0, 4, rl.WHITE)
  
  rl.DrawLineV(rl.Vector2{ player_pos.x, player_pos.y }, mouse_position, rl.RED)

  rl.DrawRectanglePro(rl.Rectangle{ player_pos.x, player_pos.y, player_size.x, player_size.y }, rl.Vector2{ player_size.x / 2, player_size.y / 2 }, player_rotation, rl.RED)
  // drawing cooldown bar

  cooldown_bar_height := f32(dash_cooldown / 3.0) * 60
  rl.DrawRectanglePro(rectangle_from_points({player_pos.x - player_default_size - 12, player_pos.y + 40 - cooldown_bar_height}, {player_pos.x - player_default_size, player_pos.y + 40}), rl.Vector2(0), 0, rl.RED)
  
  rl.DrawRectanglePro(rl.Rectangle{ player_dash_target.x, player_dash_target.y, 20, 20 }, rl.Vector2{ 10, 10 }, 0, rl.ORANGE)

  rl.DrawLineV(player_pos, player_pos + player_direction * 20, rl.PURPLE)

  draw_bullets()
  draw_enemies()

  rl.EndMode2D()

  // camera smooth scrolling stuff
  horizontal_delta: f32
  vertical_delta: f32
  scroll_bounds_center := rl.Vector2{screen_width / 2, screen_height / 2}
  horizontal_threshold := scroll_bounds.width / 2
  vertical_threshold := scroll_bounds.height / 2
  player_pos_screen := rl.GetWorldToScreen2D(player_pos, game_camera)

  camera_midpoint_coef: f32 = 10.0
  if rl.IsKeyDown(.LEFT_SHIFT) do camera_midpoint_coef = 200.0
  camera_midpoint := player_pos_screen + rl.Vector2Normalize((rl.GetMousePosition() - player_pos_screen)) * camera_midpoint_coef

  point_to_centralize := camera_midpoint
  horizontal_delta = math.abs(point_to_centralize.x - scroll_bounds_center.x)
  vertical_delta   = math.abs(point_to_centralize.y - scroll_bounds_center.y)
  camera_target := rl.GetScreenToWorld2D(point_to_centralize, game_camera)
  game_camera.target.x = math.lerp(game_camera.target.x, camera_target.x, f32(0.1))
  game_camera.target.y = math.lerp(game_camera.target.y, camera_target.y, f32(0.1))
  if false && camera_state == 0 {
    rl.DrawRectangle(auto_cast point_to_centralize.x, auto_cast point_to_centralize.y, 10, 10, rl.BLUE)
    if !rl.CheckCollisionPointRec(point_to_centralize, scroll_bounds) {
      if horizontal_delta > horizontal_threshold {
        if point_to_centralize.x < scroll_bounds_center.x {
          game_camera.target.x -= horizontal_delta - horizontal_threshold
        } else {
          game_camera.target.x += horizontal_delta - horizontal_threshold  
        }
      }
      if vertical_delta > vertical_threshold {
        if point_to_centralize.y < scroll_bounds_center.y {
          game_camera.target.y -= vertical_delta - vertical_threshold
        } else {
          game_camera.target.y += vertical_delta - vertical_threshold  
        }
      }
    }
  }
  else if camera_state == 1 {
    game_camera.target = player_pos
  }

  current_y := i32(10)
  draw_shadowed_text(rl.TextFormat("FPS: %i", rl.GetFPS()), 10, current_y, 20, FLAT_GREEN)
  current_y += 22
  draw_shadowed_text(rl.TextFormat("Camera zoom: %.3f", game_camera.zoom), 10, current_y, 20, rl.LIGHTGRAY)
  current_y += 22
  draw_shadowed_text(rl.TextFormat("MousePosition: %.3f, %.3f", mouse_position.x, mouse_position.y), 10, current_y, 20, rl.LIGHTGRAY)
  current_y += 22
  draw_shadowed_text(rl.TextFormat("Rotation: %.3f", player_rotation), 10, current_y, 20, rl.LIGHTGRAY)
  current_y += 22
  draw_shadowed_text(rl.TextFormat("Player health: %.3f", player_health), 10, current_y, 20, rl.LIGHTGRAY)
  if is_dash_cooldown {
    current_y += 22
    draw_shadowed_text(rl.TextFormat("Cooldown: %.3f", dash_cooldown), 10, current_y, 20, rl.LIGHTGRAY)
  }
  current_y += 22
  
  draw_shadowed_text(rl.TextFormat("Current Time: %f", rl.GetTime()), 10, current_y, 20, rl.LIGHTGRAY)
  current_y += 22

  draw_shadowed_text(rl.TextFormat("Gun next: %f", player_gun.next_shoot_time), 10, current_y, 20, rl.LIGHTGRAY)
  current_y += 22

  screen_mouse_position := rl.GetMousePosition()
  rl.DrawTexturePro(cursor_texture, rl.Rectangle{ 0, 0, auto_cast cursor_texture.width, auto_cast cursor_texture.height }, { screen_mouse_position.x, screen_mouse_position.y, auto_cast cursor_texture.width * 2, auto_cast cursor_texture.height * 2 }, { auto_cast cursor_texture.width, auto_cast cursor_texture.height}, f32(0.0),  rl.WHITE)

  rl.EndDrawing()

  return true
}

parse_argument :: proc($T: typeid, argument: string) -> (T, bool)
  where intrinsics.type_is_integer(T)
{
  return strconv.parse_int(argument)
}

parse_arguments :: proc(arguments: ^Arguments, flags: ^rl.ConfigFlags)
{
  for arg, i in os.args {
    if arg == "-w"  && i + 1 != len(os.args) {
      argument, ok := parse_argument(int, os.args[i+1])
      if ok {
        arguments.width = argument
      }
    }
    else if arg == "-h"  && i + 1 != len(os.args) {
      argument, ok := parse_argument(int, os.args[i+1])
      if ok {
        arguments.height = argument
      }
    }
    else if arg == "-nomsaa" {
      flags^ -= rl.ConfigFlags{.MSAA_4X_HINT}
    }
    else if arg == "-fullscreen" {
      arguments.fullscreen = true
    }
    fmt.println(arg)
  }
}

load_default_flags :: proc() -> rl.ConfigFlags
{
  result := rl.ConfigFlags{}
  result += rl.ConfigFlags{.MSAA_4X_HINT, .WINDOW_RESIZABLE}
  return result
}

load_default_arguments :: proc() -> Arguments
{
  result: Arguments
  result.width = 1280
  result.height = 720
  result.msaa = true
  result.fullscreen = false
  return result
}

@(export)
game_init_window :: proc()
{
  args := load_default_arguments()
  flags := load_default_flags()
  parse_arguments(&args, &flags)
  rl.SetConfigFlags(flags)
  rl.InitWindow(i32(args.width), i32(args.height), "Shooter Game")

  if args.fullscreen {
    width := rl.GetMonitorWidth(rl.GetCurrentMonitor())
    height := rl.GetMonitorHeight(rl.GetCurrentMonitor())
    rl.SetWindowSize(width, height)
    rl.ToggleFullscreen()
  }
  
  rl.SetTargetFPS(60)
  rl.SetExitKey(nil)
  rl.HideCursor()
}

@(export)
game_init :: proc()
{
  g_mem = new(GameMemory)
  using g_mem
  hide_cursor = true
  window_is_resized()
  game_camera.zoom = 0.1
  target_zoom = 1.0

  reserve(&bullets, 128)
  reserve(&enemies, 128)

  player_size = {80, 80}
  player_pos = {screen_width / 2, screen_height / 2}

  player_gun = Gun {
    type = .Auto,
    bullet_speed = 1500,
    rpm = 150,
    spread = 0.0
  }

  horizontal_padding = f32(0.4)
  vertical_padding = f32(0.3)
  scroll_bounds_a = {screen_width * horizontal_padding, screen_height * vertical_padding}
  scroll_bounds_b = {screen_width - (screen_width * horizontal_padding), screen_height - (screen_height * vertical_padding)}
  scroll_bounds = rectangle_from_points(scroll_bounds_a, scroll_bounds_b)
  player_health = 100
  camera_state = 0
  background = rl.LoadTexture("assets/grass.png")
  cursor_texture = rl.LoadTexture("assets/crosshair.png")
  for i in 0..<3 {
    x := rand.float32_range(0, screen_width)
    y := rand.float32_range(0, screen_height)
    //spawn_enemy(x, y, 100, 100)
    fmt.printfln("Spawning enemy {0}", i)
  }
}

@(export)
game_update:: proc() -> bool
{
  using g_mem
  return update_and_render() && rl.WindowShouldClose() == false
}

@(export)
game_memory:: proc() -> rawptr
{
  return g_mem
}

@(export)
game_memory_size :: proc() -> int
{
  return size_of(GameMemory)
}

@(export)
game_hot_reloaded :: proc(mem: ^GameMemory) 
{
  g_mem = mem 
}

@(export)
game_force_reload :: proc() -> bool 
{
  return rl.IsKeyPressed(.F6)
}

@(export)
game_force_restart :: proc() -> bool
{
  return rl.IsKeyPressed(.F7)
}

@(export)
game_shutdown :: proc()
{
  free(g_mem)
}

