extends Resource
class_name EnemyData

## Definição de um inimigo. O balanceamento vive em resources/enemies/*.tres.

@export var display_name := "Inimigo"
@export var max_health := 30.0
@export var speed := 3.0
@export var base_damage := 1
@export var reward := 6
@export var color := Color(0.9, 0.3, 0.3)
@export var radius := 0.3
@export var height := 0.7
