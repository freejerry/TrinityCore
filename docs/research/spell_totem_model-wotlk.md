# spell_totem_model: WotLK-correctness (TDB343-only table)

**Verdict:** Trim (confidence: high). This table exists in TDB343 but not in 3.3.5a. Update under sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows in raw TDB343:** 342
- **Is a WotLK feature?** yes
- **Purpose:** Maps a totem spell + caster RaceID to a CreatureDisplayInfo DisplayID so a summoned totem shows race-specific artwork. Loaded by SpellMgr::LoadSpellTotemModel (src/server/game/Spells/SpellMgr.cpp:4962, registered World.cpp:1818), validating SpellID against the spell store, RaceID against ChrRaces, DisplayID against CreatureDisplayInfo; consumed via SpellMgr::GetModelForTotem (SpellMgr.cpp:5013) in Totem::InitStats (src/server/game/Entities/Totem/Totem.cpp:73), which calls SetDisplayId(totemDisplayId) or falls back to the totem creature's default model when no row matches.

## Correct state for C

Only rows for WotLK-era totem spells cast by WotLK shaman races. Keep SpellID in {2484 Earthbind, 5394 Healing Stream, 8143 Tremor, 8512 Windfury, 16191 Mana Tide} crossed with RaceID in {2 Orc, 6 Tauren, 8 Troll, 11 Draenei} = 20 rows. Drop all 22 post-WotLK spells (51485 Earthgrab is MoP; 98008/108280 MoP; 157153/188592/188616/192058/192077/192222/196932/198838/202188/204330-204336/207399/210651-210660 Legion; 324386/355580 Shadowlands) and every post-WotLK race row (3 Dwarf & 9 Goblin = Cataclysm shaman; 24/25/26 Pandaren = MoP; 28/31/32/34/35/36 = Legion/BfA allied races).

## Dead values / contamination

Heavy contamination: 22 of 27 distinct SpellIDs are post-WotLK (MoP 51485/98008/108280; Legion 157153/188592/188616/192058/192077/192222/196932/198838/202188/204330/204331/204332/204336/207399/210651/210657/210660; Shadowlands 324386/355580) and will be skipped by the loader (spell not in 3.4.3 spell store). Race contamination in every spell block: RaceID 3 (Dwarf) & 9 (Goblin) shaman are Cataclysm 4.0.3, 24/25/26 (Pandaren) MoP 5.0, 28/31/32/34/35/36 (Nightborne/Highmountain/Mag'har/Dark Iron/Vulpera/Zandalari) Legion+/BfA — none exist on a WotLK 3.3.5a-content server.

## Evidence

- **Table is 343-only cosmetic override: sets totem display by caster race, else falls back to creature default model.**  
  — src/server/game/Entities/Totem/Totem.cpp:73 SetDisplayId(GetModelForTotem(...)); SpellMgr.cpp:4962-5010 loader
- **Race-specific totem artwork is a WotLK feature: Patch 3.3.0 (2009-12-08) gave each Horde race unique totem artwork; Draenei totems date to TBC 2.0.**  
  — https://warcraft.wiki.gg/wiki/Shaman_totem (patch history: 3.3.0 'Each of the horde races now have unique totem artwork')
- **Kept spells are WotLK-valid: 2484 Earthbind & 5394/8143/8512 (Classic), 16191 Mana Tide is the WotLK talent spell.**  
  — https://www.wowhead.com/wotlk/spell=16191 ; https://www.wowhead.com/classic/spell=2484
- **51485 Earthgrab Totem is a Mists of Pandaria spell ID (WotLK Earthgrab was 8376/8378), so dropped.**  
  — https://www.wowhead.com/spell=51485/earthgrab-totem (titled Mists of Pandaria Classic)
- **Dwarf(3) and Goblin(9) shaman are Cataclysm (4.0.3a, 2010-11-23); Pandaren(24-26) MoP; allied races 28/31/32/34/35/36 Legion/BfA — none are WotLK shaman races (Orc/Tauren/Troll/Draenei only).**  
  — https://warcraft.wiki.gg/wiki/Shaman_races ; WebSearch Cataclysm 4.0.3 race/class combos
- **High SpellIDs 98008/108280 (MoP), 157153-210660 (Legion), 324386/355580 (Shadowlands) confirm the bulk of rows are post-WotLK content added after 3.3.5a.**  
  — world_d.spell_totem_model full dump (27 distinct SpellIDs, min 2484 max 355580)

## Verification notes

DisplayIDs for the 20 kept rows are validated against the 3.4.3 client CreatureDisplayInfo by the loader (SpellMgr.cpp:5000). The Orc/Troll totem art (30756-30763) and Draenei art (19071-19075) are WotLK-era displays; Tauren (4587-4590) are classic generic totem models. Confirm all resolve on the 3.4.3.54261 client in the orchestrator's DBErrors.log pass; any that log "non-existing model" should be dropped (the totem then falls back to its creature default, harmless).

---
_343-only research workflow, run wf_18cbaa1a-47d. Trims validated via world_c reload + DBErrors.log._
