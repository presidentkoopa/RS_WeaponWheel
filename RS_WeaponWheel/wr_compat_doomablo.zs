// DOOMABLO COMPATIBILITY.
//
// Doomablo (https://github.com/sidav/doomablo) is real ZScript, unlike
// LegenDoom and DRLA -- and its rarity is a plain public field because of
// it. generatedRarity is declared on the Affixable mixin
// (zscript/affixable/affixable.zs) and applied to RwWeapon itself
// (zscript/rweapons/randomized_weapon.zs: "class RwWeapon : DoomWeapon
// abstract { mixin Affixable; }"), so every Doomablo weapon carries it
// directly -- no owned-item walk (wr_compat_legendoom.zs) or
// class-ancestry climb (wr_compat_drla.zs) needed. This is read exactly
// the way RS_Main's own Tier field is, in rsRows() (zscript.zs): this
// fork's field reflection natives, by name, no compile-time dependency on
// RwWeapon at all.
//
// Seven tiers, not the six the mod's own README lists -- Common(0)/
// Uncommon(1)/Rare(2)/Epic(3)/Legendary(4)/Mythic(5) plus Unique(6), the
// one adding_new_uniques.txt calls out separately as "max rarity" and the
// README's prose just doesn't enumerate. Names and the palette both come
// straight from RaritiesHelper (zscript/misc/rarities_helper.zs) --
// getRarityName() and indicatorColorForRarity(), the same colour Doomablo
// itself puts on the floating beam over a dropped item, so the sheet
// agrees with what the player already saw on the ground.
//
// WHAT THIS DOES NOT COVER: the applied-affix list (100+ per the mod's own
// README). appliedAffixes is an array<Affix>, and each concrete Affix
// subclass's display name comes from a VIRTUAL METHOD (getName(),
// zscript/affix/affix.zs), not a field -- field reflection reads raw
// field VALUES by name, it cannot invoke a method on a class this file has
// no compile-time knowledge of, and there is no array-element reflection
// in this fork's native set either (HasField/GetFieldInt/Bool/Float/
// String/Name/Object/FieldCount/FieldAt -- none of those give you element
// N of a named array field). Unlike the other two mods' second axis
// (LegenDoom's effects, DRLA's mods), this one is genuinely unreachable
// without either a Doomablo-side Service or new engine reflection natives
// -- not attempted here.
class wr_CompatDoomablo
{
	const DBL_COMMON    = 0;
	const DBL_UNCOMMON  = 1;
	const DBL_RARE      = 2;
	const DBL_EPIC      = 3;
	const DBL_LEGENDARY = 4;
	const DBL_MYTHIC    = 5;
	const DBL_UNIQUE    = 6;

	const COLOR_COMMON    = 0xFFFFFF;
	const COLOR_UNCOMMON  = 0x00FF00;
	const COLOR_RARE      = 0x1111FF;
	const COLOR_EPIC      = 0xCC00FF;
	const COLOR_LEGENDARY = 0xFFFF00;
	const COLOR_MYTHIC    = 0x00FFFF;
	const COLOR_UNIQUE    = 0xFF0000;

	private static double cv(string name, double fallback)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetFloat() : fallback;
	}

	// FOUND, RARITY. A single level.GetFieldInt call -- the simplest read
	// of the four mods surveyed, since Doomablo already stores this the
	// same way RS_Main does.
	static bool, int RarityOf(Weapon w)
	{
		int rarity;
		if (!w || cv("wr_dbl_compat", 1.0) <= 0.0) return false, 0;
		if (!level.GetFieldInt(w, "generatedRarity", rarity)) return false, 0;

		// Range-checked against the seven tiers this file actually knows
		// about (README lists six; adding_new_uniques.txt's Unique is the
		// seventh, see the file header). RarityWord()/RarityColor()'s own
		// switches fall through anything unrecognized to COMMON/white with
		// no other signal -- so an unranged value here reads to the player
		// as a confident "this is Common", indistinguishable from a
		// genuine Common roll, rather than as what it actually is: a tier
		// number this file was never taught. A future Doomablo release
		// adding an 8th tier should show as unreadable, the same honest
		// "false" every other unrecognized read in this file already
		// returns, not as its own lowest rarity.
		if (rarity < DBL_COMMON || rarity > DBL_UNIQUE) return false, 0;

		return true, rarity;
	}

	static string RarityWord(int r)
	{
		switch (r)
		{
			case DBL_UNIQUE:    return "UNIQUE";
			case DBL_MYTHIC:    return "MYTHIC";
			case DBL_LEGENDARY: return "LEGENDARY";
			case DBL_EPIC:      return "EPIC";
			case DBL_RARE:      return "RARE";
			case DBL_UNCOMMON:  return "UNCOMMON";
		}
		return "COMMON";
	}

	static color RarityColor(int r)
	{
		switch (r)
		{
			case DBL_UNIQUE:    return color(COLOR_UNIQUE);
			case DBL_MYTHIC:    return color(COLOR_MYTHIC);
			case DBL_LEGENDARY: return color(COLOR_LEGENDARY);
			case DBL_EPIC:      return color(COLOR_EPIC);
			case DBL_RARE:      return color(COLOR_RARE);
			case DBL_UNCOMMON:  return color(COLOR_UNCOMMON);
		}
		return color(COLOR_COMMON);
	}

	// Same (bool, color) shape as rsTierLookup() / the other two compat
	// files' TierOf(), so all four drop into cardColorFor()/tierColorOf()'s
	// call chain identically.
	static bool, color TierOf(Weapon w)
	{
		bool found; int rarity;
		[found, rarity] = RarityOf(w);
		color none;
		if (!found) return false, none;
		return true, RarityColor(rarity);
	}
}
