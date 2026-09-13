-- creature_template_gossip: drop rows whose MenuID exists in no gossip_menu source (343-internal
-- dangling refs, 42 menu ids absent from TDB343 and TDB335.26091). Runs after 2026_09_13_28.
DELETE FROM `creature_template_gossip` WHERE `MenuID` NOT IN (SELECT `MenuID` FROM `gossip_menu`);
