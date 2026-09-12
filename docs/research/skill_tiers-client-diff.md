# skill_tiers verification: TDB343 vs 3.3.5a client vs 3.4.3 client

**Question:** Is TDB343's `skill_tiers` (58 rows) correct for a server running WotLK
3.3.5a **content** on a modern **3.4.3.54261** WoW Classic client?

**Verdict: IMPORT TDB343'S 58 ROWS VERBATIM. No delta required.**

All extraction below was done from the local client files (not web guessing).

---

## 1. Sources actually extracted

| Source | How | Result |
|---|---|---|
| 3.3.5a `SkillTiers.dbc` | MPQ `Data/enTW/locale-enTW.MPQ` via `mpyq` (DBFilesClient lives in the **locale** MPQs, not common/patch) | WDBC, **26 records, 33 fields** (`ID` + `Cost[16]` + `Value[16]`), recsize 132 |
| 3.4.3 `SkillRaceClassInfo.db2` (FDID 1240406) | CASC via local CDN proxy `127.0.0.1:8100`; resolved through build-config root (old pre‑8.2 root, magic `0x00000005`) + encoding, range-fetched from archive `01f0908f…` | WDC4, **240 records, 7 fields**, layout_hash `0271228c` |
| 3.4.3 `SkillTiers` | root + community listfile | **Does not exist** in the 3.4.3 client (see §4) |

**Important layout note (3.3.5a `SkillTiers.dbc`):** the record is `ID` + **16 `Cost` fields** +
**16 `Value` fields**. TrinityCore's `skill_tiers.Value1..16` map to the **`Value` block only**
(the max-skill caps). The task hint of "17 uint32 columns" was wrong; it is 33.

---

## 2. 3.3.5a `SkillTiers.dbc`  vs  TDB343 `skill_tiers` (row-by-row)

- IDs in 3.3.5a: `2,21,22,23,24,41,61,62,63,81,121,122,123,124,125,126,127,141,142,143,161,181,182,221,222,223` (26)
- **Every 3.3.5a ID is present in TDB343.** IDs in 335 missing from 343: **none.**
- TDB343 adds **32 extra tiers** not in 3.3.5a (all Cataclysm+ profession/secondary tiers):
  `224,230,233,234,235,236,237,295,333,335,336,338,451-463,472,473,474,478,480,481,482`.

### Value differences on common IDs
Only the **multi-step** tiers differ, and only in steps **beyond the WotLK cap**. Steps
1–6 are byte-identical everywhere. `Value[]` shown as steps 1..12 (13-16 are 0 in both):

| ID | 3.3.5a Value[] | TDB343 Value[] | First differing step |
|---|---|---|---|
| 2   | 75,150,225,300,375,450 | 75,150,225,300,375,450,**525,600,700,800,900,1000** | 7 |
| 23  | 75,150,225,300,375,450 | 75,150,225,300,375,450,**525,600,700,750,825,900** | 7 |
| 41  | 75,150,225,300,375,450 | …,**525,600,700,800,900,1000** | 7 |
| 61  | 75,150,225,300,375,450 | …,**525,600,700,750,825,900** | 7 |
| 62  | 75,150,225,300,375,450 | …,**525,600,700,800,900,1000** | 7 |
| 63  | 75,150,225,300,375,450 | …,**525,600,700,750,825,900** | 7 |
| 161 | 75,150,225,300,375,450 | …,**525,600,700,800,900,1000** | 7 |
| 223 | 75,150,225,300 | 75,150,225,300,**375** | 5 |

All other common IDs (21,22,24,81,121-127,141,142,143,181,182,221,222) are **identical**.
The added steps are the post-WotLK expansion caps (525=Cata, 600=MoP, 700=WoD, 800=Legion, …;
375 = Cata "Master Riding" for tier 223).

---

## 3. 3.4.3 client cross-check — every referenced SkillTierID exists (no crash/hole)

Parsed `SkillRaceClassInfo.db2` (WDC4, bit-packed). The `SkillTierID` column (9-bit field,
field index 6) has these **distinct non-zero** values, and which SkillID uses each:

| SkillTierID | Used by SkillID(s) | Meaning | In TDB343's 58? |
|---|---|---|---|
| 2   | 182 (Herbalism), 186 (Mining) | gathering | ✅ |
| 21  | 98,109,111,113,115,137,139,141,313,315,673,759 | languages | ✅ |
| 23  | 356 (Fishing) | ✅ |
| 41  | 164 (Blacksmithing),165 (Leatherworking),171 (Alchemy),202 (Engineering),755 (Jewelcrafting),773 (Inscription) | primary crafting | ✅ |
| 61  | 185 (Cooking) | ✅ |
| 62  | 197 (Tailoring),333 (Enchanting) | ✅ |
| 63  | 129 (First Aid) | ✅ |
| 161 | 393 (Skinning) | ✅ |
| 181 | 148,149,150,152,533,553,554,713 | riding/weapon | ✅ |
| 182 | 148,149,150,152,533,553,554 | ✅ |
| 223 | 762 (Riding) | ✅ |

**11/11 referenced SkillTierIDs are present in TDB343's 58 rows.** Records with
`SkillTierID = 0` (the majority) reference no tier. **No missing tier → no lookup hole / crash.**
(Field 6 identification is certain: it is the only field whose every non-zero value is a valid
tier ID present in BOTH the 3.3.5a `SkillTiers.dbc` and TDB343, and the skill→tier mapping matches
known professions exactly.)

---

## 4. Why the extra steps are inert (the deciding mechanism)

The 3.4.3 client ships **no `SkillTiers` file** (absent from the root manifest; the community
listfile only has a legacy `dbfilesclient/skilltiers.dbc` FDID 801762 that is **not in the build**).
So the client does **not** enforce skill caps itself — the server's `skill_tiers` is authoritative,
and gameplay is driven by WotLK **content**.

TrinityCore derives the cap in `Spell::EffectLearnSkill` / `EffectSkillStep`
(`src/server/game/Spells/SpellEffects.cpp:2337` and `:4568`):

```cpp
SkillTiersEntry const* tier = sObjectMgr->GetSkillTier(rcEntry->SkillTierID);
uint16 maxSkillVal = tier->GetValueForTierIndex(damage - 1);   // damage = STEP from the content spell
```

`GetValueForTierIndex(tierIndex)` (`ObjectMgr.cpp:7788`) returns `Value[tierIndex]`, clamped to
`MAX_SKILL_STEP-1` (=15) and walking back over trailing zeros. The **step (`damage`) comes from the
WotLK content spell** (`SPELL_EFFECT_SKILL` / `SKILL_STEP` base points), **not** from the tier's
highest defined step.

WotLK content never grants a step above the WotLK step count:
- Professions cap at **step 6 → `Value[5]` = 450** (identical in 335 and 343).
- Riding (tier 223) caps at **step 4 → `Value[3]` = 300** (identical; the TDB343 step-5 = 375 is Cata "Master Riding").

Therefore the extended values (`Value[6..11]` = 525–1000, and 223's step-5 = 375) are **never indexed**
by 3.3.5a content, and the 32 extra tier rows are simply **unreferenced**. The importable data is,
for every WotLK-reachable step, **byte-identical to the 3.3.5a client's authoritative caps.**

---

## 5. Recommendation

**Import TDB343's 58 `skill_tiers` rows verbatim.** It is correct and safe:

1. **No holes** — all 11 SkillTierIDs referenced by the 3.4.3 client's `SkillRaceClassInfo.db2`
   exist among the 58 rows.
2. **WotLK caps correct** — steps 1–6 (professions) and 1–4 (riding) match the 3.3.5a
   `SkillTiers.dbc` exactly, and those are the only steps WotLK content can reach.
3. The extra Cataclysm+ steps/rows are inert given 3.3.5a content + content-driven step lookup.

**Optional purist hardening (not required):** if you want the table to literally mirror WotLK,
zero the post-WotLK steps on the 8 referenced multi-step tiers (steps 7-16 for
2,23,41,61,62,63,161; step 5 for 223). This changes nothing functionally as long as no imported
spell has a `SKILL`/`SKILL_STEP` effect with a step beyond the WotLK count — which is the case for
pure 3.3.5a content. Given that, verbatim import is the simpler and equally-correct choice.

---

## Extraction reproduction notes
- 3.3.5a DBC: `mpyq` venv at `/tmp/mpqvenv`; file read from `Data/enTW/locale-enTW.MPQ`
  (locale MPQ override order: `patch-<loc>-3 > -2 > patch-<loc> > lichking-locale > expansion-locale > locale > base`).
- 3.4.3 db2: local CDN proxy alive at `127.0.0.1:8100`; the local `casc-out` partial CASC
  (data.000, 9806 blobs, no .idx / no root / no encoding) was **insufficient alone**, so root/encoding/archive
  were fetched through the proxy. Root is the **old pre-8.2 format** (interleaved md5+lookup, 24-byte stride).
- WDC4 parsed manually (bit-packed, `field_storage_info`); IDs from the id_list block.
