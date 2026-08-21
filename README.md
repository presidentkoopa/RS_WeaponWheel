# RS_WeaponWheel

indepedant wheels for each hand arranged around a centeral datacard reading weapon data from RS as well as several other major Doom randomizers

doomablo, doomrl, borderdoom, othere

Support for over 100+ weapons per wheel, sorted by subcards

arrange up to 12 weapons around the wheel before it collapses into slots

navigate with laser point and FIRE to select

or, reach into wheel and GRAB the gun you want

compat with RS_Holsters to remove weapons from the respective wheels and add them bakc when holstered and not

![The wheel in action](media/demo.gif)

20 second gif or so, showing wheel deployment, and later, wheel in action with 100 weapons
*(sorry the capture quality is rough — VR footage always is)*

---

## The data card

The panel in the middle of the ring isn't a static label — it's a live read
of whatever weapon is currently under your selector, and it updates as you
browse without you having to commit to anything. Point at a different card
and the sheet retargets instantly, same as the ring itself.

**Every weapon gets a baseline, mod or no mod:** its slot number (or tier
name, for weapons that have one), a handling tag when it's melee, two-handed
or off-hand-only, its ammo type and loaded count, the reserve behind a
magazine, and a computed shots-to-empty rather than a raw round count —
nobody plans around "186 cells," they plan around "four more shots."

**RS Weapon's own arsenal gets the full readout**, because the sheet reads
the same fields RS Weapon's own screens do — the two surfaces can never
disagree about a number:

- The full tier ladder as both a word and a color — Cursed, Trash, Basic,
  Common, Uncommon, Advanced, Designer, Prototype.
- Condition, with an explicit **BACKFIRE** warning once it drops under 20%
  — the one threshold on the sheet that gets called out in words instead of
  left for you to infer from a color.
- DPS, Accuracy, and Crit Chance, each independently masked with `???`
  whenever a curse has locked it — DPS masks too, since it's derived from a
  cursed number and showing it anyway would leak exactly what the curse is
  hiding.
- Magazine size against the *rolled* capacity, not the ammo type's generic
  default — masked the same way when capacity itself is cursed.
- Velocity, rate of fire, and pellet count.

**And it reads eight other weapon mods, entirely without their permission.**
Nothing here is a hard dependency — the card asks "does this field exist
on the thing in your hand?" at runtime, rather than being compiled against
any of these mods' own classes. Load none of them and the sheet just falls
back to the baseline above; load one and its data appears with no
configuration needed.

| Mod | What the card reads |
| --- | --- |
| **LegenDoom** | Rarity tier and its color (Common → Legendary), plus whatever rolled effect the weapon carries |
| **DRLA** (DoomRL Arsenal) | Assembly tier, and every Mod Station upgrade currently installed |
| **Doomablo** | Full 7-tier rarity (Common → Unique); separately, your character's level, current/next-level XP, and unspent stat points; your Inferno level; and your five rolled player stats (Vitality, Crit Chance, Crit Damage, Strength, Rare Find) |
| **Pandemonia** (base game) | Weapon durability, internal magazine count, the two-slot sidegrade upgrade system, and your character's Game Level |
| **Pandemonia: Anarchy** | The Anarchic Sigil's own 3-level XP bar — the one real player-leveling system in the whole Pandemonia family |
| **Pandemonia: Insurrection** | Eleven stacking augment types, a separate durability system, "Superior" augment text, a per-weapon color tag, a combo/charge bar a few weapons use, and the Sacrosanct Aeonstave's own weapon-specific leveling |
| **Guncaster** | Spell cooldown and five player resource pools (charge, hover, glide, stomp, curse) |
| **MetaDoom** | Plasma rifle heat buildup, and Unmaker demon key count |
| **BorderDoom** | Cached per-weapon damage, accuracy, rate of fire, recoil, clip size, and rolled level — read from the array the game's own stat-lookup writes into, never from the (unsafe) call itself |

None of that needed the mod's source at build time — every row above is a
plain field read off whatever's actually in your hand, by name, at
runtime. A mod that isn't loaded just fails that read cleanly and the row
never appears; nothing crashes, nothing has to be told what's present.

**Visual polish that isn't tied to any of the above:** an optional ambient
shimmer any weapon set can opt into regardless of whether it has a rarity
system to color by, and a hover light with a short grace period so panning
across the gap between cards doesn't read as the light blinking off and on.

---

## Every stat, for every weapon

The seven RS Weapon-only rows above used to be a special case — one mod got
a full readout, everything else got a handful of generic lines. That's
gone. DPS, damage, rate of fire, accuracy, magazine size, pellet count,
crit chance and velocity now resolve for **any** weapon, from any mod or
none, by asking the same question three ways: does a mod declare this as a
real field, has the wheel *observed* it by watching the weapon fire, or is
it cursed and hidden. Whichever answers wins; nothing is ever invented.

- **Damage prints as a range**, not an average — `12-18`, not `15`. Most
  Doom weapons roll their damage, so an average is a number the gun can
  never actually deal.
- **Magazine size is the highest load ever actually seen**, not the ammo
  type's generic ceiling — mods routinely give that headroom, so the
  obvious source prints a full magazine as a fraction of a number it never
  reaches.
- **Recoil is gone.** It modeled a crosshair kick — the game aiming for
  you — and in VR your hand is the aim. Not reduced, removed.

A hidden tracker backs all of it: kills, shots fired, hit rate, headshots
(once **RS_Headshots** is loaded), and time actually spent holding each
weapon — counted per gun, survives a save, and works on a stock pistol as
readily as a rolled legendary. Twelve mods are now read directly, the
newest being **Combined Arms** (Artificer, BlastMaster, Tech Monk, Past
Linked) — no ZScript in that one at all, so its four classes' heat, charge
and durability systems are read straight out of inventory item counts
instead of fields.

## Point at a weapon and ask "is it better"

The sheet no longer needs the ring open. Point at any weapon lying in the
world and, after a moment's rest, the same card appears at that hand — and
if it's holding something else, the card becomes a full side-by-side table
instead: every stat, every mod-specific row either weapon has, ammo
compatibility, tier, and which hand it costs you, with the better side of
each row lit and the worse one dimmed. Two weapons from the same mod land
in one row; two from different mods each get their own, since an
augment count and a Mod Station slot aren't the same axis and forcing them
into one comparison would invent a number that isn't real. A cursed stat
still shows as `???` with neither side declared the winner — comparing
across a curse would leak exactly what it's hiding.

## Two more shapes for the ring itself

Both off by default, neither replacing the ring or the fan:

- **Honeycomb** lays the same cards out as a gapless hex spiral instead of
  a circle. A ring divides 360° by its card count, so every extra weapon
  tightens every gap; a comb grows outward at a spacing that never does.
- **Constellation** changes what a crowded slot unfolds into — instead of
  a tidy three-lane fan, its weapons scatter as stars around the one you
  opened, with a line drawn from hub to each as it arrives. A background
  starfield can run independently of either, just quiet drifting points of
  light behind the ring.

---

Setup, keybinds, and every option explained are in
[SETUP.md](SETUP.md); the engineering rationale is in [DESIGN.md](DESIGN.md).
