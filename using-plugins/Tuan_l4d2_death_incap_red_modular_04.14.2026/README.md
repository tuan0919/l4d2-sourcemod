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
   - Heuristic nguon hazard/chay/no, utility theo doi source event.

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
