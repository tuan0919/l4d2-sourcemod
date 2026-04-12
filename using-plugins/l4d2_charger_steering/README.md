# L4D2 Elite Charger Steering

## Muc tieu

Plugin nay da duoc rewrite thanh nhanh Elite SI rieng cho Charger, tap trung duy nhat vao bot control trong pha charge.

- Khong con feature dieu khien cho human charger.
- Khong con hint/chat/flag phuc tap cua ban goc.
- Su dung gate theo elite subtype de tranh chong voi nhanh HardSI.

## Rule apply

Mac dinh plugin chi apply khi:

1. Client la bot infected.
2. Dung class Charger.
3. Dang trong trang thai charge.
4. Khong dang carry victim.
5. La Elite SI va co subtype khop `l4d2_charger_steering_elite_subtype`.

Neu tat `l4d2_charger_steering_elite_only`, plugin co the apply cho moi Charger bot.

## Cvar

Config autoexec: `cfg/sourcemod/l4d2_charger_steering.cfg`

```cfg
// 0=Off, 1=On.
l4d2_charger_steering_allow "1"

// 0=Apply cho moi charger bot, 1=Chi apply cho elite subtype charger steering.
l4d2_charger_steering_elite_only "1"

// Subtype id duoc cap boi plugin l4d2_elite_SI_reward.
l4d2_charger_steering_elite_subtype "3"

// Steering strength moi frame (0.0-1.0).
l4d2_charger_steering_bot_strength "0.22"

// Tam tim target survivor.
l4d2_charger_steering_target_range "1200.0"

// 1=Bo qua survivor dang incap khi chon target.
l4d2_charger_steering_ignore_incapped "1"

// Toc do ngang toi thieu khi steering.
l4d2_charger_steering_min_speed "250.0"
```

## Tich hop elite

Plugin dung native:

- `L4D2_IsEliteSI(client)`
- `L4D2_GetEliteSubtype(client)`

Neu library `l4d2_elite_SI_reward` khong co mat, plugin se khong apply khi `elite_only=1`.

## Changelog local

### 13/04/2026

- Rewrite tu ban Charger Steering goc thanh nhanh Elite SI bot-control.
- Loai bo toan bo logic human steering/strafe/hint/flags.
- Them gate elite subtype de tach rieng khoi HardSI.
