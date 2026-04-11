# Tuan_AI_HardSI

## Update 11/04/2026

- Tách elite subtype để plugin chỉ apply nhánh `HardSI` cho đúng chủng elite tương ứng.
- Thêm gate theo native `L4D2_GetEliteSubtype(client)` để tránh overlap movement với `l4d_infected_movement`.
- Từ update `12/04/2026`, gate subtype này cũng là điểm tách giữa `HardSI` và `ChargerAction`, tránh việc Charger elite ăn chồng AI của 2 plugin.
- Đồng bộ source compile trong `using-plugins` với bản `.smx` đã deploy.

## File chính

- `scripting/Tuan_AI_HardSI.sp`

## Reference

- `reference/plugins-docs/tuan_ai_hardsi_11042026.md`
