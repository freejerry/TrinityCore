-- gossip_menu: adopt TDB343 (sniff, covers our creature_template_gossip MenuIDs best); backfill from
-- TDB335.26091 the menu(s) our gossip refs need that 343 lacks. Clears most 'menu doesn't exist' warnings.
INSERT INTO `gossip_menu` (`MenuID`,`TextID`,`VerifiedBuild`) VALUES (7999,9853,0),(9856,10887,0);
