extends Resource
class_name TowerData

## Definição de uma torre. O balanceamento vive em resources/towers/*.tres,
## então adicionar uma torre nova não exige mexer em código.

@export var display_name := "Torre"
@export var cost := 20
@export_multiline var description := ""
@export var color := Color(0.75, 0.8, 0.9)
## Altura da base até o ponto onde a mão pinça (topo/cabeça).
@export var grip_height := 0.9

@export_group("Visual")
## Cena visual opcional. Quando preenchida, substitui a cabeça procedural.
@export var visual_scene: PackedScene
@export_range(0.1, 2.0, 0.05) var visual_scale := 1.0
## Ponto de origem do disparo no espaço local da cabeça.
@export var muzzle_offset := Vector3(0.0, 0.0, 0.3)
## Ajuste de orientação do visual para alinhar a frente com o alvo.
@export var aim_yaw_offset_degrees := 0.0

@export_group("Combate")
@export_enum("Projétil", "Laser") var attack_mode: int = 0
@export var damage := 10.0
@export var attack_range := 4.0
@export var fire_interval := 1.0
@export var projectile_speed := 12.0
## 0.0 = sem slow. 0.4 = 40% mais lento.
@export_range(0.0, 0.9, 0.05) var slow_factor := 0.0
@export var slow_duration := 0.0
