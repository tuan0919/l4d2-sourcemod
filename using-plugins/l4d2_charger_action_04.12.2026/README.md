# Plugin Description

Changes how the Charger can be used.

# Features

- Jumping:
The cvar l4d2_charger_jump lets chargers jump while charging.
- Collision:
The cvar l4d2_charger_charge controls if charging into a survivor grabs them (default game behaviour) or throws them out the way.
- Pummel:
The cvar l4d2_charger_finish will drop survivors after charging with them instead of default game behaviour to pummel.
- Pickup:
The cvar l4d2_charger_pickup allows chargers to melee punch survivors to grab and drop them.
- Survivor Shove:
The cvar l4d2_charger_shove allows survivors to shove chargers and release a survivor being pummeled or carried.

## ConVars:

Saved to l4d2_charger_action.cfg in your servers \cfg\sourcemod\ folder.

```php
// 0=Plugin off, 1=Plugin on.
l4d2_charger_allow      "1"

// Bots can: 0=Grab survivor on contact (game default). 1=Fling survivors on contact instead of grab. 2=Random choice.
l4d2_charger_bots       "1"

// Humans can: 0=Grab survivor on contact (game default). 1=Fling survivors on contact instead of grab.
l4d2_charger_charge     "1"

// Amount of damage to deal on collision when hitting or grabbing a survivor
l4d2_charger_damage     "10"

// After carrying and charging: 0=Pummel (game default). 1=Drop survivor. 2=Drop when a carried survivor is incapped. 3=Both 1 and 2. 4=Continue to carry.
l4d2_charger_finish     "3"

// Allow chargers to automatically pick up incapacitated players whilst charging over them. 0=Off. 1=On. 2=Only when not pinned by other Special Infected.
l4d2_charger_incapped   "1"

// Allow chargers to jump while charging. 0=Off. 1=When alone. 2=Also when carrying a survivor.
l4d2_charger_jump       "2"

// 0=Unlimited. Maximum number of jumps per charge.
l4d2_charger_jumps      "0"

// Allow chargers to carry and drop survivors with the melee button (RMB). 0=Off. 1=Grab Incapped. 2=Grab Standing. 4=Drop Incapped. 8=Drop Standing. 16=Grab while charging (requires l4d2_charger_punch cvar). Add numbers together.
l4d2_charger_pickup     "31"

// Allow pummel to be started and stopped while carrying a survivor (LMB) or Scope/Zoom (MMB/M3) when l4d2_charger_repeat is on. 0=Off. 1=Incapped only. 2=Any survivor.
l4d2_charger_pummel     "2"

// 0=Off. 1=Allow punching while charging.
l4d2_charger_punch      "1"

// 0=Off. 1=Allow charging while carrying either after charging or after grabbing a survivor and after the charge meter has refilled.
l4d2_charger_repeat     "0"

// Survivors can shove chargers to release pummeled victims. 0=Off. 1=Release only. 2=Stumble survivor. 4=Stumble charger. 7=All. Add numbers together.
l4d2_charger_shove      "7" 
```

