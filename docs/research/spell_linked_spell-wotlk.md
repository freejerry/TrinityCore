# spell_linked_spell: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** Constructed (confidence: high). Final update: sql/updates/world/wotlk_classic/2026_09_13_*_world.sql (self-contained literal), verified to reproduce world_c on raw TDB343 and to load with 0 DBErrors on the 3.4.3 client.

- **Rows:** world_d (raw TDB343) = 336, world_335 = 350
- **Difference pattern:** partial_overlap
- **Structure:** Schema is byte-identical in world_d (TDB343) and world_335: columns spell_trigger int(11), spell_effect int(11), type tinyint unsigned, comment mediumtext, UNIQUE KEY (spell_trigger,spell_effect,type). No column-semantics change. Only content differs.

## Difference

Partial overlap. 106 rows exist only in 335 (all WotLK content: ICC Putricide 72838/70530 and Blood-Queen 71473/70871, Holy Nova ranks, Arcane Missiles ranks, Consume Shadows, Shadow Embrace, Improved Moonkin, Dispersion, ToC Light/Dark essence 67176-67224, Gunship Paralytic Toxin 67618-67623, Magic Rooster 65917, Ardent Defender 66235, Drums of the Wild 69381 — genuine 3.3.5a rows TDB343 dropped). 92 rows exist only in world_d; the large majority are legitimate WotLK-era rows (Worg Disguise, Isle of Conquest 66548-66551, holiday/quest scripts, Bronjahm 68839, Void Shift 54343) that 3.3.5a simply predates — those are kept. 16 of the 343-only rows are post-WotLK contamination (see dead_or_contaminated). No key-collision rows (no shared trigger/effect/type with differing comment), so the two sides' unique rows are cleanly separable. Note the pair -33896/-33897 'Desperate Defense' (335) vs 33896/33897 (343) — sign flip, both kept as distinct keys.

## Correct WotLK dataset

The WotLK-correct set = the shared rows + all 106 335-only WotLK rows re-added + the WotLK-era 343-only rows kept, MINUS the 16 post-WotLK (Cata/MoP/WoD/Shadowlands) rows TDB343 accreted. Concretely, applied to raw TDB343 (world_d): DELETE 16 contaminated rows and INSERT the 106 missing 3.3.5a rows, yielding 336 - 16 + 106 = 426 rows.

## Dead values / contamination

16 post-WotLK rows in world_d (identified by expansion-specific mechanics/spell ids, all beyond 3.3.5a): Focus-resource hunter rows 56641->77443 'Steady Shot Focus' and 77767->91954 'Cobra Shot Focus' (Focus = Cataclysm); 73325->92833 'Priest - Leap of Faith' (Cata spell); 106877->106871 'Sha Spike' and 147647->147648 'Grasp of Y'Shaarj' and 147640->147644 'Charge - Reaper' (MoP); 108212->137681 'Burst of Speed - Rogue Talent' and 137005->89832 'Death Strike Enabler' (MoP); 165961->126056 'Stag Form' (WoD travel form); 190319->-383637 'Combustion / Fiery Rush' (383637 is Legion/DF); 310143->-342783 'Soulshape / Crystallized Dreams' and 324867->-345673 & 324867->-342662 'Fleshcraft' (Shadowlands covenant abilities); and the Echo Isles troll intro pair -93342->71037 'Zuni Lvl 1 Trigger' & 71035->93342 'Troll Introduction' plus -92237->92237 'Tarindrella Guardian Aura' (worgen/troll revamp = Cataclysm; effect ids 92237/92833/93342 are Cata-range).

## Evidence

- **Schema for spell_linked_spell is byte-identical in world_d and world_335 (spell_trigger int11, spell_effect int11, type tinyint, comment mediumtext, UNIQUE(trigger,effect,type)).**  
  — docker SHOW CREATE TABLE spell_linked_spell in world_d and world_335 — identical output
- **world_d has 336 rows, world_335 has 350; 106 rows are 335-only and 92 rows are 343-only (partial overlap, no shared-key comment collisions).**  
  — docker COUNT(*) + bidirectional (SELECT*) EXCEPT (SELECT*) + JOIN-on-key WHERE comment<>comment (empty)
- **The core loader validates every trigger and effect spell id via GetSpellInfo and skips+logs (sql.sql) rows whose spell does not exist on the running client, so 3.4.3-invalid re-added rows are self-pruning at load.**  
  — src/server/game/Spells/SpellMgr.cpp:2201-2264 (LoadSpellLinked; TC_LOG_ERROR 'does not exist' at 2220/2236)
- **335-only rows are all authentic WotLK content: ICC Putricide Volatile Ooze (72838/70530), Blood-Queen Lana'thel (70871/72648/72650/71481-71483), ToC Faction Champions Light/Dark essence (67176-67224), Gunship Paralytic Toxin (67618-67623), Magic Rooster (65917) — all 3.3.5a-era encounters/items.**  
  — world_335 EXCEPT world_d dump; ICC/ToC encounter spells documented at warcraft.wiki.gg / wowhead (Wrath 3.3/3.2 content)
- **16 world_d rows are post-WotLK: Focus resource (Steady/Cobra Shot Focus) is a Cataclysm hunter mechanic; Leap of Faith (Priest) added in Cataclysm; Sha Spike and Grasp of Y'Shaarj are Mists of Pandaria; Stag Form travel-form split is Warlords of Draenor; Soulshape/Fleshcraft (310143/324867) are Shadowlands covenant abilities; effect id 383637 is Legion/Dragonflight range.**  
  — comment text in world_d 343-only dump matched to WoW patch history (wowhead.com / warcraft.wiki.gg spell pages; ids >100000 and Focus/Sha/Y'Shaarj/covenant mechanics postdate 3.3.5a)

## Verification notes (pre-DBErrors)

Two verification items for the orchestrator's DBErrors.log pass, none of which change the WotLK-authenticity judgment: (1) The 106 re-added 3.3.5a rows should be confirmed loadable on the 3.4.3 client — most reference core-scripted encounter/class spells that exist, but a handful of talent-triggered links (Improved Moonkin Form 48384/48395/48396->50170-50172, Shadow Embrace 32386-32391, Pursuit of Justice 26022/26023, Consume Shadows 54501) and glyph/rank spells (Glyph of Shadowflame -61291->-63311, Arcane Missiles -36032) may reference ids the 3.4.3 client dropped; if a row logs 'does not exist' at load it will self-skip and can be pruned. (2) The Echo Isles/worgen deletions -93342/71037, 71035/93342, -92237/92237 sit partly in WotLK numeric range (71035/71037) but reference Cataclysm effect ids (92237/93342) and Cataclysm-revamp content (Zuni troll intro, Tarindrella), so I deleted them as post-WotLK — worth a human sanity-check that the 71035/71037 triggers were not reused for legitimate WotLK links.

---
_C-layer research workflow (deferred batch), run wf_e38612bd-12c._


## Update — 3.4.3 DBErrors.log validation

Reloaded world_c: 37 spell IDs absent from the 3.4.3 client (ICC/ToC/Gunship encounter + talent-trigger links) dropped. Final **381 rows**, loads with 0 DBErrors.
