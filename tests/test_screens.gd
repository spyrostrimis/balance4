extends TestCase
## The screens around a mission (M7.5): the title screen's pages, the
## briefing, the debriefing, and the settings, saved between runs.

const MISSION_1 := "res://data/missions/first_claim_blue.tres"
const MISSION_1_RED := "res://data/missions/first_claim_red.tres"
const MISSION_2 := "res://data/missions/holding_the_claim_blue.tres"
const STORY := [MISSION_1, MISSION_1_RED, MISSION_2]
const MAP_SCENE := "res://scenes/map_view.tscn"
const TEST_FILE := "user://test_settings_round_trip.cfg"


func test_settings_are_kept_between_runs() -> void:
	var settings := GameSettings.new()
	settings.path = TEST_FILE
	settings.master = 0.3
	settings.music = 0.0
	settings.effects = 1.0
	settings.scroll_speed = 1.5
	settings.fullscreen = false
	settings.save_settings()
	var next_run := GameSettings.new()
	next_run.path = TEST_FILE
	next_run.load_settings()
	check_eq([next_run.master, next_run.music, next_run.effects, next_run.scroll_speed, next_run.fullscreen],
			[0.3, 0.0, 1.0, 1.5, false], "the next run reads back every setting")
	check_eq(next_run.scroll_pixels_per_second(), 720.0, "1.5 times the usual scroll speed")
	var broken := ConfigFile.new()
	broken.set_value("controls", "scroll_speed", 99.0)
	broken.set_value("audio", "master", -4.0)
	broken.save(TEST_FILE)
	next_run.load_settings()
	check_eq([next_run.scroll_speed, next_run.master], [GameSettings.SCROLL_MAX, 0.0], "values out of range are kept in range")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))
	settings.free()
	next_run.free()


func test_volumes_drive_the_audio_buses() -> void:
	for bus: String in ["Master", "Music", "Effects"]:
		check(AudioServer.get_bus_index(bus) >= 0, "there is a %s bus" % bus)
	var settings := tree.root.get_node_or_null("Settings") as GameSettings
	check(settings != null, "the settings are loaded as an autoload")
	if settings == null:
		return
	var music := AudioServer.get_bus_index("Music")
	settings.music = 0.0
	settings.apply_volume("music")
	check(AudioServer.is_bus_mute(music), "music at 0 mutes the music bus")
	settings.music = 0.5
	settings.apply_volume("music")
	check(not AudioServer.is_bus_mute(music) and is_equal_approx(AudioServer.get_bus_volume_db(music), linear_to_db(0.5)),
			"and at half it plays at half")
	settings.use_defaults()
	settings.apply()


func test_title_screen_pages() -> void:
	var title := (load("res://scenes/main.tscn") as PackedScene).instantiate() as TitleScreen
	tree.root.add_child(title)
	check_eq(title.current_page(), "main", "the title screen opens on Play, Practice, Settings and Quit")
	title.show_page("play")
	check_eq(title.current_page(), "play", "Play lists the story missions")
	for key: String in TitleScreen.STORY:
		check(title.mission_button(key) != null and title.mission_button(key).is_visible_in_tree(), "with a button for %s" % key)
	check_eq(TitleScreen.mission_label("mission-2"), "Mission 2: Holding the Claim  (Blue)", "named after the mission")
	check_eq(TitleScreen.mission_label("raid-desert"), "Raid trial  (Red, desert)", "a trial says its side and map")
	title.show_page("practice")
	for key: String in TitleScreen.PRACTICE:
		check(title.mission_button(key) != null and title.mission_button(key).is_visible_in_tree(), "Practice has %s" % key)
	title.show_page("settings")
	check(title._settings.visible, "Settings shows the settings")
	title._settings.close()
	check_eq(title.current_page(), "main", "and Back returns to the main page")
	title.free()


func test_briefing() -> void:
	for path: String in STORY:
		var def := load(path) as MissionDef
		check(def.briefing != "" and def.debriefing_won != "" and def.debriefing_lost != "",
				"%s has a briefing and both debriefings" % def.id)
	var mission_1 := load(MISSION_1) as MissionDef
	check_eq(mission_1.next_mission, MISSION_2, "Mission 1 as Blue leads on to Mission 2")
	MapView.requested_mission = MISSION_2
	var briefing := (load(BriefingScreen.SCENE) as PackedScene).instantiate() as BriefingScreen
	tree.root.add_child(briefing)
	MapView.requested_mission = ""
	check(briefing.def != null and briefing.def.id == &"holding_the_claim_blue", "the briefing shows the requested mission")
	var lines := BriefingScreen.objective_lines(briefing.def)
	check_eq(lines.size(), 2, "with the two objectives the player starts with, not the hidden ones")
	check(lines[1].begins_with("Bring the Prince"), "the first task: %s" % lines[1])
	check_eq(BriefingScreen.start_cell(briefing.def), Vector2i(4, 44), "and marks where Blue starts")
	briefing.free()


func _view(path: String) -> MapView:
	MapView.requested_mission = path
	var view := (load(MAP_SCENE) as PackedScene).instantiate() as MapView
	tree.root.add_child(view)
	MapView.requested_mission = ""
	return view


func test_debriefing() -> void:
	var view := _view(MISSION_1)
	view.mission.finish(Mission.PLAYER_TEAM, &"hold")
	view._process(0.05)
	check(view.hud.is_result_shown(), "a won mission ends in the debriefing")
	check(view.hud._result_story.text.begins_with("The rock is ours"), "which tells the story's next step")
	check(view.hud.result_text_shown().contains("You held the Orichalcum rock"), "how it was won")
	check(view.hud._next.visible, "and offers the next mission")
	check(view.hud._result_rows.size() >= 2, "it lists the objectives")
	view.free()
	view = _view(MISSION_1)
	view.mission.finish(Mission.ENEMY_TEAM, &"hold")
	view._process(0.05)
	check(view.hud._result_story.text.begins_with("Red holds the rock"), "a lost mission says what was lost")
	check(not view.hud._next.visible, "and has no next mission")
	view.free()


func test_settings_from_the_pause_menu() -> void:
	var view := _view(MISSION_2)
	view.set_paused(true)
	view.hud.show_settings()
	check(view.hud.is_settings_shown(), "the pause menu opens the settings")
	view.set_paused(false)
	check(not view.hud.is_settings_shown(), "carrying on closes them")
	check_eq(view.camera.scroll_speed, GameSettings.BASE_SCROLL_SPEED, "the camera scrolls at the set speed")
	view.free()
