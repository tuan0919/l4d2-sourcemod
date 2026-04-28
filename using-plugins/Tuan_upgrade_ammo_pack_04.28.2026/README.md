# Tuan_upgrade_ammo_pack

## Mô tả

Plugin thay đổi cơ chế upgrade ammo pack (lửa/nổ) trong L4D2:
- Khi dùng pack, primary weapon hiện tại được đánh dấu có upgrade ammo vĩnh viễn.
- Hiệu ứng đạn lửa/nổ dùng upgrade ammo props gốc của game, không inject damage type riêng.
- Sau reload, số đạn upgrade trong clip được sync theo `m_iClip1`.
- Có thể đổi tự do giữa đạn lửa và đạn nổ bằng cách dùng pack loại khác.
- Cho phép nhặt ammo pile bình thường.
- Tự nhận lại state permanent upgrade khi weapon được restore/equip lại và vẫn còn upgrade bit.

## Cơ chế hoạt động

### Khi dùng pack

1. Hook `SDKHook_Use` trên entity `upgrade_ammo_incendiary` / `upgrade_ammo_explosive`.
2. Đánh dấu weapon entity là upgraded và lưu loại upgrade.
3. Sau frame kế tiếp, set `m_upgradeBitVec` bit tương ứng.
4. Sync `m_nUpgradedPrimaryAmmoLoaded` theo clip hiện tại (`m_iClip1`).

### Khi bắn

- Hook `SDKHook_FireBulletsPost` trên survivor.
- Nếu weapon đang upgraded và không trong reload watcher, sync lại `m_nUpgradedPrimaryAmmoLoaded = m_iClip1`.
- Re-apply `m_upgradeBitVec` nếu game tự clear bit upgrade.

### Khi reload

- Hook event `weapon_reload`.
- Clear `m_nUpgradedPrimaryAmmoLoaded` và upgrade ammo bit ở reload start để HUD hiển thị lượng đạn thật trong súng/reserve.
- Dùng `SDKHook_PostThink` để restore upgrade visual sau khi reload xong hoặc bị interrupt.
- Với súng nạp cả băng một lần, restore khi clip tăng so với clip lúc bắt đầu reload.
- Với shotgun nạp từng viên, watcher không restore ở viên đầu tiên; nó chờ reload kết thúc hoặc bị interrupt rồi mới restore upgrade visual theo clip hiện tại.
- Nếu reload bị interrupt do stagger, bị SI bắt, đổi weapon hoặc reload prop báo kết thúc, plugin restore lại upgrade visual theo clip hiện tại rồi dừng watcher.

### Ammo pickup

- Hook event `ammo_pickup` post để refresh lại visual/state sau khi game xử lý nhặt đạn.
- Không block ammo pickup; player vẫn nhặt đạn thường bình thường.

### Import state khi nhặt/equip súng

- Hook `SDKHook_WeaponEquipPost` trên survivor và delay 1 frame để đọc props sau khi game/plugin khác set xong.
- Nếu primary weapon có `m_upgradeBitVec` fire/explosive, plugin chuyển nó thành permanent upgraded weapon theo logic hiện tại.
- Có fallback ở `FireBulletsPost`, `weapon_reload`, `ammo_pickup` và `player_spawn` để tránh miss timing.
- Có callback `L4D2_OnSaveWeaponHxGiveC(client)` để import state sau khi `l4d2_ty_saveweapons` restore súng qua map.

### Restore qua map

- Plugin không tự lưu state theo client nữa.
- Nếu plugin khác restore lại weapon props, plugin đọc `m_upgradeBitVec` trên weapon đang cầm để import lại state.

## CVar

| CVar | Default | Mô tả |
|------|---------|-------|
| `tuan_upgrade_ammo_enable` | `1` | Bật/tắt plugin |

## Files

- Source: `addons/sourcemod/scripting/Tuan_upgrade_ammo_pack.sp`
- Snapshot: `using-plugins/Tuan_upgrade_ammo_pack_04.28.2026/Tuan_upgrade_ammo_pack.sp`
- Compiled: `addons/sourcemod/plugins/qol/Tuan_upgrade_ammo_pack.smx`

## Changelog

### v3.3.5 (28/04/2026)

- Fix lỗi `Invalid game event handle 0` khi nhặt ammo pile.
- Đổi hook `ammo_pickup` từ `EventHookMode_PostNoCopy` sang `EventHookMode_Post` vì callback cần đọc `userid` từ event payload.

### v3.3.4 (28/04/2026)

- Remove logic block `ammo_pickup`; player được nhặt ammo pile bình thường.
- Remove save/restore state riêng theo client trên `map_transition` / `mission_lost` / disconnect.
- Giữ callback `L4D2_OnSaveWeaponHxGiveC(client)` và import từ weapon props để tương thích `l4d2_ty_saveweapons` mà không cần tracking riêng.
- Sau ammo pickup, plugin chỉ refresh lại visual/state nếu weapon đã là permanent upgraded.

### v3.3.3 (28/04/2026)

- Remove toàn bộ `OnTakeDamage` hook và logic inject `DMG_BURN` / `DMG_BLAST`.
- Đạn lửa/nổ giờ dựa hoàn toàn vào `m_upgradeBitVec` và `m_nUpgradedPrimaryAmmoLoaded` của game.
- Giảm hook thừa trên survivor/infected/witch và giữ behavior gần vanilla hơn.

### v3.3.2 (28/04/2026)

- Fix súng upgrade bị restore/nhặt lại chỉ còn behavior vanilla 1 băng đạn sau map transition.
- Thêm import state từ `m_upgradeBitVec` khi survivor equip primary weapon đã có upgrade bit.
- Tích hợp callback `L4D2_OnSaveWeaponHxGiveC(client)` để nhận lại state ngay sau khi `l4d2_ty_saveweapons` give lại súng.
- Thêm fallback import trước fire/reload/ammo pickup/damage để súng nâng cấp luôn đi qua logic permanent upgrade của plugin.

### v3.3.1 (25/04/2026)

- Fix shotgun reload từng viên chỉ hiển thị upgrade ammo ở viên đầu tiên sau khi reload.
- Fix upgrade ammo visual/state có thể biến mất khi reload bị interrupt bởi stagger, bị SI bắt hoặc đổi weapon.
- Giữ behavior cũ: clear upgrade visual trong lúc reload để người chơi thấy lượng đạn thật.
- Riêng shotgun chờ reload kết thúc/interrupted rồi mới restore upgrade visual, tránh kẹt ở viên đầu tiên.
- Thêm guard chống hook PostThink trùng trên cùng client.

### v3.3.0 (22/04/2026)

- Revamp upgrade ammo thành trạng thái vĩnh viễn theo weapon entity.
- Hỗ trợ switch tự do giữa incendiary và explosive pack.
- Sync damage type bằng `OnTakeDamage` thay vì phụ thuộc hoàn toàn vào ammo counter gốc.
