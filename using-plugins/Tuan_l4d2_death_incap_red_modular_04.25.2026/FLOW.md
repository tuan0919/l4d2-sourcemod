# FLOW.md — Logic hệ thống Death/Incap Red Announce

Cập nhật: 25/04/2026

---

## Tổng quan

Plugin announce lên chat (màu đỏ) khi survivor bị incap hoặc chết, kèm theo tên kẻ tấn công và nguyên nhân cụ thể. Ngoài ra còn announce khi survivor giết SI/Witch.

---

## Kiến trúc module

```
Tuan_l4d2_death_incap_red.sp   ← wrapper, include tất cả module
│
├── death_incap_red_defs.inc           ← constants, enums, global variables
├── death_incap_red_lifecycle.inc      ← OnPluginStart, OnMapStart, OnClientDisconnect
├── death_incap_red_events.inc         ← hook game events (player_death, player_incapacitated_start, ...)
├── death_incap_red_entity_hooks.inc   ← OnEntityCreated, OnEntityDestroyed
├── death_incap_red_tracking.inc       ← OnTakeDamageAlive, timers, fire source resolution
├── death_incap_red_hazard.inc         ← hazard entity detection, fire source ring buffers
├── death_incap_red_outcome.inc        ← ResolveAttacker, ResolveCause (entry point chính)
├── death_incap_red_survivor_cause.inc ← ResolveSurvivorCause, ResolveSurvivorKillSICause
└── death_incap_red_notify_state.inc   ← helper functions, IsWallbangKill, chat print
```

---

## Flow chính: Survivor bị incap / chết

```
Event: player_incapacitated_start / player_death
        │
        ▼
PrintOutcome(victim, attackerClient, attackerEnt, weapon, dmgType, isIncap, bleedingOut)
        │
        ├─ ResolveAttacker(...)
        │       │
        │       ├─ Check Elite SI natives (ToxicGas, Ignitor, Leaker)
        │       ├─ Check attackerClient team (2=survivor, 3=SI)
        │       ├─ TryResolveFromEntity(attackerEnt)
        │       ├─ HasRecentSnapshot → dùng g_iLastAttacker/g_iLastInflictor
        │       └─ ShouldTreatAsSelf (fall/burn/blast không có attacker) → Attacker_Survivor self
        │
        └─ ResolveCause(victim, weapon, dmgType, attackerClient, attackerEnt, kind, ...)
                │
                ├─ kind == Attacker_CI  → "physical"
                ├─ kind == Attacker_SI  → ResolveSpecialInfectedCause(...)
                ├─ kind == Attacker_Survivor → ResolveSurvivorCause(...)
                ├─ IsFireCause          → "fire"
                ├─ IsExplosiveCause     → "explosive"
                ├─ DMG_FALL             → "falling"
                └─ FormatWeaponName     → tên vũ khí cụ thể
```

---

## Flow: Resolve cause khi attacker là Survivor

```
ResolveSurvivorCause(victim, attackerClient, attackerEnt, eventWeapon, dmgType, ...)
        │
        ├─ GetBestWeaponLabel → baseWeapon (từ eventWeapon hoặc snapshot weapon)
        │
        ├─ fire = IsFireCause || IsFireFromEntities
        │       │
        │       └─ TryCauseFromFireEntitySource  ← ưu tiên cao nhất
        │               │
        │               ├─ TryResolveFireSourceFromEntity(attackerEnt)
        │               │       └─ check fire source cache (g_iFireEntSourceType)
        │               ├─ TryResolveFireSourceFromEntity(snapInflictor)
        │               └─ FindBestFireSource(victimPos) ← position-based fallback
        │
        │       ├─ IsGascanSource      → "gascan"
        │       ├─ IsFireworkSource    → "firework crate"
        │       ├─ IsFuelBarrelSource  → "fuel barrel"
        │       ├─ IsMolotovSource     → "molotov"
        │       ├─ TryCauseFromHazardContext → từ g_iLastHazardType[attacker]
        │       ├─ IsLikelyGascanInferno → "gascan" (positive evidence từ ring buffer)
        │       ├─ bulletFireState     → "WeaponName/fire bullet"
        │       └─ fallback            → "fire"
        │
        └─ explosive = IsExplosiveCause || IsExplosiveFromEntities
                ├─ IsPipeBombSource    → "pipebomb"
                ├─ IsFireworkSource    → "firework crate"
                ├─ IsFuelBarrelSource  → "fuel barrel"
                ├─ IsGascanSource      → "gascan"
                ├─ TryCauseFromHazardContext
                ├─ bulletExplosiveState → "WeaponName/explosive bullet"
                └─ fallback            → "explosive"
```

---

## Hệ thống truy vết fire source

### Vấn đề cốt lõi

Khi molotov hoặc gascan cháy, Source Engine tạo entity `inferno`. Entity này không có property nào phân biệt nguồn gốc. Plugin dùng 2 tầng resolution:

### Tầng 1 — Deterministic (BFS linked entities)

```
inferno spawn → Frame_MarkFireEntitySource (next frame)
        │
        └─ ResolveFireSourceDeterministic(fireEnt)
                │
                └─ BFS qua: m_hOwnerEntity, m_hMoveParent, m_hEffectEntity,
                            m_hInflictor, m_hPhysicsAttacker, m_hThrower
                        │
                        ├─ Tìm thấy molotov_projectile → Hazard_Molotov ✓
                        ├─ Tìm thấy gascan entity      → Hazard_Gascan ✓
                        └─ Không tìm thấy → rơi vào Tầng 2
```

Vấn đề: `molotov_projectile` thường bị destroy trước khi `inferno` spawn → BFS miss.

### Tầng 2 — Heuristic (position + time matching)

```
ResolveFireSourceHeuristic(fireEnt)
        │
        ├─ 1. FindBestFireSource(origin)
        │       └─ duyệt g_vSourcePos ring buffer (MAX_SOURCE_EVENTS slots)
        │          score = distance + age * 90.0 → chọn score thấp nhất
        │
        ├─ 2. FindRecentMolotovDestroy(origin, 4s, 300 units)
        │       └─ duyệt g_vMolotovDestroyPos ring buffer (32 slots)
        │          ghi khi molotov_projectile bị destroy
        │
        ├─ 3. FindRecentGascanExplode(origin, 8s, 400 units)
        │       └─ duyệt g_vGascanExplodePos ring buffer (32 slots)
        │          ghi khi gascan bị destroy sau khi nhận damage
        │
        └─ 4. Fallback: WasRecentMolotovThrow(owner, 20s)
```

### Kết quả được cache

```
g_iFireEntSourceType[fireEnt]  = HazardType (Molotov/Gascan/...)
g_iFireEntOwner[fireEnt]       = survivor owner
g_fFireEntMarkTime[fireEnt]    = timestamp
g_iFireEntSourceConfidence[fireEnt] = Deterministic / Heuristic
```

Cache này được dùng bởi `TryReadFreshFireSourceCache` trong `OnTakeDamageAlive` và `TryCauseFromFireEntitySource`.

---

## Chain fire: molotov → gascan t1 → gascan tn

```
Tuan ném molotov
        │
        ▼
molotov_projectile destroy
        ├─ AddSourceEvent(Hazard_Molotov, pos, Tuan)
        └─ ghi MolotovDestroy ring buffer (pos, Tuan, timestamp)
        │
        ▼
inferno spawn tại vị trí molotov
        └─ Frame_MarkFireEntitySource → cache (Hazard_Molotov, owner=Tuan)
        │
        ▼
inferno cháy lan gascan_t1
        └─ OnHazardTakeDamagePost(gascan_t1, attacker=inferno)
                ├─ ResolveDamageOwnerClient → owner=0 (inferno không có owner client)
                ├─ TryReadFreshFireSourceCache(inferno) → (Hazard_Molotov, owner=Tuan) ✓
                └─ ghi g_iHazardLastOwner[gascan_t1] = Tuan
        │
        ▼
gascan_t1 nổ → destroy
        ├─ AddSourceEvent(Hazard_Gascan, pos, Tuan)
        └─ ghi GascanExplode ring buffer (pos, Tuan, timestamp)
        │
        ▼
inferno_t1 spawn từ gascan_t1
        └─ Frame_MarkFireEntitySource → cache (Hazard_Gascan, owner=Tuan)
        │
        ▼
inferno_t1 cháy lan gascan_t2 → ... (lặp lại, owner=Tuan xuyên suốt)
```

---

## SI/Tank bắt lửa rồi chạy xa

```
SI đi vào inferno (molotov/gascan)
        │
        ▼
OnTakeDamageAlive(victim=SI, DMG_BURN)
        └─ TryGetFireSourceMetaForDamage(SI, inflictor)
                └─ TryReadFreshFireSourceCache(inflictor) → (HazardType, owner)
        └─ lưu vào SI fire snapshot:
                g_iSIFireSourceType[SI]  = HazardType
                g_iSIFireSourceOwner[SI] = owner
                g_fSIFireSourceTime[SI]  = now
                g_bSIWasOnFire[SI]       = true
        │
        ▼
SI chạy ra xa, entityflame gắn trên người SI
(inferno gốc đã tắt, không còn link về owner)
        │
        ▼
SI chết cháy → player_death (attacker=0, weapon="entityflame")
        └─ Event_PlayerDeath
                └─ isFirDeath = true
                └─ GetSIFireSnapshot(SI) → (HazardType, owner=Tuan) ✓
                └─ announce: "Tuan killed Hunter (gascan)"
        │
SI hết cháy (IsClientCurrentlyOnFire = false)
        └─ ClearSIFireSnapshot(SI) ← reset để lần cháy tiếp theo resolve lại
```

---

## Heroic pipebomb tracking

```
pipe_bomb_projectile created
        │
        ▼
Frame_InitHeroicPipe
        ├─ targetname == elite_hunter_heroic_pipe -> kind=Hunter Heroic
        ├─ targetname == elite_jockey_heroic_pipe -> kind=Jockey Heroic
        └─ cache owner tu m_hThrower/m_hOwnerEntity
        │
        ▼
OnEntityDestroyed(pipe)
        └─ ghi ring buffer: pos + owner + kind + timestamp
        │
        ▼
ResolveAttacker / ResolveSpecialInfectedCause
        ├─ uu tien targetname tren attackerEnt/snapshot inflictor
        ├─ neu entity da mat: FindRecentHeroicPipeExplosion(victimPos)
        ├─ neu death event la self/suicide gan thoi diem pipe no: van uu tien recent heroic pipe truoc self fallback
        └─ neu Jockey Heroic dung forced suicide: query native `EliteSI_JockeyHeroic_GetRecentDamageCause`
                ├─ Hunter -> "Elite Hunter (Heroic)"
                └─ Jockey -> "Elite Jockey (Heroic)"
```

Cause hien chung la `Heroic Pipebomb` cho ca Hunter va Jockey.
Truong hop Jockey Heroic force suicide survivor sau khi pipe no van resolve thanh `Elite Jockey (Heroic)` + `Heroic Pipebomb`.

---

## Wallbang detection

```
SI chết → Event_PlayerDeath
        │
        ├─ attackerClient là survivor + DMG_BULLET
        │
        └─ IsWallbangKill(attacker, victim)
                │
                ├─ GetClientEyePosition(attacker) → eyePos
                ├─ GetClientAbsOrigin(victim) + z+36 → victimPos (center mass)
                ├─ TR_TraceRayFilterEx(eyePos, dir, MASK_SHOT, TraceFilter_IgnorePlayers)
                │       └─ TraceFilter_IgnorePlayers: chỉ hit entity > MaxClients (world/props)
                │
                └─ Nếu ray hit world TRƯỚC victim (distToHit < distToVictim)
                   VÀ distToHit > 20 units (tránh false positive)
                   → wallbang = true → append "wallbang" vào cause
```

---

## Các cause quan trọng

| Cause | Điều kiện |
|-------|-----------|
| `molotov` | inferno từ molotov_projectile, xác nhận qua MolotovDestroy ring buffer |
| `gascan` | inferno từ gascan nổ, xác nhận qua GascanExplode ring buffer |
| `firework crate` | entity classname chứa `firework`/`fire_cracker` hoặc model path |
| `fuel barrel` | entity classname `fuel_barrel` hoặc model path |
| `propane tank` | entity classname chứa `propan` hoặc model path |
| `oxygen tank` | entity classname chứa `oxygen`/`oxygentank` hoặc model path |
| `pipebomb` | classname `pipe_bomb_projectile` hoặc weapon chứa `pipe` |
| `fire bullet` | `g_fLastIncendiaryShot[attacker]` trong 6s + baseWeapon là bullet weapon |
| `explosive bullet` | `g_fLastExplosiveShot[attacker]` trong 6s + baseWeapon là bullet weapon |
| `Hunter pounce` | `m_pounceAttacker == attackerClient` |
| `Smoker choke` | `m_tongueOwner == attackerClient` |
| `Jockey ride` | `m_jockeyAttacker == attackerClient` |
| `Charger pummel` | `m_pummelAttacker` hoặc `m_carryAttacker == attackerClient` |
| `Spitter acid` | `DMG_ACID` hoặc weapon chứa `spit`/`insect_swarm` |
| `Tank rock` | weapon `tank_rock` hoặc entity classname `tank_rock` |
| `Smoker Toxic Gas` | EliteSI_ToxicGas native |
| `Smoker Ignitor Burn/Fire Patch` | EliteSI_Ignitor native |
| `Boomer Leaker Fire` | EliteSI_Leaker native |
| `falling` | `DMG_FALL` |
| `wallbang` | trace ray hit world trước victim tại killing blow |
| `headshot` | event field `headshot` |
| `fire bullet` | incendiary ammo upgrade |
| `explosive bullet` | explosive ammo upgrade |

---

## Snapshot system

Mỗi khi `OnTakeDamageAlive` được gọi, plugin lưu snapshot của damage gần nhất:

```
g_iLastAttacker[victim]   = attacker client
g_iLastInflictor[victim]  = inflictor entity
g_iLastWeapon[victim]     = weapon entity
g_iLastDmgType[victim]    = damage type flags
g_fLastDmgTime[victim]    = timestamp
```

Snapshot hợp lệ trong `SNAPSHOT_VALID_WINDOW` giây. Dùng để resolve cause khi event data không đủ thông tin (attacker=0, weapon="world", v.v.).

---

## Anchor bot

Plugin dùng một fake client (bot) tên `[RedAnnounce]` ở team 3 (infected) làm "anchor" để gửi chat màu đỏ qua `CPrintToChatEx`. Bot này được tạo tự động nếu chưa tồn tại và được dọn dẹp khi plugin unload.
