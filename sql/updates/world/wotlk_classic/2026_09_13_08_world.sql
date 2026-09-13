-- spell_totem_model: 20 WotLK totem model rows (dropped MoP/Legion totems). Self-contained; applied to raw TDB343 reproduces world_c. See docs/research/spell_totem_model-wotlk.md.
DELETE FROM `spell_totem_model`;
INSERT INTO `spell_totem_model` (`SpellID`,`RaceID`,`DisplayID`) VALUES
(2484,2,30757),(2484,6,4588),(2484,8,30761),(2484,11,19073),
(5394,2,30759),(5394,6,4587),(5394,8,30763),(5394,11,19075),
(8143,2,30757),(8143,6,4588),(8143,8,30761),(8143,11,19073),
(8512,2,30756),(8512,6,4590),(8512,8,30760),(8512,11,19071),
(16191,2,30759),(16191,6,4587),(16191,8,30763),(16191,11,19075);
