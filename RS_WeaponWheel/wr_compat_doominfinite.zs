// DOOM INFINITE COMPATIBILITY.
//
// A roguelite over the classic maps: runs of randomly-chosen levels
// separated by a hub called Limbo, with a procedural weapon generator
// rolling exotic ammo types, alternate fire modes, alt-fire modules and up
// to three "quirks" onto every gun that spawns.
//
// THE BEST-CASE TARGET OF EVERY MOD READ SO FAR, for one specific reason:
// InfiniteWeapon (ZSCRIPT/PLAYER/zWeaponsBase.zsc) is real ZScript with
// around 180 plain declared fields, and its Tick() calls SetupWeapon()
// BEFORE its own `if (ownedByPlayer)` gate -- so a weapon lying on the
// floor, owned by nobody, already knows its damage, fire rate, spread,
// pellet count, crit, ammo type, fire mode and quirks. Every other mod
// here either hides its rolls until pickup or keeps them somewhere
// unreachable. This one hands them over on the ground, which is exactly
// what inspect mode was built for.
//
// GATE EVERYTHING ON isSetup. The weapon finds the WeaponGenerator
// singleton through a ThinkerIterator, which can take a tic or two after
// spawn -- read before that and the fields are structurally there but
// still zero.
//
// TWO FIELDS ARE INVERTED, AND GETTING THIS WRONG WOULD BE WORSE THAN NOT
// READING THEM. statFireRate is the DELAY BETWEEN SHOTS IN TICS (fed
// straight to A_SetTics), so LOWER is faster; statSpread is in TENTHS OF A
// DEGREE, so LOWER is more accurate. The sheet's universal rows are all
// higher-is-better, and the comparison card colours the larger side green.
// So fire rate is CONVERTED here to shots-per-second before it is handed
// over, and spread is deliberately NOT fed to the Accuracy resolver at all
// -- it gets its own clearly-labelled row instead, because silently
// feeding an inverted stat into a higher-is-better comparison would light
// the worse weapon green.
//
// NO NUMERIC RARITY LADDER, despite appearances. isUnique is a plain bool
// ("did this weapon get any roll at all"), and uniqnessRating is a
// per-archetype CONSTANT (pistol 75, chaingun 10) that is written once and
// then read by nothing in the entire mod -- not ZScript, not its ACS. The
// real quality axis is the flavour quirk, whose name string this file
// matches against. That is stringly-typed and slightly ugly, and it is the
// only option: the authoritative `quirks` field is an Array<int>, which is
// a PDynArray rather than the fixed PArray GetFieldIntArray resolves, and
// HasQuirk() is a method. The name strings are stable literals from the
// generator's own table.
class wr_CompatDoomInfinite
{
	// Flavour quirks, in the mod's own display colours (TEXTCOLO.txt and
	// the generator's quirkNames[] table). These are the closest thing to a
	// tier this mod has.
	const COLOR_LEGENDARY = 0xFF8800;   // \c[FIRE]
	const COLOR_BLESSED   = 0x99DDFF;   // \c[ICE]
	const COLOR_REFINED   = 0xFFC529;   // \c[GOLD]
	const COLOR_DEMONIC   = 0xFF2020;   // \c[RED]
	const COLOR_CURSED    = 0xA03030;   // \c[BRICK]
	const COLOR_SYMBIOTIC = 0x44DD44;   // \c[GREEN]
	const COLOR_CHAOTIC   = 0xFF66CC;   // per-letter rainbow in the mod
	const COLOR_CRUDE     = 0xC8A882;   // \c[TAN]
	const COLOR_HEAVY     = 0x883030;   // \c[DARKRED]

	// The purple the mod puts on a unique weapon's own dynamic light
	// (A_AttachLight("UniqueLight", ... "ae00f4")). Used for a weapon that
	// rolled SOMETHING but no flavour quirk, so the card still says
	// "this one is not plain" in the mod's own visual language.
	const COLOR_UNIQUE = 0xAE00F4;

	// Heat is a 0-100 counter against a `const` threshold of 100 -- a
	// constant rather than a field, so it cannot be read and is written
	// here instead. overheatPercent already carries the fraction; this is
	// only for wording the raw counter.
	const HEAT_MAX = 100;

	// The Arena despawn clock. arenaTimeout is likewise a const, not a
	// field: a dropped weapon starts counting once the round it spawned in
	// has passed, and vanishes at 30.
	const ARENA_TIMEOUT = 30;

	private static double cv(string name, double fallback)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetFloat() : fallback;
	}

	// IS THIS A DOOM INFINITE WEAPON, AND IS IT READY TO BE READ.
	//
	// isSetup is the gate rather than the mere existence of a field: every
	// field below exists from the moment the actor spawns, but they hold
	// zeroes until the generator has applied a blueprint. A weapon read one
	// tic too early would show a coherent-looking all-zero card rather than
	// nothing at all, which is worse.
	static bool Ready(Weapon w)
	{
		int setup;
		if (!w || cv("wr_di_compat", 1.0) <= 0.0) return false;
		if (!level.GetFieldBool(w, "isSetup", setup)) return false;
		return setup != 0;
	}

	// STRIP GZDOOM COLOUR ESCAPES.
	//
	// Every display string this mod stores -- ammoName, quirkAName and the
	// rest -- arrives pre-formatted with \c[NAME] escapes baked in, because
	// the mod draws them straight into its own ACS HUD. The sheet colours
	// its own rows and cannot render an embedded escape, so a raw string
	// would print visible junk. The escape is TEXTCOLOR_ESCAPE (0x1C)
	// followed by [NAME]; this drops that and keeps the text.
	static string Plain(string s)
	{
		string outp = "";
		int n = s.Length();
		for (int i = 0; i < n; ++i)
		{
			int c = s.ByteAt(i);
			if (c == 0x1C)
			{
				// Skip the escape and its bracketed colour name. A bare
				// escape with no bracket (malformed, but cheap to survive)
				// just eats the next character.
				++i;
				if (i < n && s.ByteAt(i) == 0x5B)   // '['
				{
					while (i < n && s.ByteAt(i) != 0x5D) ++i;   // to ']'
				}
				continue;
			}
			outp = outp .. s.Mid(i, 1);
		}
		return outp;
	}

	private static string fieldStr(Weapon w, string field)
	{
		string s;
		if (!level.GetFieldString(w, field, s)) return "";
		return Plain(s);
	}

	private static int fieldInt(Weapon w, string field)
	{
		int v;
		if (!level.GetFieldInt(w, field, v)) return 0;
		return v;
	}

	//==========================================================================
	// THE NAME. baseName is the archetype ("super shotgun"); subName is the
	// LOOT name, written by the generator's own priority cascade over the
	// weapon's quirks -- a gun with Q_LEGENDARY and Q_DEMONIC reads
	// "LEGENDARY DEMONIC". Empty on a plain weapon.
	//
	// FOUND, FULL NAME.
	static bool, string NameOf(Weapon w)
	{
		if (!Ready(w)) return false, "";

		string sub = fieldStr(w, "subName");
		string base = fieldStr(w, "baseName");
		if (sub.Length() == 0 && base.Length() == 0) return false, "";
		if (sub.Length() == 0) return true, base.MakeUpper();
		if (base.Length() == 0) return true, sub;
		return true, sub .. " " .. base.MakeUpper();
	}

	//==========================================================================
	// FLAVOUR, matched off the three quirk name strings.
	//
	// Stringly-typed on purpose and not by preference -- see the file
	// header: the numeric quirk list is an Array<int> this fork's array
	// reflection cannot reach, and HasQuirk() is a method. The strings are
	// stable literals from the generator's own quirkNames[] table, matched
	// case-insensitively against the text left after the colour escape is
	// stripped.
	//
	// Ordered by weight, best first -- a weapon carrying both LEGENDARY and
	// CURSED is a legendary weapon with a drawback, not a cursed one.
	//
	// FOUND, COLOUR, WORD.
	static bool, color, string FlavorOf(Weapon w)
	{
		color none;
		if (!Ready(w)) return false, none, "";

		string all = (fieldStr(w, "quirkAName") .. " "
		           .. fieldStr(w, "quirkBName") .. " "
		           .. fieldStr(w, "quirkCName")).MakeLower();

		if (all.IndexOf("legendary") >= 0) return true, color(COLOR_LEGENDARY), "LEGENDARY";
		if (all.IndexOf("blessed")   >= 0) return true, color(COLOR_BLESSED),   "BLESSED";
		if (all.IndexOf("refined")   >= 0) return true, color(COLOR_REFINED),   "REFINED";
		if (all.IndexOf("symbiotic") >= 0) return true, color(COLOR_SYMBIOTIC), "SYMBIOTIC";
		if (all.IndexOf("chaotic")   >= 0) return true, color(COLOR_CHAOTIC),   "CHAOTIC";
		if (all.IndexOf("demonic")   >= 0) return true, color(COLOR_DEMONIC),   "DEMONIC";
		if (all.IndexOf("cursed")    >= 0) return true, color(COLOR_CURSED),    "CURSED";
		if (all.IndexOf("heavy")     >= 0) return true, color(COLOR_HEAVY),     "HEAVY";
		if (all.IndexOf("crude")     >= 0) return true, color(COLOR_CRUDE),     "CRUDE";

		// No flavour quirk, but the weapon still rolled SOMETHING -- exotic
		// ammo, a fire mode, a plain quirk, an alt module. The mod marks
		// exactly this case with a purple light on the pickup, so the card
		// borrows that colour rather than inventing one.
		int uniq, modded;
		level.GetFieldBool(w, "isUnique", uniq);
		level.GetFieldBool(w, "isModded", modded);
		if (uniq != 0 || modded != 0) return true, color(COLOR_UNIQUE), "UNIQUE";

		return false, none, "";
	}

	// Same (bool, color) shape as every other tier reader here, so this
	// drops into tierColorOf()/cardColorFor()'s chain unchanged.
	static bool, color TierOf(Weapon w)
	{
		bool got; color c; string word;
		[got, c, word] = FlavorOf(w);
		return got, c;
	}

	//==========================================================================
	// THE UNIVERSAL STATS, for wr_stats.zs.
	//
	// Every one of these is DECLARED data -- the mod stores its rolled
	// values as plain fields rather than burying them in fire-state action
	// function arguments the way an ordinary GZDoom weapon does. That makes
	// this the only mod besides RS Weapon and BorderDoom that can answer
	// these before a shot has ever been fired.

	// FOUND, DAMAGE PER PELLET.
	static bool, int DamageOf(Weapon w)
	{
		if (!Ready(w)) return false, 0;
		int d = fieldInt(w, "statDamage");
		if (d <= 0) return false, 0;
		return true, d;
	}

	// FOUND, SHOTS PER SECOND -- CONVERTED, not raw.
	//
	// statFireRate is the delay between shots in tics and is fed straight
	// into A_SetTics, so it is LOWER-IS-FASTER. Handing that to the sheet's
	// rate-of-fire row, which is higher-is-better everywhere else, would
	// make a fast weapon read as slow and would colour the wrong side of a
	// comparison green. 35 is Doom's fixed tic rate.
	static bool, double RofOf(Weapon w)
	{
		if (!Ready(w)) return false, 0.0;
		int tics = fieldInt(w, "statFireRate");
		if (tics <= 0) return false, 0.0;
		return true, 35.0 / double(tics);
	}

	// FOUND, PELLETS PER SHOT.
	static bool, int PelletsOf(Weapon w)
	{
		if (!Ready(w)) return false, 0;
		int n = fieldInt(w, "statNumShots");
		if (n <= 0) return false, 0;
		return true, n;
	}

	// FOUND, CRIT CHANCE PERCENT. Already a percent, unlike RS Weapon's
	// 0..1 fraction -- handed over as-is rather than scaled.
	static bool, double CritOf(Weapon w)
	{
		if (!Ready(w)) return false, 0.0;
		int c = fieldInt(w, "statCrit");
		if (c <= 0) return false, 0.0;
		return true, double(c);
	}

	//==========================================================================
	// SPREAD, which gets its OWN row rather than feeding the Accuracy
	// resolver -- see the file header. statSpread is in tenths of a degree
	// and lower is better; Accuracy everywhere else on this sheet is
	// higher-is-better, and quietly mixing the two would invert the verdict
	// on the comparison card.
	//
	// FOUND, DEGREES.
	static bool, double SpreadOf(Weapon w)
	{
		if (!Ready(w)) return false, 0.0;
		int s = fieldInt(w, "statSpread");
		if (s <= 0) return false, 0.0;
		return true, double(s) * 0.1;
	}

	//==========================================================================
	// THE LOADOUT ROW -- ammo type, fire mode and alt module, the three
	// axes the generator actually rolls. All three are stored as finished
	// display strings by the mod itself, so this needs no name table of its
	// own the way wr_compat_drla.zs's mod tags do.
	static bool, string LoadoutOf(Weapon w)
	{
		if (!Ready(w)) return false, "";

		string s = fieldStr(w, "ammoName");
		string fm = fieldStr(w, "fireModeName");
		string alt = fieldStr(w, "altModeName");

		// NORMAL is the default fire mode and says nothing -- listing it
		// would put a word on the card for every weapon that did not roll
		// one, which is most of them.
		if (fm.Length() > 0 && fm.MakeLower() != "normal")
			s = s.Length() ? (s .. "  " .. fm) : fm;

		if (alt.Length() > 0)
			s = s.Length() ? (s .. "  " .. alt) : alt;

		return s.Length() > 0, s;
	}

	// THE QUIRK LIST, all three slots. "---" is the mod's own filler for an
	// empty slot and is dropped rather than printed.
	static bool, string QuirksOf(Weapon w)
	{
		if (!Ready(w)) return false, "";

		string s = "";
		s = appendQuirk(w, s, "quirkAName");
		s = appendQuirk(w, s, "quirkBName");
		s = appendQuirk(w, s, "quirkCName");
		return s.Length() > 0, s;
	}

	private static string appendQuirk(Weapon w, string s, string field)
	{
		string q = fieldStr(w, field);
		if (q.Length() == 0 || q == "---") return s;
		q = q.MakeUpper();
		return s.Length() ? (s .. " " .. q) : q;
	}

	//==========================================================================
	// OVERHEAT. The mod tracks a full 0-100 heat model and then shows the
	// player nothing but smoke puffs -- confirmed against its own ACS,
	// which never reads any of these four fields. A real gauge is new
	// information rather than a prettier version of something already on
	// screen.
	//
	// isOverheat is deliberately NOT read: it latches true on the first
	// shot and is never cleared, so it answers "has this weapon ever been
	// fired", not "is it hot".
	//
	// FOUND, COUNTER, PERCENT.
	static bool, int, double HeatOf(Weapon w)
	{
		if (!Ready(w)) return false, 0, 0.0;

		double pct;
		if (!level.GetFieldFloat(w, "overheatPercent", pct)) return false, 0, 0.0;

		int counter = fieldInt(w, "overheatCounter");
		if (counter <= 0) return false, 0, 0.0;

		return true, counter, clamp(pct, 0.0, 1.0);
	}

	// THE SUPERCHARGER'S CHARGE. altOverchargeValue climbs in steps of ten
	// to forty, and while it is above zero the weapon deals TRIPLE damage
	// -- a fact the game communicates only with sparks. Worth a row on its
	// own for that reason.
	//
	// FOUND, CHARGE, MAX.
	static bool, int, int OverchargeOf(Weapon w)
	{
		if (!Ready(w)) return false, 0, 0;
		int v = fieldInt(w, "altOverchargeValue");
		if (v <= 0) return false, 0, 0;
		return true, v, 40;
	}

	//==========================================================================
	// JAM CHANCE, and the honest framing of it.
	//
	// jamChance is a roll against 256, but it only ever fires on a weapon
	// carrying the JAMMING quirk (A_CheckJam checks the quirk first). So
	// the number is meaningless on a weapon without it, and this returns
	// nothing rather than printing odds for a jam that cannot happen.
	//
	// The mod shows the word JAMMING and never the odds behind it.
	//
	// FOUND, PERCENT.
	static bool, int JamOf(Weapon w)
	{
		if (!Ready(w)) return false, 0;

		string all = (fieldStr(w, "quirkAName") .. " "
		           .. fieldStr(w, "quirkBName") .. " "
		           .. fieldStr(w, "quirkCName")).MakeLower();
		if (all.IndexOf("jamming") < 0) return false, 0;

		int jc = fieldInt(w, "jamChance");
		if (jc <= 0) return false, 0;
		return true, jc * 100 / 256;
	}

	// AMMO COST PER SHOT. Exotic ammo types can multiply the blueprint
	// cost, so the live value is what matters. Only reported where it is
	// more than one, since one-per-shot is the unremarkable default.
	//
	// FOUND, COST.
	static bool, int AmmoCostOf(Weapon w)
	{
		if (!Ready(w)) return false, 0;
		int c = fieldInt(w, "ammoCost");
		if (c <= 1) return false, 0;
		return true, c;
	}

	// WHAT THIS WEAPON CAN NEVER BE RE-MODDED INTO. The three lock quirks
	// each pin one axis at the Limbo mod station, which is a real reason to
	// leave a weapon on the floor and nothing on screen says so.
	//
	// FOUND, TEXT.
	static bool, string LocksOf(Weapon w)
	{
		if (!Ready(w)) return false, "";

		int a, m, alt;
		level.GetFieldBool(w, "ammoLocked", a);
		level.GetFieldBool(w, "modeLocked", m);
		level.GetFieldBool(w, "altLocked",  alt);

		string s = "";
		if (a   != 0) s = "AMMO";
		if (m   != 0) s = s.Length() ? (s .. " MODE") : "MODE";
		if (alt != 0) s = s.Length() ? (s .. " ALT")  : "ALT";
		if (s.Length() == 0) return false, "";
		return true, s;
	}

	//==========================================================================
	// THE ARENA DESPAWN CLOCK, and the one row here with a deadline on it.
	//
	// A weapon on the floor in Infinite Arena starts counting the moment
	// the round it spawned in ends, and disappears at thirty seconds. The
	// game shows this only as the sprite slowly going translucent -- there
	// is no number anywhere. Pointing at a weapon and being told it has
	// eleven seconds left is information the player currently has to guess
	// at by squinting.
	//
	// FOUND, SECONDS REMAINING.
	static bool, int DespawnOf(Weapon w)
	{
		if (!Ready(w)) return false, 0;

		int elapsed = fieldInt(w, "internalSecond");
		if (elapsed <= 0) return false, 0;

		int left = ARENA_TIMEOUT - elapsed;
		if (left < 0) left = 0;
		return true, left;
	}

	//==========================================================================
	// IS THE PLAYER INSIDE ONE OF THE MOD'S OWN MENUS.
	//
	// Limbo is a walkable hub with a vendor, a mod station and a guide, and
	// each opens a full-screen ACS interface. DOOM Infinite gates its OWN
	// input on exactly this pair -- `if (user_paused || currentMenuID !=
	// MENU_NONE)` appears throughout zPlayer.zsc to stop doors opening and
	// weapons firing from inside a menu.
	//
	// INSPECT MODE HAS TO RESPECT IT AND THE RING DOES NOT. The ring is
	// summoned by a deliberate keypress -- a player who opens the shop and
	// then presses the wheel key meant to. Inspect mode fires on DWELL,
	// unasked, purely because a laser happened to rest somewhere -- and
	// inside a menu the laser is resting on the menu. An uninvited card
	// floating over the vendor screen is the one place this feature could
	// actively get in the way, so it goes quiet there.
	//
	// MENU_NONE = 0, GUIDE = 1, MOD = 2, SHOP = 3.
	static bool Suppressed(PlayerPawn pmo)
	{
		if (!pmo || cv("wr_di_compat", 1.0) <= 0.0) return false;

		int menu;
		if (level.GetFieldInt(pmo, "currentMenuID", menu) && menu != 0) return true;

		int paused;
		if (level.GetFieldInt(pmo, "user_paused", paused) && paused != 0) return true;

		return false;
	}

	//==========================================================================
	// PLAYER-SIDE. The run's own numbers, independent of which weapon is in
	// hand, so these are read off the owner the same way Doomablo's player
	// level and Guncaster's resources are.
	//
	// FOUND, MAPS COMPLETED, LOOPS.
	static bool, int, int RunOf(Weapon w)
	{
		if (!w || !w.Owner || cv("wr_di_compat", 1.0) <= 0.0) return false, 0, 0;

		int maps;
		if (!level.GetFieldInt(w.Owner, "classicMapsCompleted", maps)) return false, 0, 0;

		int loops;
		level.GetFieldInt(w.Owner, "classicMapLoop", loops);
		return true, maps, loops;
	}

	// THE PLAYER'S OWN STAT BLOCK -- damage and speed multipliers as
	// percentages (the mod keeps HUD-ready integer mirrors of both, so no
	// scaling is needed here), plus luck, which is added straight into the
	// random rolls behind every drop in the game.
	//
	// FOUND, DAMAGE %, SPEED %, LUCK.
	static bool, int, int, int StatsOf(Weapon w)
	{
		if (!w || !w.Owner || cv("wr_di_compat", 1.0) <= 0.0) return false, 0, 0, 0;

		int dmg;
		if (!level.GetFieldInt(w.Owner, "user_statHudDamage", dmg)) return false, 0, 0, 0;

		int spd, luck;
		level.GetFieldInt(w.Owner, "user_statHudSpeed", spd);
		level.GetFieldInt(w.Owner, "user_statLuck", luck);
		return true, dmg, spd, luck;
	}

	// HOW MANY PASSIVE PERKS ARE STACKED UP. The names live in a
	// `static const` table -- a class constant rather than a field, so not
	// reflectable -- but the COUNT is a plain int and is the number that
	// actually says how far into a run the player is.
	//
	// FOUND, COUNT.
	static bool, int PerksOf(Weapon w)
	{
		if (!w || !w.Owner || cv("wr_di_compat", 1.0) <= 0.0) return false, 0;

		int n;
		if (!level.GetFieldInt(w.Owner, "powerupsTotal", n)) return false, 0;
		if (n <= 0) return false, 0;
		return true, n;
	}
}
