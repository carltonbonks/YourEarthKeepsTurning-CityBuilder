class_name AutoPlayer
extends RefCounted
## A simple scripted player for headless balance runs and tests.
## It stands in for a human making decisions so we can simulate many runs fast.

## "bounty": 10g on the toughest enemy type; "shaman": 10g on shamans; "common": 5g on the most numerous type;
## "none": never posts bounties.
var bounty_style := "bounty"


func play_run(run: RunState) -> void:
	while not run.is_over():
		decide(run)
		var battle := run.start_battle()
		battle.run_to_end()
		run.finish_battle(battle)
		if run.phase == RunState.Phase.RELIC:
			run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")


func decide(run: RunState) -> void:
	if run.keep_hp < run.keep_max_hp() * 0.5:
		run.repair_keep()
	if run.round_number <= 2:
		run.build_market()
	while run.heroes.size() < 5 and run.recruit():
		pass
	if bounty_style == "shaman" and run.wave_counts().has("shaman"):
		run.set_bounty("shaman", 10)
	if bounty_style == "common":
		var counts := run.wave_counts()
		var most := ""
		for id: String in counts:
			if most == "" or counts[id] > counts[most]:
				most = id
		run.set_bounty(most, 5)
	if bounty_style == "bounty":
		var worst := ""
		var worst_hp := 0.0
		for id: String in run.wave_counts():
			var hp := float(run.content.enemies[id]["hp"])
			if hp > worst_hp:
				worst_hp = hp
				worst = id
		var amount := 10
		while amount > 0 and not run.set_bounty(worst, amount):
			amount -= run.content.int_num("bounty_step")
