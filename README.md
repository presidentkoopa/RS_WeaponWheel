# RS_WeaponWheel

Your weapons, as cards floating in the room around your hand. Point at one and
pull the trigger, or just reach out and grab it.

Built for VR.

![The wheel in action](media/demo.gif)

---

## You will need

A build of **DoomXR** with billboard support. This mod uses engine features that
do not exist in stock GZDoom and it will not load without them.

---

## Getting started

Load `RS_WeaponWheel.pk3` after your IWAD and any weapon mod.

Then bind the two keys — **Options → RSVR HUD → Controls**:

- **Off hand wheel**
- **Main hand wheel**

There is one per hand and that is the only handedness setting there is. Whichever
hand you summon it on is the hand that wears the ring, points at it, and receives
whatever you pick. There is nothing to configure wrong.

---

## Using it

**Open it.** The ring appears about a metre in front of the hand you summoned it
with, and time slows down if you have BulletTimeX loaded.

**Point.** A laser comes off that hand and stops on whatever card you are aiming
at. The card lights up, breathes, and steps toward you. Your controller ticks.

**Or reach.** Put your hand into a card and that beats the beam — you had to
physically go there, so it wins over wherever the laser happened to be pointing.

**Take it.** Pull either trigger. The weapon is in your hand instantly — no
lowering, no raising, no animation to wait through.

**Or don't.** The middle of the ring is whatever you are already holding and it
cannot be selected. Open the ring, change your mind, do nothing, and you keep
your gun. Let go and it folds away by itself after a few seconds.

### Things worth knowing

**The ring is in the same order every time.** Slot 4 is in the same direction on
your first map and your last, whether or not you own anything in it. Learn it
once by feel and you can stop looking at it.

**A slot with several weapons fans out.** Rest on it for a moment and its others
unfold outward. Move to one and take it as normal.

**Empty guns look empty.** A weapon with nothing left rests a darker colour, its
gauge is empty, and confirming it makes a different noise. You find out at your
wrist instead of at the trigger.

**Picking the gun your other hand is holding does something sensible.** If your
weapon set ships a second copy, you get that — one in each hand. If it does not,
your hands swap. Nothing is ever dropped, and doing it again puts them back.

---

## Making it yours

Everything is under **Options → RSVR HUD**. Nothing needs the console.

**Placement** — how far ahead the ring floats, how wide it is, how high above
your hand it sits, how far it leans toward you. All live: open the ring and drag
a slider and it moves as you watch.

**Reach** — how close your hand has to get to count as touching a card. Set it to
0 and only the laser selects. Bring **Ring distance ahead** down toward 0 and the
cards come into actual arm's reach.

**Cards** — size, how much the hovered one grows and breathes, whether ammo is
shown, and two different ways of drawing a card entirely:

- **Sharp plates** — perfectly crisp at any distance, with a glow on the one you
  are pointing at.
- **Painted card faces** — the weapon drawn large enough to run off the edges of
  its card, ammo as a pair of bars, and scanlines over the whole thing. Looks
  like a device instead of a menu.

Try both. They are genuinely different and neither is the "right" one.

**The room** — the laser can have dust hanging in it, a wave of light can wash
over the room when the ring opens, mist can pool around the cards, and marks can
spin on the floor under your feet. All off-by-default or subtle; all separate
switches. **Fine tuning…** has the shaping numbers behind each.

**Feel** — clicks and controller rumble on hover, expand, confirm and dismiss.
The ring sits where you cannot comfortably look at it, so most of what it tells
you arrives through your ears and your wrists. Rumble respects your engine
setting; turning haptics off in DoomXR cannot be overridden from here.

---

## If something looks wrong

Turn on **Options → RSVR HUD → Troubleshooting → Print diagnostics on open**.
It prints one line when the ring opens saying what actually got built — how many
cards, which card style is live, and whether the painted faces painted. It only
reports problems you would not otherwise be able to see.

---

## Credits

Selection sounds from the `hf_sel` set.

Design notes and engine requirements are in [DESIGN.md](DESIGN.md).
