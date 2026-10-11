#!/usr/bin/env python3
"""Turns saved run records into tidy CSV tables for spreadsheets, databases and Tableau.

Reads every run record (one JSON per file, a JSON list, or JSON lines) from the input
folder, and rewrites one CSV per table in the output folder. Rows join on run_id.
Re-running is safe: runs are de-duplicated by run_id and the tables are rebuilt.

Usage: python3 tools/export_csv.py <raw_folder> <csv_folder>

Run records come from the game's Run history (Copy / Download) and from
tools/balance_run.gd out=... (bot runs). See RunState.to_record() for the format.
"""

import csv
import json
import os
import sys

RESOURCES = ["food", "fuel", "wood", "stone", "shells", "flint", "hides", "bone", "obsidian",
             "copper", "cassiterite", "tin", "bronze"]
ROLES = ["tribesperson", "warrior", "craftsperson"]


def load_records(folder):
    runs = {}
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if not name.endswith((".json", ".jsonl")):
            continue
        with open(path, encoding="utf-8") as f:
            text = f.read().strip()
        if not text:
            continue
        if name.endswith(".jsonl"):
            items = [json.loads(line) for line in text.splitlines() if line.strip()]
        else:
            data = json.loads(text)
            items = data if isinstance(data, list) else [data]
        for record in items:
            run_id = str(record.get("id") or "%s-%s" % (record.get("player", "unknown"), int(record.get("seed", 0))))
            record["_run_id"] = run_id
            record["_source_file"] = name
            runs[run_id] = record
    return list(runs.values())


def n(value):
    """Whole numbers come back from JSON as floats (12.0); write them as 12."""
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def write(folder, table, columns, rows):
    path = os.path.join(folder, table + ".csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: n(row.get(k, "")) for k in columns})
    return len(rows)


def main(raw_folder, out_folder):
    os.makedirs(out_folder, exist_ok=True)
    records = load_records(raw_folder)
    tables = {name: [] for name in
              ["runs", "rounds", "picks", "builds", "wave_enemies", "deaths", "nights", "relic_offers", "heroes",
               "loot", "whims", "market_sales", "crafted", "promotions"]}

    for r in records:
        rid = r["_run_id"]
        player = str(r.get("player", "unknown"))
        rounds = r.get("rounds", [])
        all_deaths = [d for rd in rounds for d in rd.get("deaths", [])]
        tables["runs"].append({
            "run_id": rid, "player": player, "player_kind": player.split(":")[0],
            "bot_style": player.split(":")[1] if ":" in player else "",
            "game_version": r.get("game_version", ""), "record_format": r.get("format", ""),
            "seed": r.get("seed", ""), "saved_at": r.get("saved_at", ""), "result": r.get("result", ""),
            "won": 1 if r.get("result") == "won" else 0,
            "round_reached": r.get("round_reached", ""), "rounds_to_win": r.get("rounds_to_win", ""),
            "hearth_hp_end": r.get("keep_hp", ""), "townsfolk_lost": r.get("townsfolk_lost", ""),
            "heroes_lost": len(r.get("fallen", [])), "heroes_alive_end": len(r.get("heroes", [])),
            "townsfolk_end": sum(r.get("townsfolk", {}).values()),
            "relics_taken": len(r.get("relics", [])), "buildings_total": len(r.get("buildings", [])),
            "huts": r.get("buildings", []).count("hut"),
            "watch_posts": r.get("buildings", []).count("watch_post"),
            "deaths_total": len(all_deaths), "source_file": r["_source_file"],
            "age_end": r.get("age", "neolithic"), "age_up_round": r.get("age_up_round", 0),
            "tools": "+".join(r.get("tools", [])), "heroes_departed": len(r.get("departed", [])),
            "promotions": sum(len(rd.get("promotions", [])) for rd in rounds),
            **{"stock_end_" + k: r.get("stock", {}).get(k, "") for k in RESOURCES},
        })
        for h in r.get("heroes", []) + r.get("fallen", []):
            tables["heroes"].append({"run_id": rid, "items": len(h.get("items", [])), **{k: h.get(k, "") for k in
                                     ["name", "class", "trait", "level", "kills", "alive", "weapon", "armor", "charm",
                                      "gold", "max_hp", "energy", "lodging", "mood"]},
                                     "departed": 0})
        for h in r.get("departed", []):
            tables["heroes"].append({"run_id": rid, "items": len(h.get("items", [])), "departed": 1, **{k: h.get(k, "") for k in
                                     ["name", "class", "trait", "level", "kills", "alive", "weapon", "armor", "charm",
                                      "gold", "max_hp", "energy", "lodging", "mood"]}})

        for rd in rounds:
            rn = rd.get("round", "")
            battle = rd.get("battle", {})
            deaths = rd.get("deaths", [])
            wave = rd.get("wave", {})
            folk_start = rd.get("townsfolk_start", {})
            folk_end = rd.get("townsfolk_end", {})
            tables["rounds"].append({
                "run_id": rid, "round": rn, "wave_size": sum(wave.values()),
                "wave_sides": "+".join(rd.get("wave_sides", [])), "wave_side_count": len(rd.get("wave_sides", [])),
                "hearth_hp_start": rd.get("keep_hp_start", ""), "hearth_damage": battle.get("keep_damage", ""),
                "hearth_hp_after": battle.get("keep_hp_after", ""), "wave_seconds": battle.get("seconds", ""),
                "hero_retreats": battle.get("retreats", ""),
                "hero_deaths": sum(1 for d in deaths if d.get("hero")),
                "townsfolk_deaths": sum(1 for d in deaths if not d.get("hero")),
                "heroes_start": rd.get("heroes_start", ""),
                "townsfolk_start": sum(folk_start.values()), "townsfolk_end": sum(folk_end.values()) if folk_end else "",
                "buildings_ordered": sum(1 for a in rd.get("actions", []) if a.get("kind", "build") == "build"),
                "left_hungry": rd.get("left_hungry", 0),
                "roads_staked": sum(1 for a in rd.get("actions", []) if a.get("kind") == "road"),
                "staked_squares": rd.get("town", {}).get("staked", ""),
                "trail_squares": rd.get("town", {}).get("trails", ""),
                "paving_stone": rd.get("paving", {}).get("stone", 0),
                **{"paved_" + k: rd.get("town", {}).get("paved", {}).get(k, 0) for k in ["stone_path", "cobbled_road"]},
                "relic_pick": rd.get("relic_pick", ""),
                "loot_found": len(rd.get("loot", [])),
                "loot_worn": sum(1 for i in rd.get("loot", []) if i.get("equipped")),
                "items_sold": len(rd.get("sales", [])),
                "sales_town_cut": sum(s.get("town_cut", 0) for s in rd.get("sales", [])),
                "hero_spending_lodging": rd.get("hero_spending", {}).get("tavern", 0),
                "hero_spending_carousing": rd.get("hero_spending", {}).get("carousing", 0),
                "market_goods_sold": len(rd.get("market", [])),
                "market_shells": sum(m.get("price", 0) for m in rd.get("market", [])),
                "goods_crafted": sum(rd.get("crafted", {}).values()),
                "prize_shells": rd.get("prizes", 0), "obsidian_bought": rd.get("obsidian", 0),
                "age": rd.get("age", "neolithic"), "cassiterite_bought": rd.get("cassiterite", 0),
                "promotions": len(rd.get("promotions", [])), "heroes_left_unhappy": len(rd.get("heroes_left", [])),
                **{"traded_" + k: rd.get("trades", {}).get(k, 0) for k in ["tin", "cassiterite"]},
                **{"yield_" + k: rd.get("yields", {}).get(k, 0) for k in ["hides", "bone"]},
                **{"price_" + k: rd.get("prices", {}).get(k, "") for k in ["arms", "hides", "charms", "provisions"]},
                "survived": 1 if "relic_pick" in rd or (r.get("result") == "won" and rn == r.get("round_reached")) else 0,
                **{"start_" + k: folk_start.get(k, 0) for k in ROLES},
                **{"stock_start_" + k: rd.get("stock_start", {}).get(k, "") for k in RESOURCES},
                **{"stock_end_" + k: rd.get("stock_end", {}).get(k, "") for k in RESOURCES},
            })
            for p in rd.get("picks", []):
                offered = p.get("offered", [])
                taken = p.get("taken", "")
                tables["picks"].append({
                    "run_id": rid, "round": rn, "day": p.get("day", ""),
                    "offered_1": offered[0] if len(offered) > 0 else "",
                    "offered_2": offered[1] if len(offered) > 1 else "",
                    "offered_3": offered[2] if len(offered) > 2 else "",
                    "hero_offered": 1 if any(o.startswith("hero:") for o in offered) else 0,
                    "taken": taken or "(skipped)", "taken_kind": "hero" if taken.startswith("hero:") else ("none" if not taken else "townsfolk"),
                })
            for a in rd.get("actions", []):
                if a.get("kind", "build") not in ("build", "price"):
                    continue
                tables["builds"].append({"run_id": rid, "round": rn, "building": a.get("building", a.get("kind", ""))})
            for enemy, count in wave.items():
                tables["wave_enemies"].append({"run_id": rid, "round": rn, "enemy": enemy, "count": count})
            for d in deaths:
                tables["deaths"].append({
                    "run_id": rid, "round": rn, "day": d.get("day", ""), "at_night": 1 if d.get("night") else 0,
                    "name": d.get("name", ""), "role": d.get("role", ""), "is_hero": 1 if d.get("hero") else 0,
                    "killer": d.get("killer") or "unknown",
                })
            for night in rd.get("nights", []):
                tables["nights"].append({
                    "run_id": rid, "round": rn, "night": night.get("night", ""), "raiders": night.get("raiders", ""),
                    "kills": night.get("kills", ""), "hearth_damage": night.get("hearth_damage", ""),
                    "deaths": len(night.get("deaths", [])),
                    "left_hungry": len(night.get("left", [])) - len(night.get("heroes_left", [])),
                    "left_unhappy": len(night.get("heroes_left", [])), "cold": 1 if night.get("cold") else 0,
                    "wave_night": 1 if night.get("night") == 3 else 0,
                })
            for item in rd.get("loot", []):
                tables["loot"].append({
                    "run_id": rid, "round": rn, "day": item.get("day", ""), "hero": item.get("hero", ""),
                    "trait": item.get("trait", ""), "base": item.get("base", ""), "slot": item.get("slot", ""),
                    "tier": item.get("tier", ""), "affixes": "+".join(item.get("affixes", [])),
                    "value": item.get("value", ""), "worn": 1 if item.get("equipped") else 0,
                })
            for m in rd.get("market", []):
                tables["market_sales"].append({"run_id": rid, "round": rn, **{k: m.get(k, "") for k in
                                               ["day", "hero", "trait", "recipe", "tier", "price", "stall"]}})
            for pr in rd.get("promotions", []):
                tables["promotions"].append({"run_id": rid, "round": rn, **{k: pr.get(k, "") for k in
                                             ["day", "role", "name", "became", "trait", "joined_round"]}})
            for recipe, count in rd.get("crafted", {}).items():
                tables["crafted"].append({"run_id": rid, "round": rn, "recipe": recipe, "count": count})
            for w in rd.get("whims", []):
                tables["whims"].append({"run_id": rid, "round": rn, "day": w.get("day", ""),
                                        "hero": w.get("hero", ""), "whim": w.get("whim", "")})
            for relic in rd.get("relic_offer", []):
                tables["relic_offers"].append({"run_id": rid, "round": rn, "relic": relic,
                                               "picked": 1 if rd.get("relic_pick") == relic else 0})

    columns = {
        "runs": list(tables["runs"][0].keys()) if tables["runs"] else ["run_id"],
        "rounds": list(tables["rounds"][0].keys()) if tables["rounds"] else ["run_id"],
        "picks": ["run_id", "round", "day", "offered_1", "offered_2", "offered_3", "hero_offered", "taken", "taken_kind"],
        "builds": ["run_id", "round", "building"],
        "wave_enemies": ["run_id", "round", "enemy", "count"],
        "deaths": ["run_id", "round", "day", "at_night", "name", "role", "is_hero", "killer"],
        "nights": ["run_id", "round", "night", "raiders", "kills", "hearth_damage", "deaths", "left_hungry", "left_unhappy", "cold",
                   "wave_night"],
        "relic_offers": ["run_id", "round", "relic", "picked"],
        "heroes": ["run_id", "name", "class", "trait", "level", "kills", "alive", "weapon", "armor", "charm", "items",
                   "gold", "max_hp", "energy", "lodging", "mood", "departed"],
        "loot": ["run_id", "round", "day", "hero", "trait", "base", "slot", "tier", "affixes", "value", "worn"],
        "whims": ["run_id", "round", "day", "hero", "whim"],
        "market_sales": ["run_id", "round", "day", "hero", "trait", "recipe", "tier", "price", "stall"],
        "crafted": ["run_id", "round", "recipe", "count"],
        "promotions": ["run_id", "round", "day", "role", "name", "became", "trait", "joined_round"],
    }
    for table, rows in tables.items():
        count = write(out_folder, table, columns[table], rows)
        print("%-13s %6d rows" % (table, count))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
