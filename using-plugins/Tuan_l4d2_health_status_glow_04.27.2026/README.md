# Tuan_l4d2_health_status_glow (04.27.2026)

## Muc tieu

Plugin hien glow tinh trang mau cua teammate survivor khi viewer dang cam health item va dung trong tam range.

Health item kich hoat glow:

- `weapon_first_aid_kit`
- `weapon_defibrillator`
- `weapon_pain_pills`
- `weapon_adrenaline`

Target chi tinh survivor dang song va dang dung. Survivor incap/hanging khong hien health-status glow de tranh conflict voi remote-save glow.

## Runtime files

- Source: `addons/sourcemod/scripting/Tuan_l4d2_health_status_glow.sp`
- Plugin: `addons/sourcemod/plugins/qol/Tuan_l4d2_health_status_glow.smx`
- Config: `cfg/sourcemod/Tuan_l4d2_health_status_glow.cfg`
- Snapshot: `using-plugins/Tuan_l4d2_health_status_glow_04.27.2026/`

## Cach hoat dong

1. Viewer phai la survivor human, dang song, khong incap/hanging.
2. Viewer phai dang cam health item o slot medkit/defib hoac pills/adrenaline.
3. Target phai la survivor teammate dang song, dang dung, khong incap/hanging.
4. Target phai nam trong tam `Tuan_l4d2_health_status_glow_range`.
5. Plugin tao proxy glow invisible attach vao target va filter bang `SDKHook_SetTransmit`.
6. Chi viewer hop le moi nhan proxy glow, nen glow khong bi hien global cho tat ca moi nguoi.

## Mau glow

Thu tu uu tien:

- BnW: trang `255 255 255`.
- Tong mau `<= Tuan_l4d2_health_status_glow_low_health`: vang `255 255 0`.
- Tong mau `> Tuan_l4d2_health_status_glow_low_health`: xanh la `0 255 0`.

Tong mau = real health `GetClientHealth()` + temp health `L4D_GetTempHealth()`.

BnW duoc doc tu:

- `m_bIsOnThirdStrike`
- fallback `m_currentReviveCount >= survivor_max_incapacitated_count`

## Toi uu runtime

- Moi target chi co toi da 1 proxy glow entity.
- Holder state `dang cam health item` duoc cache vao `g_iHeldHealthItem`.
- Dung `Attachments_OnWeaponSwitch` cua Silver `attachments_api` de update cache nhanh khi doi weapon.
- Van giu fallback `OnPlayerRunCmd` de plugin van hoat dong neu `attachments_api` khong fire forward.
- `SetTransmit` chi check viewer/target/range/cache, khong tinh health va khong doc classname.
- Proxy luu target bang `m_hOwnerEntity`, nen `SetTransmit` map nguoc ve target O(1), khong loop `MaxClients`.
- Mau health duoc sync theo timer, default `0.5s`, va chi set lai glow khi state mau doi.
- Cleanup proxy khi target disconnect/death/team change, round reset, map end hoac plugin unload.
- Glow proxy van dung `SetAttached` de giu render on dinh, kem bonemerge + `EF_PARENT_ANIMATES` de dong bo animation cua player va giam outline T-pose.
- `m_nGlowRange` duoc set theo `Tuan_l4d2_health_status_glow_range` thay vi unlimited, de glow tat dung hon khi viewer ra khoi tam.

## CVAR

Config runtime:

```cfg
cfg/sourcemod/Tuan_l4d2_health_status_glow.cfg
```

```cfg
Tuan_l4d2_health_status_glow_enable "1"
Tuan_l4d2_health_status_glow_range "650.0"
Tuan_l4d2_health_status_glow_low_health "40"
Tuan_l4d2_health_status_glow_sync_interval "0.5"
```

## Compile

Compile tai:

```bat
cd l4d2-sourcemod\addons\sourcemod\scripting
spcomp.exe Tuan_l4d2_health_status_glow.sp -o..\plugins\qol\Tuan_l4d2_health_status_glow.smx
```

## Changelog

### 27/04/2026

- Tao plugin moi `Tuan_l4d2_health_status_glow`.
- Hien health-status glow cho survivor teammate khi viewer cam health item va dung gan target.
- BnW glow trang, mau <= 40 glow vang, mau > 40 glow xanh la.
- Chi target survivor dang dung moi hien glow; incap/hanging khong tinh.
- Dung proxy invisible + `SetTransmit` de glow chi hien voi viewer hop le.
- Toi uu bang holder cache, `Attachments_OnWeaponSwitch`, owner lookup O(1), va `L4D2_SetEntityGlow()` tu `left4dhooks`.
- Fix glow proxy: giu `SetAttached` input de proxy tiep tuc render, them bonemerge/parent-animates de giam T-pose, va gioi han engine glow range theo CVAR range de glow mat khi viewer ra khoi tam.
