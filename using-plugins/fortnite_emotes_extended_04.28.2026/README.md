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

```txt
l4d2-fastdl-contents/models/player/custom_player/foxhound/
l4d2-fastdl-contents/sound/kodua/fortnite_emotes/
```

## Changelog 04.28.2026

* Tích hợp bản `SM Fortnite Emotes Extended - L4D Version` vào hệ thống.
* Sửa detect engine để L4D2 dùng đúng nhánh logic L4D.
* Sửa lỗi sound name có thể bị thành `.mp3.mp3`.
* Compile sạch warning bằng SourceMod compiler hiện có trong repo.
