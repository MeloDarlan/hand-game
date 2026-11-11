extends Node
class_name WaveManager

## Controla as ondas: monta a fila de spawn, instancia inimigos e avisa o
## GameManager sobre abates e vazamentos. Não conhece créditos nem HUD.

signal wave_started(index: int)
signal wave_cleared(index: int, bonus: int)
signal all_waves_cleared
signal enemy_killed(reward: int)
signal enemy_leaked(base_damage: int)

const DEFAULT_WAVE_PATHS := [
	"res://resources/waves/wave_01.tres",
	"res://resources/waves/wave_02.tres",
	"res://resources/waves/wave_03.tres",
]

@export var waves: Array = []

var _index := -1
var _queue: Array = []
var _clock := 0.0
var _running := false
var _alive := 0

@onready var _board: Board = %Board
@onready var _enemies_root: Node3D = %Enemies


func _ready() -> void:
	if waves.is_empty():
		for path in DEFAULT_WAVE_PATHS:
			var wave := load(path)
			if wave != null:
				waves.append(wave)
	set_process(false)


func _process(delta: float) -> void:
	_clock += delta

	while not _queue.is_empty() and float(_queue[0]["time"]) <= _clock:
		var entry: Dictionary = _queue.pop_front()
		_spawn(entry["data"] as EnemyData)

	_check_clear()


func start_next_wave() -> void:
	if _running or not has_next_wave():
		return

	_index += 1
	var wave := waves[_index] as WaveData
	if wave == null:
		return

	_queue.clear()
	var time := 0.0
	for group_resource in wave.groups:
		var group := group_resource as WaveGroup
		if group == null or group.enemy_data == null:
			continue
		time += group.start_delay
		for _i in group.count:
			_queue.append({"data": group.enemy_data, "time": time})
			time += group.spawn_interval

	_clock = 0.0
	_alive = 0
	_running = true
	set_process(true)
	wave_started.emit(_index)


func stop() -> void:
	_running = false
	_queue.clear()
	set_process(false)


func get_wave_count() -> int:
	return waves.size()


func get_current_wave_number() -> int:
	return _index + 1


func has_next_wave() -> bool:
	return _index + 1 < waves.size()


func is_running() -> bool:
	return _running


func _spawn(data: EnemyData) -> void:
	if data == null:
		return

	var enemy := Enemy.new()
	_enemies_root.add_child(enemy)
	enemy.setup(data, _board.get_path_world_points())
	enemy.died.connect(_on_enemy_died)
	enemy.leaked.connect(_on_enemy_leaked)
	_alive += 1


func _on_enemy_died(enemy: Enemy) -> void:
	_alive = maxi(_alive - 1, 0)
	var reward := enemy.data.reward if enemy.data != null else 0
	enemy_killed.emit(reward)
	_check_clear()


func _on_enemy_leaked(enemy: Enemy) -> void:
	_alive = maxi(_alive - 1, 0)
	var damage := enemy.data.base_damage if enemy.data != null else 1
	enemy_leaked.emit(damage)
	_check_clear()


func _check_clear() -> void:
	if not _running:
		return
	if not _queue.is_empty() or _alive > 0:
		return

	_running = false
	set_process(false)

	var bonus := 0
	var wave := waves[_index] as WaveData
	if wave != null:
		bonus = wave.bonus_credits

	wave_cleared.emit(_index, bonus)
	if not has_next_wave():
		all_waves_cleared.emit()
