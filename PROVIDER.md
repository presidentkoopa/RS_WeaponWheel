# Filling the stats panel from your own mod

The wheel never names a weapon mod. It asks:

```zscript
ServiceIterator.Find("RS_WheelStats")
svc.GetString("stats", "", 0, 0, <the weapon actor>)
```

and draws whatever comes back. Answer it and your weapons get a panel; answer it
from three different mods and each one describes its own guns. No patch pk3, no
hard dependency, nothing to keep in version step.

With nothing listening the wheel falls back to what it can see itself — loaded
rounds, reserve, slot — so the panel is never empty.

---

## The format

Newline-separated rows, tab-separated fields, first field names the row.
Deliberately boring: a provider needs a string builder and nothing else. A
malformed row is skipped rather than fatal, because a stats panel must never be
able to break a weapon menu.

```
title  <name>
tier   <word>            <0xRRGGBB>
promo  <count>
stat   <label>  <value>  <0xRRGGBB>  <fill 0-1>  <earned 0-1>  <flag>  <was>  <stacks>  <bonus>
cond   <now>    <max>    <backfire percent>
sock   <used>   <total>
affix  <name>
```

**Rows draw in the order you send them.** The provider owns the priority — it
knows which stat matters for its own weapons and the wheel has no business
guessing. Only `cond` is forced to the bottom, because it is the one row that
changes what happens when you pull the trigger.

**`earned` is the portion of `fill` that was gained rather than rolled**, and it
draws brighter than the rest of the bar. That two-tone split is the whole reason
the bar exists: it tells you a weapon's history at a glance in a way a number
cannot.

**The label draws in your colour, the value stays neutral.** The eye finds a row
by hue and reads the number without the hue arguing with it. Every card on the
ring is already a saturated colour, so a monochrome panel beside them reads as
belonging to a different program — pick a fixed colour per stat and people learn
to find "damage" by looking rather than by reading.

**`flag`** is empty, `cursed`, or `locked`.

**The last three fields are the curse detail**, and they are what make a cursed
row worth looking at rather than merely marked:

- **`was`** — what the stat was before. Printed small beside the current value,
  because the whole point of a wound is the distance from what it was.
- **`stacks`** — drawn as countable pips under the bar. Depth matters: with two
  stacks the next lift frees nothing and only un-halves.
- **`bonus`** — what the next *clean* lift pays back, drawn in warm amber. A deep
  curse is a wound **and** a stored reward, and showing only the first half makes
  it read as a dead loss.

The gap between `fill` and full is hatched in crimson, so the reader sees how
much was taken without comparing two numbers.

---

## A provider

```zscript
class RS_WheelStats : Service
{
    override String GetString(String request, String s, int i, double d,
                              Object o, Name n)
    {
        if (request != "stats") return "";

        let w = RS_Weapon(o);
        if (w == null) return "";        // not ours -- let someone else answer

        String out = "title\t" .. w.GetTag() .. "\n";

        out = out .. "tier\t" .. TierWord(w.Tier) .. "\t"
                  .. String.Format("0x%06X", RS_TierPalette.RGB(w.Tier) & 0xFFFFFF) .. "\n";

        if (w.PromotionCount > 0)
            out = out .. "promo\t" .. w.PromotionCount .. "\n";

        out = out .. StatRow("Damage", "" .. w.DamagePerShot, 0xD9453C,
                             w.DamagePerShot / 200.0,
                             w.EarnedDamage() / 200.0,
                             w.CurseStackDamage > 0 ? "cursed" : "",
                             w.PreCurseDamage > 0 ? "" .. w.PreCurseDamage : "",
                             w.CurseStackDamage,
                             w.LiftBonusPercent(w.CurseStackDamage));

        out = out .. StatRow("Accuracy", "" .. int(w.Accuracy), 0x4FA3D1,
                             w.Accuracy / 100.0,
                             w.EarnedAccuracy() / 100.0,
                             w.CurseStackAccuracy > 0 ? "cursed" : "",
                             w.PreCurseAccuracy > 0 ? "" .. int(w.PreCurseAccuracy) : "",
                             w.CurseStackAccuracy,
                             w.LiftBonusPercent(w.CurseStackAccuracy));

        // ... velocity, crit, capacity, rate of fire, pellets, choke

        out = out .. "sock\t" .. RS_GunBonsaiBridge.CountActiveAffixes(w)
                  .. "\t" .. w.GunBonaiSockets .. "\n";

        // Backfire only bites below 20 -- see RS_Roll.GetConditionEffects.
        int backfire = w.Condition < 10 ? 35 : (w.Condition < 20 ? 20 : 0);
        out = out .. "cond\t" .. int(w.Condition) .. "\t100\t" .. backfire .. "\n";

        return out;
    }

    static String StatRow(String label, String value, int col,
                          double fill, double earned, String flag,
                          String was = "", int stacks = 0, int bonus = 0)
    {
        return "stat\t" .. label .. "\t" .. value .. "\t"
             .. String.Format("0x%06X", col) .. "\t"
             .. clamp(fill, 0.0, 1.0) .. "\t"
             .. clamp(earned, 0.0, 1.0) .. "\t" .. flag .. "\t"
             .. was .. "\t" .. stacks .. "\t" .. bonus .. "\n";
    }
}
```

**Return `""` for a weapon that is not yours.** The wheel takes the first
non-empty answer, so a provider that describes everything blocks every other
provider. Check the cast and bow out.

**Use your own colour table rather than writing one here.** RS_Main has exactly
one — `RS_TierPalette` — and its own header says a fifth surface calls it rather
than writing a table. This is that fifth surface.

---

## Registering it

A `Service` subclass is found by name, so it only has to exist:

```
// in your ZSCRIPT lump
#include "zscript/RS_WheelStats.zs"
```

`ServiceIterator.Find` matches on the name containing `RS_WheelStats`, so
`RS_WheelStats_DLRA` and `RS_WheelStatsHD` both answer too.
