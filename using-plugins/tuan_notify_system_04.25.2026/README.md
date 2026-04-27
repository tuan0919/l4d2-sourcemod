# tuan_notify_system (rewrite 13/04/2026, update 27/04/2026)

## Muc tieu rewrite

Tach ro he thong thong bao thanh nhom plugin co ten dong bo, de nhin vao la thay quan he phu thuoc va vai tro tung plugin:

- Death/Incap chat do plugin rieng quan ly (`Tuan_l4d2_death_incap_red`)
  - Source hien tai duoc tach module tai `using-plugins/Tuan_l4d2_death_incap_red_modular_04.14.2026/`
- HUD/event feed dung bo `tuan_notify_*`

## Kien truc

He thong notify moi gom cac plugin sau:

1. `scripting/Tuan_l4d2_show_hud_message.sp`
   - Core display aggregator (HUD + optional chat mirror)
   - Expose native/forward qua library `tuan_notify_core`

2. `scripting/tuan_notify_member_events.sp`
   - Collector nhan `Tuan_custom_forwards` va publish message vao core
   - Gom cac nhanh event: BW / throwable / explosion / gear transfer

3. `scripting/tuan_notify_member_bw.sp`
   - Source member cho Black & White events

4. `scripting/tuan_notify_member_throwable.sp`
   - Source member cho throwable events

5. `scripting/tuan_notify_member_explosion.sp`
   - Source member cho explosion events

## Luu y migration

- Ten plugin source member cu (`Tuan_l4d_blackandwhiteordead`, `Tuan_l4d_throwable_announcer`, `Tuan_l4d_explosion_announcer`) da duoc thay bang prefix dong bo `tuan_notify_member_*`.
- Death/Incap member trong he HUD da bo, death/incap chat duoc giao cho `Tuan_l4d2_death_incap_red`.
- Phien ban nay (04.25.2026) la standalone hoan toan: cac file `_source.sp` da duoc merge truc tiep vao wrapper tuong ung va xoa bo. Khong con phu thuoc file trung gian.

## Changelog

### 27/04/2026
- `tuan_notify_member_bw`: Hook forward `Tuan_OnClient_SelfRevived` từ `Tuan_l4d_incapped_weapons` để sync lại trạng thái BnW nội bộ sau self-revive. Nếu self-revive làm survivor vào last life, plugin sẽ cập nhật `g_bPlayerBW` và phát `Tuan_OnClient_GoBnW`; nếu không còn BnW thì reset state để tránh heal notification sai.

### 25/04/2026
- `tuan_notify_member_bw_source`: Hook forward `LevelStartHeal_OnHealed` từ plugin `level_start_heal` để reset trạng thái BW tracking (`g_bPlayerBW`) khi survivor được heal đầu map. Tránh thông báo nhầm "is at last life" sau khi plugin đã clear BW state.
- Thêm `level_start_heal.inc` vào include của `tuan_notify_member_bw_source.sp` (optional dependency).

### 21/04/2026
- `tuan_notify_member_throwable_source`: Fix bug thong bao sai "Infected / Special Infected thrown molotov/pipebomb" khi cac con Elite SI bi chet hoac kich hoat roi do lua/bomb tren map (vi du: Boomer Leaker, Smoker Ignitor, Hunter Heroic). Phien ban nay chan hoan toan event WeaponFire + ThrownMolotov neu nguon the event thuoc ve Team 3 (Infected).

## CVAR chinh

### Core

- `tuan_notify_core_chat_notification`
- `tuan_notify_core_screen_hud_notification`
- `tuan_notify_core_kill_feed`
- `tuan_notify_core_legacy_forward_mode`

### Collector events

- Prefix: `tuan_notify_member_evt_*`

## Compile

Compile cac file wrapper/member tai thu muc `addons/sourcemod/scripting/`:

- `Tuan_l4d2_show_hud_message.sp`
- `tuan_notify_member_events.sp`
- `tuan_notify_member_bw.sp`
- `tuan_notify_member_throwable.sp`
- `tuan_notify_member_explosion.sp`
