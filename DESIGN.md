# RS_WeaponWheel

A weapon selector that lives in the world rather than on the HUD: cards in a
ring around your hand, pointed at with the engine's own laser sight and taken
by pulling the trigger — or by reaching into one.

Built for VR, against a fork of GZDoom with a billboard system. **It will not
run on stock GZDoom.** See [Engine requirements](#engine-requirements).

---

## Design

**A slot per cell, always.** Every slot keeps its bearing on the ring whether or
not you own anything in it. Slot 4 is in the same direction on the first map and
on the last, so the ring is learnable by feel and you stop reading it. Cards you
do not own still consume their place.

**The centre is neutral.** It shows what the hand already holds and is not
selectable. Opening the rig and doing nothing means "keep what I have", which
makes every card on the ring a genuine change. An empty hand still gets a
centre — it reads *Empty*.

**A fan for a crowded slot.** Dwell on a slot holding more than one weapon and
its others fan out along three bearings, outward and to either side. Outward is
free space, so a fan can never cross a neighbour, and the spread narrows as the
ring gets busier. A slot with one weapon never expands — a submenu with a single
entry exists only to be dismissed.

**Two ways in, and they are not rivals.** The beam is for a card across the
ring; your hand is for the one you are already at. When both answer, the hand
wins — you had to put it there, so it is the more deliberate act. Reaching is
switched off with `wr_touch 0`, which leaves the beam alone.

**Instant equip.** No lower, no raise. `MoveWeaponToHand` is the correct engine
call and is unusable here: it ends in `DropWeapon`, which starts the deselect
animation, so the gun arrives half a second after you asked for it. In a menu
you have already spent time in, that reads as the pick not registering.

**Picking the gun your other hand holds** looks for a free `_2`..`_9` clone
first — weapon sets ship those precisely so you can hold two — and swaps the
hands if there is not one. Nothing is ever put down.

**Dry weapons say so.** A weapon with no ammo rests a different colour, its
gauge is empty, and confirming it plays a different sound. You find out at the
wrist rather than at the trigger.

---

## Two ways to draw a card

Both ship, neither is strictly better, and `wr_canvas` switches between them.

**Composed** — one billboard per element, each positioned, oriented, rolled and
scaled in map units every tic. Every readable part is a **distance field**, so
it stays perfectly sharp at any size and the name can carry a glow.

**Painted** — the artwork is composed into a canvas texture in ordinary 2D pixel
coordinates and the card shows that one image. This buys things a billboard
cannot do at all: a quad has no clip, so a composed card can only ever *shrink*
a sprite until it fits a box, while a canvas **crops** — the weapon runs off the
card edges. Ammo is a fill bar — it used to be pips, one per round below
twelve and ten as tenths above, and that had a real fault: a magazine
draining past twelve changed how many pips were lit *and* how many were on
screen, which reads as a mid-drain refill even though nothing reloaded. A
bar has one state, always, and shrinks monotonically as you fire.

The name and the count stay as field billboards on top either way. A canvas is a
raster and shows its pixels held close in VR; `BB_SEGMENT` never will.

A canvas is a **command queue, not a picture** — the engine plays it into the
texture and then empties it, so anything permanently on screen must be repainted
every tic. Painting once gives exactly one good frame.

---

## Engine requirements

Uses natives that do not exist upstream. Several were added for it:

| Native | What it does |
| --- | --- |
| `AddBillboardPersistent` and friends | oriented world quads with hit testing |
| `AddBillboardGroup` / `AnimateBillboardGroup` | one transform over a whole card, eased per frame |
| `RollBillboard` | the third angle — spin in the quad's own plane |
| `BB_SDFPANEL` | a plate solved as a distance field, so it can glow |
| `SuppressVRInput` | claim the thumbsticks so snap turn stops firing mid-choice |
| `ForceVRLaser(on, hand)` | borrow the engine's laser as a cursor, on one named hand |
| `SetVRLaserRange` | stop that laser at a billboard, which its own trace cannot see |
| `VRHaptic(hand, intensity, ms)` | buzz a controller |
| `SetVolumetricBeam`, `SetSweepBand`, `SetFogSlab`, `AddShape` | the room effects |

The fork documents these in its own `FORK_CHANGES.md`, sections 22 to 26.

---

## Building

```bash
.\build.ps1
```

Writes `RS_WeaponWheel.pk3` to the repo root. `-Dev` also builds
`RS_WeaponWheel_dev.pk3`; `-Deploy <dir>` copies what it built.

No `zipdir`, and no GZDoom source tree — a pk3 is a zip with the package
folder's contents at its root, which the script writes directly. It refuses to
build if it finds an archive **inside** a package folder, because that archive
is content: a `.zip` left in `RS_WeaponWheel/` gets packed into the next
`RS_WeaponWheel.pk3` as a stale copy of the whole mod.

**The dev package is separate on purpose.** `AddPlayerClasses` is global and
permanent, so the "Rig Test" pawn — nine weapons and full ammo, for looking at
a populated ring — used to appear in the New Game class list of every game the
mod was loaded with. It lives in `RS_WeaponWheel_dev` now and ships to nobody.

Adding a new engine native means rebuilding **both** engine targets — the
executable *and* the pk3 target carrying the ZScript declarations. Building only
the first gives a clean compile and a script error at load.

---

## Settings

All live: change one with the ring open and the next tic has it. Everything is
reachable from **Options → Wrist Rig** — nothing here is console-only.

Two binds, one per hand. Whichever hand you summon it on is the hand that wears
it, points at it, and receives what you pick, so there is no handedness setting
to get wrong.

`wr_debug` prints one line naming what actually got built: card count, which
plate payload is live, canvas faces painted against wanted, icons resolved, and
which hand. Deliberately narrow — it reports only the failures you cannot see.

---

## Later: a forearm holster rail

Not built. Recorded because the machinery is already most of the way there and
the hard part is not the part that looks hard.

**The idea.** You turn your off hand toward your face at about chest height —
the gesture you make to check a watch — and a row of cards unrolls along that
forearm, sitting *behind* your weapon so it never occludes what you are aiming
at. Consumables rather than weapons: grenades, throwables, stimpacks, keys.
Chosen by looking at one, or by reaching across with the main hand.

**The gesture is the feature.** It is not a bind, and that is the point. Rolling
your wrist to look at your arm is a thing people already do, it costs no button,
and it cannot fire by accident during a fight the way a held key can. The rig
already reads wrist roll — `handRollOf` exists and `wr_roll` uses it — so the
trigger is a roll threshold plus a rough check that the forearm is pointing at
the head, both of which are one dot product away from data the mod already has.

**Most of this mod transfers untouched.** The plates, canvas faces, readouts,
sounds, haptics, the group grow-in and fold-away, the hover glow, the dim, the
shadow — none of that knows or cares that it is showing a weapon. Two things
change:

- **Layout.** A rail instead of a ring: positions along the aim vector rather
  than around it. Smaller than `bearingForIndex`, not larger.
- **Contents and commit.** `Inventory` items with `bInvBar` set, walked from
  `pmo.Inv`, and `UseInventory(item)` instead of the equip path. Ammo readouts
  become stack counts.

**Selection is solved by where the rail is, and that is worth noticing.** The
first sketch of this put the cards along the firing line, which is the obvious
place and the wrong one: they end up collinear with the laser from that same
hand, so the beam runs the length of the row and "nearest hit" answers every
time. Putting the rail on the OFF forearm and turning it toward your face
removes the problem instead of working around it — the row is now broadside to
you and off the firing axis entirely.

That leaves two ways in, and they should both exist:

- **Reach across with the main hand.** Costs nothing: pointing with the other
  hand is already what `mPokeHand` does, and both the beam and the reach-in test
  work unchanged.
- **Look at one.** `AimBillboard` from the eye along the view vector is the same
  call the hand already makes with a different origin. Cheap, and it is the only
  option that needs neither hand — which matters when both are full.

Gaze wants a dwell before it commits, or looking past a card picks it.

**Not body holsters.** Those were considered early and rejected: reaching to an
unseen point on your own torso has no feedback and no way to be learned. A
forearm rail is in front of you, visible, and can say what it is holding.

---

## Later: gesture casts

Also not built, and smaller than it sounds — the same rail idea with the row
cut down to three.

Hold the off hand in a particular orientation and three cards appear around it:
one below, one to each side. Each is bound to its own button, so the ORIENTATION
picks the set and the button picks the member. Turn your hand a different way and
the same three buttons mean three different things.

That is a spell system without a spell system: no menu, no mode, no cooldown UI.
The gesture is the selection, and the reason it works is the same reason the ring
works — a fixed position is learnable, and once learned you stop looking at it.

**Three is the number on purpose.** It is what fits around a hand without
overlapping, it maps to buttons you already have, and it is few enough to know by
feel. Beyond three this becomes the ring again and should just be the ring.

**What it needs that does not exist yet:** an orientation classifier — palm up,
palm down, thumb in, and so on — from the same hand pose data `handRollOf` and
`handAim` already read. Everything downstream of that is cards, which is built.
