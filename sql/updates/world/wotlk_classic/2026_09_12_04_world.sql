-- spell_required: Restore 20 WotLK spell dependency chains dropped by TDB343.
-- Verified: applied to raw TDB343 this reproduces the 3.3.5a (world_335) set exactly.
INSERT INTO `spell_required` (`spell_id`,`req_spell`) VALUES
(16689,339),(16810,1062),(16811,5195),(16812,5196),(16813,9852),(17329,9853),
(25782,19838),(25894,19854),(25899,20911),(25916,25291),(25918,25290),(27009,26989),
(27141,27140),(27143,27142),(27681,14752),(48933,48931),(48934,48932),(48937,48935),
(48938,48936),(53312,53308);
