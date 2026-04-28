# l4d_population_editor (update 29/04/2026)

## Muc dich

Plugin `[L4D & L4D2] Infected Populations Editor` dung de thay doi danh sach model common infected ma game chon khi spawn, thong qua config rieng thay vi ghi de `scripts/population.txt` bang VPK.

Ban dang dung trong server nay duoc bump len `1.8` tu upstream `1.7` va cai dat cau hinh rieng de moi map, moi khu vuc nav deu dung cung mot population list gom tat ca common infected trong game.

## Cach hoat dong

- Plugin load `addons/sourcemod/data/l4d_population_editor.cfg` khi map start hoac khi chay `sm_pop_reload`.
- Config hien tai chi co section `all`, tro toi `scripts/population_all_common.txt`.
- File population chi co section `default`, vi vay neu nav area khong co ten rieng thi game fallback ve `default`.
- Detour `SelectModelByPopulation` chon model theo ti le cumulative percentage va override model spawn.
- Tong phan tram trong section `default` phai bang `100`, neu sai plugin se reset custom data.

## File da cai dat

```txt
addons/sourcemod/scripting/l4d_population_editor.sp
addons/sourcemod/plugins/qol/l4d_population_editor.smx
addons/sourcemod/gamedata/l4d_population_editor.txt
addons/sourcemod/data/l4d_population_editor.cfg
scripts/population_all_common.txt
```

## Config hien tai

```txt
"populations"
{
	"all"
	{
		"file" "scripts/population_all_common.txt"
	}
}
```

## Command

```txt
sm_pop_reload
```

Reload lai `addons/sourcemod/data/l4d_population_editor.cfg` va file population dang duoc tro toi.

## Luu y van hanh

- Plugin can `DHooks` va `Left 4 DHooks`.
- Neu mot model trong `population_all_common.txt` khong ton tai tren server runtime, plugin se log loi va vo hieu hoa custom population cho map hien tai.
- Neu game update lam sai signature trong `gamedata/l4d_population_editor.txt`, plugin co the fail load.

## Changelog

### 29/04/2026

- Them plugin vao `using-plugins/l4d_population_editor_04.29.2026` de quan ly nhu plugin dang su dung.
- Bump `PLUGIN_VERSION` len `1.8`.
- Cap nhat source tu upstream `1.5` len logic upstream `1.7`.
- Cau hinh plugin dung `scripts/population_all_common.txt` cho tat ca map/gamemode.
- Them custom population script chi co section `default`, gom tat ca common infected model va khong phan biet khu vuc/map.
