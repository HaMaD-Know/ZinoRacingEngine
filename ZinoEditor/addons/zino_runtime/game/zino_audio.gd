class_name ZinoAudio
extends Node
## Game audio: mixer buses (Music, SFX, Engine), sound/music playback from project files, and a
## procedural engine voice per vehicle driven by RPM and throttle plus tyre squeal from wheel slip.
## No audio files are required for engines; custom samples can be layered via the Audio Studio.

const BUSES := ["Music", "SFX", "Engine"]
const MIX_RATE := 22050.0

var project_root := "res://"           # absolute project path in the editor, res:// in exports
var engine_enabled := true
var tires_enabled := true
var settings := {"masterVolume": 1.0, "musicVolume": 0.8, "sfxVolume": 0.9, "engineVolume": 0.8, "engineCylinders": 6, "engineCharacter": 0.5}
var _music: AudioStreamPlayer
var _voices := {}                      # vehicle -> {player, playback, phase, sub_phase, squeal}
var _sfx: Array[AudioStreamPlayer] = []

func _ready() -> void:
	ensure_buses()
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	apply_volumes()

static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")

func apply_volumes() -> void:
	set_volume("Master", float(settings.masterVolume) * 100.0)
	set_volume("Music", float(settings.musicVolume) * 100.0)
	set_volume("SFX", float(settings.sfxVolume) * 100.0)
	set_volume("Engine", float(settings.engineVolume) * 100.0)

func set_volume(bus: String, percent: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(clampf(percent / 100.0, 0.0, 2.0)))

## Loads an audio file (ogg, wav, mp3) from the project. Returns null with a reason on failure.
func load_stream(rel_path: String) -> Dictionary:
	var p := rel_path.replace("\\", "/")
	if p.contains("..") or p.begins_with("/") or p.contains(":"):
		return {"error": "sound paths must be inside the project"}
	var full := project_root.path_join(p)
	# Exported games: audio is a Godot-imported resource (the raw file is not packaged).
	if project_root.begins_with("res://") and ResourceLoader.exists(full):
		var res := load(full) as AudioStream
		return {"stream": res} if res else {"error": "could not load " + p}
	if not FileAccess.file_exists(full):
		return {"error": "sound not found: " + p}
	var stream: AudioStream
	match p.get_extension().to_lower():
		"ogg": stream = AudioStreamOggVorbis.load_from_file(full)
		"wav": stream = AudioStreamWAV.load_from_file(full)
		"mp3": stream = AudioStreamMP3.load_from_file(full)
		_: return {"error": "unsupported sound format: " + p.get_extension()}
	if stream == null:
		return {"error": "could not decode " + p}
	return {"stream": stream}

func play_sound(rel_path: String) -> String:
	var r := load_stream(rel_path)
	if r.has("error"):
		return r.error
	var pl := AudioStreamPlayer.new()
	pl.bus = "SFX"
	pl.stream = r.stream
	add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()
	_sfx.append(pl)
	return ""

func play_music(rel_path: String, loop: bool) -> String:
	var r := load_stream(rel_path)
	if r.has("error"):
		return r.error
	var s: AudioStream = r.stream
	if s is AudioStreamOggVorbis or s is AudioStreamMP3:
		s.loop = loop
	elif s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	_music.stream = s
	_music.play()
	return ""

func stop_music() -> void:
	_music.stop()

func stop_all() -> void:
	_music.stop()
	for p in _sfx:
		if is_instance_valid(p):
			p.queue_free()
	_sfx.clear()

# --- Procedural engine and tyres ----------------------------------------------------------

func attach_vehicle(v: ZinoVehicle) -> void:
	if _voices.has(v):
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	var pl := AudioStreamPlayer3D.new()
	pl.stream = gen
	pl.bus = "Engine"
	pl.unit_size = 12.0
	pl.max_distance = 300.0
	v.add_child(pl)
	pl.play()
	_voices[v] = {"player": pl, "playback": pl.get_stream_playback(), "phase": 0.0, "sub": 0.0, "noise": 0.0, "rpm": 900.0}

func _process(_delta: float) -> void:
	for v in _voices.keys():
		if not is_instance_valid(v):
			_voices.erase(v)
			continue
		_fill(v, _voices[v])

func _fill(v: ZinoVehicle, voice: Dictionary) -> void:
	var pb: AudioStreamGeneratorPlayback = voice.playback
	if pb == null:
		return
	var frames := pb.get_frames_available()
	if frames <= 0:
		return
	var target_rpm := v.rpm
	var load := clampf(v.throttle, 0.0, 1.0)
	var slip := 0.0
	if tires_enabled:
		for w in v.wheels():
			if w.is_in_contact():
				slip = maxf(slip, 1.0 - clampf(w.get_skidinfo(), 0.0, 1.0))
		if v.speed_kmh < 8.0:
			slip = 0.0
	pb.push_buffer(render(voice, target_rpm, load, slip, settings, frames, engine_enabled))

## Synthesises `frames` stereo samples of engine + tyre sound. `voice` keeps phase state between calls.
static func render(voice: Dictionary, target_rpm: float, load: float, slip: float, settings: Dictionary, frames: int, engine_on: bool = true) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	var cyl := float(settings.get("engineCylinders", 6))
	var character := float(settings.get("engineCharacter", 0.5))
	var vol_engine := (0.25 + 0.55 * load) if engine_on else 0.0
	var vol_squeal := clampf((slip - 0.25) * 1.6, 0.0, 0.6)
	for i in frames:
		voice.rpm = lerpf(voice.rpm, target_rpm, 0.0025)
		var firing: float = voice.rpm / 60.0 * cyl * 0.5        # combustion pulses per second
		voice.phase = fmod(voice.phase + firing / MIX_RATE, 1.0)
		voice.sub = fmod(voice.sub + firing * 0.5 / MIX_RATE, 1.0)
		var saw: float = voice.phase * 2.0 - 1.0
		var pulse: float = 1.0 if voice.phase < 0.3 + 0.2 * character else -1.0
		var sub: float = sin(voice.sub * TAU)
		voice.noise = lerpf(voice.noise, randf_range(-1.0, 1.0), 0.35)
		var s: float = (saw * 0.35 + pulse * 0.25 * character + sub * 0.4 + voice.noise * 0.08 * load) * vol_engine
		if vol_squeal > 0.0:
			s += sin(voice.phase * TAU * 7.0 + voice.noise * 3.0) * 0.15 * vol_squeal + randf_range(-1.0, 1.0) * 0.12 * vol_squeal
		s = clampf(s * 0.5, -1.0, 1.0)
		out[i] = Vector2(s, s)
	return out
