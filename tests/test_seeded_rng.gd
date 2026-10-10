extends TestCase


func test_same_seed_gives_same_rolls() -> void:
	var a := SeededRng.new(4821)
	var b := SeededRng.new(4821)
	for i in 20:
		check_eq(a.randi_range(0, 1000), b.randi_range(0, 1000), "roll %d differs" % i)


func test_different_seeds_diverge() -> void:
	var a := SeededRng.new(1)
	var b := SeededRng.new(2)
	var rolls_a := []
	var rolls_b := []
	for i in 10:
		rolls_a.append(a.randi_range(0, 1000000))
		rolls_b.append(b.randi_range(0, 1000000))
	check(rolls_a != rolls_b, "seeds 1 and 2 produced identical rolls")


func test_pick_from_empty_is_null() -> void:
	check_eq(SeededRng.new(7).pick([]), null, "pick([]) should return null")
