# Tuan_upgrade_ammo_pack

## Mô tả

Plugin thay đổi cơ chế upgrade ammo pack (lửa/nổ) trong L4D2:
- Khi dùng pack, primary weapon hiện tại được đánh dấu có upgrade ammo vĩnh viễn.
- Mỗi phát bắn gây thêm damage type tương ứng: `DMG_BURN` cho incendiary, `DMG_BLAST` cho explosive.
- Sau reload, số đạn upgrade trong clip được sync theo `m_iClip1`.
- Có thể đổi tự do giữa đạn lửa và đạn nổ bằng cách dùng pack loại khác.
- Chặn nhặt ammo pile khi súng primary đang ở trạng thái upgraded.
- Giữ trạng thái upgrade qua map transition nếu weapon classname khớp.

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

### Block ammo pile

- Hook event `ammo_pickup` pre.
- Nếu primary weapon đang upgraded thì return `Plugin_Handled`.

### Save / restore

- Khi `map_transition`, `mission_lost` hoặc client disconnect, lưu loại upgrade và weapon classname.
- Khi player spawn lại, restore upgrade nếu primary weapon classname khớp.

## CVar

| CVar | Default | Mô tả |
|------|---------|-------|
| `tuan_upgrade_ammo_enable` | `1` | Bật/tắt plugin |

## Files

- Source: `addons/sourcemod/scripting/Tuan_upgrade_ammo_pack.sp`
- Snapshot: `using-plugins/Tuan_upgrade_ammo_pack_04.25.2026/Tuan_upgrade_ammo_pack.sp`
- Compiled: `addons/sourcemod/plugins/qol/Tuan_upgrade_ammo_pack.smx`

## Changelog

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
