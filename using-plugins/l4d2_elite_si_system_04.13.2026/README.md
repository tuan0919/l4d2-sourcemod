# l4d2_elite_si_system (rewrite 13/04/2026)

## Muc tieu rewrite

Rewrite lai he thong Elite SI + reward HP theo huong module, giam chong cheo logic va tach ro vai tro tung plugin.

## Kien truc moi

He thong moi gom 6 plugin nho, load doc lap:

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
   - Thuong Temp HP cho Elite SI / Tank / Witch
   - Scale theo difficulty + headshot bonus
   - Expose forward:
     - `EliteSIReward_OnGranted(receiver, amount, sourceClass, mode)`

3. `scripting/l4d2_elite_si_hardsi.sp`
   - Nhanh AI HardSI chi cho subtype `HardSI`
   - Bao gom boomer/spitter/tank bhop, hunter pounce tuning, jockey pressure, charger force-charge,
     smoker action hook de tranh bug `nb_assault`

4. `scripting/l4d2_elite_si_ability_movement.sp`
   - Nhanh movement ability cho subtype `AbilityMovement`
   - Giu toc do khi cast `ability_tongue`, `ability_spit`, `ability_throw`

5. `scripting/l4d2_elite_si_charger_steering.sp`
   - Nhanh bot steering cho Charger trong luc charge
   - Gate theo subtype `ChargerSteering`

6. `scripting/l4d2_elite_si_charger_action.sp`
   - Wrapper gate cho nhanh `ChargerAction` (subtype rieng)
   - Export native `EliteSI_IsChargerAction(client)` de plugin charger action logic goi truc tiep

## Subtype mapping

- `0`: none
- `1`: HardSI
- `2`: AbilityMovement
- `3`: ChargerSteering
- `4`: ChargerAction

## Cvar moi (khong tai su dung key cu)

Tat ca cvar moi su dung prefix:

- `l4d2_elite_si_core_*`
- `l4d2_elite_reward_*`
- `l4d2_elite_hardsi_*`
- `l4d2_elite_ability_move_*`
- `l4d2_elite_charger_steering_*`
- `l4d2_elite_charger_action_*`

## Tich hop giua plugin

- Core cap du lieu subtype bang native
- Cac nhanh behavior (HardSI / AbilityMovement / ChargerSteering) doc native de gate dung subtype
- Core + Reward expose global forward de plugin khac co the subscribe event

## Compile

Da compile thanh cong 5 file `.sp` bang `spcomp.exe` trong qua trinh rewrite.

## Luu y migration

- Khi ap dung bo rewrite moi, nen unload cac plugin cu de tranh duplicate logic:
  - `l4d2_elite_SI_reward`
  - `Tuan_AI_HardSI`
  - `l4d_infected_movement`
  - `l4d2_charger_steering` (ban cu)
