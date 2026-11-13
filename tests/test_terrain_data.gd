extends TestCase
## The terrain and biome definitions in data/.

const BIOMES := ["res://data/biomes/forest.tres", "res://data/biomes/desert.tres"]


func _ids(biome: Biome) -> Array:
	var out := []
	for t in biome.terrains:
		out.append(String(t.id))
	return out


func test_biomes_are_valid() -> void:
	for path in BIOMES:
		var biome := load(path) as Biome
		check(biome != null, "%s loads as a Biome" % path)
		if biome == null:
			continue
		check_eq(Array(biome.problems()), [], "problems in %s" % path)


func test_forest_terrains() -> void:
	var biome := load(BIOMES[0]) as Biome
	check_eq(_ids(biome), ["grass", "dirt", "stone", "water", "forest", "ore_rock"], "forest terrains in drawing order")


func test_desert_terrains() -> void:
	var biome := load(BIOMES[1]) as Biome
	check_eq(_ids(biome), ["sand", "dunes", "hardpan", "rock", "ore_rock"], "desert terrains in drawing order")


func test_only_rock_ground_is_buildable() -> void:
	var buildable := []
	for path in BIOMES:
		for t in (load(path) as Biome).terrains:
			if t.buildable:
				buildable.append(String(t.id))
	check_eq(buildable, ["stone", "rock"], "buildable terrains")


func test_only_flat_ground_is_walkable() -> void:
	# Units walk on flat ground only. Water, trees and the Orichalcum rock block them.
	var blocked := []
	var open := []
	for path in BIOMES:
		for t in (load(path) as Biome).terrains:
			if t.walkable:
				open.append(String(t.id))
			else:
				blocked.append(String(t.id))
	check_eq(blocked, ["water", "forest", "ore_rock", "ore_rock"], "impassable terrains")
	check_eq(open, ["grass", "dirt", "stone", "sand", "dunes", "hardpan", "rock"], "walkable terrains")


func test_symbol_lookup() -> void:
	var biome := load(BIOMES[0]) as Biome
	check_eq(biome.terrain_index_for_symbol("."), 0, "symbol '.'")
	check_eq(biome.terrain_index_for_symbol("w"), 3, "symbol 'w'")
	check_eq(biome.terrain_index_for_symbol("?"), -1, "unknown symbol")
	check_eq(biome.terrain_index_for_id(&"stone"), 2, "id 'stone'")
	check_eq(biome.terrain_index_for_id(&"lava"), -1, "unknown id")


func test_atlas_sizes() -> void:
	for path in BIOMES:
		var biome := load(path) as Biome
		for i in biome.terrains.size():
			var t := biome.terrains[i]
			var expected := Vector2(256, 256) if i == 0 else Vector2(2048, 512)
			check_eq(t.tiles.get_size(), expected, "%s atlas size" % t.id)
		check_eq(biome.decor.get_height(), 32, "%s decor atlas height" % biome.id)
		check_eq(biome.decor.get_width() % 32, 0, "%s decor atlas width is whole tiles" % biome.id)


func test_minimap_colours_differ() -> void:
	for path in BIOMES:
		var biome := load(path) as Biome
		var seen := {}
		for t in biome.terrains:
			check(not seen.has(t.minimap_color), "%s shares its minimap colour" % t.id)
			seen[t.minimap_color] = true
