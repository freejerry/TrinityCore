-- gossip_menu: adopt TDB343; drop rows whose TextID references an npc_text absent from TDB343
-- (npc_text is TDB343 verbatim; 3.3.5 npc_text schema differs so no backfill). Same-DB subquery.
DELETE FROM `gossip_menu` WHERE `TextID`<>0 AND `TextID` NOT IN (SELECT `ID` FROM `npc_text`);
