# SpellName.db2 (3.4.3.54261) — the valid client SpellID set

**Goal:** a deterministic, reusable list of every valid SpellID in the 3.4.3.54261
WoW Classic client, so migrations can gate "does spell X exist in the 3.4.3 client?"

**Result artifacts (in `/Users/shinichi/Works/side-project/wow343-archive/`):**

| file | ids | min | max | meaning |
|---|---|---|---|---|
| `spellname_343_ids.txt` | **30291** | 1 | 446920 | **AUTHORITATIVE** — union of all locale builds (use this for existence checks) |
| `spellname_343_ids_enUS.txt` | 30032 | 1 | 446920 | enUS/enGB build, all sections decrypted (what a TrinityCore server extracts to `dbc/enUS`) |
| `spellname_343_ids_zhTW.txt` | 29718 | 1 | 446920 | zhTW build (deployed client locale); +41 encrypted ids it cannot read (covered by enUS) |

Use the **union** by default: a SpellID present in any locale build is a real client
spell, so the union avoids false-negatives. If you specifically need "what THIS
TrinityCore server has in its DBStore", that is the enUS set.

---

## What SpellName.db2 is and where it came from

- Canonical id set = `SpellName.db2`'s id-list (Spell.db2 / SpellMisc.db2 key by
  SpellID / SpellMiscID and are not the canonical set — SpellMisc even keys by its
  own ID up to 739337).
- **FDID correction:** the task hint said FDID **1024015**. That FDID is **not in the
  3.4.3.54261 root at all.** The real SpellName.db2 FDID (community listfile +
  confirmed by the client root) is **1990283**. (`spell.db2`=1140089,
  `spellmisc.db2`=1003144.)

Two independent real client extracts were used (they are genuinely per-locale builds
— the client root stores a **separate content hash per locale** for FDID 1990283):

1. `/Users/shinichi/Works/side-project/wow343-archive/zhTW-db2-3.4.3.54261.tar.gz`
   → `zhTW/SpellName.db2` (927 KB) — a raw zhTW-locale dump.
2. `/Users/shinichi/Works/side-project/tdb343-test/data/dbc/enUS/SpellName.db2` (969 KB)
   — extracted+processed by TrinityCore's DB2 tooling.

Both are WDC4, unencrypted magic (no BLTE-'E' blocker on the file itself),
layout_hash `0xb0dd8f60`, field_count 1 (record = Name string offset), flags 0x4
(ids live in the id_list block, not inline).

### The per-file difference is real, not a parse bug
- Section 0 (the main, unencrypted section): zhTW 26923 records vs enUS 27231. The
  enUS file was processed by TrinityCore (`DBCache` hotfixes merged), so its md5 no
  longer matches the pristine CASC content hash and section 0 carries extra rows.
- Sections 1-9 (~41 high-id records): in the **zhTW dump they are TACT-encrypted**
  (real non-zero `tact_key`s, e.g. `0x03893b2a239c5105`) and the dump shipped no
  keys, so they decode to zeros and are unreadable. In the **enUS file those same
  sections carry `tact_key = 0x5452494e49545900` = ASCII "TRINITY\0"** — TrinityCore's
  tooling decrypted them and re-tagged the key, exposing the real ids (423330…423868).
  So enUS covers the ids zhTW cannot read.
- Neither is a strict superset: 259 low-range (<100000) ids are zhTW-only, 573 are
  enUS-only. Hence the **union** is the safe existence set.

## Sanity checks (against the union)
- MUST be present: `53341` Rune of Cinderglacier ✅, `24867` Feral Swiftness ✅.
  `47179` "Nurturing Instinct" is **ABSENT in both builds** — verified not a parse
  miss: enUS has 47170-47178, 47181, 47182, 47184… but real gaps at 47179/47180/47183.
  47179 is simply not a SpellName id in the 3.4.3 client (the task's example was off).
- MUST be absent: `125610` (MoP Battle Pet Training) ✅ absent, `389501` (Dragonflight)
  ✅ absent.

## How it was done (reproduction)

The full authoritative CASC install lives at `~/WoW 3.4.3 Test/Data` (build key
`c91609c69ed2ab39d44039390a1be969` = 3.4.3.54261, KR/zhTW branch; has config/ + .idx +
data.NNN). Its root is the **old pre-8.2 format, magic `0x00000005`** (no TSFM,
parse from offset 0; per block: uint32 count, uint32 contentFlags, uint32 localeFlags,
int32 fdid-delta[count], then {md5[16]+nameHash[8]}[count] → 28-byte record stride).
The root resolver + WDC4 id parser are checked into the tools dir:

- `wow343-archive/tools/extract_db2_by_fdid.py` — resolve FDID → CKEY (root) → EKEY
  (encoding) → read local idx/data.NNN → BLTE-decode. Run e.g.
  `FDID=1990283 python3 extract_db2_by_fdid.py`. Root parse validated by finding the
  known-present FDID 1240406 (SkillRaceClassInfo) and consuming the root to its exact
  end (596 blocks, 398740 files).
- `wow343-archive/tools/wdc4_ids.py <file.db2>` — WDC4 header + section parser that
  dumps the id-list (handles id_list block + copy table).

**Note on the local CASC path:** the install's *encoding table did not contain the
db2 content hashes* for FDID 1990283/1140089/1003144 (the db2 payload wasn't in the
downloaded blobs), so the id set was taken from the two already-extracted db2 files
above (both confirmed as 3.4.3.54261 SpellName by FDID/root/locale-hash provenance),
not re-fetched. The CDN proxy at 127.0.0.1:8100 was **down** during this run; it was
not needed. If a pristine per-locale SpellName is ever required, fetch the locale
content hash from the root (listed by `extract_db2_by_fdid.py`) via the proxy.

## Regenerate the union
```
python3 - <<'PY'
import sys; sys.path.insert(0,"/Users/shinichi/Works/side-project/wow343-archive/tools")
# parse both files, skip all-zero (encrypted) sections, drop id 0, union, sort.
PY
```
(see the inline script in the extraction session; or just re-union the two
`spellname_343_ids_{enUS,zhTW}.txt` files.)
