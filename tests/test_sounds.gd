extends TestCase
## Sound (M7.7): the sound bank names a sound for every event the game plays,
## the Sounds autoload plays them on the right bus, and the game turns what
## happens into sounds.

const EVENTS := [&"click", &"select", &"order", &"order_attack", &"denied", &"hit", &"shot", &"death",
		&"explosion", &"wreck", &"mend", &"restore", &"place", &"ready", &"trained", &"low_power", &"transform",
		&"repair", &"steal", &"message", &"victory", &"defeat", &"music_menu", &"music_mission"]
const BASE_TRIAL := "res://data/missions/base_trial_blue.tres"
const MISSION_2 := "res://data/missions/holding_the_claim_blue.tres"


func _sounds() -> SoundPlayer:
	return tree.root.get_node_or_null("Sounds") as SoundPlayer


func test_the_bank_has_every_event() -> void:
	var bank := load(SoundPlayer.BANK) as SoundBank
	check(bank != null, "the sound bank loads")
	if bank == null:
		return
	for id: StringName in EVENTS:
		var event := bank.get_event(id)
		check(event != null and not event.streams.is_empty() and event.streams.all(func(s: AudioStream) -> bool: return s != null),
				"%s has a sound" % id)
		if event != null:
			var music := String(id).begins_with("music_")
			check_eq(event.bus, &"Music" if music else &"Effects", "%s plays on the right bus" % id)
	check(bank.get_event(&"no_such_event") == null, "an unknown event has none")


func test_the_player_plays_events() -> void:
	var sounds := _sounds()
	check(sounds != null, "the Sounds autoload is loaded")
	if sounds == null:
		return
	check(sounds.play(&"steal"), "an event plays")
	check(not sounds.play(&"steal"), "but not again straight away (each event has a shortest gap)")
	check(not sounds.play(&"no_such_event"), "an unknown event does nothing")
	check_eq(sounds.played.back(), &"steal", "what played is remembered")
	sounds.play_music(&"music_menu")
	check_eq(sounds.music_playing(), &"music_menu", "music plays")
	sounds.stop_music()
	check_eq(sounds.music_playing(), &"", "and stops")


func test_production_is_heard() -> void:
	var mission := Mission.new(load(BASE_TRIAL))
	var world := mission.world
	var generator := load("res://data/buildings/blue_generator.tres") as BuildingType
	world.production.queue(Mission.PLAYER_TEAM, Production.BUILDINGS, generator)
	for i in 60 * SimWorld.TICKS_PER_SECOND:
		mission.tick()
		if world.production.ready_building(Mission.PLAYER_TEAM) != null:
			break
	check(world.effects.any(func(e: Dictionary) -> bool: return e["kind"] == &"ready"), "a finished building is announced")


func test_the_game_sounds_what_happens() -> void:
	var sounds := _sounds()
	MapView.requested_mission = MISSION_2
	var view := (load("res://scenes/map_view.tscn") as PackedScene).instantiate() as MapView
	tree.root.add_child(view)
	MapView.requested_mission = ""
	check_eq(sounds.music_playing(), &"music_mission", "a mission plays its music")
	var middle := (view.camera.get_view_rect().get_center() / MapData.CELL_SIZE).floor()
	view.world.shroud_for(Mission.PLAYER_TEAM).reveal_circle(Vector2i(middle), 3)
	view.world.effects.append({"kind": &"hit", "tick": view.world.tick_count + 1, "team": 1,
			"from": middle, "to": middle, "ranged": true})
	view.world.effects.append({"kind": &"death", "tick": view.world.tick_count + 1, "team": 1,
			"from": middle, "to": middle, "vehicle": true})
	view._listen()
	check(sounds.played.slice(-2) == ([&"shot", &"explosion"] as Array[StringName]),
			"a shot and an exploding vehicle in view are heard: %s" % [sounds.played.slice(-3)])
	var far := Vector2(view.map.get_size()) - Vector2.ONE
	view.world.effects.append({"kind": &"hit", "tick": view.world.tick_count + 2, "team": 1, "from": far, "to": far})
	var count := sounds.played.size()
	view._heard_tick = view.world.tick_count + 1
	view._listen()
	check(sounds.played.size() == count or sounds.played.back() != &"hit", "a fight out of sight is not")
	view.mission.add_message("Scout", "Test.")
	view._listen()
	check_eq(sounds.played.back(), &"message", "a mission message chimes")
	view.free()
	sounds.stop_music()
