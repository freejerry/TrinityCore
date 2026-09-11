-- WotLK Classic: fix reputation_reward_rate for Sons of Hodir (1119) and Kurenai (978)
-- TDB343 has a column-shift bug: the rep multiplier landed in creature_rate/spell_rate
-- instead of the quest_* columns. Correct WotLK values:
--   1119 Sons of Hodir: patch 3.3.0 sped up faction rep ~30% via QUESTS (TC issue #28798)
--   978  Kurenai: only the repeatable Obsidian Warbeads turn-in is 2x (TC issue #20600)
UPDATE `reputation_reward_rate` SET `quest_rate`=1.3, `quest_daily_rate`=1.3, `quest_weekly_rate`=1.3, `quest_monthly_rate`=1.3, `quest_repeatable_rate`=1.3, `creature_rate`=1, `spell_rate`=1 WHERE `faction`=1119;
UPDATE `reputation_reward_rate` SET `spell_rate`=1 WHERE `faction`=978;
