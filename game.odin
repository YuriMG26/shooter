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
import      "core:strings"
import      "core:c/libc"

Point :: [2]f32
Rect  :: rl.Rectangle
FLAT_GREEN :: rl.Color { 0xAC, 0xFB, 0xC5, 0xFF }

// global constants
player_default_size :: 80
dash_duration       :: 0.1
default_enemy_size  :: 150
default_bullet_size :: 8

EnemyState :: enum
{
  Patrol,
  Alert,
  Attacking
}

GunType :: enum
{
  SemiAuto,
  Shotgun,
  Auto
}

Gun :: struct
{
  type             : GunType,
  rpm              : int,
  bullets_in_mag   : int,
  mag_capacity     : int,
  spread           : f64,
  bullets_per_shot : int,
  bullet_speed     : f64,
  bullet_damage    : f64,
  name             : string,
  last_shoot_time  : f64,
  next_shoot_time  : f64,
}

GunTable := map[string]Gun {
  "M1911"     = Gun { bullets_per_shot = 1, type = .SemiAuto,   rpm = 900, bullet_speed = 4000, name = "M1911", mag_capacity = 7, bullets_in_mag = 7, bullet_damage = 50  }, // M1911
  "AK-47"     = Gun { bullets_per_shot = 1, type = .Auto,       rpm = 300, bullet_speed = 4500, name = "AK-47", mag_capacity = 31, bullets_in_mag = 31, bullet_damage = 20, spread = 3  }, // AK-47
  "SPAS-12"   = Gun { bullets_per_shot = 4, type = .Shotgun,    rpm = 200, bullet_speed = 5000, name = "SPAS-12", mag_capacity = 6, bullets_in_mag = 6, bullet_damage = 5, spread = 15,  }, // SPAS-12
}

DroppedGun :: struct
{
  position: [2]f32,
  rotation: f32,
  gun_data: Gun,
}

Bullet :: struct
{
  x, y        : f32,
  direction   : [2]f32,
  time_to_live: f64,
  damage      : f64,
  spawned_in  : f64,
  speed       : f64,
  type        : f64,
}

Enemy :: struct
{
  state          : EnemyState,
  player_detect  : bool,
  x, y           : f32,
  starting_health: f32,
  rotation       : f32,
  health         : f32,
  speed          : f32,
  starting_speed : f32,
  direction      : rl.Vector2,
}

Arguments :: struct
{
  width   : int,
  height  : int,
  msaa    : bool,
  fullscreen    : bool,
}

GameFontSizes :: enum
{
  Size14,
  Size16,
  Size18,
  Size20,
  Size22,
  Size24,
  Size30,
  Size34,

  TotalSizes
}

Circle :: struct
{
  x, y   : f32,
  radius : f32,
}

AABB :: struct
{
  min, max: Point
}

GameFonts :: struct
{
  inconsolata: [GameFontSizes.TotalSizes]rl.Font
}

GameMemory :: struct
{
// TODO Default Values
  player_collider            : Circle,
  player_pos                 : [2]f32,
  player_new_pos             : [2]f32,
  player_size                : [2]f32,
  player_rotation            : f32,
  player_health              : f32, // default = 100
  player_has_gun             : bool,
  player_collide             : bool,
  player_dashing             : bool,
  player_gun                 : Gun,
  player_colliding_wall      : int,
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
  mouse_position_world       : rl.Vector2,
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

  game_fonts                 : GameFonts,

  walls                      : [dynamic]rl.Rectangle,
  bullets                    : [dynamic]Bullet,
  enemies                    : [dynamic]Enemy,
  dropped_guns               : [dynamic]DroppedGun,
}

g_mem: ^GameMemory

look_at :: #force_inline proc(a, b: Point) -> f32 {
  return math.to_degrees(math.atan2(a.x - b.x, b.y - a.y))
}

player_drop_gun :: proc()
{
  using g_mem
  // Do this vector computation in the beginning of every frame
  vector_direction := rl.Vector2Normalize(mouse_position_world - player_pos)
  drop_position := player_pos + (vector_direction * 100)
  player_has_gun = false
  dropped_gun := DroppedGun {
    position = drop_position,
    rotation = player_rotation,
    gun_data = player_gun
  }
  append(&dropped_guns, dropped_gun)
  player_gun = Gun{}
}

player_pickup_gun :: proc(gun: DroppedGun)
{
  using g_mem
  player_gun = gun.gun_data
  player_has_gun = true 
}

check_dropped_gun_pickups :: proc()
{
  using g_mem

  if player_has_gun do return

  for gun, index in dropped_guns {
    if rl.CheckCollisionCircles(gun.position, 25.0 / 2, player_pos, player_default_size / 2) {
      player_pickup_gun(gun)
      unordered_remove(&dropped_guns, index)
    }
  }
}

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
    if player_dashing && dash_duration + dash_timestamp < rl.GetTime() do player_dashing = false
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
    player_dashing = true
    dash_cooldown = 3.0
    dash_begin_position = player_pos
    dash_vector = player_dash_target - dash_begin_position
  }

  if player_dashing { 
    player_new_pos = player_pos
    player_physics_steps :: 4
    player_direction = player_direction / player_physics_steps
    for i in 0..< player_physics_steps {
      player_new_pos = player_new_pos + player_direction
      for wall, wall_index in walls {
        collide, normal, depth := intersect_circle_rec(player_new_pos, player_size.x / 2.0, wall)
        if collide {
          player_colliding_wall = wall_index 
          move(&player_new_pos, -normal * depth)
        }
      }
    }
  }
  else do player_new_pos = player_pos + player_direction

  player_collider = Circle{x = player_new_pos.x, y = player_new_pos.y, radius = player_size.x / 2.0}

  check_dropped_gun_pickups()
  
  if player_has_gun && rl.IsKeyPressed(.G) {
    player_drop_gun()
  }
}

window_is_resized :: proc()
{
  using g_mem
  screen_width  = f32(rl.GetScreenWidth())
  screen_height = f32(rl.GetScreenHeight())
  game_camera.offset = rl.Vector2{ screen_width / 2, screen_height / 2 }
}

init_default_walls :: proc()
{
  door_gap :: 200
  using g_mem
  append(&walls, rl.Rectangle{0, 200, 2400, 50})
  append(&walls, rl.Rectangle{1150, 200, 50, 500})
  append(&walls, rl.Rectangle{1150, 200 + 500 + door_gap, 50, (200 + 1200) - (200 + 500 + door_gap)})
  append(&walls, rl.Rectangle{0, 200 + 1200, 2400, 50})
  // append(&walls, rl.Rectangle{700, 200, 50, 200})
  // append(&walls, rl.Rectangle{700, 200, 50, 200})
}

spawn_enemy_random :: proc()
{
  using g_mem
  x := rand.float32_range(0, screen_width)
  y := rand.float32_range(0, screen_height)
  speed := rand.float32_range(0, 200)
  spawn_enemy(x, y, 100, speed)
}

spawn_enemy :: proc(x, y, health, speed: f32)
{
  using g_mem
  enemy_to_spawn := Enemy {
    state = EnemyState.Patrol,
    x = x, y = y, health = health, speed = speed,
    starting_health = health, starting_speed = speed,
    rotation = rand.float32_range(0, 360),
  }
  append(&enemies, enemy_to_spawn)
}

simulate_enemy :: #force_inline proc(enemy: ^Enemy, index: int)
{
  using g_mem
  if enemy.health <= enemy.starting_health / 2 do enemy.speed = enemy.starting_speed / 2
  if enemy.health <= 0 do unordered_remove(&enemies, index)

  enemy.direction = rl.Vector2{0, 1}
  enemy.direction = rl.Vector2Rotate(enemy.direction, math.to_radians(enemy.rotation))

  switch(enemy.state)
  {
    case .Patrol: {
      if enemy.player_detect do enemy.state = .Alert 
    } 
    case .Alert: {
      enemy.rotation = look_at({enemy.x, enemy.y}, player_pos) 
      direction := rl.Vector2Normalize(rl.Vector2{player_pos.x - enemy.x, player_pos.y - enemy.y})
      enemy.x += direction.x * delta_time * enemy.speed
      enemy.y += direction.y * delta_time * enemy.speed
    }
    case .Attacking: {

    }
  }

}

simulate_enemies :: proc()
{
  using g_mem
  for &enemy, index in enemies {
    simulate_enemy(&enemy, index)
  }
}

draw_enemies :: proc()
{
  using g_mem
  default_color :: rl.YELLOW
  enemy_max_health :: 100
  for &enemy, index in enemies {
    // TODO: rotation is being calculated here but should be doing this in simulate_enemies()
    // rotation := math.to_degrees(math.atan2(enemy.x - player_pos.x, player_pos.y - enemy.y))
    color := default_color
    health_factor := enemy.health / enemy_max_health
    color.g = u8(255 * health_factor)
    rl.DrawRectanglePro(rl.Rectangle{enemy.x, enemy.y, default_enemy_size, default_enemy_size}, rl.Vector2{default_enemy_size / 2, default_enemy_size / 2}, enemy.rotation, color)

    fov :: 90
    line_size :: 1000
    left_line := rl.Vector2Rotate(enemy.direction, math.to_radians(f32(-fov/2)))
    right_line := rl.Vector2Rotate(enemy.direction, math.to_radians(f32(fov/2)))
    // rl.DrawLineV({enemy.x, enemy.y}, {enemy.x + enemy.direction.x * 50, enemy.y + enemy.direction.y * 50}, rl.RED)

    line_color := rl.RED
    
    to_player_vector_not_normalized := player_pos - rl.Vector2{enemy.x, enemy.y}
    to_player_vector_normalized := rl.Vector2Normalize(to_player_vector_not_normalized)

    dot := rl.Vector2DotProduct(enemy.direction, to_player_vector_normalized)
    a := enemy.direction
    b := to_player_vector_normalized

    // angle := rl.Vector2DotProduct(a, b)
    angle: f32
    bottom_part   : f32
    top_part      : f32
    initial_angle : f32
    angle_acos    : f32

    if !rl.Vector2Equals(a, b) {
      bottom_part   = (math.sqrt((a.x * a.x) + (a.y * a.y)) * math.sqrt((b.x * b.x) + (b.y * b.y)))
      top_part      = (a.x * b.x + a.y * b.y)
      initial_angle = top_part / bottom_part
      angle_acos = math.acos(initial_angle)
      angle = math.to_degrees(angle_acos)
    }
    else {
      angle = 0.0
    }
    
    rl.DrawText(str, auto_cast enemy.x - 100, auto_cast enemy.y - 100, 20, rl.BLACK)

    if angle < fov / 2 && rl.Vector2Distance({enemy.x, enemy.y}, player_new_pos) < 1500 {
      
      // TODO: speed
      current_y: i32 = auto_cast enemy.y - 100
      collided_with_wall := false
      for wall, windex in walls {
        // raycast
        collide, tmin, tmax := intersect_ray_rec({enemy.x, enemy.y}, to_player_vector_normalized, wall)
        if collide {
          rl.DrawText(rl.TextFormat("collision = %d", windex), auto_cast enemy.x, current_y, 20, rl.BLACK)
          current_y += 22
          if tmin < rl.Vector2Length(to_player_vector_not_normalized) {
            collided_with_wall = true
            break
          }
        }
      }
      if collided_with_wall == false {
        line_color = rl.GREEN
        enemy.player_detect = true
      } 
    } else do enemy.player_detect = false

    rl.DrawLineV({enemy.x, enemy.y}, {enemy.x + left_line.x * line_size, enemy.y + left_line.y * line_size}, line_color)
    rl.DrawLineV({enemy.x, enemy.y}, {enemy.x + right_line.x * line_size, enemy.y + right_line.y * line_size}, line_color)
  }
}

// TODO: move from here
points_from_rectangle :: proc(rect: rl.Rectangle) -> [4]Point // clockwise
{
  return {
    {rect.x, rect.y},
    {rect.x + rect.width, rect.y},
    {rect.x + rect.width, rect.y + rect.height},
    {rect.x, rect.y + rect.height}
  }
}

// THIS IS EXPENSIVE
get_closest_point :: proc(a: Point, points: []Point) -> Point
{
  min_distance : f32 = 9999999 // INT_MAX ?
  min_point: Point
  for point in points {
    distance := rl.Vector2Distance(point, a)
    if distance < min_distance {
      min_distance = distance
      min_point = point
    }
  }
  return min_point
}

aabb_from_rect :: #force_inline proc(rect: Rect) -> AABB
{
  return {
    {rect.x, rect.y},
    {rect.x + rect.width, rect.y + rect.height}
  }
}

get_closest_point_rect :: proc(aabb: AABB, point: Point) -> (result: Point)
{
  result = Point(0)
  for i in 0..<2 {
    v := point[i] 
    if v < aabb.min[i] do v = aabb.min[i]
    if v > aabb.max[i] do v = aabb.max[i]
    result[i] = v
  }
  return
}

intersect_ray_rec :: proc(ray_origin, ray_direction: Point, rect: Rect) -> (bool, f32, f32)
{
  inv_dir := rl.Vector2{1.0 / ray_direction.x, 1.0 / ray_direction.y}

  t1 := (rect.x - ray_origin.x) * inv_dir.x
  t2 := ((rect.x + rect.width) - ray_origin.x) *inv_dir.x
  t3 := (rect.y - ray_origin.y) * inv_dir.y
  t4 := ((rect.y + rect.height) - ray_origin.y) * inv_dir.y

  tmin := math.max(math.min(t1, t2), math.min(t3, t4))
  tmax := math.min(math.max(t1, t2), math.max(t3, t4))

  if tmax < 0.0 || tmin > tmax {
    return false, 0.0, 0.0
  }
  return true, tmin, tmax
}

intersect_circle_rec :: proc(center: [2]f32, radius: f32, rect: Rect) -> (collide: bool, normal: rl.Vector2, depth: f32)
{
  collide = false
  normal = rl.Vector2(0)
  depth = 0.0

  aabb := aabb_from_rect(rect)
  closest_point = get_closest_point_rect(aabb, center)

  distance := rl.Vector2Distance(closest_point, center)
  
  if distance >= radius {
    return
  }
  collide = true
  normal = rl.Vector2Normalize(closest_point - center)
  depth = radius - distance

  return
}

draw_walls :: proc()
{
  using g_mem
  for wall, index in walls {
    rl.DrawRectangleRec(wall, rl.RED)
  }
}

closest_point: Point

move :: #force_inline proc(p: ^rl.Vector2, v: rl.Vector2)
{
  p^ += v
}

simulate_walls :: proc()
{
  using g_mem
  player_collide = false
  player_colliding_wall = -1
  for wall, wall_index in walls {
    // TODO: better check collisions in other places?
    // Player wall collision
    // NOTE: if the player is dashing, the collision is being handled on move_player() for now, but this
    // will change when I make a better collision system with triggers maybe
    if !player_dashing {
      collide, normal, depth := intersect_circle_rec(player_new_pos, player_size.x / 2.0, wall)
      if collide {
        player_colliding_wall = wall_index 
        move(&player_new_pos, -normal * depth)
      }
    }
    for &enemy in enemies {
      collide, normal, depth := intersect_circle_rec({enemy.x, enemy.y}, default_enemy_size / 2.0, wall)
      if collide {
        v := - normal * depth
        enemy.x += v.x
        enemy.y += v.y
      }
    }
  }
}

draw_dropped_guns :: proc()
{
  using g_mem
  for gun, index in dropped_guns {
    color := rl.PURPLE
    if gun.gun_data.type == .Auto do color = rl.BLUE
    else if gun.gun_data.type == .Shotgun do color = rl.BROWN
    rl.DrawRectanglePro(rl.Rectangle{gun.position.x, gun.position.y, 25, 25}, {25/2,25/2}, gun.rotation, color)
    rl.DrawCircle(auto_cast gun.position.x, auto_cast gun.position.y, 25/2, rl.Color{90, 255, 90, 170})
  }
}

simulate_player_gun :: proc(mouse_direction: [2]f32)
{
  using g_mem

  if !player_has_gun || player_gun.bullets_in_mag == 0 do return

  // TODO: better logic for dispatch
  func := rl.IsMouseButtonDown
  switch player_gun.type
  {
    case .Auto: {
      func = rl.IsMouseButtonDown
    }
    case .SemiAuto, .Shotgun: {
      func = rl.IsMouseButtonPressed
    }
    
  }
  if func(.LEFT) {
    gun := &player_gun
    inv_rpm := f64(60.0) / f64(gun.rpm)

    // TODO: need to handle burst mechanics
    if rl.GetTime() > gun.next_shoot_time {
      for i in 0..<gun.bullets_per_shot {
        position_point := rl.Vector2{
          player_pos.x + (mouse_direction.x * ((player_default_size / 2) + 15)),
          player_pos.y + (mouse_direction.y * ((player_default_size / 2) + 15))
        }
        rotation := rand.float32_range(auto_cast -gun.spread, auto_cast gun.spread)
        direction := rl.Vector2Rotate(mouse_direction, math.to_radians(f32(rotation)))
        spawn_bullet(position_point.x, position_point.y, player_rotation, direction, gun.bullet_speed)
      }
      gun.next_shoot_time = rl.GetTime() + inv_rpm
      gun.bullets_in_mag -= 1
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
  // fmt.printfln("Spawning bullet \t bullet size: {0} \t container: %p", len(bullets), &bullets) 
}

simulate_bullets :: proc()
{
  using g_mem
  // first check if any died
  for &bullet, index in bullets {
    // maybe needs two loops so it doesn't get any inconsistencies.
    if bullet.time_to_live + bullet.spawned_in < rl.GetTime() {
      // fmt.printfln("Removing bullet {0} \t bullet size: {1} \t container: %p", index, len(bullets), &bullets) 
      unordered_remove(&bullets, index)
      continue
    }

    steps :: 4
    velocity := (bullet.direction * delta_time * auto_cast bullet.speed) / steps
    for i in 0..< steps {
      collided := false
      bullet.x += velocity.x
      bullet.y += velocity.y
    // NOTE: this collision is being handled here so the collision can be handled in a 4 steps per tick manner
      for wall, wall_index in walls {
        if collided == false && rl.CheckCollisionCircleRec(rl.Vector2{bullet.x, bullet.y}, default_bullet_size/2, wall) {
          collided = true
          unordered_remove(&bullets, index)
          break
        }
      }
      if collided do break
    }
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
      // unordered_remove(&bullets, bullet_index)
      // player_health -= 30
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

  player_collide = false

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

  player_rotation = math.atan2(player_pos.x - mouse_position_world.x, mouse_position_world.y - player_pos.y) 
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
  mouse_position_world = rl.GetScreenToWorld2D(rl.GetMousePosition(), game_camera)

  check_collision()

  mouse_direction: rl.Vector2 = mouse_position_world - player_pos
  mouse_direction = rl.Vector2Normalize(mouse_direction)

  move_player()

  simulate_player_gun(mouse_direction)

  if player_health <= 0 {
    return false
  }

  rl.BeginMode2D(game_camera)

  simulate_walls()

  draw_dropped_guns()

  rl.DrawRectanglePro(rl.Rectangle{ player_pos.x, player_pos.y, player_size.x, player_size.y }, rl.Vector2{ player_size.x / 2, player_size.y / 2 }, player_rotation, rl.RED)

  // drawing cooldown bar
  cooldown_bar_height := f32(dash_cooldown / 3.0) * 60
  rl.DrawRectanglePro(rectangle_from_points({player_pos.x - player_default_size - 12, player_pos.y + 40 - cooldown_bar_height}, {player_pos.x - player_default_size, player_pos.y + 40}), rl.Vector2(0), 0, rl.RED)
  
  rl.DrawRectanglePro(rl.Rectangle{ player_dash_target.x, player_dash_target.y, 20, 20 }, rl.Vector2{ 10, 10 }, 0, rl.ORANGE)

  rl.DrawLineV(player_pos, player_pos + player_direction * 20, rl.PURPLE)

  draw_bullets()
  draw_enemies()
  draw_walls()

  rl.DrawCircle(auto_cast player_collider.x, auto_cast player_collider.y, player_collider.radius, rl.Color{50, 255, 50, 180})

  rl.DrawRectangleV(closest_point, rl.Vector2{30, 30}, rl.GREEN)

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
  draw_shadowed_text(rl.TextFormat("MousePosition: %.3f, %.3f", mouse_position_world.x, mouse_position_world.y), 10, current_y, 20, rl.LIGHTGRAY)
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

  draw_shadowed_text(rl.TextFormat("Colliding wall: %d", player_colliding_wall), 10, current_y, 20, rl.LIGHTGRAY)
  current_y += 22


  screen_mouse_position_world := rl.GetMousePosition()

  cursor_coef := 1.2
  rl.DrawTexturePro(cursor_texture, rl.Rectangle{ 0, 0, auto_cast cursor_texture.width, auto_cast cursor_texture.height }, { screen_mouse_position_world.x, screen_mouse_position_world.y, auto_cast (cursor_texture.width * auto_cast cursor_coef), auto_cast (cursor_texture.height * auto_cast cursor_coef) }, { auto_cast (cursor_texture.width * auto_cast cursor_coef) / 2, auto_cast (cursor_texture.height * auto_cast cursor_coef) / 2}, f32(0.0),  rl.WHITE)

  font_size := 30.0
  rl.DrawTextEx(game_fonts.inconsolata[GameFontSizes.Size30], rl.TextFormat("Current Weapon: %s (%d/%d)", player_gun.name, player_gun.bullets_in_mag, player_gun.mag_capacity), rl.Vector2{10, auto_cast rl.GetScreenHeight() - auto_cast (font_size + 4.0)}, auto_cast font_size, 0, rl.BLACK)

  rl.EndDrawing()

  if !player_collide {
    player_pos = player_new_pos
  }

  return true
}

parse_argument_int :: proc($T: typeid, argument: string) -> (T, bool)
  where intrinsics.type_is_integer(T)
{
  return strconv.parse_int(argument)
}

parse_argument_float :: proc($T: typeid, argument: string) -> (T, bool)
  where intrinsics.type_is_float(T)
{
  return strconv.parse_f32(argument)
}

parse_argument :: proc {
  parse_argument_int,
  parse_argument_float,
}

parse_arguments :: proc(arguments: ^Arguments, flags: ^rl.ConfigFlags)
{
  for arg, i in os.args {
    t: typeid
    if arg == "-w"  && i + 1 != len(os.args) {
      argument, ok := parse_argument(int, os.args[i+1])
      t = int
      if ok {
        arguments.width = argument
      }
    }
    else if arg == "-h"  && i + 1 != len(os.args) {
      argument, ok := parse_argument(int, os.args[i+1])
      t = f32
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
    fmt.printfln("{0} => {1}", t, arg)
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

  game_fonts.inconsolata[GameFontSizes.Size14] = rl.LoadFontEx("assets/fonts/inconsolata.ttf", 14, nil, 0)
  game_fonts.inconsolata[GameFontSizes.Size16] = rl.LoadFontEx("assets/fonts/inconsolata.ttf", 16, nil, 0)
  game_fonts.inconsolata[GameFontSizes.Size18] = rl.LoadFontEx("assets/fonts/inconsolata.ttf", 18, nil, 0)
  game_fonts.inconsolata[GameFontSizes.Size20] = rl.LoadFontEx("assets/fonts/inconsolata.ttf", 20, nil, 0)
  game_fonts.inconsolata[GameFontSizes.Size22] = rl.LoadFontEx("assets/fonts/inconsolata.ttf", 22, nil, 0)
  game_fonts.inconsolata[GameFontSizes.Size24] = rl.LoadFontEx("assets/fonts/inconsolata.ttf", 24, nil, 0)
  game_fonts.inconsolata[GameFontSizes.Size30] = rl.LoadFontEx("assets/fonts/inconsolata.ttf", 30, nil, 0)
  game_fonts.inconsolata[GameFontSizes.Size34] = rl.LoadFontEx("assets/fonts/inconsolata.ttf", 34, nil, 0)

  reserve(&bullets, 128)
  reserve(&enemies, 128)

  player_colliding_wall = -1
  player_size = {80, 80}
  player_pos = {screen_width / 2, screen_height / 2}
  player_collide = false

  player_gun = GunTable["M1911"]
  player_has_gun = true

  horizontal_padding = f32(0.4)
  vertical_padding = f32(0.3)
  scroll_bounds_a = {screen_width * horizontal_padding, screen_height * vertical_padding}
  scroll_bounds_b = {screen_width - (screen_width * horizontal_padding), screen_height - (screen_height * vertical_padding)}
  scroll_bounds = rectangle_from_points(scroll_bounds_a, scroll_bounds_b)
  player_health = 100
  camera_state = 0

  background = rl.LoadTexture("assets\\grass.png")

  cursor_texture = rl.LoadTexture("assets\\crosshair.png")
  for i in 0..<3 {
    x := rand.float32_range(0, screen_width)
    y := rand.float32_range(0, screen_height)
    //spawn_enemy(x, y, 100, 100)
    fmt.printfln("Spawning enemy {0}", i)
  }
  
  init_default_walls()
  for i in 0..<12 {
    r := int(rand.float32_range(0, 3))
    choice: string
    if r == 0 do choice = "M1911"
    if r == 1 do choice = "AK-47"
    if r == 2 do choice = "SPAS-12"
    fmt.printfln("{0} ----- Spawning {1}", r, choice)

    x, y: f32

    for wall in walls {
      for {
        x = rand.float32_range(-1000.0, 1000.0)
        y = rand.float32_range(-1000.0, 1000.0)
        if !rl.CheckCollisionCircleRec(rl.Vector2{x, y}, 12.5, wall) {
          break;
        }
      }
    }

    rotation := rand.float32_range(0, 270)
    dropped_gun := DroppedGun {
      position = {x, y}, rotation = rotation,
      gun_data = GunTable[choice]
    } 
    append(&dropped_guns, dropped_gun) 
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

