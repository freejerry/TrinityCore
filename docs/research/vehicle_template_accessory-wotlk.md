# vehicle_template_accessory: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the intended WotLK set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 427, world_335 (3.3.5a) = 202
- **Difference pattern:** 343_superset
- **Structure:** Schema byte-identical between world_d and world_335: (entry, accessory_entry, seat_id, minion, description, summontext[summontype], summontimer), PK(entry, seat_id), no RideSpellID column. Note: the wotlk_classic core loader (src/server/game/Globals/ObjectMgr.cpp:3205) SELECTs an extra `RideSpellID` column that neither raw DB has — a 3.4.3-core schema evolution that the target world_c schema must carry; it is orthogonal to this content-set task, which operates on world_d's actual columns. Column `description` is a comment field never read by the core.

## Difference

Purely additive both directions, zero value diffs on shared keys. 198 (entry,seat_id) rows are shared and byte-identical. world_d (343) adds 229 net-new keys absent from 335. world_335 has 4 keys absent from 343 (36794/0, 39759/0, 39819/0, 39860/0). 198 shared + 229 = 427 (343); 198 + 4 = 202 (335).

## Correct WotLK dataset

The exact 202-row set present in world_335. This equals world_d's shared 198 rows plus the 4 WotLK rows 343 dropped (Scourgelord Tyrannus / Pit of Saron; and the Operation: Gnomeregan Tankbuster Cannon, Irradiated Mechano-Tank, Gnomeregan Mechano-Tank), and EXCLUDES the 229 post-WotLK accessory rows 343 added.

## Dead values / contamination

Contamination: the 229 net-new 343 rows are post-WotLK content that 3.3.5a never had — Cataclysm (Twilight Highlands: Twilight Rider/Buzzard/Stormwaker/Firebird 34282/39833/39839/40650, Deathwing 49841/51033/51148, Wildhammer Gryphons 45881/46088/47186; goblin Kezan/Lost Isles: Sassy Hardwrench 38918/38929, Kezan Citizen 38526, KTC Waiter/Waitress 48719/48721/48805/48806; Operation Gnomeregan Cata rebuild 39039/43259; Occu'thar Baradin Hold 52363), MoP (Grand Expedition Yak 62809, Hozen 56739/154765), Legion (Valarjar/Storm Drake 97068/99804/101638, Garothi Worldbreaker/Antorus 122450, Guarm/Trial of Valor 114323, Runecarver 101013), BfA/Shadowlands (Sylvanas Shadowcopy 175732), Dragonflight (Kyrakka 199790). All must be dropped. No dead/negative sentinel values present.

## Proposed delta (vs raw TDB343)

```sql
-- Remove the 229 post-WotLK accessory rows 343 added (keys not present in the WotLK reference),
-- then re-add the 4 WotLK rows 343 dropped. Result == world_335's 202-row set.
DELETE `d` FROM `vehicle_template_accessory` `d`
LEFT JOIN `world_335`.`vehicle_template_accessory` `s`
  ON `d`.`entry` = `s`.`entry` AND `d`.`seat_id` = `s`.`seat_id`
WHERE `s`.`entry` IS NULL;

INSERT INTO `vehicle_template_accessory`
  (`entry`,`accessory_entry`,`seat_id`,`minion`,`description`,`summontype`,`summontimer`)
VALUES
  (36794,36658,0,1,'Scourgelord Tyrannus on Scourgelord Tyrannus',6,300),
  (39759,39755,0,1,'Tankbuster Cannon - Irradiated Infantry',7,0),
  (39819,39755,0,1,'Irradiated Mechano-Tank - Irradiated Infantry',7,0),
  (39860,39264,0,1,'Gnomeregan Mechano-Tank - Gnomeregan Mechano-Tank Pilot',7,0);
```

## Evidence

- **Schema identical in both DBs (entry,accessory_entry,seat_id,minion,description,summontype,summontimer; PK entry,seat_id; no RideSpellID)**  
  — SHOW CREATE TABLE vehicle_template_accessory in world_d and world_335 — identical output
- **Row counts: 343=427, 335=202**  
  — SELECT COUNT(*) on both DBs
- **Difference is purely additive: 229 rows in 343 not in 335, 4 rows in 335 not in 343, and every one of those 229 is a net-new (entry,seat_id) key (LEFT JOIN world_335 -> NULL for all 229); zero value diffs on the 198 shared keys**  
  — EXCEPT both directions + JOIN on shared keys returning empty value-diff set + LEFT JOIN COUNT=229
- **The 4 335-only rows are entirely absent from 343 (not value diffs): d.accessory_entry NULL in LEFT JOIN**  
  — LEFT JOIN world_335 s -> world_d d on (entry,seat_id): all 4 rows show d_acc NULL
- **36794 Scourgelord Tyrannus is a WotLK Pit of Saron 3.3 boss (level 82)**  
  — world_335.creature_template entry 36794 name='Scourgelord Tyrannus' minlevel=maxlevel=82
- **39759/39819/39860 are Operation: Gnomeregan level-80 content in the 3.3.5a-era reference (Tankbuster Cannon, Irradiated Mechano-Tank, Gnomeregan Mechano-Tank), riding Irradiated Infantry 39755 / Gnomeregan Mechano-Tank Pilot 39264**  
  — world_335.creature_template entries 39759/39819/39860/39755/39264, all level 80
- **229 net-new 343 rows are post-WotLK by name/expansion: Deathwing 49841/51033/51148, Twilight Highlands Wildhammer 45881/47186, Kezan goblin KTC Waiter 48719, MoP Grand Expedition Yak 62809, Legion Garothi Worldbreaker 122450/Guarm 114323, Dragonflight Kyrakka 199790**  
  — SELECT entry,description ORDER BY entry on the 229 net-new-343 rows (descriptions)
- **Core reads the table but never uses `description`; it validates entry/accessory/rideSpell and requires npc_spellclick_spells**  
  — src/server/game/Globals/ObjectMgr.cpp:3205-3250

---
_Generated from C-layer research workflow (batch 2), run wf_f9c949d0-e24._
