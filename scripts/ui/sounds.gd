class_name SoundPlayer
extends Node
## Plays the game's sounds and music by event name (see SoundBank and
## data/sounds/sound_bank.tres). Loaded as the autoload "Sounds"; anything can
## call SoundPlayer.sound(&"click"). Effects go to the Effects bus, music to
## the Music bus, so the settings' volumes apply.

const BANK := "res://data/sounds/sound_bank.tres"
## How many effects can sound at once; the oldest is cut off for a new one.
const VOICES := 12
## How many recent events are remembered (for tests and debugging).
const LOG_SIZE := 64
## How long to wait between stopping every sound and quitting, in seconds.
## Godot keeps hold of a sound that was playing until its audio thread has
## let it go, and reports it as leaked if the game quits before then.
const QUIT_DELAY := 0.25

var bank: SoundBank
## The latest events played, newest last.
var played: Array[StringName] = []
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_played := {}
var _music: AudioStreamPlayer
var _music_id := &""


func _ready() -> void:
	get_tree().auto_accept_quit = false       # closing the window goes through quit_game()
	bank = load(BANK) as SoundBank
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Effects"
		add_child(voice)
		_voices.append(voice)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	_music.finished.connect(func() -> void: _music.play())       # the music loops


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


## Stop every sound and the music.
func stop_all() -> void:
	_music_id = &""
	for voice: AudioStreamPlayer in _voices + [_music]:
		voice.stop()
		voice.stream = null


## Quit the game: stop every sound, wait for the audio to let go of them
## (QUIT_DELAY), then quit.
func quit_game(exit_code := 0) -> void:
	stop_all()
	await get_tree().create_timer(QUIT_DELAY, true, false, true).timeout
	get_tree().quit(exit_code)


## Play an event, if anything is loaded for it and it did not sound too
## recently (see SoundEvent.min_gap). Returns whether it was played.
func play(id: StringName, volume_offset_db := 0.0) -> bool:
	var event := bank.get_event(id) if bank != null else null
	if event == null or event.streams.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -1000000)) < int(event.min_gap * 1000.0):
		return false
	_last_played[id] = now
	var voice := _free_voice()
	voice.stream = event.streams[randi() % event.streams.size()]
	voice.bus = event.bus
	voice.volume_db = event.volume_db + volume_offset_db
	voice.pitch_scale = 1.0 + randf_range(-event.pitch_variation, event.pitch_variation)
	voice.play()
	played.append(id)
	if played.size() > LOG_SIZE:
		played.pop_front()
	return true


func _free_voice() -> AudioStreamPlayer:
	for voice in _voices:
		if not voice.playing:
			return voice
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return voice


## Play a music event in a loop; nothing changes if it is already playing.
func play_music(id: StringName) -> void:
	if id == _music_id and _music.playing:
		return
	var event := bank.get_event(id) if bank != null else null
	if event == null or event.streams.is_empty():
		return
	_music_id = id
	_music.stream = event.streams[0]
	_music.volume_db = event.volume_db
	_music.play()


func stop_music() -> void:
	_music_id = &""
	_music.stop()


## The music event playing now, or &"".
func music_playing() -> StringName:
	return _music_id if _music.playing else &""


## The autoload, from anywhere; null if it is not loaded.
static func instance() -> SoundPlayer:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Sounds") as SoundPlayer if tree != null else null


## Play an event through the autoload, if there is one.
static func sound(id: StringName, volume_offset_db := 0.0) -> void:
	var player := instance()
	if player != null:
		player.play(id, volume_offset_db)


## Quit the game through the autoload (see quit_game()), or at once without it.
static func quit(exit_code := 0) -> void:
	var player := instance()
	if player != null:
		player.quit_game(exit_code)
	else:
		(Engine.get_main_loop() as SceneTree).quit(exit_code)


static func music(id: StringName) -> void:
	var player := instance()
	if player != null:
		if id == &"":
			player.stop_music()
		else:
			player.play_music(id)
