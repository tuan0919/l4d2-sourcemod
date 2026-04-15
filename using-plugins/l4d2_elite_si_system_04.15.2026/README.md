# l4d2_elite_si_system (rewrite 13/04/2026, update 15/04/2026)

## Muc tieu rewrite

Rewrite lai he thong Elite SI + reward HP theo huong module, giam chong cheo logic va tach ro vai tro tung plugin.

## Kien truc moi

He thong moi gom 7 plugin nho, load doc lap:

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

3. `scripting/l4d2_elite_si_hardsi.sp`
   - Nhanh AI HardSI chi cho subtype `Abnormal behavior`
   - Bao gom boomer/spitter/tank bhop, hunter pounce tuning, jockey pressure, charger force-charge,
     smoker action hook de tranh bug `nb_assault`

4. `scripting/l4d2_elite_si_ability_movement.sp`
   - Nhanh movement ability cho subtype `Strange Movement`
   - Giu toc do khi cast `ability_tongue`, `ability_spit`, `ability_throw`

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

## Subtype mapping

- `0`: none
- `1`: Abnormal behavior (legacy internal: HardSI)
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

## Cvar moi (khong tai su dung key cu)

Tat ca cvar moi su dung prefix:

- `l4d2_elite_si_core_*`
- `l4d2_elite_reward_*`
- `l4d2_elite_hardsi_*`
- `l4d2_elite_ability_move_*`
- `l4d2_elite_charger_steering_*`
- `l4d2_elite_charger_action_*`
- `l4d2_elite_smoker_noxious_*`

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

- Smoker elite khong con roll qua `l4d2_elite_si_core_smoker_ability_subtype_chance`.
  Thay vao do roll ngau nhien 1 trong 11 Noxious subtype.

- Chat announce elite SI da doi sang mau theo `{red}` (colors include),
  dong bo voi he thong notify hien tai.

- Core bo sung auto-load safeguard cho module noxious:
  - `l4d2_elite_si_core_auto_load_smoker_noxious`
    - `0`: khong auto-load
    - `1`: auto `sm plugins load qol/l4d2_elite_si_smoker_noxious.smx` neu module chua load

- Co bo sung runtime cfg de de override tren server:
  - `cfg/sourcemod/l4d2_elite_si_smoker_noxious.cfg`

## Tich hop giua plugin

- Core cap du lieu subtype bang native
- Cac nhanh behavior (Abnormal behavior / Strange Movement / ChargerSteering / ChargerAction / Smoker Noxious)
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

- Tich hop vao `Tuan_l4d2_death_incap_red`:
  - Resolve dung cause dac thu noxious thay vi gom chung `Smoker claws`.

- Core bo sung cooldown spawn elite de tranh burst nhieu elite cung luc:
  - `l4d2_elite_si_core_spawn_cooldown`
    - Mac dinh `20.0`s
