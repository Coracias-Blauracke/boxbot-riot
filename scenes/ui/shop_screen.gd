class_name ShopScreen
extends CanvasLayer

## Every player's shop panel, for the duration of the shop phase.
##
## Sits ABOVE the HUD, because during the shop the panels are the screen. The
## HUD's corner readouts would only repeat what each panel's own header already
## says, and at four players there is no room for both.
##
## Panels are placed by ShopLayout, which follows the HUD's corner map - a
## player who learned where they are during combat finds themselves in the same
## place here.

var run: RunModel
var stat_sheet: StatSheet

var _panels: Array[ShopPanel] = []

func bind(p_run: RunModel, players: Array[Character], p_sheet: StatSheet) -> void:
	run = p_run
	stat_sheet = p_sheet
	run.phase_changed.connect(_on_phase_changed)

	for index in players.size():
		var panel := ShopPanel.new()
		panel.bind(
			index, players[index].model, run.shop_for(index), players[index].input,
			stat_sheet, players[index].data as CharacterData
		)
		panel.ready_requested.connect(_on_ready_requested)
		add_child(panel)
		_panels.append(panel)

	get_viewport().size_changed.connect(_place_panels)
	_place_panels()
	_set_shown(run.phase == WorldTypes.Phase.SHOP)

## Routed through the run rather than set on the shop, because RunModel is what
## decides that everybody is ready and starts the next wave.
func _on_ready_requested(index: int, value: bool) -> void:
	run.set_player_ready(index, value)

## Capture only: buys one item and parks every cursor on the owned strip, so a
## tile's detail can be photographed without a hand on a pad.
##
## Deferred to the moment the shop OPENS. Doing it at startup bought nothing,
## silently, because offers do not exist until the first wave ends - which is
## exactly the sort of thing a capture is supposed to catch.
var _park_on_owned: bool = false

func park_cursor_on_owned() -> void:
	_park_on_owned = true

func _park_now() -> void:
	for index in _panels.size():
		# The grant is because a wave-one player cannot afford anything, and a
		# silently failed purchase photographs an empty strip and proves nothing.
		run.players[index].add_currency(500)
		run.shop_for(index).buy(run.players[index], 0)
		_panels[index]._on_offers_changed()
		_panels[index].zone = ShopPanel.Zone.OWNED
		_panels[index].cursor = 0

func _place_panels() -> void:
	var viewport := Vector2(get_viewport().get_visible_rect().size)
	for index in _panels.size():
		_panels[index].place(ShopLayout.rect_for(index, _panels.size(), viewport))

func _on_phase_changed(phase: WorldTypes.Phase) -> void:
	_set_shown(phase == WorldTypes.Phase.SHOP)
	if phase != WorldTypes.Phase.SHOP:
		return

	# Every entry into the shop starts the cursor at the top. Leaving it where
	# it was last time drops the player onto "reroll" or into the owned strip,
	# which is never where they meant to be.
	for panel in _panels:
		panel.reset_cursor()

	if _park_on_owned:
		_park_now()

func _set_shown(shown: bool) -> void:
	visible = shown
	for panel in _panels:
		# Hidden panels stop polling their input, so a stick held during the
		# shop cannot walk a character the moment combat resumes.
		panel.visible = shown

func _process(_delta: float) -> void:
	if not visible or run == null:
		return

	var waiting := _waiting_on()
	for panel in _panels:
		panel.waiting_text = waiting

## Names the players still shopping, so a panel that has already declared ready
## says who it is waiting for rather than just sitting there.
func _waiting_on() -> String:
	var names := PackedStringArray()
	for index in run.players.size():
		if run.players[index].is_alive and not run.shops[index].is_ready:
			names.append("P%d" % (index + 1))
	return "czekam: %s" % ", ".join(names) if not names.is_empty() else "startujemy"
