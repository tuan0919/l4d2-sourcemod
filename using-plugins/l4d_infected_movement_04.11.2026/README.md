# l4d_infected_movement

## Update 11/04/2026

- Đồng bộ source plugin movement vào `using-plugins`.
- Chỉ apply movement logic cho elite subtype `AbilityMovement` thông qua `L4D2_IsEliteSI(client)` và `L4D2_GetEliteSubtype(client)`.
- Nhánh này hiện dành cho `Smoker` và `Spitter`; không dùng cho Charger vì Charger đã có nhánh `ChargerAction` riêng.
- Tự unhook/reset khi infected không còn đúng subtype để tránh overlap với `Tuan_AI_HardSI`.

## File chính

- `scripting/l4d_infected_movement.sp`

## Reference

- `reference/plugins-docs/l4d_infected_movement_11042026.md`
