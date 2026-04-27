# Tuan_l4d2_selfhelp (04.27.2026)

## Muc tieu

Plugin custom tao behavior tuong tu `l4d_selfhelp_remake` dua tren readme/data public cua upstream, khong copy source private.

Tinh nang chinh:

- Survivor bi incap, hanging from ledge, hoac bi SI pin co the giu Duck de self-help.
- Self-help tieu thu item y te tren nguoi: first aid kit, defibrillator, pain pills, adrenaline.
- Co progress bar theo thoi gian tung item.
- Khi bi pinned, self-help co the giet SI attacker.
- Khi dang distress, aim item y te gan do va bam `E` de nhat item.
- Survivor dang incap co the giu Duck de cuu survivor khac bi incap/ledge trong tam gan, khong ton item.
- Fire `Tuan_OnClient_SelfRevived(client)` sau khi self-revive de dong bo notify/BnW tracker.
- Fire game event `revive_success` khi incap-help-other thanh cong de notify system hien dung hanh dong help other.

## File runtime

- Source: `addons/sourcemod/scripting/Tuan_l4d2_selfhelp.sp`
- Plugin: `addons/sourcemod/plugins/qol/Tuan_l4d2_selfhelp.smx`
- Config: `cfg/sourcemod/Tuan_l4d2_selfhelp.cfg`

## Cach dung mac dinh

- Giu `Duck` khi dang incap/ledge/pinned de bat dau self-help.
- Giu tiep den khi progress bar chay xong.
- Neu dang distress va thay item y te gan do, aim vao item roi bam `E` de nhat.

Priority mac dinh:

```cfg
Tuan_l4d2_selfhelp_priority "1"
```

Nghia la uu tien slot 4 truoc slot 3:

- Slot 4: pills/adrenaline
- Slot 3: kit/defib

## CVAR chinh

```cfg
Tuan_l4d2_selfhelp_enable "1"
Tuan_l4d2_selfhelp_buttons "4"
Tuan_l4d2_selfhelp_priority "1"
Tuan_l4d2_selfhelp_delay "1.0"
Tuan_l4d2_selfhelp_pickup_range "100.0"
Tuan_l4d2_selfhelp_help_other_range "100.0"
Tuan_l4d2_selfhelp_help_other_time "3.0"
Tuan_l4d2_selfhelp_help_other_health "2.0"
```

Button values giong upstream:

- `4` = Duck
- `32` = Use
- `131072` = Shift
- Co the cong gia tri de yeu cau nhieu nut cung luc.

## Item config

Moi item co cac nhom cvar:

```cfg
Tuan_l4d2_selfhelp_<item>_enable "1"
Tuan_l4d2_selfhelp_<item>_time "3.0"
Tuan_l4d2_selfhelp_<item>_incap "1"
Tuan_l4d2_selfhelp_<item>_health "80.0"
Tuan_l4d2_selfhelp_<item>_permanent "0"
Tuan_l4d2_selfhelp_<item>_ledge "1"
Tuan_l4d2_selfhelp_<item>_pinned "1"
```

`<item>` gom:

- `kit`
- `defib`
- `pills`
- `adren`

`pinned`:

- `0` = khong cho dung khi bi pin
- `1` = giet attacker, khong set health rieng neu chi bi pin
- `2` = giet attacker va apply health cua item

`permanent`:

- `0` = set temp health, giu revive count cua game
- `1` = set real health va reset revive count/BnW state

## Tuong thich voi plugin hien co

Server dang co `Tuan_l4d_incapped_weapons`:

- Plugin moi khong patch memory va khong thay doi cvar cua plugin do.
- `Tuan_l4d_incapped_weapons` van cho self-revive bang pills/adrenaline theo co che dung item cua no.
- `Tuan_l4d2_selfhelp` them co che rieng bang Duck va ho tro kit/defib/pinned/ledge/pickup/help-other.
- Neu muon chi dung self-help moi cho pills/adrenaline, co the tat revive pills/adrenaline trong config `Tuan_l4d_incapped_weapons.cfg` sau.

## Build/deploy

Compile tai:

```bat
cd l4d2-sourcemod\addons\sourcemod\scripting
spcomp.exe Tuan_l4d2_selfhelp.sp -o..\plugins\qol\Tuan_l4d2_selfhelp.smx
```

## Changelog

### 27/04/2026

- Tao plugin moi `Tuan_l4d2_selfhelp`.
- Them self-help bang medical item cho incap/ledge/pinned.
- Them progress bar, item priority, pickup item bang `E`, va incap-help-other.
- Them cfg runtime `cfg/sourcemod/Tuan_l4d2_selfhelp.cfg`.
- Compile va deploy vao `addons/sourcemod/plugins/qol/Tuan_l4d2_selfhelp.smx`.

### 27/04/2026 - Fix progress bar prop

- Fix runtime error `Property "m_iProgressBarDuration" not found` khi client disconnect hoac server khong expose progress-bar sendprop tren player.
- `ShowProgress` va `ClearProgress` gio check `HasEntProp` truoc khi set `m_flProgressBarStartTime` / `m_iProgressBarDuration`.
- Neu prop khong ton tai, plugin bo qua progress bar nhung self-help van tiep tuc hoat dong.

### 27/04/2026 - Progress fallback

- `ShowProgress` gio thu `m_iProgressBarDuration` truoc, sau do thu bien the `m_flProgressBarDuration`.
- Neu netprop progress bar khong co, plugin thu gui usermessage `BarTime` neu engine ho tro.
- Them center-text countdown moi 0.5s trong luc self-help de nguoi choi van thay tien trinh neu HUD progress bar cua engine khong kha dung.
