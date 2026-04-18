# l4d2_elite_si_system (rewrite 13/04/2026, update 18/04/2026)

## Muc tieu rewrite

Rewrite lai he thong Elite SI + reward HP theo huong module, giam chong cheo logic va tach ro vai tro tung plugin.

## Kien truc hien tai

He thong moi da tach thanh bo module nho, load doc lap:

1. `scripting/l4d2_elite_si_core.sp`
   - Nguon su that cho Elite SI (roll elite, HP multiplier, mau render, subtype API)
   - Expose native:
     - `EliteSI_IsElite(client)`
     - `EliteSI_GetSubtype(client)`
     - `EliteSI_IsFireImmune(client)`
   - Backward compatibility native:
     - `L4D2_IsEliteSI(client)`
     - `L4D2_GetEliteSubtype(client)`
   - Expose forward:
     - `EliteSI_OnEliteAssigned(client, zclass, subtype)`
     - `EliteSI_OnEliteCleared(client)`

2. `scripting/l4d2_elite_si_rewards.sp`
   - Thuong Temp HP cho Elite SI, optional Normal SI, Tank, Witch
   - Scale theo difficulty + headshot bonus
   - Ho tro mau instructor hint rieng cho elite SI va normal SI
   - Expose forward:
     - `EliteSIReward_OnGranted(receiver, amount, sourceClass, mode)`

3. Nhanh `Abnormal behavior` (tach theo tung SI + 1 module director):
   - `scripting/l4d2_elite_si_hardsi_director.sp`
   - `scripting/l4d2_elite_si_hardsi_smoker.sp`
   - `scripting/l4d2_elite_si_hardsi_boomer.sp`
   - `scripting/l4d2_elite_si_hardsi_hunter.sp`
   - `scripting/l4d2_elite_si_hunter_target_switch.sp`
   - `scripting/l4d2_elite_si_hardsi_spitter.sp`
   - `scripting/l4d2_elite_si_hardsi_jockey.sp`
   - `scripting/l4d2_elite_si_hardsi_charger.sp`
   - `scripting/l4d2_elite_si_hardsi_tank.sp`

4. Nhanh `Strange Movement` (tach theo tung SI):
   - `scripting/l4d2_elite_si_infected_movement_smoker.sp`
   - `scripting/l4d2_elite_si_infected_movement_spitter.sp`
   - `scripting/l4d2_elite_si_infected_movement_tank.sp`

5. `scripting/l4d2_elite_si_smoker_pull_weapon_drop.sp`
   - Nhanh subtype rieng cho Smoker elite theo trait `Pull Weapon Drop`
   - Khi `tongue_grab` thanh cong, survivor bi keo se rot vu khi dang cam tren tay

6. `scripting/l4d2_elite_si_charger_steering.sp`
   - Nhanh bot steering cho Charger trong luc charge
   - Gate theo subtype `ChargerSteering`

7. `scripting/l4d2_elite_si_charger_action.sp`
   - Wrapper gate cho nhanh `ChargerAction` (subtype rieng)
   - Export native `EliteSI_IsChargerAction(client)` de plugin charger action logic goi truc tiep

8. `scripting/l4d2_elite_si_boomer_flashbang.sp`
   - Nhanh subtype rieng cho Boomer elite theo trait Flashbang
   - Khi bi giet, boomer se gay hieu ung flash cho survivor dang thay no

## Subtype mapping dang dung

- `0`: none
- `1`: Abnormal behavior
- `2`: Strange Movement
- `3`: ChargerSteering
- `4`: ChargerAction
- `26`: Target Switch
- `27`: Flashbang
- `28`: Pull Weapon Drop

## Rule gan subtype hien tai

- Moi SI truoc tien roll thanh Elite theo `l4d2_elite_si_core_spawn_chance`
- Sau khi da la Elite, core roll subtype bang trong so cvar rieng cua tung subtype hop le trong class do
- `0` = loai subtype do khoi random pool
- Gia tri lon hon chi lam subtype de ra hon tuong doi, khong phai phan tram tuyet doi

- `Smoker`
	- Roll trong so giua `Strange Movement` va `Pull Weapon Drop`

- `Boomer`
  - Roll trong so giua `Abnormal behavior` va `Flashbang`

- `Hunter`
  - Roll trong so giua `Abnormal behavior` va `Target Switch`

- `Spitter`
  - Roll trong so giua `Abnormal behavior` va `Strange Movement`

- `Jockey`
  - Hien tai chi co `Abnormal behavior`

- `Charger`
  - Roll trong so giua `Abnormal behavior`, `ChargerSteering`, `ChargerAction`

- `Tank`
  - Roll trong so giua `Abnormal behavior` va `Strange Movement`

## Prefix cvar con su dung

- `l4d2_elite_si_core_*`
- `l4d2_elite_reward_*`
- `l4d2_elite_si_hardsi_*`
- `l4d2_elite_si_infected_movement_*`
- `l4d2_elite_si_hunter_target_switch_*`
- `l4d2_elite_si_smoker_pull_weapon_drop_*`
- `l4d2_elite_charger_steering_*`
- `l4d2_elite_charger_action_*`
- `l4d2_elite_si_boomer_flashbang_*`

## Flow hien tai

1. SI spawn.
2. Core check `l4d2_elite_si_core_spawn_cooldown`.
3. Neu khong bi cooldown chan, core roll `l4d2_elite_si_core_spawn_chance`.
4. Neu thanh Elite:
   - buff HP theo `l4d2_elite_si_core_hp_multiplier`
   - chon 1 subtype hop le theo bo `*_subtype_chance` cua dung SI class do
   - apply render color theo class/subtype
   - plugin nhanh theo subtype tiep quan ly logic rieng

## Luu y migration

- Da go khoi he thong elite hien tai:
  - toan bo nhanh Smoker Noxious
  - toan bo nhanh Boomer Nauseating
- Khong con giu force subtype, UI card, config map hoac doc tham chieu cho 2 nhanh tren.

## Changelog tom tat

### 18/04/2026

- Tach `Strange Movement` thanh 3 plugin rieng cho Smoker, Spitter, Tank.
- Them `Hunter Target Switch` va `Boomer Flashbang` vao he thong elite subtype.
- Them `Smoker Pull Weapon Drop`: khi Smoker AI keo trung survivor thi se lam rot vu khi dang cam.
- Doi flow roll thanh: SI roll thanh Elite truoc, sau do moi roll subtype theo trong so.
- Loai bo hoan toan `Smoker Noxious` va `Boomer Nauseating` khoi he thong elite hien tai.
