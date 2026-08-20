// WEAPON STAT TRACKER.
//
// Everything else this wheel reads for the sheet -- RS Weapon's fields, the
// eight other mods' compat files -- is a READ: some other mod already
// computed the number, this wheel just asks for it by name. Nothing,
// anywhere, computes "kills with this gun" or "shots fired" or "was that a
// headshot" as a queryable field, including for RS Weapon's own arsenal.
// So this file is a TRACKER, not a compat reader: it watches the game as it
// happens and keeps its own running counters, per weapon INSTANCE, entirely
// independent of which mod (if any) that weapon came from.
//
// IDENTITY, WITHOUT A FIELD ON A CLASS WE DON'T OWN. The soft-dependency
// rule this whole mod follows means never subclassing another mod's weapon
// -- so there is nowhere to stamp an ID on the gun itself. Instead, the
// PLAYER carries a hidden ledger item (wr_StatLedger, below), and each
// entry in it holds a real Weapon object reference. Actor references are
// ordinary savegame-serialized fields -- the same mechanism that already
// keeps target/tracer/every inventory chain alive across a save/load -- so
// the exact gun you are holding when you save is still the exact gun with
// the exact same stats when you load. No new engine capability needed.
//
// ATTRIBUTION IS A GUESS, AND IT FAILS CLOSED. A WorldThingDamaged/
// WorldThingDied event does not say which of your two hands (this rig is
// genuinely dual-wielded -- player.ReadyWeapon AND player.OffhandWeapon are
// both real) caused it. attributedWeapon() below picks whichever hand's
// weapon fired most recently, inside a short window, and if both fired the
// same tic -- or neither fired recently enough to plausibly be the cause --
// it attributes to NEITHER rather than guess wrong. Same reasoning as a
// reload-sized ammo drop not being counted as one giant shot: an
// undercounted stat is honest; a misattributed one is a lie wearing a
// number.
//
// HEADSHOTS ONLY IF THAT MOD IS ACTUALLY LOADED. E:\Headshots has no
// counter of its own -- HS_Handler.WorldThingDamaged detects a headshot and
// calls HS_Marker.Confirm(), which spawns a cosmetic marker actor, plays a
// sound, and fades out. Nothing persists. So this counts HS_Marker spawns
// itself, via WorldThingSpawned -- zero duplicated hit-detection geometry,
// and it naturally only ever fires when that mod is present.
class wr_WeaponStats
{
	Weapon wpn;

	int kills;
	int shotsFired;
	int hits;
	int headshots;

	double damageSum;
	int damageSamples;

	// Ammo-drain shot detection needs a baseline to compare against, per
	// weapon, updated every tic that weapon is in a hand -- see
	// wr_StatEvents.trackFire().
	int lastAmmo1;
	int lastAmmo2;
	bool seenAmmo;

	// Rate of fire, as an exponential moving average of tics between shots
	// rather than a straight average -- so a weapon's ROF reading tracks
	// its CURRENT firing pattern (burst vs. sustained) instead of being
	// dragged down by a slow first shot from ten minutes ago.
	int lastFireTic;
	double rofEma;

	// The window a shot leaves open for WorldThingDamaged to credit it as a
	// hit. Consumed by the first damage event that lands inside it, so a
	// ten-pellet shotgun blast counts as one hit against one shot fired,
	// not ten.
	int pendingHitUntilTic;
}

// The hidden per-player carrier. Auto-granted lazily (wr_StatLedger.StatsFor
// grants it itself the first time anything asks, rather than depending
// solely on PlayerSpawned/PlayerEntered firing) so an existing save from
// before this file existed still picks it up the moment it matters.
class wr_StatLedger : Inventory
{
	Array<wr_WeaponStats> mStats;

	default
	{
		Inventory.Amount 1;
		Inventory.MaxAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.UNCLEARABLE
	}

	// Finds (or, with create=true, makes) the record for one specific
	// weapon INSTANCE on one specific player. Prunes dead references on the
	// way past -- a weapon reference nulls itself out when the actor it
	// pointed to is destroyed, same as target/tracer anywhere else in the
	// engine, so a gun that got dropped and never picked back up just
	// quietly falls out of the ledger the next time anything looks.
	static play wr_WeaponStats StatsFor(PlayerPawn pawn, Weapon w, bool create)
	{
		if (!pawn || !w) return null;

		let ledger = wr_StatLedger(pawn.FindInventory("wr_StatLedger"));
		if (!ledger)
		{
			if (!create) return null;
			ledger = wr_StatLedger(pawn.GiveInventoryType("wr_StatLedger"));
			if (!ledger) return null;
		}

		for (int i = ledger.mStats.Size() - 1; i >= 0; --i)
		{
			if (ledger.mStats[i].wpn == null) ledger.mStats.Delete(i);
		}

		for (int i = 0; i < ledger.mStats.Size(); ++i)
		{
			if (ledger.mStats[i].wpn == w) return ledger.mStats[i];
		}

		if (!create) return null;

		let s = new("wr_WeaponStats");
		s.wpn = w;
		ledger.mStats.Push(s);
		return s;
	}
}

// The EventHandler doing the actual watching. Its own file and its own
// class for the same reason wr_gunhud.zs's wr_GunTag is separate from the
// ring -- it shares no state with wr_Rig, and folding a third unrelated
// concern into an already-large class would only cost readability.
class wr_StatEvents : EventHandler
{
	// How many tics an ammo-drain-detected shot's hit-credit window stays
	// open. Generous enough for a slow projectile's travel time, short
	// enough that an unrelated later hit on the same target doesn't get
	// mistaken for this shot's result.
	const HIT_WINDOW    = 12;

	// Beyond this many tics since the last shot, a fresh one is treated as
	// the start of a new firing pattern rather than a continuation of the
	// old one -- so a rate-of-fire reading does not average in the pause
	// between one engagement and the next.
	const ROF_WINDOW    = 105;

	// How long a hand's last-fire timestamp stays eligible to explain a
	// kill or a hit. Past this, neither hand gets credit -- see the file
	// header on why undercounting beats guessing.
	const ATTRIB_WINDOW = 35;

	private static double cv(string name, double fallback)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetFloat() : fallback;
	}

	private static bool active()
	{
		return cv("wr_stats_track", 1.0) > 0.0;
	}

	// SHOT DETECTION. Not hooked off any weapon's own fire state -- there
	// is no such hook that works identically across nine mods with nothing
	// in common -- so this watches the one thing every ammo-using weapon
	// shares: its ammo pool getting smaller. A decrease big enough to be a
	// reload rather than a shot is folded into the new baseline and NOT
	// counted -- the same undercount-over-misattribute rule as everywhere
	// else in this file.
	override void WorldTick()
	{
		if (!active()) return;
		if (!playeringame[consoleplayer] || !players[consoleplayer].mo) return;

		let pawn = players[consoleplayer].mo;
		if (!pawn.player) return;

		trackFire(pawn, pawn.player.ReadyWeapon);
		trackFire(pawn, pawn.player.OffhandWeapon);
	}

	private void trackFire(PlayerPawn pawn, Weapon w)
	{
		if (!w) return;

		let s = wr_StatLedger.StatsFor(pawn, w, true);
		if (!s) return;

		int a1 = w.Ammo1 ? w.Ammo1.Amount : 0;
		int a2 = w.Ammo2 ? w.Ammo2.Amount : 0;

		if (!s.seenAmmo)
		{
			s.lastAmmo1 = a1;
			s.lastAmmo2 = a2;
			s.seenAmmo  = true;
			return;
		}

		int down1 = s.lastAmmo1 - a1;
		int down2 = s.lastAmmo2 - a2;
		int use1  = w.default.AmmoUse1 > 0 ? w.default.AmmoUse1 : 1;

		// A drop roughly the size of what ONE shot should cost -- not a
		// refill (down <= 0), and not a reload-sized jump either (more
		// than double what one shot costs). Anything outside that band is
		// ambiguous and simply becomes the new baseline, uncounted.
		bool fired = (down1 > 0 && down1 <= use1 * 2) || (down2 > 0 && down2 <= use1 * 2);

		s.lastAmmo1 = a1;
		s.lastAmmo2 = a2;

		if (!fired) return;

		s.shotsFired++;
		s.pendingHitUntilTic = level.maptime + HIT_WINDOW;

		if (s.lastFireTic > 0)
		{
			int dt = level.maptime - s.lastFireTic;
			if (dt > 0 && dt <= ROF_WINDOW)
				s.rofEma = (s.rofEma <= 0.0) ? double(dt) : (s.rofEma * 0.75 + double(dt) * 0.25);
		}
		s.lastFireTic = level.maptime;
	}

	// Which hand's weapon most plausibly caused a hit/kill/headshot landing
	// right now. See the file header -- this fails closed on ambiguity
	// rather than guessing.
	private static Weapon attributedWeapon(PlayerPawn pawn)
	{
		if (!pawn || !pawn.player) return null;

		Weapon a = pawn.player.ReadyWeapon;
		Weapon b = pawn.player.OffhandWeapon;

		wr_WeaponStats sa = a ? wr_StatLedger.StatsFor(pawn, a, false) : null;
		wr_WeaponStats sb = b ? wr_StatLedger.StatsFor(pawn, b, false) : null;

		int tA = sa ? sa.lastFireTic : 0;
		int tB = sb ? sb.lastFireTic : 0;

		if (tA <= 0 && tB <= 0) return null;
		if (level.maptime - max(tA, tB) > ATTRIB_WINDOW) return null;
		if (tA == tB) return null;

		return (tA > tB) ? a : b;
	}

	override void WorldThingDamaged(WorldEvent e)
	{
		if (!active()) return;
		if (!e.DamageSource || !e.DamageSource.player) return;
		if (e.DamageSource.player != players[consoleplayer]) return;

		let pawn = PlayerPawn(e.DamageSource);
		Weapon w = attributedWeapon(pawn);
		if (!w) return;

		let s = wr_StatLedger.StatsFor(pawn, w, true);
		if (!s) return;

		s.damageSum += e.Damage;
		s.damageSamples++;

		if (s.pendingHitUntilTic > 0 && level.maptime <= s.pendingHitUntilTic)
		{
			s.hits++;
			s.pendingHitUntilTic = 0;
		}
	}

	override void WorldThingDied(WorldEvent e)
	{
		if (!active()) return;
		if (!e.DamageSource || !e.DamageSource.player) return;
		if (e.DamageSource.player != players[consoleplayer]) return;

		let pawn = PlayerPawn(e.DamageSource);
		Weapon w = attributedWeapon(pawn);
		if (!w) return;

		let s = wr_StatLedger.StatsFor(pawn, w, true);
		if (s) s.kills++;
	}

	override void WorldThingSpawned(WorldEvent e)
	{
		if (!active()) return;
		if (!e.Thing || (("" .. e.Thing.GetClassName()) != "HS_Marker")) return;
		if (!playeringame[consoleplayer] || !players[consoleplayer].mo) return;

		let pawn = players[consoleplayer].mo;
		Weapon w = attributedWeapon(pawn);
		if (!w) return;

		let s = wr_StatLedger.StatsFor(pawn, w, true);
		if (s) s.headshots++;
	}

	// Lazy-grant covers the general case (StatsFor grants on first use),
	// but granting here too means a fresh player pawn already carries the
	// ledger before the first shot rather than creating it mid-tick.
	override void PlayerSpawned(PlayerEvent e)   { grantLedger(e.PlayerNumber); }
	override void PlayerEntered(PlayerEvent e)   { grantLedger(e.PlayerNumber); }

	private void grantLedger(int pnum)
	{
		if (!active()) return;
		if (pnum < 0 || pnum >= MAXPLAYERS || !playeringame[pnum] || !players[pnum].mo) return;
		if (players[pnum].mo.FindInventory("wr_StatLedger") != null) return;
		players[pnum].mo.GiveInventoryType("wr_StatLedger");
	}
}

// Public read API for the sheet -- zscript.zs's buildSheetRows() calls
// into this exactly the way it calls into every wr_CompatXxx file, even
// though this one reads the wheel's OWN tracked state rather than another
// mod's fields.
class wr_StatTracker
{
	private static double cv(string name, double fallback)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetFloat() : fallback;
	}

	// PLAY-SCOPED, and everything that calls into it has to be too --
	// wr_StatLedger.StatsFor ultimately touches FindInventory/
	// GiveInventoryType, which are live-game-state operations the compiler
	// will not let a data-scope function (this class's default, since it
	// is a plain Object, not an Actor) reach. Every other compat file in
	// this mod avoids the question entirely by only ever calling clearscope
	// reflection natives (Level.GetFieldInt and friends) -- this is the
	// first one that needs an actual inventory search, so it is the first
	// one that needs the keyword.
	private static play wr_WeaponStats lookup(Weapon w)
	{
		if (!w || !w.Owner || cv("wr_stats_track", 1.0) <= 0.0) return null;
		let pawn = PlayerPawn(w.Owner);
		if (!pawn) return null;
		return wr_StatLedger.StatsFor(pawn, w, false);
	}

	// FOUND, KILLS, SHOTS FIRED, HITS. Found only once at least one shot
	// has actually been detected -- a weapon that has never fired showing
	// "KILLS 0 SHOTS 0 ACC 0%" is noise, not information.
	static play bool, int, int, int BasicsOf(Weapon w)
	{
		let s = lookup(w);
		if (!s || s.shotsFired <= 0) return false, 0, 0, 0;
		return true, s.kills, s.shotsFired, s.hits;
	}

	// FOUND, AVERAGE DAMAGE PER HIT, SAMPLES. An estimate -- see this
	// file's header and the "~" the sheet prints in front of it.
	static play bool, double, int DamageOf(Weapon w)
	{
		let s = lookup(w);
		if (!s || s.damageSamples <= 0) return false, 0.0, 0;
		return true, s.damageSum / double(s.damageSamples), s.damageSamples;
	}

	// FOUND, SHOTS PER SECOND. 35.0 is Doom's fixed tic rate.
	static play bool, double RofOf(Weapon w)
	{
		let s = lookup(w);
		if (!s || s.rofEma <= 0.0) return false, 0.0;
		return true, 35.0 / s.rofEma;
	}

	// FOUND(mod loaded), COUNT. Found means "Headshots is loaded", not
	// "this weapon has landed one" -- shown at zero once the mod is
	// present, same honesty rule as every other conditional row on the
	// sheet: present-but-zero is real information, absent is not.
	static play bool, int HeadshotsOf(Weapon w)
	{
		if (!w || !w.Owner || cv("wr_stats_track", 1.0) <= 0.0) return false, 0;
		if (Object.FindClass("HS_Marker") == null) return false, 0;

		let pawn = PlayerPawn(w.Owner);
		if (!pawn) return false, 0;

		let s = wr_StatLedger.StatsFor(pawn, w, false);
		return true, s ? s.headshots : 0;
	}
}
