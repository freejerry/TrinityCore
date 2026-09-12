# Factionchange Reputations — Faction Introduction Versions

Research question: for a WotLK 3.3.5a data-migration project, determine which of a given
set of WoW faction (reputation) IDs existed in Wrath of the Lich King (patch 3.3.5a, the
last WotLK patch) versus which were introduced later (Cataclysm 4.x, Mists of Pandaria 5.x,
or Warlords of Draenor 6.x).

Sources used (primary/authoritative): wowhead.com faction pages (for canonical faction
names by ID) and warcraft.wiki.gg faction pages (for the "Patch changes → Added" infobox,
which gives the exact introduction patch).

Date researched: 2026-09-12.

## TL;DR — Core answer

**None of the 25 faction IDs existed in WotLK 3.3.5a.** Every one was introduced in
Cataclysm (4.x) or later (MoP 5.x / WoD 6.x). The full list of IDs that did NOT exist in
WotLK is therefore all 25:

```
1133, 1134, 1172, 1174, 1177, 1178, 1228, 1242, 1352, 1353, 1374, 1375, 1376,
1387, 1388, 1419, 1445, 1681, 1682, 1690, 1691, 1708, 1710, 1739, 1740
```

Breakdown by expansion introduced:

- **Cataclysm (4.x):** 1133, 1134, 1172, 1174, 1177, 1178
- **Mists of Pandaria (5.x):** 1228, 1242, 1352, 1353, 1374, 1375, 1376, 1387, 1388, 1419
- **Warlords of Draenor (6.x):** 1445, 1681, 1682, 1690, 1691, 1708, 1710, 1739, 1740

(Note: several IDs I initially expected to be MoP turned out to be WoD once verified against
the wiki patch-history infoboxes — see 1681 Vol'jin's Spear and 1682 Wrynn's Vanguard, which
are Ashran/WoD factions, not MoP 5.4 Timeless Isle factions.)

## Per-ID findings (with citations)

| ID | Faction name | Introduced | Patch | Citation |
|----|--------------|-----------|-------|----------|
| 1133 | Bilgewater Cartel | Cataclysm | 4.x (goblin racial faction) | wowhead faction=1133; warcraft.wiki.gg "Bilgewater Cartel" — "the sixth racial Horde faction to be added to the game, introduced in _Cataclysm_" |
| 1134 | Gilneas | Cataclysm | 4.0.3a (2010-11-23) | wowhead faction=1134; warcraft.wiki.gg "Gilneas (faction)" — "Patch 4.0.3a (2010-11-23): Added." |
| 1172 | Dragonmaw Clan | Cataclysm | 4.x (Twilight Highlands) | wowhead faction=1172; warcraft.wiki.gg "Dragonmaw Clan" — clan gained its in-game reputation (Twilight Highlands) during Cataclysm |
| 1174 | Wildhammer Clan | Cataclysm | 4.0.3a (2010-11-23) | wowhead faction=1174; warcraft.wiki.gg "Wildhammer Clan" — "Patch 4.0.3a (2010-11-23): Re-introduced." (Twilight Highlands reputation) |
| 1177 | Baradin's Wardens | Cataclysm | 4.0.3a (2010-11-23) | wowhead faction=1177; warcraft.wiki.gg "Baradin's Wardens" — "Patch 4.0.3a (2010-11-23): Added." (Tol Barad, Alliance) |
| 1178 | Hellscream's Reach | Cataclysm | 4.0.3a (2010-11-23) | wowhead faction=1178; warcraft.wiki.gg "Hellscream's Reach" — "Patch 4.0.3a (2010-11-23): Added." (Tol Barad, Horde) |
| 1228 | Forest Hozen | MoP | 5.0.4 (2012-08-28) | wowhead faction=1228; warcraft.wiki.gg "Forest Hozen" — "Patch 5.0.4 (2012-08-28): Added." |
| 1242 | Pearlfin Jinyu | MoP | 5.0.4 (2012-08-28) | wowhead faction=1242; warcraft.wiki.gg "Pearlfin Jinyu" — "Patch 5.0.4 (2012-08-28): Added." |
| 1352 | Huojin Pandaren | MoP | 5.0.4 (2012-08-28) | wowhead faction=1352; warcraft.wiki.gg "Huojin Pandaren" — "Patch 5.0.4 (2012-08-28): Added." |
| 1353 | Tushui Pandaren | MoP | 5.0.4 (2012-08-28) | wowhead faction=1353; warcraft.wiki.gg "Tushui Pandaren" — "Patch 5.0.4 (2012-08-28): Added." |
| 1374 | Brawl'gar Arena (Season 1) | MoP | 5.1.0 (2012-11-27) | wowhead faction=1374; warcraft.wiki.gg "Brawl'gar Arena" — "Patch 5.1.0 (2012-11-27): Added." (Brawler's Guild Horde venue) |
| 1375 | Dominance Offensive | MoP | 5.1.0 (2012-11-27) | wowhead faction=1375; warcraft.wiki.gg "Dominance Offensive" — added patch 5.1.0 (Landfall, Horde) |
| 1376 | Operation: Shieldwall | MoP | 5.1.0 (2012-11-27) | wowhead faction=1376; warcraft.wiki.gg "Operation: Shieldwall" — added patch 5.1.0 (Landfall, Alliance) |
| 1387 | Kirin Tor Offensive | MoP | 5.2.0 (2013-03-05) | wowhead faction=1387; warcraft.wiki.gg "Kirin Tor Offensive" — "Patch 5.2.0 (2013-03-05): Added." (Isle of Thunder, Alliance) |
| 1388 | Sunreaver Onslaught | MoP | 5.2.0 (2013-03-05) | wowhead faction=1388; warcraft.wiki.gg "Sunreaver Onslaught" — "Patch 5.2.0 (2013-03-05): Added." (Isle of Thunder, Horde) |
| 1419 | Bizmo's Brawlpub (Season 1) | MoP | 5.1.0 (2012-11-27) | wowhead faction=1419; warcraft.wiki.gg "Brawler's Guild"/"Brawl'gar Arena" — Brawler's Guild added patch 5.1.0 (Alliance venue) |
| 1445 | Frostwolf Orcs | WoD | 6.0.2 (2014-10-14) | wowhead faction=1445; warcraft.wiki.gg "Frostwolf Orcs" — Warlords of Draenor, Frostfire Ridge (Horde) |
| 1681 | Vol'jin's Spear | WoD | 6.0.2 (2014-10-14) | wowhead faction=1681; warcraft.wiki.gg "Vol'jin's Spear" — "Patch 6.0.2 (2014-10-14): Added." (Ashran, Horde) |
| 1682 | Wrynn's Vanguard | WoD | 6.0.2 (2014-10-14) | wowhead faction=1682; warcraft.wiki.gg "Wrynn's Vanguard" — "Patch 6.0.2 (2014-10-14): Added." (Ashran, Alliance) |
| 1690 | Brawl'gar Arena (Season 2) | WoD | 6.x (Season 2) | wowhead faction=1690; warcraft.wiki.gg "Brawler's Guild" — Season 2 took place during Warlords of Draenor (level-100 encounters) |
| 1691 | Bizmo's Brawlpub (Season 2) | WoD | 6.x (Season 2) | wowhead faction=1691; warcraft.wiki.gg "Brawler's Guild" — Season 2 = Warlords of Draenor |
| 1708 | Laughing Skull Orcs | WoD | 6.0.2 (2014-10-14) | wowhead faction=1708; warcraft.wiki.gg "Laughing Skull Orcs" — "Patch 6.0.2 (2014-10-14): Added." (Gorgrond) |
| 1710 | Sha'tari Defense | WoD | 6.0.2 (2014-10-14) | wowhead faction=1710; warcraft.wiki.gg "Sha'tari Defense" — "Patch 6.0.2 (2014-10-14): Added." |
| 1739 | Vivianne | WoD | 6.0.2 (2014-10-14) | wowhead faction=1739; warcraft.wiki.gg "Vivianne" — "Patch 6.0.2 (2014-10-14): Added." (garrison bodyguard reputation) |
| 1740 | Aeda Brightdawn | WoD | 6.x | wowhead faction=1740; warcraft.wiki.gg "Aeda Brightdawn" — Warlords of Draenor garrison bodyguard (blood elf warlock, Sunsworn) |

## Notes / verification method

- Faction names were read from wowhead.com faction pages by ID (`https://www.wowhead.com/faction=<id>/`),
  which reliably return the canonical name but do NOT show the introduction patch.
- Introduction patch/expansion was verified from warcraft.wiki.gg faction pages, whose
  "Patch changes" infobox records an explicit "Added" patch for most factions.
- A few IDs were confirmed only by expansion (not an exact patch number) where the wiki page
  lacked a patch-changes box: 1133 (Bilgewater Cartel), 1172 (Dragonmaw Clan), 1690/1691
  (Brawler's Guild Season 2), 1740 (Aeda Brightdawn). In every such case the expansion is
  unambiguous from lore/content and adjacent counterpart factions, and is still comfortably
  post-WotLK.
- Since 3.3.5a is the final WotLK patch and every faction here was added in 4.0.3a or later,
  the conclusion (none existed in WotLK 3.3.5a) holds for the entire set.
