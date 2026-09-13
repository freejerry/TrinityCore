# command: WotLK-correct data (type-diff table)

**Verdict:** TDB343 (confidence: high). Columns match 343/335 up to cosmetic type differences.

- **Rows:** world_d=620, world_335=599 | pattern: value_shift
- **Structure:** Same 2-column schema in both (PK name varchar(50), help text). Minor col-def difference only: world_d has `help mediumtext NOT NULL`, world_335 has `help longtext DEFAULT NULL`. No semantic difference for content; keep the TDB343 definition.

## Difference

343 has 620 rows, 335 has 599. ~66 names exist only in 343, ~45 only in 335. 343-only names are the modern command surface (bnetaccount*, new split ticket system: `ticket bug/complaint/suggestion *`, `go bugticket/complaintticket/suggestionticket/quest`, scene*, `modify currency`, `modify power`, debug conversation/phase/playerchoice, reload conversation_template/criteria_data/scene_template/spell_script_names/support, disable add/remove criteria, list scenes). 335-only names are legacy 3.3.5a commands (maxskill, flusharenapoints, `modify arenapoints`, `modify bit`, debug getvalue/setvalue/getitemvalue/setitemvalue/Mod32Value/setbit/update, old flat ticket system: `ticket assign/close/escalate/viewid/...`, `go ticket`, `wp event *`, instance savedata, disable add/remove achievement_criteria, and old reload names item_set_names/achievement_criteria_data/waypoint_data/*_locale). This is a command-vocabulary shift between the old 3.3.5a core and the modern 3.4.3-derived core.

## Correct WotLK dataset

The set of help-text rows matching the command names the running core (wotlk_classic, 3.4.3-derived) actually registers, which is the TDB343 modern command surface verbatim. The `command` table is a core-facing help-text lookup, not WotLK content; its correct contents are dictated by the core's registered ChatCommand tables, not by 3.3.5a. The core loader (ChatCommand.cpp:LoadCommandsIntoMap) walks each row's name into COMMAND_MAP; a name with no registered command is logged "Table `command` contains data for non-existant command" and skipped (surplus rows are harmless), and a registered command with no row just logs "missing help text". Using the 335 set would leave the modern commands (bnetaccount, split ticket system, scene, modify currency/power) with no help and fill the table with dead rows for removed legacy commands.

## Dead values / contamination

No Cata/MoP/WoD content contamination — this is a core-command help table, content-independent. The 335-only rows (maxskill, flusharenapoints, modify arenapoints/bit, debug getvalue/setvalue/Mod32Value/setbit/update, old single ticket system, go ticket, wp event, instance savedata) are legacy commands NOT registered by the wotlk_classic core (verified: 0 rbac-registered hits in src/server/scripts/Commands/*.cpp), so they would be dead/unused if kept. TDB343's rows match registered commands. Any surplus 343 rows for commands this branch may have removed would be silently skipped (logged, harmless), not contamination.

## Evidence

- **command table is loaded via SELECT name, help FROM command and used only as a help-text lookup keyed by command name**  
  — src/server/database/Database/Implementation/WorldDatabase.cpp:64 (WORLD_SEL_COMMANDS)
- **Rows whose name is not a registered command are logged 'non-existant command' and skipped; registered commands without a row just warn 'missing help text' — so the correct row set is defined by the core's registered commands**  
  — src/server/game/Chat/ChatCommands/ChatCommand.cpp:100-127
- **Core registers the modern 343-style command surface: bnetaccount, split ticket bug/complaint/suggestion system, go bugticket/complaintticket/suggestionticket/quest, modify currency, modify power, scene**  
  — src/server/scripts/Commands/cs_battlenet_account.cpp; cs_ticket.cpp:409-418; cs_go.cpp:60-67; cs_modify.cpp:66,86; cs_scene.cpp
- **335-only legacy commands are absent from the core: maxskill, flusharenapoints, modify arenapoints/bit, debug getvalue/setvalue/Mod32Value/setbit, wp event, instance savedata all return 0 rbac-registered matches**  
  — grep -rn over src/server/scripts/Commands/*.cpp for those tokens with rbac::RBAC_PERM_COMMAND => 0 hits each
- **Row counts and name-level diff: world_d=620, world_335=599; 343-only vs 335-only name lists**  
  — docker exec tdb343-db-1 mariadb COUNT(*) and LEFT JOIN diff on command.name (world_d vs world_335)
- **Schema differs only in help column definition (mediumtext NOT NULL vs longtext DEFAULT NULL), same PK**  
  — SHOW CREATE TABLE command in world_d and world_335

---
_C-layer research workflow (type-diff batch), run wf_a8fd5326-14c._