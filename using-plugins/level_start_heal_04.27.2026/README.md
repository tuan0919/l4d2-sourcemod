# Level Start Heal (v3.5)

- Author: little_froy
- URL: https://forums.alliedmods.net/showthread.php?t=340158
- Ngày cập nhật: 27/04/2026

## Chức năng

Plugin restore HP của survivor về giá trị cấu hình (mặc định 100) khi bắt đầu map mới. Cụ thể:

1. Khi survivor spawn đầu map (lần đầu tiên trong round):
   - Set HP về `level_start_heal_health` (default 100)
   - Giảm temp health tương ứng nếu HP hiện tại thấp hơn target
   - Clear trạng thái Black & White:
     - Reset `m_isGoingToDie` = 0
     - Reset `m_currentReviveCount` = 0 (hoặc gọi `Heartbeat_SetRevives` nếu có l4d_heartbeat)
     - Reset `m_bIsOnThirdStrike` = 0
     - Stop heartbeat sound
2. Fire forward `LevelStartHeal_OnHealed(int client)` sau khi heal xong

## Forward / Native (.inc)

File: `level_start_heal.inc`

```
forward void LevelStartHeal_OnHealed(int client);
```

- Được gọi sau khi plugin heal xong 1 survivor
- Các plugin khác có thể hook forward này để reset lại bộ đếm nội bộ (ví dụ: BW tracker reset `g_bPlayerBW`)

## Tương tác với hệ thống notify

Plugin `tuan_notify_member_bw_source.sp` cần hook `LevelStartHeal_OnHealed` để reset trạng thái BW tracking (`g_bPlayerBW[client] = false`), tránh thông báo nhầm "is at last life" sau khi plugin này đã heal và clear BW state.

## CVAR

| CVAR | Default | Mô tả |
|------|---------|-------|
| `level_start_heal_health` | 100 | HP target khi heal đầu map |
| `level_start_heal_version` | 3.5 | Version (read-only) |

## Files

- `level_start_heal.sp` → source plugin
- `level_start_heal.inc` → include file cho forward
- `level_start_heal.smx` → compiled plugin (đặt tại `addons/sourcemod/plugins/qol/`)
- `cfg/sourcemod/level_start_heal.cfg` → control HP target
- `cfg/sourcemod/l4d2_ty_saveweapons.cfg` → tắt restore health của `l4d2_ty_saveweapons` để tránh ghi đè heal đầu chapter

## Changelog 27/04/2026

- Compile lại `level_start_heal.smx` từ source v3.5 và deploy vào `addons/sourcemod/plugins/qol/level_start_heal.smx`.
- Fix luồng `round_start`: ngoài việc reset `First_time`, plugin giờ queue heal ở frame kế tiếp cho các survivor đang có sẵn trong game. Trường hợp chapter transition không fire `player_spawn` đúng lúc vẫn được heal.
- Thêm `cfg/sourcemod/level_start_heal.cfg` để khóa `level_start_heal_health "100"`.
- Thêm `cfg/sourcemod/l4d2_ty_saveweapons.cfg` với `l4d2_ty_saveweapons_save_health "0"`. Plugin `l4d2_ty_saveweapons` vẫn restore weapon/item, nhưng không restore HP/BW state và không ghi đè kết quả heal của plugin này.

## Conflict đã xử lý

- `l4d2_ty_saveweapons` có default `l4d2_ty_saveweapons_save_health "1"`, sẽ restore HP đã save từ chapter trước sau khi survivor spawn map mới.
- Nếu `level_start_heal` heal trước rồi `l4d2_ty_saveweapons` restore sau, HP sẽ bị kéo về giá trị cũ, nhìn như `level_start_heal` không hoạt động.
- Cấu hình hiện tại đặt `l4d2_ty_saveweapons_save_health "0"` để `level_start_heal` là plugin duy nhất quản lý HP/BW reset đầu chapter.

## Lưu ý

- Plugin tương thích với `l4d_heartbeat` (optional dependency)
- Chỉ heal survivor lần đầu spawn trong round, không heal lại nếu đã chết/incap/ledge grab trước đó
- Hỗ trợ idle/bot replace (transfer state giữa bot và player)
