# Tuan_l4d2_death_incap_red (modular 04.25.2026)

## Muc tieu ban nay

- Tao ban moi nhat de dong bo source-of-truth voi wrapper va de luu cac cap nhat lien quan `Smoker Toxic Gas`.
- Giu nguyen ten plugin, CVAR, file cfg va hanh vi announce chinh.
- Chi giam chi phi runtime o cac duong nong lien quan den fire/hazard tracking.

## Cach to chuc

- Folder nay la ban source-of-truth hien tai cua `Tuan_l4d2_death_incap_red`.
- Tat ca module `.inc` deu duoc copy local vao folder nay.
- Khong include cheo sang version cu de tranh phu thuoc an va de de backup/rollback.

## Build/deploy

- Wrapper compile van la:
  - `l4d2-sourcemod/addons/sourcemod/scripting/Tuan_l4d2_death_incap_red.sp`
- Wrapper da duoc doi include sang folder nay.
- Output `.smx` giu nguyen:
  - `Tuan_l4d2_death_incap_red.smx`

## Thay doi toi uu 17/04/2026

### 1. Tach timer anchor va burn-watch

- Bo callback hop nhat chay cho ca `5.0s` va `0.25s`.
- Anchor check gio chay timer rieng `5.0s`.
- Burn-watch timer chi duoc tao khi thuc su co victim dang bi fire-assist lock.

Loi ich:

- Giam callback lap vo ich trong luc server idle.
- Khong con truong hop anchor bi check day hon du kien do dung chung callback.

### 2. Khong scan graph entity trong damage hook nong

- Khi `OnTakeDamageAlive` gap `DMG_BURN`, plugin moi chi doc fire-source cache da co.
- Neu cache miss thi cho phep fallback heuristic nhe theo source event, khong tu deterministic-resolve graph ngay trong hook damage.

Loi ich:

- Cat bot chi phi lon nhat o duong nong khi nhieu burn tick xay ra cung luc.
- Van giu duoc kha nang resolve nguon hazard trong phan announce chinh.

### 3. Tang cua so cache fire entity

- `FIRE_SOURCE_CACHE_WINDOW`: `15.0` -> `25.0`

Loi ich:

- Giam so lan can resolve lai fire entity da duoc danh dau truoc do.
- It anh huong den do chinh xac hon viec giam manh heuristic window.

## Thay doi 19/04/2026 - Toxic Gas integration

- Tich hop native optional moi tu `l4d2_elite_si_smoker_toxic_gas`:
  - `EliteSI_ToxicGas_GetRecentDamageCause(victim)`
  - `EliteSI_ToxicGas_GetRecentDamageAttacker(victim)`
- `ResolveAttacker` va `ResolveSpecialInfectedCause` gio co the quy incap/death cua survivor ve:
  - `Elite Smoker (Toxic Gas)`
  - cause `Smoker Toxic Gas`
- Muc tieu:
  - khi toxic gas cloud lam survivor guc/chet sau khi Smoker da chet, chat red van hien attacker/cause dung voi elite type.

## Thay doi 21/04/2026 - Targetname and Snapshot resolution fix

- Fix triet de hien tuong bao attacker la `Info Particle System`:
  - Trong luong xu ly incapacitated cua Source Engine khong kem thong tin `attackerentid` vao event.
  - Fix bang cach check ca Snapshot Inflictor cua Red API giong nhu truong hop vu khi (fallback vao entity cuoi cung gay damage duoc luu lai).
  - Tich hop targetname `elite_boomer_leaker_fire`, `elite_smoker_ignitor_fire`, va `elite_smoker_toxic_gas` de attribute chinh xac sat thuong gay ra tu nguyen nhan leaker/ignitor/toxic_gas ve elite subtype tuong ung thay vi classname mac dinh.

## Ghi chu tuong thich

- Khong doi ten plugin:
  - `L4D2 Death/Incap Red Announce`
- Khong doi CVAR:
  - `l4d2_redannounce_enable`
  - `l4d2_redannounce_announce_elite_si_kill`
- Khong doi file cfg:
  - `cfg/sourcemod/Tuan_l4d2_death_incap_red.cfg`

## Thay doi 25/04/2026 - Heroic Jockey pipebomb credit

- Mo rong heroic pipe tracking tu rieng `elite_hunter_heroic_pipe` sang ca `elite_jockey_heroic_pipe`.
- Ring buffer heroic pipe explosion gio luu them loai pipe (`Hunter`/`Jockey`) de khi pipe entity destroy truoc damage event van resolve dung attacker label.
- Incap/death do pipebomb Jockey Heroic gio hien credit `Elite Jockey (Heroic)` va cause `Heroic Pipebomb` thay vi fallback sang self/explosive hoac nham Hunter Heroic.
- Logic nay dung chung path targetname + snapshot inflictor + recent explosion ring buffer voi Hunter Heroic.
- Neu Jockey Heroic module dung `ForcePlayerSuicide` de ket lieu survivor dang bi ride sau khi pipe no, Red Announce van uu tien recent heroic pipe ring buffer truoc self/suicide fallback.
- Suicide fallback gan pipe Jockey se hien `Elite Jockey (Heroic)` killed survivor voi cause `Heroic Pipebomb`.

## Khuyen nghi sau khi deploy

- Theo doi map/coi nao co nhieu fire chain de so sanh tickrate/trai nghiem truoc va sau.
- Neu van con spike khi spam molotov/gascan, buoc toi uu tiep theo nen la tach them phan `fire source` event cache trong module hazard goc.

## Thay doi 21/04/2026 (2) - Fix fire/explosion cause detection

### Van de

- Plugin nhieu luc nham lan fire tu molotov va gascan vi:
  - `molotov_projectile` bi destroy truoc khi `inferno` spawn → BFS deterministic miss, roi vao heuristic
  - `IsLikelyGascanInferno` chi loai tru molotov ma khong co positive gascan evidence
  - `HasExplicitMolotovEvidence` dung `WasRecentMolotovThrow(3.0s)` khong co distance check → race condition khi cung player nem molotov va ban gascan trong 3s
  - Khong co gascan explosion timestamp rieng de so sanh voi inferno position

### Fix

1. Them 2 ring buffer moi:
   - `GascanExplode` (32 slots): luu position + owner + timestamp khi gascan bi destroy
   - `MolotovDestroy` (32 slots): luu position + owner + timestamp khi molotov_projectile bi destroy
2. `ResolveFireSourceHeuristic`: them 2 buoc lookup ring buffer moi giua `FindBestFireSource` va fallback `WasRecentMolotovThrow`
3. `IsLikelyGascanInferno`: doi tu negative-only logic sang positive evidence (phai co gascan no gan do trong ring buffer)
4. `HasExplicitMolotovEvidence`: thu hep window 3.0→2.0s, them distance check qua molotov destroy ring buffer
5. Reset ca 2 ring buffer trong `OnMapStart`

## Thay doi 21/04/2026 (3) - SI/Tank fire source tracking

### Van de

- Khi SI/Tank bi dam vao inferno (molotov/gascan) roi chay ra xa, `entityflame` tren nguoi chung khong con link ve inferno goc.
- Plugin khong the trace owner → announce chi hien "fire" chung chung, khong biet ai gay ra.

### Fix

- Them per-client SI fire snapshot: `g_iSIFireSourceType`, `g_iSIFireSourceOwner`, `g_fSIFireSourceTime`, `g_bSIWasOnFire`
- `OnTakeDamageAlive` gio track ca team 3: moi khi SI/Tank nhan `DMG_BURN`, resolve fire source va update snapshot
- Khi SI/Tank het chay (`IsClientCurrentlyOnFire` = false), clear snapshot de lan chay tiep theo resolve lai tu dau (tranh nham lan giua 2 lan chay khac nhau)
- `Event_PlayerDeath` (victim team 3): neu SI chet boi fire ma khong co attacker ro rang, kiem tra SI fire snapshot → neu con fresh va co owner → announce dung attacker + cause

### Files thay doi

- `death_incap_red_defs.inc`: them 4 per-client SI fire snapshot arrays
- `death_incap_red_tracking.inc`: them SI fire tracking trong `OnTakeDamageAlive`, them `ClearSIFireSnapshot`, `GetSIFireSnapshot`
- `death_incap_red_events.inc`: them SI fire snapshot lookup trong `Event_PlayerDeath`
- `death_incap_red_lifecycle.inc`: reset SI fire snapshot trong `OnMapStart` va `OnClientDisconnect`

## Thay doi 21/04/2026 (4) - Chain fire owner + explosion entity fix

### Van de

- Chain fire (molotov → gascan t1 → gascan tn): `OnHazardTakeDamagePost` khong resolve duoc owner khi attacker la `inferno` entity (khong co `m_hOwnerEntity` tro ve survivor) → owner bi mat qua chain
- `IsExplosiveFromEntities` thieu check propane/oxygen entity → neu attackerEnt la propane/oxygen con song luc damage thi `explosive=false`, phai doi vao `TryCauseFromHazardContext` (4s window), neu qua 4s thi miss

### Fix

- `OnHazardTakeDamagePost`: khi `ResolveDamageOwnerClient` tra ve 0, thu lookup `TryReadFreshFireSourceCache` tren `attacker` va `inflictor` de lay owner goc tu fire source cache → chain fire gio trace duoc owner xuyen qua nhieu gascan
- `IsExplosiveFromEntities`: them check `EntityIsPropaneTank` va `EntityIsOxygenTank` tren ca `attackerEnt` va `snapInflictor`

### Files thay doi

- `death_incap_red_tracking.inc`: sua `OnHazardTakeDamagePost`
- `death_incap_red_survivor_cause.inc`: sua `IsExplosiveFromEntities`

## Thay doi 21/04/2026 (5) - Wallbang detection via trace ray

### Van de

- `penetrated` field trong `player_death` event cua L4D2 luon = 0, wallbang khong bao gio duoc detect du ban xuyen tuong/cua

### Fix

- Thay `event.GetInt("penetrated", 0) > 0` bang `IsWallbangKill(attacker, victim)`
- `IsWallbangKill`: trace ray tu attacker eye position → victim center mass voi `MASK_SHOT` + `TraceFilter_IgnorePlayers`
- Neu ray hit world geometry truoc khi reach victim va distance > 20 units → wallbang = true
- Chi chay 1 lan tai killing blow → chi phi gan bang 0

### Files thay doi

- `death_incap_red_events.inc`: doi wallbang detection
- `death_incap_red_notify_state.inc`: them `IsWallbangKill` + `TraceFilter_IgnorePlayers`
