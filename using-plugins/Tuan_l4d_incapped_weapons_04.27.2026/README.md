# Tuan_l4d_incapped_weapons (04.27.2026)

## Muc tieu

Ban nay la custom snapshot cua plugin `[L4D & L4D2] Incapped Weapons Patch` by SilverShot, dua tren upstream `1.42`.

Muc tieu chinh:

- Cho phep survivor dung weapon/item khi dang incapped nhu ban goc.
- Tach khoi ban goc bang prefix `Tuan_` de tranh conflict cvar/cfg/plugin.
- Sync self-revive voi `tuan_notify_system` de bo dem Black & White khong bi lech khi player tu revive bang pills/adrenaline.

## File runtime

- Source: `addons/sourcemod/scripting/Tuan_l4d_incapped_weapons.sp`
- Plugin: `addons/sourcemod/plugins/qol/Tuan_l4d_incapped_weapons.smx`
- Config: `cfg/sourcemod/Tuan_l4d_incapped_weapons.cfg`
- Gamedata: `addons/sourcemod/gamedata/Tuan_l4d_incapped_weapons.txt`
- Translation: `addons/sourcemod/translations/Tuan_l4d_incapped_weapons.phrases.txt`

Ban goc `l4d_incapped_weapons` da duoc remove khoi runtime de tranh load song song va conflict memory patch/cvar.

## Thay doi so voi ban goc

- Doi `PLUGIN_VERSION` thanh `04.27.2026`.
- Doi library name thanh `Tuan_l4d_incapped_weapons`.
- Doi gamedata sang `Tuan_l4d_incapped_weapons.txt`.
- Doi translation phrase sang `Tuan_l4d_incapped_weapons.phrases`.
- Doi AutoExecConfig sang `Tuan_l4d_incapped_weapons`.
- Doi tat ca cvar runtime sang prefix `Tuan_l4d_incapped_weapons_*`.
- Doi thoi diem fire forward `Tuan_OnClient_SelfRevived`: forward chi duoc fire sau khi plugin da apply xong revive props, BnW props, main health va temp health.

## Tuong thich BnW notify

Plugin nay van fire forward:

```sourcepawn
Tuan_OnClient_SelfRevived(int client)
```

Khac biet quan trong: forward duoc fire sau khi `RevivePlayer()` da set xong cac props lien quan:

- `m_currentReviveCount`
- `m_bIsOnThirdStrike` tren L4D2
- `m_isGoingToDie`
- main health
- temp health buffer

`tuan_notify_member_bw` da duoc update de hook forward nay. Khi nhan self-revive, notify BW se doc lai trang thai BnW that cua player va sync `g_bPlayerBW`:

- Neu player vua vao BnW: set tracker true va fire `Tuan_OnClient_GoBnW`.
- Neu player khong con BnW: reset tracker false.
- Neu tracker da dung san: khong spam duplicate notification.

Muc tieu la tranh case player self-revive lam state BnW trong game va state BnW cua notify bi khac nhau, dan den heal notification sai ve sau.

## CVAR

Config duoc luu tai:

```cfg
cfg/sourcemod/Tuan_l4d_incapped_weapons.cfg
```

Danh sach cvar custom giu nguyen y nghia va value hien tai tu ban goc:

```cfg
Tuan_l4d_incapped_weapons_allow "1"
Tuan_l4d_incapped_weapons_delay_adren "5.0"
Tuan_l4d_incapped_weapons_delay_pills "5.0"
Tuan_l4d_incapped_weapons_delay_text "2"
Tuan_l4d_incapped_weapons_friendly "0.0"
Tuan_l4d_incapped_weapons_heal_adren "-1"
Tuan_l4d_incapped_weapons_heal_pills "-1"
Tuan_l4d_incapped_weapons_heal_revive "1"
Tuan_l4d_incapped_weapons_heal_text "1"
Tuan_l4d_incapped_weapons_health "20"
Tuan_l4d_incapped_weapons_melee "0"
Tuan_l4d_incapped_weapons_modes ""
Tuan_l4d_incapped_weapons_modes_off ""
Tuan_l4d_incapped_weapons_modes_tog "0"
Tuan_l4d_incapped_weapons_pistol "0"
Tuan_l4d_incapped_weapons_restrict "12,24,30,31"
Tuan_l4d_incapped_weapons_revive "4"
Tuan_l4d_incapped_weapons_throw "0"
```

## Web UI

Tab `Incapped Weapons` trong webapp da duoc doi sang cvar custom `Tuan_l4d_incapped_weapons_*` va ghi vao file:

```cfg
cfg/sourcemod/Tuan_l4d_incapped_weapons.cfg
```

Web UI khong con ghi vao `cfg/sourcemod/l4d_incapped_weapons.cfg`.

## Compile

Compile tai:

```bat
cd l4d2-sourcemod\addons\sourcemod\scripting
spcomp.exe Tuan_l4d_incapped_weapons.sp -o..\plugins\qol\Tuan_l4d_incapped_weapons.smx
```

Do `tuan_notify_member_bw.sp` cung duoc update de sync self-revive, compile lai:

```bat
spcomp.exe tuan_notify_member_bw.sp -o..\plugins\qol\tuan_notify_member_bw.smx
```

## Changelog

### 27/04/2026

- Tao custom snapshot `Tuan_l4d_incapped_weapons_04.27.2026` tu ban goc `l4d_incapped_weapons_02.23.2026`.
- Prefix cvar/cfg/gamedata/translation/source/plugin sang `Tuan_l4d_incapped_weapons`.
- Tao config moi `cfg/sourcemod/Tuan_l4d_incapped_weapons.cfg` tu value runtime cu.
- Update self-revive forward timing de notify BW doc duoc state sau khi props da apply.
- Update Web UI tab `Incapped Weapons` sang custom cvars.
- Remove ban goc khoi runtime de tranh xung dot.
