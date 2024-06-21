package collision_test

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import rand "core:math/rand"

player_pos: [2]f32
player_size: [2]f32
player_rotation: f32

delta_time: f32

move_player :: proc()
{
  if rl.IsKeyDown(.W) do player_pos.y -= 100 * delta_time
  if rl.IsKeyDown(.S) do player_pos.y += 100 * delta_time
  if rl.IsKeyDown(.A) do player_pos.x -= 100 * delta_time
  if rl.IsKeyDown(.D) do player_pos.x += 100 * delta_time
}

screen_width: f32
screen_height: f32

game_camera: rl.Camera2D

window_is_resized :: proc()
{
  screen_width  = f32(rl.GetScreenWidth())
  screen_height = f32(rl.GetScreenHeight())
  game_camera.offset = rl.Vector2{ screen_width / 2, screen_height / 2 }
}

Bullet :: struct
{
  x, y: f32,
  direction: [2]f32,
  time_to_live: f64,
  spawned_in: f64,
}

Enemy :: struct
{
  x, y: f32,
  health: f32,
  speed: f32,
}

bullets: [dynamic]Bullet
enemies: [dynamic]Enemy

spawn_enemy :: proc(x, y, health, speed: f32)
{
  enemy_to_spawn := Enemy {
    x = x, y = y, health = health, speed = speed
  }
  append(&enemies, enemy_to_spawn)
}

simulate_enemies :: proc()
{
  for &enemy, index in enemies {
    if(enemy.health <= 0) do unordered_remove(&enemies, index)
    direction := rl.Vector2Normalize(rl.Vector2{player_pos.x - enemy.x, player_pos.y - enemy.y})
    enemy.x += direction.x * delta_time * enemy.speed
    enemy.y += direction.y * delta_time * enemy.speed
  }
}

default_enemy_size :: 150
draw_enemies :: proc()
{
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

spawn_bullet :: proc(x, y, rotation: f32, direction: [2]f32)
{
  bullet_to_spawn := Bullet {
    x = x, y = y,
    direction = direction,
    time_to_live = 3.0,
    spawned_in = rl.GetTime() // TODO: game timer
  }
  fmt.printfln("Spawning bullet at %.2f %.2f", x, y)
  append(&bullets, bullet_to_spawn)
}

simulate_bullets :: proc()
{
  bullet_speed :: 500
  // first check if any died
  for &bullet, index in bullets {
    // maybe needs two loops so it doesn't get any inconsistencies.
    if bullet.time_to_live + bullet.spawned_in < rl.GetTime() {
      unordered_remove(&bullets, index)
      continue
    }
    bullet.x += bullet.direction.x * delta_time * bullet_speed
    bullet.y += bullet.direction.y * delta_time * bullet_speed
  }
}

default_bullet_size :: 8
draw_bullets :: proc()
{
  for bullet in bullets {
    rl.DrawRectanglePro(rl.Rectangle{bullet.x, bullet.y, default_bullet_size, default_bullet_size}, rl.Vector2{default_bullet_size / 2, default_bullet_size / 2}, 0, rl.RED)
  }
}

check_collision :: proc()
{
  for &enemy, enemy_index in enemies {
    for &bullet, bullet_index in bullets {
      if rl.CheckCollisionCircles(rl.Vector2{bullet.x, bullet.y}, default_bullet_size / 2, rl.Vector2{enemy.x, enemy.y}, default_enemy_size / 2) {
        unordered_remove(&bullets, bullet_index)
        enemy.health -= 50
      }
    }
  }
}

mouse_position: rl.Vector2
main :: proc()
{
  rl.InitWindow(1280, 720, "hmmmm")
  defer rl.CloseWindow()

  window_is_resized()

  game_camera.zoom = 0.1

  player_size = { 80, 80 }
  player_pos = { screen_width / 2, screen_height / 2 }

  
  for i in 0..<3 {
    x := rand.float32_range(0, screen_width)
    y := rand.float32_range(0, screen_height)
    spawn_enemy(x, y, 100, 100)
  }

  background := rl.LoadTexture("assets/grass.png")

  target_zoom := f32(1.0)

  for !rl.WindowShouldClose()
  {
    if rl.IsWindowResized() {
      window_is_resized()
    }
    delta_time = rl.GetFrameTime()

    player_rotation = math.atan2(player_pos.x - mouse_position.x, mouse_position.y - player_pos.y) 
    player_rotation = math.to_degrees(player_rotation)

    rl.BeginDrawing()
    rl.ClearBackground(rl.SKYBLUE)

    simulate_bullets()
    simulate_enemies()


    game_camera.target = rl.Vector2{ player_pos.x, player_pos.y }

    target_zoom += rl.GetMouseWheelMove() * 0.05;
    game_camera.zoom = rl.Lerp(game_camera.zoom, target_zoom, 0.1)
    mouse_position = rl.GetScreenToWorld2D(rl.GetMousePosition(), game_camera)

    check_collision()

    mouse_direction: rl.Vector2 = { mouse_position.x - player_pos.x, mouse_position.y - player_pos.y }
    mouse_direction = rl.Vector2Normalize(mouse_direction)


    if rl.IsMouseButtonPressed(.LEFT) {
      x := player_pos.x + mouse_direction.x
      y := player_pos.y + mouse_direction.y
      spawn_bullet(x, y, player_rotation, {mouse_direction.x, mouse_direction.y})
    }

    move_player()

    rl.BeginMode2D(game_camera)

    rl.DrawTextureEx(background, rl.Vector2{-1000, -1000}, 0, 4, rl.WHITE)
    
    rl.DrawLineV(rl.Vector2{ player_pos.x, player_pos.y }, mouse_position, rl.RED)

    rl.DrawRectanglePro(rl.Rectangle{ player_pos.x, player_pos.y, player_size.x, player_size.y }, rl.Vector2{ player_size.x / 2, player_size.y / 2 }, player_rotation, rl.WHITE)

    draw_bullets()
    draw_enemies()

    rl.EndMode2D()

    current_y := i32(30)
    rl.DrawText(rl.TextFormat("Position: %.3f, %.3f", player_pos.x, player_pos.y), 10, current_y, 20, rl.BLACK)
    current_y += 22
    rl.DrawText(rl.TextFormat("MousePosition: %.3f, %.3f", mouse_position.x, mouse_position.y), 10, current_y, 20, rl.BLACK)
    current_y += 22
    rl.DrawText(rl.TextFormat("Rotation: %.3f", player_rotation), 10, current_y, 20, rl.BLACK)

    rl.DrawFPS(10, 10)

    rl.EndDrawing()
  }
}
