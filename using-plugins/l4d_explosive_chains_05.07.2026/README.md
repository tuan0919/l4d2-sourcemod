# l4d_explosive_chains (05.07.2026)

## Muc dich

- Cai plugin `[L4D & L4D2] Explosive Chains Credit` cua Silvers.
- Giu credit cho survivor da ban/dot gascan, propane, oxygen, fireworks crate, fuel barrel khi fire/explosion chain lan sang entity khac.
- Ho tro `Tuan_l4d2_death_incap_red` resolve attacker/cause chinh xac hon khi co nhieu molotov/gascan gan nhau.

## Source

- Source goc: `reference/plugins-reference/l4d_explosive_chains.sp`
- Source deploy: `addons/sourcemod/scripting/game-fixes/l4d_explosive_chains.sp`
- Output deploy: `addons/sourcemod/plugins/game-fixes/l4d_explosive_chains.smx`

## Ghi chu tuong thich

- Plugin nay set owner credit len cac prop/entity bang `m_hOwnerEntity`, `m_hBreaker`, `m_hPhysicsAttacker` va rewrite attacker khi damage den player/infected/witch den tu entity da co owner.
- `Tuan_l4d2_death_incap_red_modular_05.07.2026` se doc cac owner props nay nhu deterministic owner hint, nhung khong hard-require plugin nay.
