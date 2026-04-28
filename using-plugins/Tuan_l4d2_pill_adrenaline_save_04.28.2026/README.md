# Tuan_l4d2_pill_adrenaline_save (04.28.2026)

## Muc tieu

Plugin cho phep survivor dang song, dang cam `pain pills` hoac `adrenaline`, nhin vao survivor dang incap va bam `USE` de cuu tu xa.

Target khong dung day ngay lap tuc. Plugin dua target vao animation get-up giong `Tuan_l4d_incapped_weapons` self-revive, doi het animation roi moi revive va gui notify.

## Phan tich animation self-revive goc

`Tuan_l4d_incapped_weapons` khong goi `L4D_ReviveSurvivor()` ngay khi player dung pills/adrenaline. Flow animation nhu sau:

- Khi item heal/revive xong cast, neu `Tuan_l4d_incapped_weapons_revive` khac `0`, plugin set `m_TimeForceExternalView` de ep third-person tam thoi.
- Plugin set `m_reviveOwner` cua target bang chinh target (`m_reviveOwner = client`). Game coi survivor dang trong trang thai revive/get-up, nen se play animation dung day.
- Plugin tao timer `TIMER_ANIM = 5.0` giay.
- Trong luc animation, plugin co the hook damage de interrupt/reset/block/godmode tuy theo mode.
- Khi timer ket thuc, plugin set `m_reviveOwner = -1`, sau do moi goi `L4D_ReviveSurvivor(client)`.
- Ban custom da doi forward `Tuan_OnClient_SelfRevived` sang sau khi revive/BnW props apply xong, de notify doc state dung.

Plugin nay reuse dung pattern can thiet:

- Set `m_TimeForceExternalView`.
- Set `m_reviveOwner = target`.
- Doi `Tuan_l4d2_pill_adrenaline_save_anim_time` giay, default `5.0`.
- Clear `m_reviveOwner`.
- Goi `L4D_ReviveSurvivor(target)`.
- Apply health.
- Fire forward custom sau khi target da dung day thanh cong.

## Runtime files

- Source: `addons/sourcemod/scripting/Tuan_l4d2_pill_adrenaline_save.sp`
- Plugin: `addons/sourcemod/plugins/qol/Tuan_l4d2_pill_adrenaline_save.smx`
- Config: `cfg/sourcemod/Tuan_l4d2_pill_adrenaline_save.cfg`
- Snapshot: `using-plugins/Tuan_l4d2_pill_adrenaline_save_04.28.2026/`

## Cach hoat dong

1. Survivor healer phai dang song, team Survivor, khong incap/hanging.
2. Healer cam active weapon slot pills la `weapon_pain_pills` hoac `weapon_adrenaline`.
3. Healer nhin vao survivor dang incap trong tam range.
4. Healer bam `USE`.
5. Plugin remove item tren tay healer.
6. Target play get-up animation trong `Tuan_l4d2_pill_adrenaline_save_anim_time` giay.
7. Khi animation xong, target duoc revive bang `L4D_ReviveSurvivor()`.
8. Plugin fire forward `Tuan_OnClient_RemoteItemSaved(healer, target, itemType)`.
9. `tuan_notify_member_events` publish Script HUD sau khi animation/revive thanh cong.
10. `tuan_notify_member_bw` sync lai BnW state cua target tu props that.

## Forward

Plugin tao forward:

```sourcepawn
Tuan_OnClient_RemoteItemSaved(int healer, int target, int itemType)
```

`itemType`:

- `0` = pain pills
- `1` = adrenaline

Forward chi duoc fire sau khi target da play xong animation va `L4D_ReviveSurvivor()` da chay.

## Tuong thich notify/BnW

Da update `tuan_notify_system_04.25.2026`:

- `tuan_notify_member_events` co handler `Tuan_OnClient_RemoteItemSaved` va cvar `tuan_notify_member_evt_notify_remote_item_save`.
- `tuan_notify_member_bw` co handler `Tuan_OnClient_RemoteItemSaved` de doc lai `m_bIsOnThirdStrike` / `m_currentReviveCount` cua target sau revive.
- Plugin khong fire fake `revive_success`, tranh duplicate message `helped up` va tranh flow BnW bi tinh 2 lan.

## Chat hint

Khi co survivor dang incap va healer switch sang cam pills/adrenaline, plugin print rieng cho healer:

```text
[Remote Save] You can use pain pills/adrenaline to save an incapacitated teammate from range. Aim at them and press USE.
```

Hint co cooldown de tranh spam.

## Remote save glow

Khi co survivor dang incap trong tam remote save va mot survivor dang cam `pain pills` hoac `adrenaline`, target se hien glow xanh la.

Glow duoc tao bang proxy entity vo hinh attach vao target va filter bang `SDKHook_SetTransmit`, nen chi client hien dang cam pills/adrenaline moi thay. Plugin khong bat glow truc tiep tren player that de tranh glow bi hien global cho tat ca moi nguoi.

Glow duoc cleanup khi khong con holder hop le, target revive/death/doi team, round reset, map end hoac plugin unload.

Toi uu runtime:

- Cache holder state `dang cam pills/adrenaline` thay vi check classname trong moi lan `SetTransmit`.
- Dung forward `Attachments_OnWeaponSwitch` cua Silver `attachments_api` de update cache ngay khi doi weapon, neu plugin API dang load.
- Van giu fallback `OnPlayerRunCmd` de plugin hoat dong an toan khi `attachments_api` khong co hoac forward bi miss.
- Dung `m_hOwnerEntity` tren glow proxy de map nguoc ve target O(1), khong can loop `MaxClients` trong `SetTransmit`.
- Dung stock `L4D2_SetEntityGlow()` tu `left4dhooks` de set glow an toan hon thay vi set tung prop thu cong.
- Glow proxy van dung `SetAttached` de giu render on dinh, kem bonemerge + `EF_PARENT_ANIMATES` de dong bo animation cua player va giam outline T-pose.
- `m_nGlowRange` duoc set theo `Tuan_l4d2_pill_adrenaline_save_range` thay vi unlimited, de glow tat dung hon khi viewer ra khoi tam.

## Guard double-save

Plugin co guard de tranh 2 healer consume item cho cung 1 target trong khoang thoi gian rat ngan:

- Reserve target bang `g_bSavingTarget[target]` truoc khi remove pills/adrenaline cua healer.
- Neu target co `m_reviveOwner > 0` thi coi nhu dang duoc revive/self-revive, remote save bi chan truoc khi consume item.
- Neu `RemovePlayerItem()` fail thi rollback reservation va khong start save.
- Sau khi remote save thanh cong, target bi block save lai trong `0.5s` bang `g_fTargetSaveBlockedUntil`.
- Timer complete check dung timer handle va `g_bSavingTarget[target]` de bo qua stale timer.
- `TryStartRemoteSave()` check ca target dang saving va short block sau save, tranh case target vua duoc revive nhung incap prop chua settle kip trong frame tiep theo.

## CVAR

Config runtime:

```cfg
cfg/sourcemod/Tuan_l4d2_pill_adrenaline_save.cfg
```

```cfg
Tuan_l4d2_pill_adrenaline_save_enable "1"
Tuan_l4d2_pill_adrenaline_save_range "650.0"
Tuan_l4d2_pill_adrenaline_save_anim_time "5.0"
Tuan_l4d2_pill_adrenaline_save_main_health "20"
Tuan_l4d2_pill_adrenaline_save_temp_health "-1.0"
Tuan_l4d2_pill_adrenaline_save_godmode "1"
Tuan_l4d2_pill_adrenaline_save_chat_hint "1"
Tuan_l4d2_pill_adrenaline_save_chat_hint_cooldown "8.0"
Tuan_l4d2_pill_adrenaline_save_use_hint_cooldown "1.0"
```

Ghi chu:

- `temp_health = -1.0` dung game cvar `survivor_revive_health`.
- `main_health = 20` mimic setting self-revive hien tai cua `Tuan_l4d_incapped_weapons`.
- `godmode = 1` chan damage vao target trong luc get-up animation.

## Compile

Compile tai:

```bat
cd l4d2-sourcemod\addons\sourcemod\scripting
spcomp.exe Tuan_l4d2_pill_adrenaline_save.sp -o..\plugins\qol\Tuan_l4d2_pill_adrenaline_save.smx
spcomp.exe tuan_notify_member_events.sp -o..\plugins\qol\tuan_notify_member_events.smx
spcomp.exe tuan_notify_member_bw.sp -o..\plugins\qol\tuan_notify_member_bw.smx
```

## Changelog

### 28/04/2026

- Fix case target dang duoc revive thu cong boi survivor khac van cho remote save.
- `IsTargetSaveBusy()` gio check them `m_reviveOwner > 0`, nen remote save bi chan truoc khi consume pills/adrenaline.

### 27/04/2026

- Tao plugin moi `Tuan_l4d2_pill_adrenaline_save`.
- Remote save bang held pain pills/adrenaline + aim target + press `USE`.
- Target play get-up animation truoc khi revive.
- Consume item cua healer khi start save.
- Them forward `Tuan_OnClient_RemoteItemSaved`.
- Update notify events/BnW de hien Script HUD va sync BnW an toan.
- Them glow xanh la cho survivor incap trong tam remote save, chi hien voi client dang cam pills/adrenaline.
- Glow dung proxy invisible + `SetTransmit` de tranh hien global va cleanup an toan theo lifecycle cua target/plugin.
- Toi uu glow bang holder cache, `Attachments_OnWeaponSwitch`, owner lookup O(1), va `L4D2_SetEntityGlow()` tu `left4dhooks`.
- Guard double-save: reserve target truoc khi consume item, rollback neu remove item fail, va block save lai `0.5s` sau khi target duoc revive thanh cong.
- Fix glow proxy: giu `SetAttached` input de proxy tiep tuc render, them bonemerge/parent-animates de giam T-pose, va gioi han engine glow range theo CVAR range de glow mat khi viewer ra khoi tam.
