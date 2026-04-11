# L4D2 Charger Action

## Mô tả

Plugin gốc thay đổi cách Charger hoạt động: fling khi va chạm, jump trong lúc charge, pickup/drop survivor, shove release, manual pummel.

Bản đang dùng trên server đã được migrate để làm **một chủng Elite SI riêng cho Charger**.

Điểm quan trọng:

- Plugin này không còn được hiểu là logic cho mọi Charger.
- Khi `l4d2_charger_elite_only` bật, toàn bộ logic chỉ apply cho Charger thuộc **elite subtype ChargerAction**.
- Subtype này được cấp bởi plugin `l4d2_elite_SI_reward` qua native:
  - `L4D2_IsEliteSI`
  - `L4D2_GetEliteSubtype`

## Quan hệ với hệ Elite SI

- Elite reward plugin roll Charger thường thành Elite theo `l4d_hp_rewards_elite_chance`.
- Nếu Charger đã là Elite, plugin reward tiếp tục roll subtype theo `l4d_hp_rewards_elite_charger_action_chance`.
- Khi subtype trả về `3` (`ChargerAction`), plugin này mới can thiệp behavior nếu `l4d2_charger_elite_only=1`.
- Nếu subtype không phải `ChargerAction`, Charger đó sẽ rơi về nhánh khác, thường là `HardSI`.

## Cvar hiện dùng

Config autoexec mặc định vẫn là `cfg/sourcemod/l4d2_charger_action.cfg`.

### Cvar gốc

```cfg
// 0=Plugin off, 1=Plugin on.
l4d2_charger_allow "1"

// Bots can: 0=Grab survivor on contact (game default). 1=Fling survivors on contact instead of grab. 2=Random choice.
l4d2_charger_bots "1"

// Humans can: 0=Grab survivor on contact (game default). 1=Fling survivors on contact instead of grab.
l4d2_charger_charge "1"

// Amount of damage to deal on collision when hitting or grabbing a survivor.
l4d2_charger_damage "10"

// After carrying and charging: 0=Pummel (game default). 1=Drop survivor. 2=Drop when a carried survivor is incapped. 3=Both 1 and 2. 4=Continue to carry.
l4d2_charger_finish "3"

// Allow chargers to automatically pick up incapacitated players whilst charging over them. 0=Off. 1=On. 2=Only when not pinned by other Special Infected.
l4d2_charger_incapped "1"

// Allow chargers to jump while charging. 0=Off. 1=When alone. 2=Also when carrying a survivor.
l4d2_charger_jump "2"

// 0=Unlimited. Maximum number of jumps per charge.
l4d2_charger_jumps "0"

// Allow chargers to carry and drop survivors with the melee button (RMB).
l4d2_charger_pickup "31"

// Allow pummel to be started and stopped while carrying a survivor.
l4d2_charger_pummel "2"

// 0=Off. 1=Allow punching while charging.
l4d2_charger_punch "1"

// 0=Off. 1=Allow charging while carrying either after charging or after grabbing a survivor and after the charge meter has refilled.
l4d2_charger_repeat "0"

// Survivors can shove chargers to release pummeled victims. 0=Off. 1=Release only. 2=Stumble survivor. 4=Stumble charger. 7=All.
l4d2_charger_shove "7"
```

### Cvar custom cho nhánh elite

```cfg
// 0=Apply cho mọi Charger. 1=Chỉ apply cho elite subtype ChargerAction.
l4d2_charger_elite_only "1"

// ID subtype elite mà plugin này nhận. Phải khớp plugin reward.
l4d2_charger_elite_subtype "3"
```

## File test

Đã có file test nhanh tại:

```txt
cfg/sourcemod/l4d2_charger_action_elite.cfg
```

## Changelog local

### 12/04/2026

- Migrate plugin thành một chủng Elite Charger riêng cho server.
- Thêm gate subtype để plugin không còn apply lên mọi Charger elite khác.
- Thêm cvar custom `l4d2_charger_elite_only` và `l4d2_charger_elite_subtype`.
- Tích hợp với `l4d2_elite_SI_reward` để ChargerAction được roll độc lập, không mix với các chủng elite khác.
