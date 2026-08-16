version "4.10"

// Test loadout -- everything, immediately, so the rig can be looked at with a
// full arc instead of a fist and a pistol.
//
// Pick "Rig Test" in Player Setup. Deliberately a separate class rather than
// giving weapons on level start: this leaves a normal game normal, and it
// survives map changes and saves without any code watching for them.
//
// SEPARATE PACKAGE, not part of RS_WeaponWheel.pk3. AddPlayerClasses is
// global and permanent -- a class registered there is in the New Game class
// list of every game the mod is loaded with, forever, whether or not anyone
// wanted a debug pawn. Load RS_WeaponWheel_dev.pk3 alongside the mod while
// iterating and nobody else ever sees it.
//
// Nothing here references wr_Rig, so this package loads on its own.
class WR_TestPlayer : DoomPlayer
{
	Default
	{
		Player.DisplayName "Rig Test";

		Player.StartItem "Fist";
		Player.StartItem "Chainsaw";
		Player.StartItem "Pistol";
		Player.StartItem "Shotgun";
		Player.StartItem "SuperShotgun";
		Player.StartItem "Chaingun";
		Player.StartItem "RocketLauncher";
		Player.StartItem "PlasmaRifle";
		Player.StartItem "BFG9000";

		Player.StartItem "Clip",      400;
		Player.StartItem "Shell",     100;
		Player.StartItem "RocketAmmo", 100;
		Player.StartItem "Cell",      600;
	}
}

// =====================================================================
// DEV LOADOUTS -- one full-arsenal pawn per RS_Main class.
// ---------------------------------------------------------------------
// WR_TestPlayer above shows nine stock weapons: one per slot, never a
// crowded one. These nine mirror RS_Main's own selectable classes (Dual
// Pistols .. Dual Chainguns, Vanilla+, MeatGrinder) but grant EVERY
// weapon that class can ever hold, all at once -- a real WIDE ring, with
// slots crowded enough to actually exercise fan-out and the canvas
// pool's over-12 fallback, instead of nine cards that never fight for
// space.
//
// SOFT DEPENDENCY ON RS_MAIN, DELIBERATELY -- same shape as
// wr_RigService in the main package, same reason. Every grant below is a
// class NAME STRING (GiveInventory("VR_Pistol", 1)), which ZScript
// resolves at RUNTIME -- never `: VR_DualClassBase` or `RS_Weapon(w)`,
// which would need RS_Main's classes to exist at COMPILE TIME. That
// matters here specifically: a hard reference would make this whole
// FILE fail to compile without RS_Main loaded, and WR_TestPlayER lives
// in the same file -- so plain wheel testing would break too, for
// something only these nine classes need. Load this package without
// RS_Main and these nine spawn holding a grenade and nothing else:
// GiveInventory on an unresolved class name prints one console line and
// moves on, the same graceful degrade this project already leans on for
// RS_TierColorService and every other ServiceIterator.Find lookup.
//
// Every family name below was read directly out of RS_Main's own
// source (zscript/weapons/rs_weapon, rs_gh_weapon, rs_ps_weapon) -- each
// declares base/2/3 mainhand and 4/5/6 offhand identities, uniformly.
// RS_Weapon.AttachToOwner tops up a magazine to Capacity the instant a
// weapon lands in inventory, so granting the six identities is the
// whole job -- no separate "Loaded" ammo grant is needed or wanted.
// =====================================================================

class WR_DevKit : Object
{
	// Grants a weapon family's six identities -- base/2/3 mainhand,
	// 4/5/6 offhand. A runtime string, same trick RS_ClassGating already
	// uses on `Actor.Spawn(mainhand .. gap, wep.pos)`: ZScript resolves a
	// class from a string expression at the point of use, not at compile
	// time, so a family that does not exist (RS_Main absent, or a typo
	// here) fails that one GiveInventory silently instead of the whole
	// package refusing to load.
	static play void GiveFamily(Actor pawn, string famBase)
	{
		pawn.GiveInventory(famBase, 1);
		pawn.GiveInventory(famBase .. "2", 1);
		pawn.GiveInventory(famBase .. "3", 1);
		pawn.GiveInventory(famBase .. "4", 1);
		pawn.GiveInventory(famBase .. "5", 1);
		pawn.GiveInventory(famBase .. "6", 1);
	}

	// A generous flat reserve. Real Ammo items clamp to their own
	// MaxAmount on pickup, so there is no number to tune here -- this
	// only has to be bigger than any MaxAmount in the project.
	static play void GiveAmmo(Actor pawn, string ammoClass)
	{
		pawn.GiveInventory(ammoClass, 9999);
	}

	// A single grant, routed through a parameter rather than called with
	// a literal directly at the site -- see GrantDualCommon's own note
	// on why that distinction is load-bearing here: `pawn.GiveInventory(
	// "VR_Fist", 1)` written straight into another class's method body
	// resolves the class name EAGERLY, at compile time, and could not
	// see VR_Fist coming from a separately-loaded pk3 (RS_Main). Handed
	// through this parameter instead, `cls` is an opaque runtime value
	// the compiler cannot fold, so resolution defers to the same
	// runtime lookup GiveFamily/GiveAmmo already use successfully for
	// every other grant in this file.
	static play void GiveOne(Actor pawn, string cls)
	{
		pawn.GiveInventory(cls, 1);
	}

	// THE ONLY THING THAT NEEDS TO KNOW WHICH WEAPONS ARE FILLERS.
	//
	// RS_Weapon.IsHandFiller() is the real, authoritative answer --
	// VR_DualClassBase.SeatHands (RS_Main's own) reads it directly -- but
	// calling it means casting to RS_Weapon, a COMPILE-TIME reference to
	// a class this package does not own. Named explicitly instead: every
	// class in RS_Main that overrides IsHandFiller() true, among the
	// families granted below (VR_Fist, RS_GH_Fist, RS_PS_Fist, and their
	// 2..6 identity clones, which INHERIT the override rather than
	// repeating it -- confirmed against RS_Main's own source, not
	// assumed). A real gun always outranks these in SeatHands below.
	private static bool IsFiller(Weapon w)
	{
		if (!w) return false;
		Name cn = w.GetClassName();
		return cn == 'VR_Fist'     || cn == 'VR_Fist2'     || cn == 'VR_Fist3'
		    || cn == 'VR_Fist4'    || cn == 'VR_Fist5'     || cn == 'VR_Fist6'
		    || cn == 'RS_GH_Fist'  || cn == 'RS_GH_Fist2'  || cn == 'RS_GH_Fist3'
		    || cn == 'RS_GH_Fist4' || cn == 'RS_GH_Fist5'  || cn == 'RS_GH_Fist6'
		    || cn == 'RS_PS_Fist'  || cn == 'RS_PS_Fist2'  || cn == 'RS_PS_Fist3'
		    || cn == 'RS_PS_Fist4' || cn == 'RS_PS_Fist5'  || cn == 'RS_PS_Fist6';
	}

	// Simplified version of VR_DualClassBase.SeatHands (RS_Main,
	// zscript/player/VR_PlayerClasses.zs) -- same shape, same reason:
	// GiveInventory is hand-blind, so without this a pawn holding forty
	// weapons spawns holding whichever one happened to land in Inv last.
	// A real gun always beats a filler for a hand; a filler is only
	// seated if it is genuinely all that hand has.
	// featured is the class's OWN weapon -- the one its name promises. Without
	// it this seated whichever real weapon happened to be first in Inv, and
	// since every Dual class is also granted rocket/plasma/BFG by
	// GrantDualCommon, "DEV Dual Revolvers" spawned holding a BFG. Same
	// tiebreaker RS_Main's own SeatHands applies via GetMainhandClass: the
	// FLAG still decides which hand, this only decides which of your own guns
	// is the featured one.
	static play void SeatHands(PlayerPawn pmo, string featured = "")
	{
		if (!pmo || !pmo.player) return;

		Weapon mainGun = null, mainFiller = null;
		Weapon offGun  = null, offFiller  = null;

		for (Inventory item = pmo.Inv; item != null; item = item.Inv)
		{
			let w = Weapon(item);
			if (!w) continue;

			bool filler = IsFiller(w);
			if (w.bOffhandWeapon)
			{
				if (filler) { if (!offFiller) offFiller = w; }
				else        { if (!offGun)    offGun    = w; }
			}
			else
			{
				if (filler) { if (!mainFiller) mainFiller = w; }
				else        { if (!mainGun)    mainGun    = w; }
			}
		}

		// The class's own weapon wins the main hand over anything else it was
		// also granted. Offhand takes the _4 identity of the same family, so
		// both hands are the gun the class is named after.
		if (featured.Length())
		{
			let fw = Weapon(pmo.FindInventory(featured));
			if (fw && !fw.bOffhandWeapon) mainGun = fw;

			let fo = Weapon(pmo.FindInventory(featured .. "4"));
			if (fo && fo.bOffhandWeapon) offGun = fo;
		}

		Weapon mainWep = mainGun ? mainGun : mainFiller;
		Weapon offWep  = offGun  ? offGun  : offFiller;

		if (mainWep) pmo.player.ReadyWeapon   = mainWep;
		if (offWep)  pmo.player.OffhandWeapon = offWep;

		pmo.player.PendingWeapon = WP_NOCHANGE;
		pmo.BringUpWeapon();
	}
}

// Shared spawn plumbing for all nine DEV_ classes below.
//
// Plain DoomPlayer, not RS_Main's VR_DualClassBase -- see the header
// comment above for why. The grenade StartItem here is the ONLY
// Default-block StartItem in the whole chain, and it has to be:
// DoomPlayer's own Default block grants vanilla Pistol/Fist/Clip, and
// declaring even one Player.StartItem line in a subclass REPLACES the
// inherited list entirely rather than adding to it -- confirmed against
// the engine source (thingdef_properties.cpp's DropItemSet guard resets
// DropItemList the first time a subclass's OWN parse hits a StartItem
// line). So this one line is what keeps two vanilla Doom weapons off
// every ring below. Leaf classes declare no StartItem of their own and
// inherit this one.
class WR_DevPlayerBase : DoomPlayer abstract
{
	Default
	{
		Player.StartItem "RS_Grenade";
		Player.StartItem "RS_GrenadeAmmo", 3;
	}

	// Each leaf grants its own arsenal here.
	virtual void GrantLoadout(PlayerPawn pmo) {}

	// The weapon this class is NAMED after, so it is the one in your hands at
	// spawn rather than whatever GiveInventory happened to add last. Empty
	// means "no preference" -- correct for the whole-set classes, which are
	// not named after any single gun.
	virtual string FeaturedClass() { return ""; }

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		GrantLoadout(self);
		WR_DevKit.SeatHands(self, FeaturedClass());
	}
}

// Shared by every DEV_Dual_X leaf below: fists, the three heavy-ordnance
// families, and every ammo type any of the seven Dual_X families uses.
// Sequential calls rather than a loop over a name list, matching
// RS_ClassGating's own "sequential ifs, not a loop" choice in the same
// project -- `static const TYPE name[] = {}` does not reliably resolve
// on this engine build, and explicit calls sidestep the question rather
// than trusting an untested workaround.
class WR_DevDualBase : WR_DevPlayerBase abstract
{
	protected void GrantDualCommon(PlayerPawn pmo)
	{
		// GiveOne, NOT pmo.GiveInventory("VR_Fist", 1) written directly
		// here. That was the first version, and it did not compile:
		// "Unknown class name 'VR_Fist' of type 'Inventory'". A string
		// LITERAL passed straight into GiveInventory is resolved EAGERLY,
		// at compile time, and this file's compile pass could not see a
		// class declared in RS_Main, a separately-loaded pk3 -- unlike
		// every OTHER grant below, which already goes through a `string`
		// PARAMETER (GiveFamily's famBase, GiveAmmo's ammoClass) and so
		// was never eagerly checked at all. GiveOne exists to put these
		// two grants through that same parameter indirection.
		// Slot 1: two fists and a chainsaw. Then ONE of each heavy.
		//
		// GiveOne, not GiveFamily, and that is the fix rather than a
		// preference. The heavies were granted as full six-identity
		// families like the class weapon, which put EIGHTEEN heavy guns on
		// a class named after a revolver -- they swamped the ring and the
		// hand seat picked a BFG out of them. The six identities belong to
		// the family the class is named for, and to nothing else.
		WR_DevKit.GiveOne(pmo, "VR_Fist");
		WR_DevKit.GiveOne(pmo, "VR_Fist2");
		WR_DevKit.GiveOne(pmo, "VR_Chainsaw");
		WR_DevKit.GiveOne(pmo, "VR_RocketLauncher");
		WR_DevKit.GiveOne(pmo, "VR_PlasmaRifle");
		WR_DevKit.GiveOne(pmo, "VR_BFG9000");

		WR_DevKit.GiveAmmo(pmo, "Clip");
		WR_DevKit.GiveAmmo(pmo, "VR_Shell");
		WR_DevKit.GiveAmmo(pmo, "VR_ChaingunAmmo");
		WR_DevKit.GiveAmmo(pmo, "RocketAmmo");
		WR_DevKit.GiveAmmo(pmo, "Cell");
	}
}

class DEV_Dual_Pistol : WR_DevDualBase
{
	Default { Player.DisplayName "DEV Dual Pistols"; }
	override void GrantLoadout(PlayerPawn pmo)
	{
		WR_DevKit.GiveFamily(pmo, "VR_Pistol");
		GrantDualCommon(pmo);
	}
	override string FeaturedClass() { return "VR_Pistol"; }
}

class DEV_Dual_Revolver : WR_DevDualBase
{
	Default { Player.DisplayName "DEV Dual Revolvers"; }
	override void GrantLoadout(PlayerPawn pmo)
	{
		WR_DevKit.GiveFamily(pmo, "VR_Revolver");
		GrantDualCommon(pmo);
	}
	override string FeaturedClass() { return "VR_Revolver"; }
}

class DEV_Dual_Rifle : WR_DevDualBase
{
	Default { Player.DisplayName "DEV Dual Rifles"; }
	override void GrantLoadout(PlayerPawn pmo)
	{
		WR_DevKit.GiveFamily(pmo, "VR_Rifle");
		GrantDualCommon(pmo);
	}
	override string FeaturedClass() { return "VR_Rifle"; }
}

class DEV_Dual_SMG : WR_DevDualBase
{
	Default { Player.DisplayName "DEV Dual SMGs"; }
	override void GrantLoadout(PlayerPawn pmo)
	{
		WR_DevKit.GiveFamily(pmo, "VR_SMG");
		GrantDualCommon(pmo);
	}
	override string FeaturedClass() { return "VR_SMG"; }
}

class DEV_Dual_Shotgun : WR_DevDualBase
{
	Default { Player.DisplayName "DEV Dual Shotguns"; }
	override void GrantLoadout(PlayerPawn pmo)
	{
		WR_DevKit.GiveFamily(pmo, "VR_Shotgun");
		GrantDualCommon(pmo);
	}
	override string FeaturedClass() { return "VR_Shotgun"; }
}

class DEV_Dual_SSG : WR_DevDualBase
{
	Default { Player.DisplayName "DEV Dual Super Shotguns"; }
	override void GrantLoadout(PlayerPawn pmo)
	{
		WR_DevKit.GiveFamily(pmo, "VR_SuperShotgun");
		GrantDualCommon(pmo);
	}
	override string FeaturedClass() { return "VR_SuperShotgun"; }
}

class DEV_Dual_Chaingun : WR_DevDualBase
{
	Default { Player.DisplayName "DEV Dual Chainguns"; }
	override void GrantLoadout(PlayerPawn pmo)
	{
		WR_DevKit.GiveFamily(pmo, "VR_Chaingun");
		GrantDualCommon(pmo);
	}
	override string FeaturedClass() { return "VR_Chaingun"; }
}

class DEV_VanillaPlus : WR_DevPlayerBase
{
	Default { Player.DisplayName "DEV Vanilla+"; }

	// Every RS_GH_ family that exists, per
	// zscript/weapons/rs_gh_weapon/*.zs -- Vanilla+ is UNGATED
	// (RS_GH_Weaponset.GetFamily() is the EVR_Family_None default, so
	// RS_ClassGating's fill/replace never touches it), so a real
	// Vanilla+ player can end up holding any of these from ordinary map
	// pickups. 21 families x 6 identities is up to 126 cards -- the
	// exact scenario wr_canvas's pool-of-12 fallback exists for, so this
	// class is as much a test of THAT as of the ring itself.
	override void GrantLoadout(PlayerPawn pmo)
	{
		WR_DevKit.GiveFamily(pmo, "RS_GH_Fist");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Chainsaw");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Pistol");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Revolver");
		WR_DevKit.GiveFamily(pmo, "RS_GH_PumpShotgun");
		WR_DevKit.GiveFamily(pmo, "RS_GH_AssaultShotgun");
		WR_DevKit.GiveFamily(pmo, "RS_GH_SSG");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Minigun");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Rifle");
		WR_DevKit.GiveFamily(pmo, "RS_GH_SMG");
		WR_DevKit.GiveFamily(pmo, "RS_GH_MP40");
		WR_DevKit.GiveFamily(pmo, "RS_GH_RocketLauncher");
		WR_DevKit.GiveFamily(pmo, "RS_GH_GrenadeLauncher");
		WR_DevKit.GiveFamily(pmo, "RS_GH_HandGrenade");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Plasma");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Railgun");
		WR_DevKit.GiveFamily(pmo, "RS_GH_BFG9000");
		WR_DevKit.GiveFamily(pmo, "RS_GH_BFG10k");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Unmaker");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Flamethrower");
		WR_DevKit.GiveFamily(pmo, "RS_GH_Machinegun");

		WR_DevKit.GiveAmmo(pmo, "Clip");
		WR_DevKit.GiveAmmo(pmo, "Shell");
		WR_DevKit.GiveAmmo(pmo, "Cell");
		WR_DevKit.GiveAmmo(pmo, "RocketAmmo");
	}
}

class DEV_MeatGrinder : WR_DevPlayerBase
{
	Default { Player.DisplayName "DEV MeatGrinder"; }

	// Every RS_PS_ family, per zscript/weapons/rs_ps_weapon/*.zs -- also
	// ungated, same reasoning as Vanilla+ above. 9 families x 6 = 54.
	override void GrantLoadout(PlayerPawn pmo)
	{
		WR_DevKit.GiveFamily(pmo, "RS_PS_Fist");
		WR_DevKit.GiveFamily(pmo, "RS_PS_Chainsaw");
		WR_DevKit.GiveFamily(pmo, "RS_PS_Machinegun");
		WR_DevKit.GiveFamily(pmo, "RS_PS_AutoShotgun");
		WR_DevKit.GiveFamily(pmo, "RS_PS_SSG");
		WR_DevKit.GiveFamily(pmo, "RS_PS_Chaingun");
		WR_DevKit.GiveFamily(pmo, "RS_PS_RocketLauncher");
		WR_DevKit.GiveFamily(pmo, "RS_PS_Plasma");
		WR_DevKit.GiveFamily(pmo, "RS_PS_BFG");

		WR_DevKit.GiveAmmo(pmo, "Clip");
		WR_DevKit.GiveAmmo(pmo, "Shell");
		WR_DevKit.GiveAmmo(pmo, "Cell");
		WR_DevKit.GiveAmmo(pmo, "RocketAmmo");
	}
}
