# Tuan_upgrade_ammo_pack

## Mô tả

Plugin thay đổi cơ chế upgrade ammo pack (lửa/nổ) trong L4D2:
- Khi dùng pack → set toàn bộ đạn hiện có (clip + reserve) thành đạn lửa/nổ, cap 254
- Sau khi upgrade, mỗi lần reload đạn nạp vào clip đều là đạn lửa/nổ
- Không thể nhặt đạn từ ammo pile trên map khi súng đang ở upgrade mode
- Chỉ có thể refill bằng pack cùng loại
- Không thể đổi loại đạn (lửa → nổ hoặc ngược lại) khi đã upgrade

## Cơ chế hoạt động

### Khi dùng pack
1. Tính `totalAmmo = clip + reserve`, cap tại 254
2. Set `m_nUpgradedPrimaryAmmoLoaded = totalAmmo`
3. Set `m_upgradeBitVec` bit tương ứng (incendiary/explosive)
4. Đánh dấu weapon entity là upgraded

### Sau reload
- Timer 0.25s poll tất cả survivor
- Detect clip tăng (reload xong) → sync `m_nUpgradedPrimaryAmmoLoaded = m_iClip1`
- Re-apply `m_upgradeBitVec` nếu game tự clear

### Block ammo pile
- Hook event `ammo_pickup` pre → block nếu primary weapon đang upgraded

### Reset state
- Drop súng
- Player chết
- Round start
- Entity destroyed

## CVar

| CVar | Default | Mô tả |
|------|---------|-------|
| `tuan_upgrade_ammo_enable` | `1` | Bật/tắt plugin |

## Files

- `Tuan_upgrade_ammo_pack.sp` — source code
- Compiled: `addons/sourcemod/plugins/Tuan_upgrade_ammo_pack.smx`

## Changelog

### v1.0.0 (22/04/2026)
- Release đầu tiên
