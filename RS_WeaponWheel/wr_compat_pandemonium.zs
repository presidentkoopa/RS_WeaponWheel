// PANDEMONIUM (INSURRECTION) COMPATIBILITY.
//
// Pandemonium is a suite of separate packages -- Anarchy, Ascension,
// Insurrection, Renovation, Monsters -- and only one of them matters here.
// Anarchy's own weapons (e.g. "Class DustQuadShotgun : DustSuperShotgun",
// PandAWZS/Weapons/Slot3/QuadShotgun.txt) do not use the class this file
// reads at all. Insurrection's own roster does: every Insurrection weapon
// is a "PandInsWeapon : ZWeapon : Weapon" (PandIZS/BaseActors.txt,
// PandIZS/zwl/zweapon.zs), and THAT class is where all of this lives.
//
// NO RARITY OR TIER CONCEPT EXISTS HERE -- checked, same as MetaDoom/
// Guncaster/Pandemonium's own Anarchy/Weapons pack. What Insurrection has
// instead is an AUGMENT system: up to a per-weapon cap (maxaugs) of
// stacked upgrades across eleven named types, plus an independent
// DURABILITY system, plus a one-off "Superior" augment that carries its
// own free-text description already written for that specific weapon.
// None of this is a tier/rarity ladder, so unlike wr_compat_legendoom.zs/
// wr_compat_drla.zs/wr_compat_doomablo.zs, this file never touches the
// sheet's title row or tierColorOf()/cardColorFor() -- purely supplementary
// rows, same relationship DRLA's Mod Station read has to DRLA's own tier.
//
// EVERY FIELD HERE IS PLAIN -- no owned-item walk, no class-ancestry climb.
// Read the same way RS_Main's Tier and Doomablo's generatedRarity are, via
// this fork's field reflection natives, because Insurrection is real
// ZScript and simply declared these as ordinary int/bool/string fields on
// the class every one of its weapons inherits from.
class wr_CompatPandemonium
{
	private static double cv(string name, double fallback)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetFloat() : fallback;
	}

	private static bool active(Weapon w)
	{
		return w && cv("wr_pand_compat", 1.0) > 0.0;
	}

	// FOUND, CURRENT, MAX. curaugs/maxaugs (BaseActors.txt:57-65) are the
	// running total and the per-weapon cap -- "found" here really means
	// "this is a PandInsWeapon", since the fields exist (defaulted to 0)
	// on every Insurrection weapon whether or not anything is installed.
	static bool, int, int CountOf(Weapon w)
	{
		int cur, max;
		if (!active(w)) return false, 0, 0;
		if (!level.GetFieldInt(w, "curaugs", cur)) return false, 0, 0;
		level.GetFieldInt(w, "maxaugs", max);
		return true, cur, max;
	}

	// Short tags for the eleven named augment counters (BaseActors.txt:
	// 67-81), each with a "+N" suffix once a type is stacked past one --
	// Strength alone reads "STR", two reads "STR+2". aug_moreaugs is
	// skipped: its own name ("Augment Formatter") marks it as a display
	// helper internal to Insurrection's own UI, not a real augment count.
	static string BreakdownOf(Weapon w)
	{
		if (!active(w)) return "";

		string s = "";
		s = appendAug(w, s, "aug_str", "STR");
		s = appendAug(w, s, "aug_prs", "PREC");
		s = appendAug(w, s, "aug_hst", "HSTE");
		s = appendAug(w, s, "aug_cap", "CAP");
		s = appendAug(w, s, "aug_bls", "BLST");
		s = appendAug(w, s, "aug_chs", "CHAOS");
		s = appendAug(w, s, "aug_flm", "FLM");
		s = appendAug(w, s, "aug_scv", "SCAV");
		s = appendAug(w, s, "aug_sup", "SUP");
		s = appendAug(w, s, "aug_arc", "ARC");
		s = appendAug(w, s, "aug_mag", "MAGI");
		return s;
	}

	private static string appendAug(Weapon w, string s, string field, string tag)
	{
		int n;
		if (!level.GetFieldInt(w, field, n) || n <= 0) return s;
		string t = (n > 1) ? String.Format("%s+%d", tag, n) : tag;
		return s.Length() ? (s .. " " .. t) : t;
	}

	// FOUND(HasDurability), CURRENT, MAX, BROKEN. Not every Insurrection
	// weapon opts into the durability system (property HasDurability,
	// BaseActors.txt:44-51) -- that flag, not just a successful field
	// read, is the real gate, same reasoning CountOf() does NOT need
	// because curaugs/maxaugs apply to every weapon uniformly.
	static bool, int, int, bool DurabilityOf(Weapon w)
	{
		// GetFieldBool's own out-param is int, not bool (FORK_CHANGES.md
		// §30 -- confirmed against rsRows()'s own LockedDamage read a few
		// hundred lines up in zscript.zs, same pattern), so these are read
		// into int locals and compared explicitly rather than passed as bool.
		int hasI;
		if (!active(w) || !level.GetFieldBool(w, "dwep", hasI) || hasI == 0) return false, 0, 0, false;

		int cur, max, brokenI;
		level.GetFieldInt(w, "durability", cur);
		level.GetFieldInt(w, "dmax", max);
		level.GetFieldBool(w, "dbroken", brokenI);
		return true, cur, max, brokenI != 0;
	}

	// FOUND(gotsupped), TEXT. sup_string (property SuperiorString,
	// BaseActors.txt:105-106) is written per-weapon by Insurrection
	// itself, so this needs no name table the way wr_compat_legendoom.zs's
	// effect suffixes or wr_compat_drla.zs's mod tags do -- the field IS
	// the display text.
	static bool, string SuperiorOf(Weapon w)
	{
		int gotI; string txt;
		if (!active(w) || !level.GetFieldBool(w, "gotsupped", gotI) || gotI == 0) return false, "";
		level.GetFieldString(w, "sup_string", txt);
		return true, txt;
	}
}
