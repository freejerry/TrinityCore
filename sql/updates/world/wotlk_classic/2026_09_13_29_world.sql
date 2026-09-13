-- creature_template_gossip: drop rows whose MenuID is absent from gossip_menu (343-internal dangling +
-- menus removed by 2026_09_13_28). Runs after 2026_09_13_28.
DELETE FROM `creature_template_gossip` WHERE `MenuID` NOT IN (SELECT `MenuID` FROM `gossip_menu`);
