# tuan_notify_system (rewrite 13/04/2026)

## Muc tieu rewrite

Tach ro he thong thong bao thanh nhom plugin co ten dong bo, de nhin vao la thay quan he phu thuoc va vai tro tung plugin:

- Death/Incap chat do plugin rieng quan ly (`Tuan_l4d2_death_incap_red`)
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

## Source include local (khong include path ra ngoai module)

De tranh phu thuoc duong dan include sang folder khac, source member duoc dat local ngay trong `scripting/`:

- `tuan_notify_member_bw_source.sp`
- `tuan_notify_member_throwable_source.sp`
- `tuan_notify_member_explosion_source.sp`
- `tuan_notify_core.inc`

## Luu y migration

- Ten plugin source member cu (`Tuan_l4d_blackandwhiteordead`, `Tuan_l4d_throwable_announcer`, `Tuan_l4d_explosion_announcer`) da duoc thay bang prefix dong bo `tuan_notify_member_*`.
- Death/Incap member trong he HUD da bo, death/incap chat duoc giao cho `Tuan_l4d2_death_incap_red`.

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
