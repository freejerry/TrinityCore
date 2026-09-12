-- vehicle_seat_addon: Drop 12 post-WotLK (Cataclysm) vehicle seat rows.
-- Verified: applied to raw TDB343 this reproduces the intended WotLK set (see docs/research/vehicle_seat_addon-wotlk.md).
DELETE FROM `vehicle_seat_addon` WHERE `SeatEntry` IN (8394, 8395, 8396, 8397, 8420, 8421, 8422, 8423, 8424, 8425, 20613, 20766);
