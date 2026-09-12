# vehicle_seat_addon: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **Mixed** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the intended WotLK set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 35, world_335 (3.3.5a) = 17
- **Difference pattern:** 343_superset
- **Structure:** Identical schema in both DBs: same 7 columns (SeatEntry PK -> VehicleSeatEntry.dbc id, SeatOrientation, ExitParamX/Y/Z/O, ExitParamValue tinyint), same InnoDB/utf8mb4_unicode_ci definition. No column-semantics differences.

## Difference

world_d (343) is a strict superset of world_335: (335 EXCEPT d) is empty, so all 17 335 rows exist byte-identically in 343. 343 adds 18 extra SeatEntry rows: 2824, 2841-2845, 8394-8397, 8420-8425, 20613, 20766. No value diffs on the 17 shared rows. Of the 18 extras, 2824/2841-2845 are valid WotLK seats (present in 3.3.5a VehicleSeat.dbc); the other 12 (8394-8397, 8420-8425, 20613, 20766) are Cataclysm/MoP/BFA seats absent from the 3.3.5a client.

## Correct WotLK dataset

23 rows = the 17 rows shared with world_335 PLUS the 6 Pilgrim's Bounty (WotLK holiday) seat overrides 2824, 2841, 2842, 2843, 2844, 2845. These 6 seats exist in the 3.3.5a VehicleSeat.dbc and belong to WotLK content (Bountiful Table chairs: Turkey/Stuffing/Pie/Cranberry/Sweet Potato Chair, creatures 34812/34819/34822/34823/34824, Wild Turkey 32820). Excludes the 12 post-WotLK seats. All 335 shared rows are kept verbatim (byte-identical in 343).

## Dead values / contamination

Post-WotLK contamination in world_d (12 rows), all absent from the 3.3.5a VehicleSeat.dbc (WotLK max seat id 7770): SeatEntry 8394-8397 and 8421-8425 = Cataclysm Silverpine Forest (same migration touches creature 44731 npc_silverpine_horde_hauler and 44732/44733); 8420 = Cataclysm (Deathstalker Rane Yorick, creatures 44882/44884, spells 83781/80743); 20613 = BFA/MoP Hozen (creature 154765 'Hozen Bunny - Hozen Raider', spell 303242 VerifiedBuild 45745); 20766 = post-WotLK (id far above WotLK range). No dead/negative values that break WotLK logic; contamination is whole extra rows, not rescaled cells.

## Proposed delta (vs raw TDB343)

```sql
DELETE FROM `vehicle_seat_addon` WHERE `SeatEntry` IN (8394, 8395, 8396, 8397, 8420, 8421, 8422, 8423, 8424, 8425, 20613, 20766);
```

## Evidence

- **Schema identical in world_d and world_335 (7 cols, SeatEntry PK, same engine/collation)**  
  — docker SHOW CREATE TABLE vehicle_seat_addon on both DBs
- **world_d=35 rows, world_335=17 rows; 335 is a strict subset of 343 ((335 EXCEPT d) empty), extras are 2824,2841-2845,8394-8397,8420-8425,20613,20766**  
  — docker (SELECT * FROM world_335..) EXCEPT (SELECT * FROM world_d..) both directions + SeatEntry lists
- **3.3.5a VehicleSeat.dbc (effective overlay patch-enTW-3, WDBC 720 records, max id 7770) contains 2824,2841,2842,2843,2844,2845 and all 17 335 seats, but NOT 8394-8397/8420-8425/20613/20766**  
  — mpyq read Data/enTW/patch-enTW-3.MPQ DBFilesClient\VehicleSeat.dbc, parsed record ids (/tmp/vsa_read.py output)
- **2824/2841-2845 are Pilgrim's Bounty (WotLK) Bountiful Table chair seats**  
  — sql/old/10.x/world/22111_2022_12_20/2022_12_05_00_world.sql:31-38 (block titled Pilgrim's Bounty, Turkey/Stuffing/Pie/Cranberry/Sweet Potato Chair creatures 34812-34824, Wild Turkey 32820)
- **8420 is Cataclysm content (Deathstalker Rane Yorick 44882, spells 83781/80743)**  
  — sql/old/9.x/world/22082_2022_11_20/2022_10_10_00_world.sql:125-142
- **8394-8397 and 8421-8425 are Cataclysm Silverpine Forest content**  
  — sql/old/9.x/world/22082_2022_11_20/2022_10_01_01_world.sql:14,47-52 (npc_silverpine_horde_hauler 44731) and 2022_10_11_00_world.sql:356 (SeatEntry IN (8421..8425))
- **20613 is BFA/MoP Hozen content (creature 154765 Hozen Bunny - Hozen Raider, spell 303242 VerifiedBuild 45745)**  
  — sql/old/9.x/world/22082_2022_11_20/2022_10_05_02_world.sql:145-151
- **Loader skips any SeatEntry not present in VehicleSeat.dbc and validates ExitParamValue < VehicleExitParamMax(3); rows are consumed only for exit-position/orientation override on dismount**  
  — src/server/game/Globals/ObjectMgr.cpp:3384,3395; src/server/game/Entities/Unit/Unit.cpp:12732-12770; src/server/game/Entities/Vehicle/VehicleDefines.h:81-115
- **Could not extract 3.4.3 VehicleSeat.db2 to cross-check (fdid 1345447 -> ckey 53440a33.. from root not present in the local partial-CASC encoding table); WotLK-correctness determined from 3.3.5a DBC instead**  
  — root parse /tmp/root_parse.py (found ckey) + parse_encoding full scan 372408 entries: CKEY not in encoding (partial CASC)

---
_Generated from C-layer research workflow (batch 2), run wf_f9c949d0-e24._
