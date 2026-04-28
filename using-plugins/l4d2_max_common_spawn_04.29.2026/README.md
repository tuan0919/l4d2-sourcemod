# l4d2_max_common_spawn (update 29/04/2026)

## Muc dich

Plugin gioi han so common infected (`infected`) dang ton tai tren map theo cvar `z_common_limit`.

Plugin nay khong spawn them common infected va khong tang horde truc tiep. No chi theo doi entity common hien co va xoa bot neu tong so common active vuot qua gioi han.

## Cach hoat dong

- Khi plugin start / round start / late load, quet tat ca entity classname `infected` de dem va track common hien co.
- Doc `z_common_limit` lam `maxCommon`.
- Hook thay doi `z_common_limit`; khi cvar doi thi cap nhat `maxCommon` va cleanup lai.
- Khi common moi duoc tao (`OnEntityCreated`), tang `totalCommon` va kiem tra co vuot limit khong.
- Khi common bi destroy (`OnEntityDestroyed`), giam `totalCommon` neu entity do dang duoc track.

## Leniency voi Director

Plugin co `directorLeniency = 5` de tranh xung dot qua gat voi vanilla Director:

- Khi cleanup chua active, chi bat dau cleanup neu `totalCommon > z_common_limit + 5`.
- Khi cleanup da active, plugin ep nghiem `totalCommon > z_common_limit`.
- Neu vuot gioi han, plugin doi timer 3 giay roi moi cleanup.
- Trong luc cleanup active, common moi spawn vuot limit se bi xoa o `SDKHook_SpawnPost`.

## Command

```txt
sm_common_limit
```

In trang thai hien tai:

```txt
Common: <totalCommon> / <z_common_limit> (+ 5) | [Active: ON/OFF]
```

## Tuong thich voi cge_l4d2_commonregulator

Plugin nay hoat dong tot voi `cge_l4d2_commonregulator` theo flow:

- `cge_l4d2_commonregulator` tinh va set `z_common_limit` theo so survivor song.
- `l4d2_max_common_spawn` bat change hook cua `z_common_limit` va dung gia tri moi lam tran common active.
- Vi du voi `cge_l4d2_commonregulator` default va 8 survivor song, `z_common_limit` thuc te la `56`; plugin nay se ep common active ve khoang 56, tam cho vuot den 61 truoc khi cleanup.

## File

```txt
scripting/l4d2_max_common_spawn.sp
addons/sourcemod/scripting/l4d2_max_common_spawn.sp
addons/sourcemod/plugins/multiplayer-stuffs/l4d2_max_common_spawn.smx
```

## Changelog

### 29/04/2026

- Them vao `using-plugins` de quan ly nhu plugin dang su dung.
- Bump version len `0.5.1-2026-04-29`.
- Ghi document muc dich, flow cleanup va tuong thich voi `cge_l4d2_commonregulator`.
