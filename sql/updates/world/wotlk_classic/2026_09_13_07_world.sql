-- mount_definitions: 28 WotLK faction-mount pairs (dropped 22 Cata/MoP/WoD). Self-contained; applied to raw TDB343 reproduces world_c. See docs/research/mount_definitions-wotlk.md.
DELETE FROM `mount_definitions`;
INSERT INTO `mount_definitions` (`spellId`, `otherFactionSpellId`) VALUES
(17229,64658),(23509,23510),(23510,23509),(55531,60424),(59785,59788),(59788,59785),(59797,59799),(59799,59797),(60114,60116),(60116,60114),(60118,60119),(60119,60118),(60424,55531),(61229,61230),(61230,61229),(61425,61447),(61447,61425),(61465,61467),(61467,61465),(61469,61470),(61470,61469),(61996,61997),(61997,61996),(64658,17229),(66087,66088),(66088,66087),(66090,66091),(66091,66090);
