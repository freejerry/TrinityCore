-- WotLK Classic: fix quest_mail_sender (Children's Week orphan thank-you mail)
-- TDB343 has QuestId and RewardMailSenderEntry SWAPPED for these rows (its "QuestId"
-- values 22817/22818/28879/28880 are orphan CREATURE entries, not quests). Restore the
-- correct WotLK rows: QuestId = the escort quest, sender = the orphan NPC.
DELETE FROM `quest_mail_sender` WHERE `QuestId` IN (22817,22818,28879,28880,10966,10967,13959,13960);
INSERT INTO `quest_mail_sender` (`QuestId`,`RewardMailSenderEntry`) VALUES
(10966,22818),(10967,22817),(13959,33533),(13960,33532);
