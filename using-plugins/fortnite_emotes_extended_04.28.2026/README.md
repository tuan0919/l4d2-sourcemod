# Fortnite Emotes Extended

## Mục đích

Thêm menu emote/dance cho player qua `!emotes`, `!emote`, `!dances`, `!dance`.

Plugin cần FastDL để client tải model emote và nhạc Fortnite trước khi dùng ổn định.

## File được thêm

```txt
addons/sourcemod/scripting/fortnite_emotes_extended.sp
addons/sourcemod/scripting/include/fnemotes.inc
addons/sourcemod/plugins/qol/fortnite_emotes_extended.smx
addons/sourcemod/translations/fnemotes.phrases.txt
```

## FastDL content liên quan

Source repo layout:

```txt
l4d2-fastdl-contents/fortnite_dances/models/player/custom_player/foxhound/
l4d2-fastdl-contents/fortnite_dances/sound/kodua/fortnite_emotes/
```

Runtime path sau khi chạy `scripts/setup_fastdl.sh`:

```txt
models/player/custom_player/foxhound/
sound/kodua/fortnite_emotes/
```

Plugin vẫn dùng runtime path trong `AddFileToDownloadsTable()`, `PrecacheModel()` và `PrecacheSound()`. Không prefix `fortnite_dances/` trong plugin.

`scripts/setup_fastdl.sh` chỉ setup hạ tầng chung và gọi `scripts/setup_fastdl_fortnite_dances.sh` khi `FASTDL_MODULES` có `fortnite_dances`. `start.bat` mặc định set `FASTDL_MODULES=fortnite_dances`.

## Changelog 04.28.2026

* Tích hợp bản `SM Fortnite Emotes Extended - L4D Version` vào hệ thống.
* Sửa detect engine để L4D2 dùng đúng nhánh logic L4D.
* Sửa lỗi sound name có thể bị thành `.mp3.mp3`.
* Compile sạch warning bằng SourceMod compiler hiện có trong repo.
* Cập nhật ghi chú FastDL theo layout module `fortnite_dances/`; sub-script `setup_fastdl_fortnite_dances.sh` sẽ flatten asset về game-relative path.
