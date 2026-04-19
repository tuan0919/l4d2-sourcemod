# l4d2_elite_si_system (rewrite 13/04/2026, update 19/04/2026)

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

6. `scripting/l4d2_elite_si_smoker_toxic_gas.sp`
   - Nhanh subtype rieng cho Smoker elite theo trait `Toxic Gas`
   - Khong dung tongue pull, uu tien ap sat va danh tay
   - Toc do di chuyen nhanh hon mac dinh
   - Khi bi shove hoac bi giet se tha lan khoi den gay sat thuong lien tuc cho survivor dung trong vung khoi
   - Ho tro cvar rieng de dieu chinh tan suat tick damage cua lan khoi
   - Mac dinh dung attribution o plugin layer de thong bao incap/death do Toxic Gas, khong phu thuoc acid entity cua Spitter

7. `scripting/l4d2_elite_si_smoker_ignitor.sp`
   - Nhanh subtype rieng cho Smoker elite theo trait `Ignitor Smoker`
   - Spawn ra tu boc chay va duoc mien nhiem burn damage
   - Tongue grab hoac melee trung survivor se dat debuff chay gay damage theo tick
   - Khi chet se tao bai lua duoi chan chi gay damage len survivor

8. `scripting/l4d2_elite_si_spitter_acid_pool.sp`
   - Nhanh subtype rieng cho Spitter elite theo trait `Acid Pool`
   - Khong spit theo kieu thuong, thay vao do rai bai acid duoi chan va tren duong di
   - Khi nhay hoac cao trung survivor se tha them puddle acid theo cooldown
   - Tang toc do di chuyen va uu tien ap sat survivor

9. `scripting/l4d2_elite_si_spitter_sneaky.sp`
   - Nhanh subtype rieng cho Spitter elite theo trait `Sneaky`
   - Giu khoang cach, lui khi survivor tien gan va khong chu dong melee pressure
   - Tang hinh theo chu ky, bi shove se mat cloak va dang cloak thi mien bullet damage
   - Moi cycle khac 2 phat acid theo 2 diem khac nhau roi moi quay lai cloak

10. `scripting/l4d2_elite_si_charger_steering.sp`
   - Nhanh bot steering cho Charger trong luc charge
   - Gate theo subtype `ChargerSteering`

11. `scripting/l4d2_elite_si_charger_action.sp`
   - Wrapper gate cho nhanh `ChargerAction` (subtype rieng)
   - Export native `EliteSI_IsChargerAction(client)` de plugin charger action logic goi truc tiep

12. `scripting/l4d2_elite_si_boomer_flashbang.sp`
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
- `29`: Toxic Gas
- `30`: Ignitor Smoker
- `31`: Acid Pool
- `32`: Sneaky

## Rule gan subtype hien tai

- Moi SI truoc tien roll thanh Elite theo `l4d2_elite_si_core_spawn_chance`
- Sau khi da la Elite, core roll subtype bang trong so cvar rieng cua tung subtype hop le trong class do
- `0` = loai subtype do khoi random pool
- Gia tri lon hon chi lam subtype de ra hon tuong doi, khong phai phan tram tuyet doi

- `Smoker`
	- Roll trong so giua `Abnormal behavior`, `Strange Movement`, `Pull Weapon Drop`, `Toxic Gas`, `Ignitor Smoker`

- `Boomer`
  - Roll trong so giua `Abnormal behavior` va `Flashbang`

- `Hunter`
  - Roll trong so giua `Abnormal behavior` va `Target Switch`

- `Spitter`
  - Roll trong so giua `Abnormal behavior`, `Strange Movement`, `Acid Pool`, `Sneaky`

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
- `l4d2_elite_si_smoker_toxic_gas_*`
- `l4d2_elite_si_smoker_ignitor_*`
- `l4d2_elite_si_spitter_acid_pool_*`
- `l4d2_elite_si_spitter_sneaky_*`
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

### 19/04/2026

- Them `Smoker Toxic Gas`: Smoker AI khong dung tongue pull, lao vao danh tay, tang toc do di chuyen, va tha khoi doc khi bi shove hoac bi giet.
- Them module runtime + cvar + web UI cho `Smoker Toxic Gas`.
- Them `Ignitor Smoker`: Smoker tu boc chay, mien burn damage, dot survivor sau tongue grab/melee, va de lai bai lua khi chet.
- Them `Spitter Acid Pool`: Spitter khong spit thuong, lao vao survivor, nhay/cao va rai puddle acid that theo cooldown.
- Them `Spitter Sneaky`: Spitter giu khoang cach, cloak theo chu ky, mien dan khi cloak, va khac burst 2 phat acid truoc khi bien mat lai.

### 18/04/2026

- Tach `Strange Movement` thanh 3 plugin rieng cho Smoker, Spitter, Tank.
- Them `Hunter Target Switch` va `Boomer Flashbang` vao he thong elite subtype.
- Them `Smoker Pull Weapon Drop`: khi Smoker AI keo trung survivor thi se lam rot vu khi dang cam.
- Doi flow roll thanh: SI roll thanh Elite truoc, sau do moi roll subtype theo trong so.
- Loai bo hoan toan `Smoker Noxious` va `Boomer Nauseating` khoi he thong elite hien tai.
