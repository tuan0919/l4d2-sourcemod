# l4d2_elite_si_system (rewrite 13/04/2026, update 25/04/2026)

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
   - Runtime da rebuild damage timer khi doi `damage_interval` / `enable`, khong can reload plugin

7. `scripting/l4d2_elite_si_smoker_ignitor.sp`
   - Nhanh subtype rieng cho Smoker elite theo trait `Ignitor Smoker`
   - Spawn ra tu boc chay va duoc mien nhiem burn damage
   - Tongue grab hoac melee trung survivor se dat debuff chay gay damage theo tick
   - Khi chet se tao bai lua (inferno) duoi chan gay damage rong rãi cho tat ca moi nguoi (giong Boomer Leaker).

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
   - Da fix round reset / clear subtype de khong con restore mau render len survivor ngoai subtype nay

10. `scripting/l4d2_elite_si_boomer_leaker.sp`
   - Nhanh subtype rieng cho Boomer elite theo trait `Leaker`
   - Tu boc chay khi spawn, khong vomit len survivor
   - Chay toi gan survivor, ngoi xuong mot luc roi tu no
   - Vu no va death deu tao `inferno` that cua engine (owner = boomer), co the dot ca survivor lan infected
   - Da noi fallback attribution voi `Tuan_l4d2_death_incap_red` de kill/incap trong inferno resolve ve `Elite Boomer (Leaker)` / `Boomer Leaker Fire`

11. `scripting/l4d2_elite_si_charger_steering.sp`
   - Nhanh bot steering cho Charger trong luc charge
   - Gate theo subtype `ChargerSteering`

12. `scripting/l4d2_elite_si_charger_action.sp`
   - Wrapper gate cho nhanh `ChargerAction` (subtype rieng)
   - Export native `EliteSI_IsChargerAction(client)` de plugin charger action logic goi truc tiep

13. `scripting/l4d2_elite_si_boomer_flashbang.sp`
    - Nhanh subtype rieng cho Boomer elite theo trait Flashbang
    - Khi bi giet, boomer se gay hieu ung flash cho survivor dang thay no

14. `scripting/l4d2_elite_si_jockey_jumper.sp`
    - Nhanh subtype rieng cho Jockey elite theo trait `Jumper`
    - Khi da cuoi trung survivor, Jockey se lien tuc day survivor nay nhay len cao
    - Muc tieu la tao them fall damage khi survivor bi roi xuong sau moi lan nhay

15. `scripting/l4d2_elite_si_jockey_heroic.sp`
    - Nhanh subtype rieng cho Jockey elite theo trait `Heroic`
    - Gan pipebomb len tay phai Jockey khi spawn
    - Khi bat survivor, module tao pipebomb projectile that cua engine de dem nguoc va phat tieng beep tren tay Jockey
    - Neu ride bi gian doan hoac Jockey bi giet, pipebomb roi xuong duoi chan/xac va tiep tuc dem nguoc
    - Khi no gay damage lon trong vung xung quanh

16. `scripting/l4d2_elite_si_tank_ignitor.sp`
    - Nhanh subtype rieng cho Tank elite theo trait `Ignitor`
    - Tank luon luon boc chay khi spawn, mien nhiem hoan toan DMG_BURN
    - Tat ca rock nem ra deu tu dong boc chay (burning rock)
    - Khi burning rock cham bat ky thu gi (world, survivor, props) se tao bai lua (inferno) tai diem va cham, giong Boomer Leaker
    - Rock chay gay them bonus damage % len survivor
    - Attribution thong qua targetname `elite_tank_ignitor_fire` de Red Announce trace credit

17. `scripting/l4d2_elite_si_tank_explosive.sp`
    - Nhanh subtype rieng cho Tank elite theo trait `Explosive`
    - Khi ném đá chạm vào bất kỳ thứ gì sẽ gây nổ với AOE damage + rung màn hình cho survivor trong radius
    - Nếu trúng trực tiếp survivor sẽ nổ ngay dưới chân survivor đó, gây thêm bonus damage
    - Attribution system expose native `EliteSI_TankExplosive_GetRecentDamageCause/Attacker` cho Red Announce trace credit

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
- `33`: Leaker
- `34`: Heroic
- `35`: Unstoppable
- `36`: Jumper
- `37`: Jockey Heroic
- `38`: Tank Ignitor
- `39`: Tank Explosive

## Rule gan subtype hien tai

- Moi SI truoc tien roll thanh Elite theo `l4d2_elite_si_core_spawn_chance`
- Sau khi da la Elite, core roll subtype bang trong so cvar rieng cua tung subtype hop le trong class do
- `0` = loai subtype do khoi random pool
- Gia tri lon hon chi lam subtype de ra hon tuong doi, khong phai phan tram tuyet doi

- `Smoker`
	- Roll trong so giua `Abnormal behavior`, `Strange Movement`, `Pull Weapon Drop`, `Toxic Gas`, `Ignitor Smoker`

- `Boomer`
  - Roll trong so giua `Abnormal behavior`, `Flashbang`, `Leaker`

- `Hunter`
  - Roll trong so giua `Abnormal behavior`, `Target Switch` va `Heroic`

- `Spitter`
  - Roll trong so giua `Abnormal behavior`, `Strange Movement`, `Acid Pool`, `Sneaky`

- `Jockey`
  - Roll trong so giua `Abnormal behavior`, `Jumper` va `Heroic`

- `Charger`
  - Roll trong so giua `Abnormal behavior`, `ChargerSteering`, `ChargerAction`, `Unstoppable`

- `Tank`
  - Roll trong so giua `Abnormal behavior`, `Strange Movement`, `Ignitor` va `Explosive`

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
- `l4d2_elite_si_boomer_leaker_*`
- `l4d2_elite_charger_steering_*`
- `l4d2_elite_charger_action_*`
- `l4d2_elite_si_charger_unstoppable_*`
- `l4d2_elite_si_boomer_flashbang_*`
- `l4d2_elite_si_hunter_heroic_*`
- `l4d2_elite_si_jockey_jumper_*`
- `l4d2_elite_si_jockey_heroic_*`
- `l4d2_elite_si_tank_ignitor_*`
- `l4d2_elite_si_tank_explosive_*`

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

### 25/04/2026 (update 2)

- Rewrite `Sneaky Spitter` v2: bo hoan toan retreat logic, velocity hack, jitter. Spitter hoat dong voi AI behavior binh thuong cua game. Chi giu 2 trait dac biet:
  - Tang hinh (cloak) theo chu ky, bi hit tu survivor se mat cloak, mien bullet damage khi dang cloak. Cloak cooldown > cloak duration de tranh tang hinh lien tuc.
  - 3 lan spit thu cong (khac acid vao survivor gan nhat), moi lan cach nhau 3s cooldown. Native spit ability bi lock de AI khong tu spit them.
- Rewrite `Acid Pool Spitter` v2: bo hoan toan velocity hack, jump logic, trail logic, melee trigger. Spitter hoat dong voi AI behavior binh thuong. Chi giu 1 trait dac biet:
  - Disable kha nang khac tu xa (lock native spit ability). Thay vao do rai acid puddle duoi chan theo cooldown (default 2.5s).
- Bo cvar cu: `retreat_range`, `retreat_speed_multiplier`, `retreat_cooldown`, `retreat_jitter`, `shot_interval`, `shot_spread_distance`, `shot_range`, `speed_multiplier`, `trail_cooldown`, `jump_cooldown`, `melee_cooldown`, `approach_range`, `jump_range`, `trail_min_distance`.

### 25/04/2026

- Them `Tank Explosive`: Elite Tank subtype moi (subtype 39). Rock nem ra se no khi cham bat ky thu gi, gay AOE blast damage + rung man hinh cho survivor trong radius. Neu trung truc tiep survivor se no ngay duoi chan, gay them bonus damage.
- Them subtype roll weight `l4d2_elite_si_core_tank_explosive_subtype_chance` va module config rieng `l4d2_elite_si_tank_explosive_*`.
- Attribution system expose native `EliteSI_TankExplosive_GetRecentDamageCause/Attacker` de Red Announce trace credit.
- Webapp UI: them card `Tank - Explosive` voi day du cvar toggle/number.
- Tank Ignitor (subtype 38) giu nguyen, khong xung dot voi Explosive (subtype 39).

- Them `Tank Ignitor`: Elite Tank luon boc chay, mien nhiem DMG_BURN hoan toan, tat ca rock nem ra deu tu dong chay va tao bai lua (inferno) tai diem va cham.
- Burning rock gay them bonus damage % len survivor (mac dinh +15%).
- Bai lua tao ra co targetname `elite_tank_ignitor_fire` de ho tro attribution cho Red Announce.
- Them subtype roll weight `l4d2_elite_si_core_tank_ignitor_subtype_chance` va module config rieng `l4d2_elite_si_tank_ignitor_*`.
- Fix `Strange Movement Spitter`: sau khi `ability_spit`, module gio ep velocity ve survivor gan nhat/huong nhin de Spitter tiep tuc di chuyen trong luc khac acid thay vi chi unlock maxspeed.
- Fix `Strange Movement Smoker`: them tracking `tongue_grab`; Smoker gio di chuyen khi ban tongue, tiep tuc di lui keo survivor sau khi grab thanh cong, va reset speed ve `z_gas_speed` thay vi `tongue_victim_max_speed`.
- Fix `Jockey Heroic`: doi tu prop/timer tu no sang `CPipeBombProjectile_Create` giong `Hunter Heroic`, de pipebomb co tieng beep countdown that cua engine.
- Khi Jockey bat survivor, active pipebomb that duoc parent vao tay phai va tiep tuc fuse/beep trong luc ride.
- Khi ride bi gian doan hoac Jockey bi giet, active pipebomb duoc `ClearParent`, roi xuong dat/xac va tiep tuc dem nguoc thay vi reset timer.
- Khi Jockey chet truoc khi bat survivor, module spawn pipebomb projectile that duoi chan voi fuse day du.
- Damage va attribution cua `Jockey Heroic` da dong bo voi `Hunter Heroic`: direct survivor damage bypass difficulty scaling, co falloff theo radius, co damage common infected va inflictor la pipe entity targetname `elite_jockey_heroic_pipe` de Red Announce trace credit.
- Hotfix damage khi pipebomb no luc van parent tren tay Jockey: manual blast gio lay tam no theo survivor dang bi ride/Jockey hien tai thay vi origin stale cua projectile dang parent.
- Hotfix lifecycle pipebomb: active pipe chi duoc consume mot lan. Sau khi pipe dang cam da no, death event cua Jockey khong con spawn them pipe moi tu xac.
- Hotfix damage khi pipe con tren tay: them pre-detonate drop sat thoi diem fuse het de engine explosion va manual damage cung dung tam no nhu case pipe da roi dat.
- Don gian hoa rule bounce: neu pipebomb het fuse khi Jockey van dang ride survivor, survivor dang bi ride se bi force-kill truc tiep, khong phu thuoc tinh damage/radius.
- Force-kill bounce gio chay bang timer rieng sau thoi diem pipe no va co fallback `ForcePlayerSuicide` neu damage cua engine chi lam survivor incap.
- Expose native `EliteSI_JockeyHeroic_GetRecentDamageCause/Attacker` de Red Announce resolve dung kill message khi fallback suicide duoc dung sau pipe no.

### 24/04/2026

- Them `Jockey Jumper`: Elite Jockey lien tuc nhay khi dang ride survivor, moi lan nhay day survivor len cao de tao them fall damage khi roi xuong.
- Them subtype roll weight `l4d2_elite_si_core_jockey_jumper_subtype_chance` va module config rieng `l4d2_elite_si_jockey_jumper_*`.
- Them thu nghiem `Jockey Heroic`: Jockey mang pipebomb tren tay, kich hoat khi ride survivor, roi pipebomb neu bi gian doan/bi giet, va no gay damage lon quanh khu vuc.

### 21/04/2026

- Da chuyen huong hoan toan attribution phu thuoc classname che phan do logic Entity tracker (targetname).
- Update logic cho Smoker Toxic Gas, Boomer Leaker, va Smoker Ignitor de chung gan dung targetname len ent khi tao moi (cu the nhu `elite_boomer_leaker_fire`, `elite_smoker_ignitor_fire`, va `elite_smoker_toxic_gas`), dam bao dong bo plugin Red API bat duoc nguon goc va chuyen hoa dung ten Elite Type vao In-game chat thay vi ten tho Entity (`Info Particle System` / `Inferno`).

### 20/04/2026

- Them `Hunter Heroic`: Elite Hunter cầm sẵn pipebomb trong tay. Khi đè survivor hoặc khi bị giết, tự động drop pipebomb xuống đất nổ gây lượng sát thương lớn.
- Hotfix trang thai logic bi loop `Handle Error 3 (Invalid Handle)` cua timer o module `Smoker Toxic Gas` chong leak qua qua trinh map transition/reloadconfig.
- Hotfix xung dot "Native already in use" cua `Core` module do duplicate build giua folder qol va plugins.

### 19/04/2026

- Them `Smoker Toxic Gas`: Smoker AI khong dung tongue pull, lao vao danh tay, tang toc do di chuyen, va tha khoi doc khi bi shove hoac bi giet.
- Them module runtime + cvar + web UI cho `Smoker Toxic Gas`.
- Them `Ignitor Smoker`: Smoker tu boc chay, mien burn damage, dot survivor sau tongue grab/melee, va de lai bai lua khi chet.
- Them `Spitter Acid Pool`: Spitter khong spit thuong, lao vao survivor, nhay/cao va rai puddle acid that theo cooldown.
- Them `Spitter Sneaky`: Spitter giu khoang cach, cloak theo chu ky, mien dan khi cloak, va khac burst 2 phat acid truoc khi bien mat lai.
- Them `Boomer Leaker`: Boomer tu boc chay, khong bile survivor, tiep can roi tu no de tao bai lua gay damage ca hai phe.

### 18/04/2026

- Tach `Strange Movement` thanh 3 plugin rieng cho Smoker, Spitter, Tank.
- Them `Hunter Target Switch` va `Boomer Flashbang` vao he thong elite subtype.
- Them `Smoker Pull Weapon Drop`: khi Smoker AI keo trung survivor thi se lam rot vu khi dang cam.
- Doi flow roll thanh: SI roll thanh Elite truoc, sau do moi roll subtype theo trong so.
- Loai bo hoan toan `Smoker Noxious` va `Boomer Nauseating` khoi he thong elite hien tai.
