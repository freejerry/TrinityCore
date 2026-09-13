-- jump_charge_params: empty on a WotLK 3.3.5a-content server (feeds SPELL_EFFECT_JUMP_CHARGE (Legion 7.0); no WotLK spell uses it).
-- Raw TDB343 ships post-WotLK rows; remove them so the table is empty.
DELETE FROM `jump_charge_params`;
