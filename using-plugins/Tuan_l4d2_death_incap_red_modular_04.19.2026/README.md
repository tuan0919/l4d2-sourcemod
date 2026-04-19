# Tuan_l4d2_death_incap_red (modular 04.19.2026)

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

## Ghi chu tuong thich

- Khong doi ten plugin:
  - `L4D2 Death/Incap Red Announce`
- Khong doi CVAR:
  - `l4d2_redannounce_enable`
  - `l4d2_redannounce_announce_elite_si_kill`
- Khong doi file cfg:
  - `cfg/sourcemod/Tuan_l4d2_death_incap_red.cfg`

## Khuyen nghi sau khi deploy

- Theo doi map/coi nao co nhieu fire chain de so sanh tickrate/trai nghiem truoc va sau.
- Neu van con spike khi spam molotov/gascan, buoc toi uu tiep theo nen la tach them phan `fire source` event cache trong module hazard goc.
