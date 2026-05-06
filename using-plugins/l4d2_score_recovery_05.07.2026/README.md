# L4D2 Score/Stats Recovery
**Ngày viết/cập nhật:** 07/05/2026

## Mô tả
Plugin này hỗ trợ giữ lại các chỉ số thống kê của survivor khi người chơi bị đứt kết nối (disconnect) hoặc thoát game rồi kết nối lại trong cùng round/map.

Bằng cách chặn sự kiện `player_disconnect` và lưu trữ các giá trị `m_zombieKills`, `m_iVersusScore`, cùng bộ biến `m_checkpoint...` bằng cơ chế in-memory string map (ánh xạ theo `SteamID`), vào khoảnh khắc user lấy lại quyền điều khiển một survivor bot (`bot_player_replace` & `player_spawn`), plugin sẽ ghi đè ngược các chỉ số đã lưu vào lại các network properties của player đó.

## Chi tiết
- **File Source:** `scripting/l4d2_score_recovery.sp`
- **Output:** `addons/sourcemod/plugins/multiplayer-stuffs/l4d2_score_recovery.smx`
- Plugin này tập trung 100% vào chỉ số (Score, Kills, Incaps stats, Heals). Vũ khí và máu không nằm trong phạm vi của plugin này.
- Lệnh test:
  - `sm_score_print [target]`: In current stats và cached stats của target ra chat/console.
  - `sm_score_recovery_print [target]`: Alias của `sm_score_print`.
- CVar test:
  - `l4d2_score_recovery_debug 1`: Tự log stats đã save/restore ra server console, và log restore chi tiết ra console của player.

## Changelog
- **07/05/2026**: Bump version lên `1.1.0`; thêm command `sm_score_print` / `sm_score_recovery_print`; thêm `l4d2_score_recovery_debug` để log dữ liệu save/restore khi test reconnect.
- **21/04/2026**: Khởi tạo plugin. Hỗ trợ bắt đầy đủ các biến Checkpoint.
