# L4D2 Score/Stats Recovery
**Ngày viết/cập nhật:** 21/04/2026

## Mô tả
Plugin này giúp giải quyết triệt để lỗi của L4D2 engine: Khi người chơi bị đứt kết nối (disconnect) hoặc thoát game bằng ý muốn rồi kết nối lại, họ sẽ bị mất toàn bộ Score trên bảng Tab, Kills, hay chỉ số thống kê ở phần cuối màn kết thúc chiến dịch (Credit Finale).

Bằng cách chặn sự kiện `player_disconnect` và lưu trữ các giá trị `m_zombieKills`, `m_iVersusScore`, cùng bộ biến `m_checkpoint...` bằng cơ chế in-memory string map (ánh xạ theo `SteamID`), vào khoảnh khắc user lấy lại quyền điều khiển một survivor bot (`bot_player_replace` & `player_spawn`), plugin sẽ ghi đè ngược các chỉ số đã lưu vào lại các network properties của con bot đó.

## Chi tiết
- **File Source:** `scripting/l4d2_score_recovery.sp`
- **Output:** `addons/sourcemod/plugins/multiplayer-stuffs/l4d2_score_recovery.smx`
- Plugin này tập trung 100% vào chỉ số (Score, Kills, Incaps stats, Heals). Vũ khí và máu không nằm trong phạm vi của plugin này.

## Changelog
- **21/04/2026**: Khởi tạo plugin. Hỗ trợ bắt đầy đủ các biến Checkpoint.
