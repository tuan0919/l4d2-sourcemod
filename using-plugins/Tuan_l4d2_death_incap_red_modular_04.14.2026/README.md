# Tuan_l4d2_death_incap_red (modular 14/04/2026)

## Muc tieu refactor

- Tach plugin death/incap thanh bo module nho, moi file phu trach 1 nhom trach nhiem.
- Giu nguyen ten plugin/CVAR/config de khong vo luong dieu khien tu webapp va server runtime.
- Don gian hoa viec doc/sua logic ma khong phai mo 1 file qua lon.

## Wrapper entrypoint

- `l4d2-sourcemod/addons/sourcemod/scripting/Tuan_l4d2_death_incap_red.sp`
  - Wrapper compile/deploy, include vao bo module trong `using-plugins`.

## Cau truc module

1. `scripting/death_incap_red_defs.inc`
   - Dinh nghia macro, enum, bien global, `myinfo`, native optional.

2. `scripting/death_incap_red_lifecycle.inc`
   - Vong doi plugin: `OnPluginStart`, map/client lifecycle, cvar change.

3. `scripting/death_incap_red_entity_hooks.inc`
   - Entity-level hook callback: create/destroy hazard source entity.

4. `scripting/death_incap_red_tracking.inc`
   - Timers + snapshot/hazard tracking callback (`OnTakeDamageAlive`, frame/timer helper).

5. `scripting/death_incap_red_events.inc`
   - Event flow chinh: incap/death/witch/shove va in ket qua chat.

6. `scripting/death_incap_red_outcome.inc`
   - Resolve attacker/cause tong quan + format ten vu khi/SI.

7. `scripting/death_incap_red_survivor_cause.inc`
   - Resolve cause chi tiet cho nhom survivor kill SI/Witch va qualifier token.

8. `scripting/death_incap_red_hazard.inc`
   - Resolve nguon hazard/chay/no theo 2 lop: deterministic (entity-link) + heuristic fallback.

9. `scripting/death_incap_red_notify_state.inc`
   - Chat printing utility, state helper, state-query helper.

10. `scripting/Tuan_l4d2_death_incap_red_modular.sp`
    - File tong include theo thu tu dependency.

## Cam ket tuong thich sau refactor

- Khong doi ten plugin:
  - `L4D2 Death/Incap Red Announce`
- Khong doi CVAR:
  - `l4d2_redannounce_enable`
  - `l4d2_redannounce_announce_elite_si_kill`
- Khong doi file cfg:
  - `cfg/sourcemod/Tuan_l4d2_death_incap_red.cfg`

## Build/deploy

- Compile wrapper:
  - `l4d2-sourcemod/addons/sourcemod/scripting/Tuan_l4d2_death_incap_red.sp`
- Output `.smx` giu nguyen:
  - `Tuan_l4d2_death_incap_red.smx`
- Deploy vao plugin QOL theo vi tri hien tai:
  - `l4d2-sourcemod/addons/sourcemod/plugins/qol/Tuan_l4d2_death_incap_red.smx`

## Update 14/04/2026 - Fire source resolver

Da refactor lai logic nhan dien `inferno/entityflame` de ro rang hon va giam false classify:

- Uu tien deterministic resolver truoc:
  - Quet graph lien ket entity (`m_hOwnerEntity`, `m_hMoveParent`, `m_hEffectEntity`, `m_hInflictor`, `m_hPhysicsAttacker`, `m_hThrower`) de truy hazard source truc tiep.
- Heuristic resolver chi dung fallback:
  - Neu deterministic khong ra ket qua moi dung match theo vi tri/thoi gian.
- Them second-pass recheck sau khi fire entity spawn:
  - Recheck delay ngan de bat cac link set tre.
- Them cache + confidence cho fire entity source:
  - Khong de ket qua heuristic de ket qua deterministic con hieu luc.
- Rule gascan/molotov an toan hon:
  - Khong override `gascan -> molotov` neu van co bang chung gascan ro rang.

Hang so moi lien quan den resolver:

- `FIRE_SOURCE_CACHE_WINDOW`
- `FIRE_ENTITY_RECHECK_DELAY`
- `FIRE_ENTITY_LINK_SCAN_MAX`

## Update 16/04/2026 - Elite Smoker Noxious cause

- Tich hop native optional tu module noxious:
  - `EliteSI_Noxious_GetRecentDamageCause(victim)`
  - `EliteSI_Noxious_GetRecentDamageAttacker(victim)`

- Khi victim bi ha guc/chet boi noxious damage, plugin uu tien resolve cause cu the:
  - `Smoker Asphyxiation`
  - `Smoker Collapsed Lung`
  - `Smoker Methane Blast`
  - `Smoker Methane Leak`
  - `Smoker Tongue Whip`
  - `Smoker Void Pocket`
  - `Smoker Restrained Hostage`

- Ket qua:
  - Giam truong hop chat do bao gom chung chung `Smoker claws` voi cac noxious damage.
