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

Setup, keybinds, and every option explained are in
[SETUP.md](SETUP.md); the engineering rationale is in [DESIGN.md](DESIGN.md).
