-- item_script_names: 9 TBC/WotLK item-script bindings (dropped Cata Sen'jin frog 53510). Self-contained; applied to raw TDB343 reproduces world_c. See docs/research/item_script_names-wotlk.md.
DELETE FROM `item_script_names`;
INSERT INTO `item_script_names` (`Id`,`ScriptName`) VALUES
(19169,'item_generic_limit_chance_above_60'),
(24538,'item_only_for_flight'),
(30175,'item_gor_dreks_ointment'),
(31088,'item_tainted_core'),
(33098,'item_petrov_cluster_bombs'),
(34475,'item_only_for_flight'),
(34489,'item_only_for_flight'),
(39878,'item_mysterious_egg'),
(44717,'item_disgusting_jar');
