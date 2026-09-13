-- creature_formations: adopt TDB343 (guid-bound to the 343 spawn set; 335 uses a different guid
-- space, so 343 is the only compatible source). Drop rows whose leader/member guid does not exist
-- in `creature` (TDB343-internal dangling refs; the core skips them at load). Self-contained
-- subqueries against `creature` in the same DB; runs after 2026_09_13_20 (creature spawns).
DELETE FROM `creature_formations` WHERE `leaderGUID` NOT IN (SELECT `guid` FROM `creature`)
                                     OR `memberGUID` NOT IN (SELECT `guid` FROM `creature`);
