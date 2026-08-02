extends Resource
class_name DynamicEffect

# Puste funkcje wirtualne gotowe do nadpisania przez konkretne efekty
func on_wave_start(_model, _amount: int) -> void:
	pass

func on_wave_end(_model, _amount: int) -> void:
	pass
