# battlefield_template: WotLK-correct data (type-diff table)

**Verdict:** TDB343 (confidence: high). Columns match 343/335 up to cosmetic type differences.

- **Rows:** world_d=1, world_335=1 | pattern: other
- **Structure:** Both DBs define columns TypeId (tinyint unsigned), ScriptName (varchar(64)), comment (text/mediumtext). Minor cosmetic schema differences only: world_d has PRIMARY KEY(TypeId) and ScriptName without a DEFAULT, uses `text` for comment; world_335 has no PK and ScriptName DEFAULT '' and `mediumtext`. Column semantics identical; the loader (BattlefieldMgr.cpp) reads only TypeId and ScriptName, so these DDL cosmetics do not affect gameplay.

## Difference

No content difference. Both DBs contain exactly one identical row: TypeId=1, ScriptName='battlefield_wg', comment=NULL. Both EXCEPT directions (world_d EXCEPT world_335 and vice versa) returned zero rows, i.e. byte-identical content.

## Correct WotLK dataset

Exactly one row registering the Wintergrasp battlefield: TypeId=1 -> ScriptName='battlefield_wg'. Wintergrasp is the sole WotLK 3.3.5a battlefield and TDB343's row matches 3.3.5a verbatim. No other battlefields (Tol Barad is Cataclysm, so correctly absent).

## Dead values / contamination

None. The only row (battlefield_wg / Wintergrasp) is a genuine WotLK feature. No post-WotLK battlefields (e.g. Tol Barad, a Cata addition) are present, so no Cata/MoP/WoD contamination.

## Evidence

- **world_d and world_335 battlefield_template content is byte-identical (both EXCEPT directions empty); each has 1 row: TypeId=1, ScriptName='battlefield_wg', comment=NULL**  
  — docker exec tdb343-db-1 mariadb: (SELECT * FROM world_d.battlefield_template) EXCEPT (SELECT * FROM world_335.battlefield_template) and reverse -> both empty; SELECT * shows single row TypeId=1 battlefield_wg
- **Core loader reads only TypeId and ScriptName from battlefield_template and maps TypeId to a battlefield type; invalid TypeId is skipped**  
  — src/server/game/Battlefield/BattlefieldMgr.cpp:53 (SELECT TypeId, ScriptName FROM battlefield_template) and :63 (Invalid TypeId error/skip)
- **TypeId=1 corresponds to Wintergrasp (BATTLEFIELD_WG), the only battlefield present in WotLK 3.3.5a**  
  — ScriptName 'battlefield_wg' registered by BattlefieldMgr; Wintergrasp is the WotLK world battlefield (Tol Barad, the next battlefield, was added in Cataclysm)

---
_C-layer research workflow (type-diff batch), run wf_a8fd5326-14c._