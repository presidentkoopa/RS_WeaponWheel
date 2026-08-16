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
