-- WotLK Classic: strip Cataclysm contamination from reputation_spillover_template.
-- TDB343 added Bilgewater Cartel (1133, goblin) and Gilneas (1134, worgen) — both
-- Cataclysm factions — and used the 5th spillover slot to link them. WotLK has no
-- 5th spillover slot; remove those rows and zero the 5th slot on all rows.
DELETE FROM `reputation_spillover_template` WHERE `faction` IN (1133,1134);
UPDATE `reputation_spillover_template` SET `faction5`=0, `rate_5`=0, `rank_5`=0;
