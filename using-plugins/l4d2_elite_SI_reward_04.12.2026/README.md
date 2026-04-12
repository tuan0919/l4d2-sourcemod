# l4d2_elite_SI_reward

## Update 12/04/2026

- Thêm elite subtype mới `ChargerSteering` cho Charger (id=3).
- Dùng cvar legacy `l4d_hp_rewards_elite_charger_action_chance` để roll Charger elite sang nhánh `ChargerSteering` thay vì `HardSI`.
- Tách rõ rule subtype:
  - `Smoker` / `Spitter`: `HardSI` hoặc `AbilityMovement`
  - `Charger`: `HardSI` hoặc `ChargerSteering`
- Giữ nguyên native `L4D2_IsEliteSI` và `L4D2_GetEliteSubtype(client)` để các plugin behavior gate đúng subtype.
- Update màu render để phân biệt ChargerSteering với Charger elite nhánh HardSI.

## Update 11/04/2026

- Cho phép chỉnh reward HP riêng cho từng SI: Smoker/Boomer/Hunter/Spitter/Jockey/Charger.
- Thêm tùy chọn scale reward theo độ khó hiện tại (`easy`, `normal`, `hard/advanced`, `impossible/expert`).
- Thêm bonus headshot dạng multiplier.
- Tank/Witch có mode thưởng riêng:
  - thưởng toàn team
  - thưởng attacker
  - cấu hình amount riêng
- Elite SI chỉ buff máu + đổi màu, không còn boost tốc độ.
- Chỉ Elite tự bốc cháy mới kháng lửa; Elite còn lại nhận damage lửa bình thường.
- Bổ sung elite subtype trung tâm: `HardSI` và `AbilityMovement`.
- `Smoker` và `Spitter` có thể random sang subtype `AbilityMovement`; các SI elite còn lại giữ nhánh `HardSI`.
- Expose native `L4D2_GetEliteSubtype(client)` để plugin AI/movement gate đúng subtype và không còn chồng logic.

## File chính

- `scripting/l4d2_elite_SI_reward.sp`

## Reference

- `reference/plugins-docs/l4d2_elite_si_reward_11042026.md`
