extends Node
class_name AudioManagerService

## SFX pontuais de combate e conclusão. Não há música de fundo.

const SFX_PATHS := {
	"shot_pew": "res://assets/audio/sfx/shot_pew.wav",
	"laser": "res://assets/audio/sfx/laser_shot.wav",
	"enemy_down": "res://assets/audio/sfx/enemy_down.wav",
	"level_complete": "res://assets/audio/sfx/level_complete.wav",
}

@export_range(0.0, 1.0) var sfx_volume := 0.72
@export_range(4, 16, 1) var sfx_voice_count := 8

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_index := 0


func _ready() -> void:
	for key in SFX_PATHS:
		var path: String = SFX_PATHS[key]
		var stream := load(path) as AudioStream
		if stream != null:
			_streams[key] = stream

	for index in sfx_voice_count:
		var voice := AudioStreamPlayer.new()
		voice.name = "SFXVoice_%02d" % index
		voice.volume_db = linear_to_db(maxf(sfx_volume, 0.001))
		add_child(voice)
		_voices.append(voice)


func play_sfx(sound_name: String, volume_scale: float = 1.0) -> void:
	if _voices.is_empty() or not _streams.has(sound_name):
		return

	var voice := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	voice.stop()
	voice.stream = _streams[sound_name]
	voice.volume_db = linear_to_db(maxf(sfx_volume * volume_scale, 0.001))
	voice.play()
