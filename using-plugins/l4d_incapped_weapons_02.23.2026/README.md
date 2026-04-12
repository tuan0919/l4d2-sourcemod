# Plugins description

Patches the game to allow using Weapons while Incapped, instead of changing weapons scripts.

## About

- Memory patch method to use weapons while incapped, instead of changing weapons scripts.
- Press the keys 1, 2, 3, 4, 5 to switch Weapons. Mouse scroll does not work.
- Grenades and Melee weapons can be used while incapped. Survivors appear to stand up to throw grenades, this can be prevented by having Left4DHooks installed.
- Supports using Pills and Adrenaline to heal or revive a player, in version 1.16 and newer.

## Weapon Fire Rate
- Recommended: WeaponHandling_API by Lux. Set wh_use_incap_cycle_cvar cvar to "0". This changes all weapon fire rates to their normal speed.
- Alternatively set the games cvar survivor_incapacitated_cycle_time to "0.1" but this will modify it for all weapons and not return them to their correct speed.

# Cvars

Saved to l4d_incapped_weapons.cfg in your servers \cfg\sourcemod\ folder.

```php
// 0=Plugin off, 1=Plugin on.
l4d_incapped_weapons_allow "1"

// Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).
l4d_incapped_weapons_modes ""

// Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).
l4d_incapped_weapons_modes_off ""

// Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.
l4d_incapped_weapons_modes_tog "0"

// L4D2 only: 0.0=Off. How many seconds a player must wait after using Adrenaline to be revived.
l4d_incapped_weapons_delay_adren "5.0"

// 0.0=Off. How many seconds a player must wait after using Pills to be revived.
l4d_incapped_weapons_delay_pills "5.0"

// 0=Off. 1=Print to chat. 2=Print to hint box. Display to player how long until they are revived, when using a _delay cvar.
l4d_incapped_weapons_delay_text "2"

// 0.0=None. 1.0=Default damage. Scales an incapped Survivors friendly fire damage to other Survivors. Multiplied against the games survivor_friendly_fire* cvars.
l4d_incapped_weapons_friendly "1.0"

// L4D2 only: -1=Revive player. 0=Off. How much to heal a player when they use Adrenaline whilst incapped.
l4d_incapped_weapons_heal_adren "50"

// -1=Revive player. 0=Off. How much to heal a player when they use Pain Pills whilst incapped.
l4d_incapped_weapons_heal_pills "50"

// 0=Off. When reviving with healing items, should player enter black and white status. 1=Pills. 2=Adrenaline. 3=Both.
l4d_incapped_weapons_heal_revive "0"

// 0=Off. 1=Print to chat. 2=Print to hint box. Print a message when incapacitated that Pills/Adrenaline can be used to heal/revive.
l4d_incapped_weapons_heal_text "1"

// How much health to give a player when they revive themselves.
l4d_incapped_weapons_health "30"

// L4D2 only: 0=No friendly fire. 1=Allow friendly fire. When using Melee weapons should they hurt other Survivors.
l4d_incapped_weapons_melee "0"

// L4D2 only: 0=Don't give pistol (allows Melee weapons to be used). 1=Give pistol (game default).
l4d_incapped_weapons_pistol "0"

// Empty string to allow all. Prevent these weapon IDs from being used while incapped. See below for details.
// L4D2: default blocks all medkits/upgrade ammo. To block grenades add "13,14,25"
l4d_incapped_weapons_restrict "12,24,30,31"

// L4D1: default blocks medkits. To block grenades add "9,10" e.g: "8,12,9,10"
l4d_incapped_weapons_restrict "8"

// Play revive animation: 0=Off. 1=On and damage can stop reviving. 2=Damage will interrupt animation and restart reviving. 3=Damage does not interrupt reviving. 4=Give god mode when reviving
l4d_incapped_weapons_revive "3"

// 0=Block throwing grenade animation to prevent standing up during throw (requires Left4DHooks plugin). 1=Allow throwing animation.
l4d_incapped_weapons_throw "0"

// Incapped Weapons plugin version.
l4d_incapped_weapons_version 
```

## Weapon Restriction Cvar

The cvar l4d_incapped_weapons_restrict uses Weapon IDs to restrict their usage. String must be comma separated.

Complete list:

```
// L4D2:
"weapon_smg"                      = 2
"weapon_pumpshotgun"              = 3
"weapon_autoshotgun"              = 4
"weapon_rifle"                    = 5
"weapon_hunting_rifle"            = 6
"weapon_smg_silenced"             = 7
"weapon_shotgun_chrome"           = 8
"weapon_rifle_desert"             = 9
"weapon_sniper_military"          = 10
"weapon_shotgun_spas"             = 11
"weapon_first_aid_kit"            = 12
"weapon_molotov"                  = 13
"weapon_pipe_bomb"                = 14
"weapon_pain_pills"               = 15
"weapon_melee"                    = 19
"weapon_chainsaw"                 = 20
"weapon_grenade_launcher"         = 21
"weapon_adrenaline"               = 23
"weapon_defibrillator"            = 24
"weapon_vomitjar"                 = 25
"weapon_rifle_ak47"               = 26
"weapon_upgradepack_incendiary"   = 30
"weapon_upgradepack_explosive"    = 31
"weapon_smg_mp5"                  = 33
"weapon_rifle_sg552"              = 34
"weapon_sniper_awp"               = 35
"weapon_sniper_scout"             = 36
"weapon_rifle_m60"                = 37

// L4D1
"weapon_smg"                      = 2
"weapon_pumpshotgun"              = 3
"weapon_autoshotgun"              = 4
"weapon_rifle"                    = 5
"weapon_hunting_rifle"            = 6
"weapon_first_aid_kit"            = 8
"weapon_molotov"                  = 9
"weapon_pipe_bomb"                = 10
"weapon_pain_pills"               = 12
```

