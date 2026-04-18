# l4d2_elite_si_system (rewrite 13/04/2026, update 16/04/2026)

## Muc tieu rewrite

Rewrite lai he thong Elite SI + reward HP theo huong module, giam chong cheo logic va tach ro vai tro tung plugin.

## Kien truc moi

He thong moi da tach nhanh Abnormal Behavior theo tung SI, tong cong 15 plugin nho, load doc lap:

1. `scripting/l4d2_elite_si_core.sp`
   - Nguon su that cho Elite SI (roll elite, HP multiplier, mau render, fire immunity)
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
     - Nhanh global cho nhac `nb_assault`.
     - Khong con exec file aggressive cfg dung chung trong `cfg/l4d2_elite_si_hardsi/`.
   - `scripting/l4d2_elite_si_hardsi_smoker.sp`
     - Smoker action hook de tranh bug `nb_assault`
   - `scripting/l4d2_elite_si_hardsi_boomer.sp`
     - Boomer bhop + vomit pressure movement
   - `scripting/l4d2_elite_si_hardsi_hunter.sp`
     - Hunter fast pounce + pounce angle tuning + leap-away gate
   - `scripting/l4d2_elite_si_hardsi_spitter.sp`
     - Spitter bhop pressure
   - `scripting/l4d2_elite_si_hardsi_jockey.sp`
     - Jockey hop pressure
   - `scripting/l4d2_elite_si_hardsi_charger.sp`
     - Charger force-charge + bhop + retarget angle
   - `scripting/l4d2_elite_si_hardsi_tank.sp`
     - Tank bhop + smart rock + allow/deny rock throw

4. Nhanh `Strange Movement` (tach theo tung SI):
   - `scripting/l4d2_elite_si_infected_movement_smoker.sp`
     - Giu toc do cho Smoker elite bot khi cast `ability_tongue`
   - `scripting/l4d2_elite_si_infected_movement_spitter.sp`
     - Giu toc do cho Spitter elite bot khi cast `ability_spit`
   - `scripting/l4d2_elite_si_infected_movement_tank.sp`
     - Giu toc do cho Tank elite bot khi cast `ability_throw`

5. `scripting/l4d2_elite_si_charger_steering.sp`
   - Nhanh bot steering cho Charger trong luc charge
   - Gate theo subtype `ChargerSteering`

6. `scripting/l4d2_elite_si_charger_action.sp`
   - Wrapper gate cho nhanh `ChargerAction` (subtype rieng)
   - Export native `EliteSI_IsChargerAction(client)` de plugin charger action logic goi truc tiep

7. `scripting/l4d2_elite_si_smoker_noxious.sp`
   - Nhanh subtype rieng cho Smoker elite theo bo Noxious Smoker
   - Moi Smoker elite chi roll dung 1 subtype Noxious, khong stack nhieu subtype
   - Hien thuc cac type: Asphyxiation, Collapsed Lung, Methane Blast, Methane Leak,
     Methane Strike, Moon Walk, Restrained Hostage, Smoke Screen, Tongue Strip,
     Tongue Whip, Void Pocket

8. `scripting/l4d2_elite_si_boomer_nauseating.sp`
   - Nhanh subtype rieng cho Boomer elite theo bo Nauseating Boomer
   - Moi Boomer elite chi roll dung 1 subtype Nauseating, khong stack nhieu subtype
   - Hien thuc cac type: Bile Belly, Bile Blast, Bile Feet, Bile Mask, Bile Pimple,
     Bile Shower, Bile Swipe, Bile Throw, Explosive Diarrhea, Flatulence

## Subtype mapping

- `0`: none
- `1`: Abnormal behavior (legacy internal: HardSI, code enum moi: `ELITE_SUBTYPE_ABNORMAL_BEHAVIOR`)
- `2`: Strange Movement (legacy internal: AbilityMovement)
- `3`: ChargerSteering
- `4`: ChargerAction
- `5`: Asphyxiation
- `6`: Collapsed Lung
- `7`: Methane Blast
- `8`: Methane Leak
- `9`: Methane Strike
- `10`: Moon Walk
- `11`: Restrained Hostage
- `12`: Smoke Screen
- `13`: Tongue Strip
- `14`: Tongue Whip
- `15`: Void Pocket
- `16`: Bile Belly
- `17`: Bile Blast
- `18`: Bile Feet
- `19`: Bile Mask
- `20`: Bile Pimple
- `21`: Bile Shower
- `22`: Bile Swipe
- `23`: Bile Throw
- `24`: Explosive Diarrhea
- `25`: Flatulence

## Cvar moi (khong tai su dung key cu)

Tat ca cvar moi su dung prefix:

- `l4d2_elite_si_core_*`
- `l4d2_elite_reward_*`
- `l4d2_elite_si_hardsi_*`
- `l4d2_elite_si_infected_movement_*`
- `l4d2_elite_charger_steering_*`
- `l4d2_elite_charger_action_*`
- `l4d2_elite_smoker_noxious_*`
- `l4d2_elite_boomer_nauseating_*`

### Reward update 14/04/2026

Bo reward da bo sung them nhom cvar de ho tro normal SI va mau hint rieng:

- `l4d2_elite_reward_normal_si_enable`
  - `0`: chi thuong elite SI
  - `1`: normal SI (non-elite) cung co reward

- `l4d2_elite_reward_normal_si_amount`
  - Luong Temp HP thuong cho normal SI

- `l4d2_elite_reward_hint_color_normal_si`
  - Mau instructor hint khi kill normal SI
  - Mac dinh: `255 255 255` (trang)

- `l4d2_elite_reward_hint_color_elite_si`
  - Mau instructor hint khi kill elite SI
  - Mac dinh: `255 255 0` (vang)

Luu y: `l4d2_elite_reward_si_enable` hien tai la cong tac tong cho reward SI.
Neu tat cvar nay thi ca elite SI va normal SI deu khong duoc thuong.

### Core + Noxious update 15/04/2026

- Core bo sung cvar:
  - `l4d2_elite_si_core_spawn_announce`
    - `0`: tat thong bao spawn elite SI
    - `1`: thong bao chat mau do, kem type + mo ta ngan

  - `l4d2_elite_si_core_spawn_cooldown`
    - Cooldown global giua 2 lan roll spawn Elite SI thanh cong
    - Mac dinh: `20.0` giay

  - `l4d2_elite_si_core_boomer_force_subtype`
    - `0`: random boomer nauseating subtype
    - `16-25`: ep dung subtype boomer de test

- Smoker elite khong con roll qua `l4d2_elite_si_core_smoker_ability_subtype_chance`.
  Thay vao do roll ngau nhien 1 trong 11 Noxious subtype.

- Elite type text da ho tro custom theo tung SI class + subtype qua file data:
  - `addons/sourcemod/data/elite_si_type_descriptions.cfg`
  - Vi du Abnormal behavior cua Charger co the dat mo ta khac Abnormal behavior cua Smoker.
  - Tu 16/04/2026: file data chi dung key subtype hop le theo tung SI class, de tranh lan mo ta giua cac class.
    - `smoker`: `5..15`
    - `boomer`: `1, 16..25`
    - `hunter`: `1`
    - `spitter`: `1, 2`
    - `jockey`: `1`
    - `charger`: `1, 3, 4`

- Core expose native moi de plugin khac lay ten/desc type dang active:
  - `EliteSI_GetTypeName(client, buffer, maxlen)`
  - `EliteSI_GetTypeDescription(client, buffer, maxlen)`
  - Legacy alias: `L4D2_GetEliteTypeName`, `L4D2_GetEliteTypeDescription`

- Chat announce elite SI da doi sang mau theo `{red}` (colors include),
  dong bo voi he thong notify hien tai.

- Core khong con auto-load module noxious.
  - Plugin `l4d2_elite_si_smoker_noxious.smx` can duoc load san trong plugin list.

- HardSI director chi con control nhac `nb_assault` qua cvar rieng.
- Khong con doc/exec aggressive cfg dung chung tu folder `cfg/l4d2_elite_si_hardsi/`.

  - Co bo sung runtime cfg de de override tren server:
  - `cfg/sourcemod/l4d2_elite_si_smoker_noxious.cfg`
  - `cfg/sourcemod/l4d2_elite_si_boomer_nauseating.cfg`

## Tich hop giua plugin

- Core cap du lieu subtype bang native
- Cac nhanh behavior (Abnormal behavior / Strange Movement / ChargerSteering / ChargerAction / Smoker Noxious / Boomer Nauseating)
  doc native de gate dung subtype
- Core + Reward expose global forward de plugin khac co the subscribe event

## Compile

Da compile thanh cong cac file `.sp` trong bo module rewrite.

## Luu y migration

- Khi ap dung bo rewrite moi, nen unload cac plugin cu de tranh duplicate logic:
  - `l4d2_elite_SI_reward`
  - `Tuan_AI_HardSI`
  - `l4d_infected_movement`
  - `l4d2_charger_steering` (ban cu)

## Changelog

### 14/04/2026

- Bo sung reward cho normal SI (co cvar bat/tat rieng)
- Bo sung cvar so HP thuong cho normal SI
- Bo sung 2 cvar mau instructor hint rieng cho normal SI va elite SI

### 15/04/2026

- Tich hop bo Noxious Smoker vao he thong elite subtype
- Smoker elite moi lan spawn chi co 1 type Noxious (khong stack)
- Doi ten hien thi subtype:
  - `HardSI` -> `Abnormal behavior`
  - `AbilityMovement` -> `Strange Movement`
- Bo sung thong bao spawn elite SI chat full mau do + mo ta ngan subtype

### 16/04/2026

- Tat publish thong bao spawn elite sang script HUD notifier.
  - `l4d2_elite_si_core_spawn_announce` chi con anh huong chat announce.

- Bo sung cvar test force subtype Smoker:
  - `l4d2_elite_si_core_smoker_force_subtype`
    - `0`: random nhu binh thuong
    - `5-15`: ep dung subtype Noxious de test

- Smoker Noxious bo sung warning instructor hint khi survivor an sat thuong dac biet:
  - `l4d2_elite_smoker_noxious_warning_hint_enable`
  - `l4d2_elite_smoker_noxious_warning_hint_cooldown`
  - `l4d2_elite_smoker_noxious_warning_hint_color`
  - `l4d2_elite_smoker_noxious_smoke_screen_hint_enable`

- Instructor hint warning da doi sang tieng Anh va khong stack.
  - Moi player chi co 1 hint active, hint moi se thay hint cu.

- Module noxious expose native de plugin khac resolve kill/incap cause:
  - `EliteSI_Noxious_GetRecentDamageCause(victim)`
  - `EliteSI_Noxious_GetRecentDamageAttacker(victim)`

- HardSI director bo hoan toan dependency vao `cfg/l4d2_elite_si_hardsi/aggressive_ai.cfg`.
  - Moi plugin trong he `l4d2_elite_si_*` tu quan ly cfg rieng thong qua `AutoExecConfig`.
  - Khong con can folder `cfg/l4d2_elite_si_hardsi/`.

- Elite type description data da duoc siet lai theo mapping subtype hop le cho tung SI class.
  - Core bo qua cac key subtype khong hop le cho class do.
  - Fix triet de truong hop file `elite_si_type_descriptions.cfg` cua 1 SI class lai chua mo ta cua class khac.

- Tich hop vao `Tuan_l4d2_death_incap_red`:
  - Resolve dung cause dac thu noxious thay vi gom chung `Smoker claws`.
  - Ten victim SI elite trong kill/incap message da doi sang dang:
    - `Elite <Class> (<TypeName>)`
    - khong con chi hien chung chung `Elite <Class>`.

- Core bo sung cooldown spawn elite de tranh burst nhieu elite cung luc:
  - `l4d2_elite_si_core_spawn_cooldown`
    - Mac dinh `20.0`s

### 16/04/2026 (Boomer Nauseating migration)

- Tich hop bo Nauseating Boomer vao he thong elite subtype.
- Them plugin moi `l4d2_elite_si_boomer_nauseating`.
- Boomer elite roll random 1 subtype boomer trong nhom `16..25`.
- Bo sung cvar force subtype boomer de test:
  - `l4d2_elite_si_core_boomer_force_subtype`
- Bo sung map CVAR + Main Config UI cho toan bo cvar boomer nauseating.

### 18/04/2026 (Strange Movement split)

- Remove plugin tong `l4d2_elite_si_ability_movement.sp`.
- Tach `Strange Movement` thanh 3 plugin rieng:
  - `l4d2_elite_si_infected_movement_smoker`
  - `l4d2_elite_si_infected_movement_spitter`
  - `l4d2_elite_si_infected_movement_tank`
- Core bo sung chance roll rieng cho movement subtype:
  - `l4d2_elite_si_core_smoker_movement_subtype_chance`
  - `l4d2_elite_si_core_spitter_ability_subtype_chance`
  - `l4d2_elite_si_core_tank_movement_subtype_chance`
- Smoker co the roll giua `Strange Movement` va bo Noxious.
- Tank da duoc dua vao mapping elite subtype cua core va Main Configurations UI.

### 15/04/2026 (Abnormal split)

- Remove plugin tong `l4d2_elite_si_hardsi.sp`.
- Tach Abnormal behavior thanh nhieu plugin nho theo tung SI:
  - `l4d2_elite_si_hardsi_smoker`
  - `l4d2_elite_si_hardsi_boomer`
  - `l4d2_elite_si_hardsi_hunter`
  - `l4d2_elite_si_hardsi_spitter`
  - `l4d2_elite_si_hardsi_jockey`
  - `l4d2_elite_si_hardsi_charger`
  - `l4d2_elite_si_hardsi_tank`
  - `l4d2_elite_si_hardsi_director` (global `nb_assault`)
- Cac cvar cua nhanh Abnormal behavior duoc doi prefix sang `l4d2_elite_si_hardsi_*` de dong bo he thong elite.

### 15/04/2026 (Cvar cleanup + MainConfig UI)

- Xoa cvar `l4d2_elite_si_core_auto_load_smoker_noxious` trong core.
  - Core khong con auto-load module noxious; plugin noxious can load san trong plugin list.

- Xoa cvar `l4d2_elite_smoker_noxious_enable` trong module noxious.
  - Noxious module luon hoat dong khi plugin duoc load.

- HardSI director khong con dung aggressive cfg dung chung.
  - Chi giu cvar dieu khien nhac `nb_assault`.

- Main Configurations (webapp) da bo 3 field UI tuong ung:
  - HardSI Director Aggressive CFG
  - Auto-load Noxious Module
  - Enable Noxious Module

- Main Configurations da bo tri lai phan Tank vao filter `Tank` rieng trong Elite Type.

- Rename title section:
  - `Common Smoker Noxious Settings` -> `Smoker Noxious - Common Settings`
  - `HardSI (Abnormal Behavior)` -> `<SI> - Abnormal Behavior`
  - Cac subtype noxious theo dang `Smoker Noxious - <Subtype>`
