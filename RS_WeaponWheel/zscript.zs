version "4.10"

// Wrist rig -- weapon cards in a ring around one hand, taken by pointing at
// one and pulling the trigger, or by reaching into it.
//
// TWO WAYS IN, and they are not rivals. The beam is for a card across the
// ring; the hand is for the one you are already at. When both answer, the hand
// wins -- you had to put it there, so it is the more deliberate act. Reaching
// is switched off with wr_touch 0, which leaves the beam alone.
//
// BBF_FIXED only, still. Camera-facing panels are tested against the wrong
// orientation and TouchBillboard on one reports a hit from anywhere in the
// room, so cards are oriented by hand every tic instead.
//
// THIS NEEDS ENGINE CHANGES, and the note here used to say it did not. It also
// used to say groups were unusable because group scale moved the picture
// without moving the hit box and a group scaled to zero stayed clickable --
// both true, both found by this mod, and both fixed in the fork (see its
// FORK_CHANGES.md section 22). The cards are grouped objects now, and the
// billboard roll axis, the VR input suppression, the borrowed laser and the
// haptics were all added for this.

// Lives outside the EventHandler on purpose.
//
// Everything declared inside an EventHandler inherits play scope, and
// InputProcess is ui -- so a helper it needs cannot live there, whatever
// qualifiers you decorate it with. A plain class is data scope and callable
// from either side. This is the same shape Gearbox uses for the same reason.
class wr_Keybind
{
	static bool isKeyFor(int key, string command)
	{
		Array<int> keys;
		bindings.GetAllKeysForCommand(keys, command);

		uint nKeys = keys.Size();
		for (uint i = 0; i < nKeys; ++i)
		{
			if (keys[i] == key) return true;
		}
		return false;
	}
}

class wr_Rig : EventHandler
{
	// Geometry, all in map units.
	const RING_RADIUS   = 26.0;   // how far the panels orbit the wrist
	const RING_RISE     = 10.0;   // how far above it they sit
	const PANEL_W       = 15.0;
	const PANEL_H       = 11.0;
	const SPREAD_DEG    = 26.0;   // angle between adjacent panels
	const MAX_PANELS    = 9;
	const TOUCH_RANGE   = 9.0;    // fingertip radius
	const HOVER_REPEAT  = 6;      // tics before a held hand re-triggers

	bool  mOpen;
	int   mRigHand;               // hand wearing the rig (1 = off)
	int   mPokeHand;              // hand doing the reaching (0 = main)

	Array<int>   mIds;
	Array<int>   mPlates;         // the visible card; mIds are the invisible hit quads
	Array<int>   mLabels;
	Array<int>   mIcons;
	Array<int>   mAmmos;          // the count under the name
	Array<Class<Weapon> > mTypes;
	Array<int>   mCardSlots;      // which slot each card stands for

	// The card's colour when nothing is happening to it. Not a constant, because
	// a dry weapon rests a different colour from a loaded one -- and hovering off
	// a card has to put back THAT colour rather than the one every card shares.
	Array<int>   mBaseColor;

	// Icon dimensions as fractions of the card, worked out once at spawn from the
	// texture's real shape. Two arrays because ZScript's dynamic arrays do not
	// take a Vector2.
	Array<double> mIconW;
	Array<double> mIconH;
	Array<double> mLabelH;        // measured so the name fits its card

	int mOpenTics;                // drives the grow-in
	double mCentreIconW, mCentreIconH;

	Array<int> mAccents;          // the slot-coloured bar along the card's top
	Array<int> mGauges;           // BB_BAR: ammo as a proportion
	Array<int> mFaces;            // one painted canvas texture per card
	Array<int> mMarks;            // "you already have this", per card
	Actor      mLight;            // one dynamic light, on the hovered card
	Array<Actor> mModels;         // a real weapon model per card, when enabled

	// ONE GROUP PER CARD, so a card is an object rather than six loose quads.
	//
	// The group carries an origin and a scale, and the ENGINE resolves the
	// animation per frame -- not at script's 35Hz, which is what the hand-rolled
	// grow was doing and why it stepped. Growth eases out with a slight
	// overshoot and collapse eases in; that curve belongs to the engine and is
	// not a parameter, which is fine, because it is a better curve than the one
	// that was here.
	Array<int> mGroups;
	int mCentreGroup;
	int mFanGroup;

	// Tics left in the collapse. The billboards outlive closeRig by exactly this
	// long so the ring can fold away instead of blinking out; everything else --
	// the weapon, the laser, the sticks, bullet time -- is handed back
	// immediately, because none of that should wait on an animation.
	int mClosingTics;

	// Set for the closes that cannot afford to linger -- death, level end, and
	// re-opening on the other hand. A ring folding away while the next one is
	// already growing would leave two rings on screen and two sets of handles
	// racing each other to be freed.
	bool mHardClose;

	// Whether the fog slab is ours right now. Tracked rather than assumed,
	// because there is no getter and clearing one we never took would wipe a
	// map's own mist.
	bool mFogHeld;
	bool mBeamHeld;
	bool mSweepHeld;

	// Shapes are a slot allocator, not a global slot, so this one is genuinely
	// ours and -1 means we hold none. Still released explicitly: the allocator
	// wraps and overwrites rather than refusing when it runs out, so a leaked
	// slot is a slot somebody else silently loses later.
	int mShapeSlot;
	bool mWaveHeld;

	// Where each card ended up this tic, so the commit burst can be thrown from
	// the card rather than from the hand. Recorded during layout because that is
	// the only place the position exists -- and read during commit, which
	// happens before the ring is torn down.
	// THREE ARRAYS, NOT ONE OF VECTOR3.
	//
	// ZScript's dynamic arrays take integral base types only -- Array<Vector3>
	// is rejected outright, exactly as Array<Vector2> is for the icon sizes
	// twenty lines up. Read cardPos() rather than indexing these directly.
	Array<double> mCardX;
	Array<double> mCardY;
	Array<double> mCardZ;

	// Which card is flipping as the ring folds, and how long is left of it.
	int mFlipCard;
	int mFlipTics;

	// The fan that opens out of a multi-weapon slot.
	Array<int>   mSubIds;
	Array<int>   mSubIcons;
	Array<int>   mSubAmmos;
	Array<int>   mSubLabels;
	Array<double> mSubIconW;
	Array<double> mSubIconH;
	Array<Class<Weapon> > mSubTypes;
	int mExpanded;                // index into mIds, or -1
	int mDwellTics;               // how long the hover has sat on one card

	bool  mWantAutoOpen;
	Vector3 mAnchor;              // the ring centre, out in front of the hand
	double  mAnchorYaw;
	bool    mHaveAnchor;
	// mAimYaw/mAimPitch/mHaveAim went with the angular gain that used them.
	int mHovered;                 // billboard id under the poking hand, 0 = none
	int mHoverTics;
	Vector3 mLastPoke;
	bool mHavePoke;
	int  mLockTics;
	int  mCentreId, mCentreIcon, mCentreLabel;
	bool    mTouching;            // hand is physically inside a card
	bool    mBtOn;                // we are the ones holding bullet time on
	int     mBtSavedUnlimited;    // their bt_adrenaline_unlimited, to put back

	//==========================================================================
	// Open / close
	//==========================================================================

	override void NetworkProcess(ConsoleEvent e)
	{
		// A wheel per hand. Whichever hand you summon it on is the hand that
		// wears it, points at it, and receives what you pick -- so the bind you
		// press already says which hand you meant.
		if (e.Name ~== "wr_toggle_off")  { toggle(1); return; }
		if (e.Name ~== "wr_toggle_main") { toggle(0); return; }
		if (e.Name ~== "wr_toggle")      { toggle(1); return; }

		if (e.Name ~== "wr_grab")
		{
			let pmo = players[consoleplayer].mo;
			if (pmo != null && mOpen && mHovered != 0) commit(pmo);
			return;
		}
	}

	// Fire commits, and never reaches the gun.
	//
	// This has to happen here rather than by reading cmd.buttons in WorldTick:
	// by the time the playsim sees the button the shot is already going to
	// happen, and the only place to stop it is before the press becomes a
	// command at all. Returning true consumes the event.
	//
	// Narrow on purpose -- only while the rig is open AND a card is actually
	// under the hand. Any wider and opening the rig would deaden your trigger.
	override bool InputProcess(InputEvent e)
	{
		if (!mOpen || mHovered == 0) return false;
		if (e.Type != InputEvent.Type_KeyDown) return false;
		// EITHER trigger. The rig is worn and worked by one hand, and which hand
		// that is depends on which key opened it -- so insisting on the main
		// trigger made the off-hand rig unusable with the off-hand controller.
		// Trigger takes it from any distance. Use is the grab, for when your hand
		// is already on the card -- same result, but it is the gesture that fits
		// what you just did with your arm.
		if (!wr_Keybind.isKeyFor(e.KeyScan, "+attack")
		 && !wr_Keybind.isKeyFor(e.KeyScan, "+oh_attack")
		 && !(mTouching && wr_Keybind.isKeyFor(e.KeyScan, "+use"))) return false;

		EventHandler.SendNetworkEvent("wr_grab");
		return true;
	}


	// Pressing the OTHER hand's key while one is open moves the rig across
	// rather than closing it, for the same reason a menu with two tabs does not
	// make you shut it to change tab.
	private void toggle(int hand)
	{
		if (mOpen && mRigHand == hand) { closeRig(); return; }

		// Moving across hands takes the old ring down HARD. Letting it fold while
		// the new one grows would put two rings in the air at once, each holding
		// handles the other is about to clear.
		if (mOpen) { mHardClose = true; closeRig(); mHardClose = false; }

		openRig(hand);
	}

	private void openRig(int hand)
	{
		let pmo = players[consoleplayer].mo;
		if (pmo == null || players[consoleplayer].playerstate != PST_LIVE) return;

		// A ring still folding away from the last open is finished off now, or
		// its handles leak the moment the arrays below are cleared.
		if (mClosingTics > 0) { destroyPanels(); mClosingTics = 0; }

		// Same hand wears the cards and catches them. Reaching across with your
		// gun hand to arm your other one was backwards: it occupies the hand you
		// need, to fill the hand you do not.
		mRigHand    = hand;
		mPokeHand   = hand;
		mHaveAnchor = false;

		gatherWeapons(pmo);
		if (mTypes.Size() == 0) return;

		spawnPanels();
		spawnCardModels(pmo);

		mOpen      = true;
		mHovered   = 0;
		mHoverTics = 0;
		mHavePoke  = false;
		mShapeSlot = -1;
		mOpenTics  = 0;

		// NOT mCardPos.Clear() -- spawnPanels has already sized it, one entry
		// per card, five lines above. Clearing it here emptied it for the ring's
		// whole life, and everything that asks "where is that card" is guarded
		// by its size, so the hovered-card light and the commit sparks both
		// silently did nothing. Reset lives in destroyPanels, next to the arrays
		// it was built alongside.
		mFlipCard  = -1;
		mFlipTics  = 0;
		mLockTics  = int(cv("wr_locktics", 140));


		// Claim the sticks. Snap turn and stick movement are decided in the VR
		// input path before any script sees a button, so without this the same
		// thumbstick that is picking a card also spins and walks you.
		level.SuppressVRInput(true);
		engineLaser(true);

		bulletTime(true);

		spawnCentre(pmo);
		layout(pmo);

		// Declared once, resolved per frame. The engine's growth curve eases out
		// with a slight overshoot, which is the little bounce a card gets as it
		// settles -- and it is not a parameter, which is fine: it is a better
		// curve than the cubic that used to be here and it runs at the
		// renderer's rate rather than at script's 35Hz.
		int growTics = int(cv("wr_growtics", 6.0));
		if (growTics > 0)
		{
			for (int i = 0; i < mGroups.Size(); ++i)
			{
				level.AnimateBillboardGroup(mGroups[i], 0.0, 1.0, growTics);
			}
			if (mCentreGroup != 0) level.AnimateBillboardGroup(mCentreGroup, 0.0, 1.0, growTics);
		}

		feedback(Sound("wristrig/open"), 0.40, 55);

		// WHAT ACTUALLY GOT BUILT, in one line.
		//
		// Deliberately narrow. Anything that fails LOUDLY -- a ring that does
		// not appear, a card in the wrong place -- needs no print, and a print
		// per event is how the console became noise the first time.
		//
		// These are the failures you cannot see. A canvas face falls back to a
		// composed one without a word, so "wr_canvas on and it looks identical"
		// reads exactly like "on and working subtly". An icon that resolves to
		// nothing leaves a blank card with no clue whether the weapon has no
		// pickup sprite or the lookup broke. Counting them is the difference
		// between a diagnosis and another round of guessing.
		if (cv("wr_debug", 0.0) > 0.0)
		{
			int faces = 0, icons = 0;
			for (int i = 0; i < mFaces.Size(); ++i)  { if (mFaces[i] != 0) ++faces; }
			for (int i = 0; i < mIcons.Size(); ++i)  { if (mIcons[i] != 0) ++icons; }

			bool wantCanvas = cv("wr_canvas", 0.0) > 0.0;

			Console.Printf(
				"\c[Gold]WRISTRIG\c- %d cards | plate %s | faces %d/%d%s | icons %d | hand %s",
				mIds.Size(),
				(plateKind() == LevelLocals.BB_SDFPANEL) ? "sdf" : "sampled",
				faces, wantCanvas ? min(mIds.Size(), FACE_POOL) : 0,
				(wantCanvas && faces == 0) ? " \c[Red]NONE PAINTED\c-" : "",
				icons,
				(mRigHand == 1) ? "off" : "main");

			// Named separately because it is the one with a known cause and a
			// known fix, rather than a number to interpret.
			if (wantCanvas && faces == 0)
			{
				Console.Printf("\c[Gold]WRISTRIG\c- canvas returned nothing: "
					"WRFACEnn undeclared, or animdefs.txt not loaded");
			}
			if (wantCanvas && mIds.Size() > FACE_POOL)
			{
				Console.Printf("\c[Gold]WRISTRIG\c- %d cards past the pool of %d "
					"fell back to composed faces", mIds.Size() - FACE_POOL, FACE_POOL);
			}
		}
	}

	// quiet is for the close that follows a commit, which has already made the
	// louder noise of its own -- two sounds a frame apart read as a stutter.
	private void closeRig(bool quiet = false)
	{
		if (!quiet) feedback(Sound("wristrig/close"), 0.18, 35);

		// THE RING FOLDS AWAY RATHER THAN BLINKING OUT.
		//
		// Everything that belongs to the PLAYER is handed back on this tic --
		// the weapon, the laser, the sticks, bullet time. None of that may wait
		// on an animation; a gun you cannot fire for a fifth of a second because
		// a menu is still playing is a menu that got you killed.
		//
		// Only the billboards linger. The group is told to collapse to zero and
		// the handles are destroyed CLOSE_TICS later by the tick, which is what
		// a group scaled to zero is for: it draws nothing, so the last frame is
		// empty whether or not the destroy has landed yet.
		if (!mHardClose && mIds.Size() > 0 && CLOSE_TICS > 0)
		{
			for (int i = 0; i < mGroups.Size(); ++i)
			{
				level.AnimateBillboardGroup(mGroups[i], 1.0, 0.0, CLOSE_TICS);
			}
			if (mCentreGroup != 0) level.AnimateBillboardGroup(mCentreGroup, 1.0, 0.0, CLOSE_TICS);
			if (mFanGroup != 0)    level.AnimateBillboardGroup(mFanGroup,    1.0, 0.0, CLOSE_TICS);

			mClosingTics = CLOSE_TICS;

			// The playsim half of the close happens now regardless.
			let pmoNow = players[consoleplayer].mo;
			engineLaser(false);
			level.SuppressVRInput(false);
			bulletTime(false);
			releaseDecor();

			mOpen     = false;
			mHovered  = 0;
			mTouching = false;
			return;
		}

		clearCardModels();
		destroyPanels();
	}

	// Every billboard and every group, gone. Split out of closeRig because the
	// collapse animation needs a second, later place to call it from -- and
	// because a half-freed ring is the one state nothing else here can handle.
	private void destroyPanels()
	{
		for (int i = 0; i < mIds.Size(); ++i)
		{
			if (mIds[i]) level.RemoveBillboard(mIds[i]);
		}
		for (int i = 0; i < mPlates.Size(); ++i)
		{
			if (mPlates[i]) level.RemoveBillboard(mPlates[i]);
		}
		for (int i = 0; i < mLabels.Size(); ++i)
		{
			if (mLabels[i]) level.RemoveBillboard(mLabels[i]);
		}
		for (int i = 0; i < mIcons.Size(); ++i)
		{
			if (mIcons[i]) level.RemoveBillboard(mIcons[i]);
		}
		for (int i = 0; i < mAmmos.Size(); ++i)
		{
			if (mAmmos[i]) level.RemoveBillboard(mAmmos[i]);
		}
		for (int i = 0; i < mAccents.Size(); ++i)
		{
			if (mAccents[i]) level.RemoveBillboard(mAccents[i]);
		}
		for (int i = 0; i < mGauges.Size(); ++i)
		{
			if (mGauges[i]) level.RemoveBillboard(mGauges[i]);
		}
		for (int i = 0; i < mFaces.Size(); ++i)
		{
			if (mFaces[i]) level.RemoveBillboard(mFaces[i]);
		}
		for (int i = 0; i < mMarks.Size(); ++i)
		{
			if (mMarks[i]) level.RemoveBillboard(mMarks[i]);
		}
		if (mCentreId)    level.RemoveBillboard(mCentreId);
		if (mCentreIcon)  level.RemoveBillboard(mCentreIcon);
		if (mCentreLabel) level.RemoveBillboard(mCentreLabel);
		mCentreId = mCentreIcon = mCentreLabel = 0;

		// Groups LAST, and not optional. A member left pointing at a dead group
		// silently snaps back to full size, so releasing them is the correct way
		// to end a group's life rather than tidy-up nobody would miss.
		for (int i = 0; i < mGroups.Size(); ++i)
		{
			if (mGroups[i]) level.RemoveBillboardGroup(mGroups[i]);
		}
		mMarks.Clear();
		mGroups.Clear();

		if (mCentreGroup != 0) level.RemoveBillboardGroup(mCentreGroup);
		mCentreGroup = 0;

		let pmo = players[consoleplayer].mo;

		engineLaser(false);
		level.SuppressVRInput(false);
		bulletTime(false);
		releaseDecor();

		collapseSlot();

		mIds.Clear();
		mPlates.Clear();
		mLabels.Clear();
		mIcons.Clear();
		mAmmos.Clear();
		mAccents.Clear();
		mGauges.Clear();
		mFaces.Clear();
		mCardX.Clear(); mCardY.Clear(); mCardZ.Clear();
		mMarks.Clear();
		mBaseColor.Clear();
		mIconW.Clear();
		mIconH.Clear();
		mLabelH.Clear();
		mTypes.Clear();
		mCardSlots.Clear();
		mTouching  = false;
		mOpen      = false;
		mOpenTics  = 0;
		mHovered   = 0;
		mDwellTics = 0;
	}

	// THE RIG NO LONGER TOUCHES THE HELD WEAPON AT ALL.
	//
	// It used to shrink it to half while the ring was up, to get the gun out of
	// the way of the hand being used as a cursor and to mark the mode. Neither
	// is needed: the ring floats a metre out in front, so the gun is not in the
	// way of anything, and the ring itself is a perfectly clear statement that
	// the rig is open.
	//
	// It also carried the worst bug in the mod. psp.scale belongs to the
	// psprite LAYER, and SetPsprite reuses that layer rather than building a
	// new one, so a scale applied by the rig survived the weapon changing
	// underneath it -- and every commit compounded it. Half, quarter, eighth.
	//
	// Gone with it: mSavedScale, mHaveSavedScale, the capture guard, the
	// per-tic re-assert, the restore on all three close paths, and
	// wr_weaponshrink. Nothing in the rig writes to a psprite any more.

	// Nothing else clears the suppression flag, and a stuck one is a player who
	// cannot turn with nothing to blame -- so it is released on every way out of
	// a level, not just the tidy one.
	// Set before ANY handler's WorldLoaded runs, which is the only moment it can
	// matter.
	//
	// BulletTimeX reads bt_adrenaline_unlimited exactly once, in its own
	// WorldLoaded, and caches it. Flipping the cvar when the wheel opens is
	// therefore a no-op -- it was read minutes ago. Adrenaline is a countdown, so
	// without this the world speeds back up underneath you mid-choice.
	//
	// The cost, stated plainly: bullet time you start yourself with its own key
	// becomes unlimited too. There is no way to scope it tighter without holding
	// a reference to the BulletTime class, and that would make BulletTimeX a hard
	// dependency of this wheel -- it would not compile without it.
	override void OnRegister()
	{
		if (!cvBool("wr_bullettime", true)) return;

		let unl = CVar.FindCVar("bt_adrenaline_unlimited");
		if (unl != null) unl.SetInt(1);
	}

	override void WorldUnloaded(WorldEvent e) { closeRig(); level.SuppressVRInput(false); }
	override void PlayerDied(PlayerEvent e)  { closeRig(); level.SuppressVRInput(false); }

	// Open on level start while iterating, so testing a change is one launch
	// instead of a launch and a keypress.
	//
	// Armed here, fired from WorldTick rather than opened here directly:
	// WorldLoaded can land before the pawn counts as PST_LIVE, and openRig bails
	// on that -- which looks exactly like the rig being broken.
	override void WorldLoaded(WorldEvent e)
	{
		// Order matters. migrateConfig WRITES user cvars, and a write that fails
		// takes the rest of this function with it -- so the auto-open flag was
		// never reached and the rig only ever opened by hand. Arm first, then do
		// anything that can go wrong.
		mWantAutoOpen = true;
		mWantAutoOpen = cvBool("wr_autoopen", true);

		migrateConfig();
	}

	// Geometry generation. Bump this whenever the numbers below change and every
	// existing config picks them up once, automatically.
	const CFG_VERSION = 17;

	private void migrateConfig()
	{
		let stamp = CVar.GetCVar("wr_cfgver", players[consoleplayer]);
		if (stamp == null || stamp.GetInt() >= CFG_VERSION) return;

		setCv("wr_panel_w", 3.5);
		setCv("wr_panel_h", 2.5);
		setCv("wr_radius",  5.0);
		setCv("wr_rise",    2.0);
		// wr_span, wr_phase and wr_follow were migrated here until the layout
		// moved from an arc to fixed bearings. Nothing reads them now and the
		// cvars are gone; an archived value left in someone's config is inert.
		setCv("wr_tilt",   12.0);

		// Gen 16: real models default ON. A changed DEFAULT can never reach
		// anyone who has already loaded the mod -- the cvar was written to their
		// config the first time and the saved value wins forever -- so turning
		// it on means rewriting it here once, which is the entire reason this
		// stamp exists.
		setCv("wr_models", 0);
		setCv("wr_touch",   7.0);
		setCv("wr_forward", 34.0);
		setCv("wr_bullettime", 1);
		setCv("wr_roll",    0.0);

		stamp.SetInt(CFG_VERSION);
		Console.Printf("\c[Gold]WRISTRIG\c- geometry updated to gen %d", CFG_VERSION);
	}

	private static void setCv(string name, double value)
	{
		let c = CVar.GetCVar(name, players[consoleplayer]);
		if (c != null) c.SetFloat(value);
	}

	// Reads a user cvar, falling back rather than aborting. GetCVar returns null
	// for anything the config has never seen, and GetFloat on null kills the VM.
	private static double cv(string name, double fallback)
	{
		let c = CVar.GetCVar(name, players[consoleplayer]);
		return (c == null) ? fallback : c.GetFloat();
	}

	// A bool cvar holds an int, and GetFloat on one returns zero -- which is why
	// wr_autoopen read false no matter what it was set to.
	private static bool cvBool(string name, bool fallback)
	{
		let c = CVar.GetCVar(name, players[consoleplayer]);
		return (c == null) ? fallback : (c.GetInt() != 0);
	}

	//==========================================================================
	// What goes on the rig
	//==========================================================================

	// Walked straight off WeaponSlots rather than sorted out of AllActorClasses.
	// Slots 1..9 then 0 is already the order the player thinks in, so there is
	// nothing to sort.
	// ONE CARD PER SLOT, at a FIXED cell.
	//
	// Filling cells left to right in pickup order meant the shotgun moved every
	// time you found something new, so nothing could ever be learned by feel.
	// Binding a slot to a cell fixes that: slot 1 is top left forever, whether
	// or not you own anything in slots 2 through 7.
	//
	// The card's face is the slot's first admissible weapon -- what you would
	// get by taking the slot outright. The rest of that slot lives behind it.
	private void gatherWeapons(PlayerPawn pmo)
	{
		mTypes.Clear();
		mCardSlots.Clear();

		let slots = players[consoleplayer].weapons;
		if (slots == null) return;

		// Every slot Doom has, not the eight a 3x3 happened to hold. Slot 0 is
		// walked last because that is where the engine's own cycling puts it.
		for (int pass = 0; pass < 10; ++pass)
		{
			int slot = (pass == 9) ? 0 : pass + 1;

			int n = slots.SlotSize(slot);

			for (int j = 0; j < n; ++j)
			{
				Class<Weapon> type = slots.GetWeapon(slot, j);
				if (type == null) continue;

				let held = Weapon(pmo.FindInventory(type));
				if (held == null) continue;

				// A weapon the rig hand is forbidden to hold would be a card
				// that does nothing when touched, so it does not get one.
				if (held.bNoHandSwitch && held.bOffhandWeapon != (mRigHand == 1)) continue;

				mTypes.Push(type);
				mCardSlots.Push(slot);

				// FANS, OR EVERYTHING ON THE RING.
				//
				// With fans on, a slot puts its FIRST admissible weapon on the
				// ring and the rest unfold out of it on dwell. That keeps the
				// ring at one card per slot, which is what makes its bearings
				// learnable by feel -- slot 4 is in the same direction whether
				// you own one weapon in it or five.
				//
				// With fans off, every weapon gets its own card and the ring
				// simply grows. It can afford to: the radius already scales with
				// the count so the chord between neighbours stays above a card
				// width, and nothing about the layout assumes eight. What you
				// give up is the fixed bearing -- picking up a second plasma
				// rifle now moves everything after it round the ring.
				//
				// Worth having both. One is learnable, the other is one reach
				// instead of a dwell and a reach.
				if (cv("wr_subcards", 1.0) > 0.0) break;
			}
		}
	}

	// Every weapon of one slot this hand may take, in slot order.
	private void slotWeapons(PlayerPawn pmo, int slot, out Array<Class<Weapon> > into)
	{
		into.Clear();

		let slots = players[consoleplayer].weapons;
		if (slots == null) return;

		int n = slots.SlotSize(slot);
		for (int j = 0; j < n; ++j)
		{
			Class<Weapon> type = slots.GetWeapon(slot, j);
			if (type == null) continue;

			let held = Weapon(pmo.FindInventory(type));
			if (held == null) continue;
			if (held.bNoHandSwitch && held.bOffhandWeapon != (mRigHand == 1)) continue;

			into.Push(type);
		}
	}

	// Fans a slot's other weapons out of its card.
	//
	// OVERLAYS rather than replaces: the eight slot cards stay where they are,
	// so the thing you opened is still visibly the thing you opened, and moving
	// away is the whole of backing out -- no gesture to learn, nothing to undo.
	//
	// A slot holding one weapon never expands. A submenu with a single entry is
	// a step that exists only to be dismissed.
	private void expandSlot(PlayerPawn pmo, int cardIndex)
	{
		collapseSlot();
		if (cardIndex < 0 || cardIndex >= mCardSlots.Size()) return;

		Array<Class<Weapon> > variants;
		slotWeapons(pmo, mCardSlots[cardIndex], variants);
		if (variants.Size() < 2) return;

		mExpanded = cardIndex;

		// The face weapon is already on the slot card, so the fan is everything
		// after it.
		// The whole fan is ONE group, so it unfolds as a unit out of the card
		// that opened it rather than as four independent things that happen to
		// appear together.
		if (mFanGroup != 0) level.RemoveBillboardGroup(mFanGroup);
		mFanGroup = level.AddBillboardGroup((0, 0, 0));

		for (int i = 1; i < variants.Size(); ++i)
		{
			let held = Weapon(pmo.FindInventory(variants[i]));
			if (held == null) continue;

			mSubTypes.Push(variants[i]);

			int sid = level.AddBillboardPersistent(
				(0, 0, 0), 3.5, 2.5, 0, 0,
				LevelLocals.BBF_FIXED, LevelLocals.BB_PANEL, 0,
				COLOR_SUB, 0, 0, "");
			level.SetBillboardGradient(sid, GRAD_IDLE);
			level.SetBillboardGroup(sid, mFanGroup);
			mSubIds.Push(sid);

			TextureID icon = iconFor(held);
			double sw = ICON_W_FRAC, sh = ICON_H_FRAC;
			// Braced deliberately: a bracketed multi-assign as an unbraced if body
			// starts a statement with '[', which the parser reads as the start of
			// an array rather than as a destructuring assignment.
			if (icon.IsValid())
			{
				[sw, sh] = fitIcon(icon, ICON_W_FRAC, ICON_H_FRAC);
			}

			mSubIconW.Push(sw);
			mSubIconH.Push(sh);

			int siid = 0;
			if (icon.IsValid())
			{
				siid = level.AddBillboardPersistent(
					(0, 0, 0), 3.5, 2.5, 0, 0,
					LevelLocals.BBF_FIXED, LevelLocals.BB_TEXTURE, icon.GetIndex(),
					0xFFFFFF, LevelLocals.BBFL_NOHIT, 0, "");
				level.SetBillboardGroup(siid, mFanGroup);
			}
			mSubIcons.Push(siid);

			// The variants in a slot are the same GUN in different states, so the
			// count under each is often the only thing telling them apart.
			int srounds = ammoLeft(held);
			int said = 0;
			if (cv("wr_ammo", 1.0) > 0.0 && srounds >= 0)
			{
				said = level.AddBillboardPersistent(
					(0, 0, 0), 3.5, 2.5, 0, 0,
					LevelLocals.BBF_FIXED, LevelLocals.BB_SEGMENT, 0,
					srounds > 0 ? COLOR_AMMO : COLOR_AMMO_DRY,
					LevelLocals.BBFL_NOHIT, 0, String.Format("%d", srounds));
				level.SetBillboardGroup(said, mFanGroup);
			}
			mSubAmmos.Push(said);

			int slid = level.AddBillboardPersistent(
				(0, 0, 0), 3.5, 2.5, 0, 0,
				LevelLocals.BBF_FIXED, LevelLocals.BB_TEXT, 0,
				COLOR_LABEL, LevelLocals.BBFL_NOHIT, 0, held.GetTag());
			level.SetBillboardGroup(slid, mFanGroup);
			mSubLabels.Push(slid);
		}

		// Unfold. Same declaration-not-a-state-machine deal as the ring.
		int fanTics = int(cv("wr_growtics", 6.0));
		if (fanTics > 0 && mSubIds.Size() > 0)
		{
			level.AnimateBillboardGroup(mFanGroup, 0.0, 1.0, fanTics);
		}
	}

	private void collapseSlot()
	{
		for (int i = 0; i < mSubIds.Size(); ++i)
		{
			if (mSubIds[i]) level.RemoveBillboard(mSubIds[i]);
		}
		for (int i = 0; i < mSubIcons.Size(); ++i)
		{
			if (mSubIcons[i]) level.RemoveBillboard(mSubIcons[i]);
		}
		for (int i = 0; i < mSubAmmos.Size(); ++i)
		{
			if (mSubAmmos[i]) level.RemoveBillboard(mSubAmmos[i]);
		}
		for (int i = 0; i < mSubLabels.Size(); ++i)
		{
			if (mSubLabels[i]) level.RemoveBillboard(mSubLabels[i]);
		}
		// The group goes with its members, or the next fan inherits a live
		// animation from the last one.
		if (mFanGroup != 0) level.RemoveBillboardGroup(mFanGroup);
		mFanGroup = 0;

		mSubIds.Clear();
		mSubIcons.Clear();
		mSubAmmos.Clear();
		mSubLabels.Clear();
		mSubIconW.Clear();
		mSubIconH.Clear();
		mSubTypes.Clear();
		mExpanded = -1;
	}

	// True when this billboard belongs to the open fan or to the card that
	// opened it -- i.e. hovering it should NOT collapse the fan.
	// Which card the stick is pointing at, or 0 if it is near centre.
	//
	// The ring's bearings are laid out in the view plane -- x across, z up --
	// which is exactly the plane a thumbstick lives in, so the mapping is one
	// atan2 and a nearest-bearing search. No cursor to steer and nothing to
	// overshoot: a direction IS a slot.
	private int stickPick(PlayerPawn pmo)
	{
		int n = mIds.Size();
		if (n == 0) return 0;

		double sx = players[consoleplayer].cmd.sidemove;
		double sy = players[consoleplayer].cmd.forwardmove;

		double dead = cv("wr_stickdead", 3000.0);
		if (sx * sx + sy * sy < dead * dead) return 0;

		double want = atan2(sy, sx);

		int best = 0;
		double bestOff = 999;

		for (int i = 0; i < n; ++i)
		{
			double d = want - bearingForIndex(i, n);
			while (d >  180) d -= 360;
			while (d < -180) d += 360;
			d = abs(d);

			if (d < bestOff) { bestOff = d; best = mIds[i]; }
		}
		return best;
	}

	// BulletTimeX, if it happens to be loaded.
	//
	// Deliberately fire-and-forget: sending its netevent by name means no class
	// reference, so this compiles and runs identically whether or not the mod is
	// present -- a hard type reference would make BulletTimeX a dependency of
	// the wheel, which is exactly what a hook should not do.
	//
	// bt_activate is a TOGGLE, so opening the rig while bullet time is already
	// running by your own hand will cancel it. Off by default for that reason.
	private void bulletTime(bool on)
	{
		if (!cvBool("wr_bullettime", true)) return;
		if (on == mBtOn) return;

		EventHandler.SendNetworkEvent("bt_activate");
		mBtOn = on;
	}

	private void tintCard(int id, bool lit)
	{
		if (id == 0) return;

		int card = cardIndexOf(id);
		if (card >= 0 && card < mPlates.Size())
		{
			// Unlit goes back to the card's OWN resting colour, not the shared
			// one -- otherwise hovering a dry weapon and moving off it quietly
			// repaints it as a full one, and the warning is gone for good.
			int rest = (card < mBaseColor.Size()) ? mBaseColor[card] : COLOR_IDLE;
			level.UpdateBillboard(mPlates[card], 0, lit ? COLOR_HOVER : rest);

			// The gradient's far end moves with the near end, or a lit card gets
			// a gold top fading into the resting card's dark blue bottom.
			level.SetBillboardGradient(mPlates[card],
				lit ? GRAD_HOVER : (rest == COLOR_DRY ? GRAD_DRY : GRAD_IDLE));
			return;
		}

		int sub = subIndexOf(id);
		if (sub >= 0) level.UpdateBillboard(id, 0, lit ? COLOR_HOVER : COLOR_SUB);
	}

	private int cardIndexOf(int id) const
	{
		for (int i = 0; i < mIds.Size(); ++i)
		{
			if (mIds[i] == id) return i;
		}
		return -1;
	}

	private int subIndexOf(int id) const
	{
		for (int i = 0; i < mSubIds.Size(); ++i)
		{
			if (mSubIds[i] == id) return i;
		}
		return -1;
	}

	// Where a fan hangs: outward from the grid's centre, through the card that
	// opened it, and onward. That keeps it clear of the other seven slots, and
	// it means the fan always grows away from your hand rather than back across
	// the cards you were choosing between.
	// The fan's group origin is its PARENT CARD, so the unfold happens out of
	// the card you opened rather than out of the middle of the fan.
	private void layoutExpansion(double base, double spread, Vector3 cardPos, Vector3 viewRight,
	                             double faceYaw, double tilt, double panelW, double panelH,
	                             double cellW)
	{
		if (mExpanded < 0 || mSubIds.Size() == 0) return;

		if (mFanGroup != 0) level.SetBillboardGroupOrigin(mFanGroup, cardPos);

		// Three bearings fanned about the slot's own -- outward and to either
		// side. Outward IS the free space, so a fan can never cross a neighbour;
		// and the spread narrows as the ring gets busier so it still cannot when
		// the neighbours are close.
		Vector3 lift = (cos(faceYaw), sin(faceYaw), 0) * LABEL_LIFT;

		for (int i = 0; i < mSubIds.Size(); ++i)
		{
			double a = base + spread - (i % 3) * spread;

			// Anything past the first three stacks further out along the same
			// bearing rather than wrapping back into the grid.
			double reach = cellW * (1 + i / 3);

			Vector3 pos = cardPos
			            + viewRight * (cos(a) * reach)
			            + (0, 0, sin(a) * reach);

			level.MoveBillboard(mSubIds[i], pos);
			level.ResizeBillboard(mSubIds[i], panelW, panelH);
			level.OrientBillboard(mSubIds[i], faceYaw, tilt, LevelLocals.BBF_FIXED);

			if (i < mSubIcons.Size() && mSubIcons[i] != 0)
			{
				level.MoveBillboard(mSubIcons[i], pos + lift + (0, 0, panelH * 0.20));
				level.ResizeBillboard(mSubIcons[i], panelW * mSubIconW[i],
				                                    panelH * mSubIconH[i]);
				level.OrientBillboard(mSubIcons[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
			}
			if (i < mSubLabels.Size() && mSubLabels[i] != 0)
			{
				level.MoveBillboard(mSubLabels[i], pos + lift - (0, 0, panelH * 0.22));
				level.ResizeBillboard(mSubLabels[i], panelW, panelH * LABEL_HEIGHT_FRAC);
				level.OrientBillboard(mSubLabels[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
			}
			if (i < mSubAmmos.Size() && mSubAmmos[i] != 0)
			{
				level.MoveBillboard(mSubAmmos[i], pos + lift - (0, 0, panelH * 0.40));
				level.ResizeBillboard(mSubAmmos[i], panelW, panelH * AMMO_H_FRAC);
				level.OrientBillboard(mSubAmmos[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
			}
		}
	}

	private bool belongsToExpansion(int id) const
	{
		if (mExpanded < 0) return false;
		if (mExpanded < mIds.Size() && mIds[mExpanded] == id) return true;

		for (int i = 0; i < mSubIds.Size(); ++i)
		{
			if (mSubIds[i] == id) return true;
		}
		return false;
	}

	// Slot number to grid cell, CLOCKWISE around the ring:
	//
	//   1 2 3
	//   8 . 4
	//   7 6 5
	//
	// Row-major numbering would put slot 4 on the left and slot 5 on the right,
	// which reads as two half-rows rather than one ring. Going round means every
	// slot has a compass bearing, and that bearing is what its variant fan grows
	// along -- so a fan can never cross another slot.
	// A RING OF N, not a 3x3 of eight.
	//
	// Eight slots on a 3x3 was the shape that fit, not the shape that is right:
	// it caps at eight, and its corners sit 1.41x further out than its edges, so
	// the "ring" is really a squashed box. Spacing them evenly round a circle
	// costs nothing, holds any number, and puts every card the same reach away.
	//
	// At eight it lands on the same compass bearings as before -- 135 for the
	// first, 45 degrees apart, clockwise -- so nothing about the feel changes at
	// the count you have been testing.
	private static double bearingForIndex(int i, int count)
	{
		if (count < 1) count = 1;
		return 135.0 - i * (360.0 / count);
	}

	// How far a fan spreads either side of its slot's bearing. Capped at 45, but
	// squeezed as the ring gets crowded so a fan cannot reach into the next
	// slot's territory.
	private static double fanSpread(int count)
	{
		if (count < 1) count = 1;
		double half = (360.0 / count) * 0.5;
		return min(45.0, half * 0.9);
	}

	// The centre cell: what this hand is already holding.
	//
	// BBFL_NOHIT throughout -- it is a readout, not a choice. Reaching into the
	// middle is how you say "never mind", and it should not be possible to
	// re-select what you already have by accident.
	// AltHUDIcon first, pickup Icon second.
	//
	// That is what BaseStatusBar.GetInventoryIcon(DI_ALTICONFIRST) does, but the
	// native is ui-scoped and everything here runs in the playsim -- so it reads
	// the two fields off Inventory itself, which are plain TextureIDs and carry
	// no scope restriction at all.
	// Pull the graphic a named state actually draws. GetSpriteTextureID() reads
	// the actor's LIVE sprite, and a weapon sitting in your backpack is not
	// animating -- so for most of them that call returns nothing and the card
	// comes out blank. The state's own sprite/frame pair is fixed at compile
	// time and does not care what the actor is doing.
	private static TextureID spriteOf(Actor a, StateLabel which)
	{
		TextureID none;
		none.SetInvalid();
		if (a == null) return none;

		State st = a.FindState(which);
		if (st == null || !st.ValidateSpriteFrame()) return none;

		TextureID tex;
		bool mirror;
		Vector2 scale;
		[tex, mirror, scale] = st.GetSpriteTexture(0);
		return tex;
	}

	private static TextureID iconFor(Inventory it)
	{
		TextureID none;
		none.SetInvalid();
		if (it == null) return none;

		// The pickup sprite -- the thing you'd see lying on the floor. This is
		// what a weapon is recognisable AS, so it leads.
		TextureID pickup = spriteOf(it, 'Spawn');
		if (pickup.IsValid()) return pickup;

		// Mods that bothered to author a real icon get it honoured next.
		if (it.AltHUDIcon.IsValid()) return it.AltHUDIcon;
		if (it.Icon.IsValid())       return it.Icon;

		// Fist and friends never spawn in the world and have no pickup sprite at
		// all. Their held graphic is the only picture of them that exists.
		TextureID ready = spriteOf(it, 'Ready');
		if (ready.IsValid()) return ready;

		return it.GetSpriteTextureID(0);
	}

	private void spawnCentre(PlayerPawn pmo)
	{
		mCentreId = mCentreIcon = mCentreLabel = 0;

		let held = (mRigHand == 1) ? players[consoleplayer].OffhandWeapon
		                           : players[consoleplayer].ReadyWeapon;

		// AN EMPTY HAND STILL GETS A CENTRE.
		//
		// This used to return here, so summoning the rig on a bare off hand gave
		// a ring with a hole in the middle: no anchor to read the bearings
		// against, and no statement of what "do nothing" would leave you with.
		// The centre is the neutral option, and neutral is a real answer even
		// when the answer is nothing.
		mCentreId = level.AddBillboardPersistent(
			(0, 0, 0), 3.5, 2.5, 0, 0,
			LevelLocals.BBF_FIXED, LevelLocals.BB_PANEL, 0,
			COLOR_CENTRE, LevelLocals.BBFL_NOHIT, 0, "");
		level.SetBillboardGradient(mCentreId, GRAD_CENTRE);

		mCentreGroup = level.AddBillboardGroup((0, 0, 0));
		level.SetBillboardGroup(mCentreId, mCentreGroup);

		mCentreIconW = ICON_W_FRAC;
		mCentreIconH = ICON_H_FRAC;

		if (held != null)
		{
			TextureID icon = iconFor(held);
			if (icon.IsValid())
			{
				[mCentreIconW, mCentreIconH] = fitIcon(icon, ICON_W_FRAC, ICON_H_FRAC);

				mCentreIcon = level.AddBillboardPersistent(
					(0, 0, 0), 3.5, 2.5, 0, 0,
					LevelLocals.BBF_FIXED, LevelLocals.BB_TEXTURE, icon.GetIndex(),
					0xFFFFFF, LevelLocals.BBFL_NOHIT, 0, "");
				level.SetBillboardGroup(mCentreIcon, mCentreGroup);
			}
		}

		string centreTag = (held != null) ? held.GetTag() : "Empty";

		mCentreLabel = level.AddBillboardPersistent(
			(0, 0, 0), 3.5, 2.5, 0, 0,
			LevelLocals.BBF_FIXED, LevelLocals.BB_TEXT, 0,
			COLOR_CENTRE_TEXT, LevelLocals.BBFL_NOHIT, 0, centreTag);
		level.SetBillboardGroup(mCentreLabel, mCentreGroup);
	}

	// How many rounds this weapon can fire right now, or -1 for one that does not
	// use ammo at all.
	//
	// Ammo1 is the field, and it is only populated once the weapon has been
	// picked up -- which every weapon on a card has been, since the card only
	// exists because FindInventory returned it.
	private static int ammoLeft(Weapon w)
	{
		if (w == null || w.Ammo1 == null) return -1;
		return w.Ammo1.Amount;
	}

	// The size to draw an icon at so it keeps its shape inside a box, returned as
	// FRACTIONS of the card so it survives wr_scale changing under it.
	//
	// Every icon used to be stretched to the same rectangle, so a rocket launcher
	// and a pistol came out identically proportioned -- which defeats the point
	// of showing a picture at all, on a ring whose whole premise is being
	// readable at a glance.
	//
	// The 1.2 is the billboard vertical stretch: the view matrix stretches world
	// Z and the billboard path never unstretches it, so an authored square
	// renders as a tall rectangle. Undo it here or "keeps its shape" is a lie.
	private static double, double fitIcon(TextureID tex, double boxWFrac, double boxHFrac)
	{
		Vector2 sz = TexMan.GetScaledSize(tex);
		if (sz.X <= 0.0 || sz.Y <= 0.0) return boxWFrac, boxHFrac;

		// Card aspect in the same units the fractions are in.
		double aspect = sz.X / sz.Y;

		double w = boxWFrac;
		double h = (w * (PANEL_W / PANEL_H)) / (aspect * CARD_STRETCH);

		if (h > boxHFrac)
		{
			h = boxHFrac;
			w = h * aspect * CARD_STRETCH * (PANEL_H / PANEL_W);
		}
		return w, h;
	}

	// One colour per slot, matching the engine's own vr_laser_color_slotN idea.
	//
	// A slot's bearing is already fixed so the ring can be learned by feel; a
	// fixed colour is the same promise made to the eye. It also means the beam
	// and the card it lands on can agree, which is the difference between a
	// pointer that indicates and one that merely reaches.
	private static color slotColor(int slot)
	{
		switch (slot)
		{
			case 1: return 0x8A8F98;   // fist, chainsaw -- no ammo, so no hue
			case 2: return 0xE8C547;
			case 3: return 0xE07A3E;
			case 4: return 0x4FA3D1;
			case 5: return 0xD1503F;
			case 6: return 0x7B5FD1;
			case 7: return 0x3FBF6F;
			case 8: return 0xD14F9B;
			case 9: return 0x46C6C0;
		}
		return 0x8A8F98;              // slot 0 and anything a mod invented
	}

	// Ammo as a fraction of capacity, or -1 for a weapon that uses none.
	private static double ammoFrac(Weapon w)
	{
		if (w == null || w.Ammo1 == null) return -1.0;
		int cap = w.Ammo1.MaxAmount;
		if (cap <= 0) return -1.0;
		return clamp(double(w.Ammo1.Amount) / cap, 0.0, 1.0);
	}

	// The label height, as a fraction of the card, that keeps the name INSIDE
	// the card.
	//
	// Names are not a fixed length -- "Fist" and "Super Shotgun" were being
	// drawn at the same size in the same box, so one floated in space and the
	// other ran off both edges. MeasureBillboardText knows the real advance of
	// the face it will actually draw in, which is the only way to get this
	// right: counting characters is correct for a monospace atlas and silently
	// wrong for every other, and the roster is reshuffled per game.
	//
	// Returns 0 from the engine when no SDF atlas is loaded. That means
	// "estimate it yourself", not "the string is empty", so it is left alone.
	private static double fitLabel(string text, double boxW, double panelH)
	{
		double h = panelH * LABEL_HEIGHT_FRAC;
		if (h <= 0.0) return LABEL_HEIGHT_FRAC;

		double w = level.MeasureBillboardText(text, h, 0);
		if (w <= 0.0) return LABEL_HEIGHT_FRAC;

		if (w > boxW) h *= boxW / w;
		return h / panelH;
	}

	// Which plate payload the cards are built from, and the shape numbers that
	// only the solved one reads.
	private static int plateKind()
	{
		return (cv("wr_sdf", 1.0) > 0.0) ? LevelLocals.BB_SDFPANEL
		                                 : LevelLocals.BB_PANEL;
	}

	// Corner radius in byte 0, border width in byte 1, each 0-15 across the
	// half-extent. BB_PANEL ignores it, which is why this can be handed to
	// both without a branch at every call site.
	private static int plateShape()
	{
		int rad = int(clamp(cv("wr_plate_radius", 4.0), 0.0, 15.0));
		int bor = int(clamp(cv("wr_plate_border", 2.0), 0.0, 15.0));
		return rad | (bor << 8);
	}

	// PAINT A CARD'S FACE INTO A CANVAS TEXTURE.
	//
	// The other way to build a card is the way this mod already does it: one
	// billboard per element, each positioned, oriented, rolled and scaled in
	// MAP UNITS every tic, with the layout expressed as fractions of the panel
	// tuned by eye. That works and it stays sharp, because the text payloads are
	// distance fields.
	//
	// This is the other option. Compose the face as an image, in ordinary 2D
	// pixel coordinates where "the bar sits eight pixels under the icon" is
	// eight pixels, and hand the card one texture. Anything drawable becomes a
	// card: a dial instead of a bar, a silhouette with marks over it, pips
	// instead of a number.
	//
	// The trade is real and it is why BOTH exist. A canvas is a RASTER -- held
	// close in VR it shows its pixels, where BB_SEGMENT never will. So the name
	// and the count stay as field billboards on top, and the canvas carries the
	// artwork underneath them.
	//
	// REPAINTED EVERY TIC, and that is not a choice.
	//
	// A canvas is a COMMAND QUEUE, not a picture. hw_entrypoint's update loop
	// does exactly this:
	//
	//     Draw2D(&canvas->Drawer, ...);
	//     canvas->Drawer.Clear();
	//
	// -- it plays the queue into the texture and then empties it. Meanwhile
	// binding the texture to draw a card re-flags it as needing an update. So a
	// canvas that stays on screen is re-rendered every frame from a queue that
	// is empty after the first one, and since these are translucent canvases the
	// engine clears them to transparent when there is nothing to draw.
	//
	// Painting once therefore gave exactly one good frame and then bare plates
	// for the rest of the ring's life, with the odd card catching whatever was
	// left in the framebuffer.
	//
	// Cheap enough: a few dozen queued 2D ops per card at 35Hz, for at most
	// twelve cards, and nothing here touches the playsim.
	// THE CANVAS SAMPLES UPSIDE DOWN.
	//
	// A canvas texture is rendered into an FBO and then read back as an ordinary
	// texture, and the V axis flips somewhere between those two -- so a face
	// painted the obvious way arrives on the card mirrored top to bottom. It is
	// invisible until there is content: an empty canvas looks identical either
	// way up, which is why this survived the first two passes and only showed
	// itself as an upside-down revolver.
	//
	// Everything below authors in NATURAL coordinates -- y=0 is the top of the
	// card as you look at it -- and these three convert. Doing it here rather
	// than pre-flipping every number means the layout still reads as the layout.
	private static int fy(int y) { return FACE_H - y; }

	// Clear takes a top and a bottom, and flipping swaps which is which.
	private void clearFlipped(Canvas c, int l, int t, int r, int b, color col)
	{
		c.Clear(l, fy(b), r, fy(t), col);
	}

	// Dim takes a top-left and a size, so only the origin moves.
	private void dimFlipped(Canvas c, color col, double amt, int x, int y, int w, int h)
	{
		c.Dim(col, amt, x, fy(y + h), w, h);
	}

	private TextureID paintFace(int pool, Weapon held, int slot, bool dry)
	{
		TextureID none;
		none.SetInvalid();

		string name = String.Format("WRFACE%02d", pool);

		let canvas = TexMan.GetCanvas(name);
		if (canvas == null) return none;   // not declared, or not a canvas

		// Without this the untouched corners come out opaque black instead of
		// letting the plate behind show through.
		TexMan.SetCanvasTextureTranslucent(name, true);

		int bg = dry ? COLOR_DRY : COLOR_IDLE;

		// The gradient, as bands. A canvas has no gradient primitive, and five
		// steps across a hundred pixels is under the eye's threshold at the size
		// a card is ever seen.
		for (int b = 0; b < FACE_BANDS; ++b)
		{
			int y0 = FACE_H * b / FACE_BANDS;
			int y1 = FACE_H * (b + 1) / FACE_BANDS;

			double k = 1.0 - 0.55 * (double(b) / (FACE_BANDS - 1));
			clearFlipped(canvas, 0, y0, FACE_W, y1, dim(bg, k));
		}

		// The slot's colour along the top edge, same promise the accent bar
		// makes on the composed card.
		clearFlipped(canvas, 0, 0, FACE_W, FACE_ACCENT, slotColor(slot));

		// THE GUN RUNS OFF THE EDGES.
		//
		// This is the one thing the billboard path cannot do at all. A billboard
		// has no clip -- a quad draws its whole texture -- so the composed card
		// can only ever SHRINK a sprite until it fits inside a box, which is why
		// every icon there sits politely in the middle looking like a catalogue
		// photo. A canvas crops. Draw the shotgun at 130% and its stock and
		// muzzle leave the card, and it reads as a weapon rather than a picture
		// of one.
		TextureID icon = iconFor(held);
		if (icon.IsValid())
		{
			Vector2 sz = TexMan.GetScaledSize(icon);
			double aspect = (sz.X > 0 && sz.Y > 0) ? (sz.X / sz.Y) : 1.6;

			double bleed = clamp(cv("wr_canvas_bleed", 1.30), 0.6, 2.5);
			double iw = FACE_W * bleed;
			double ih = iw / aspect;

			// Bleeding sideways is the good version; bleeding through the top
			// and bottom takes the whole silhouette away, so height is capped
			// and the width follows it back down.
			// Capped to the artwork band, not the whole canvas: the lower third is
			// the readouts and a sprite that reaches it is a sprite behind a label.
			double hcap = READOUT_TOP - PIP_TOP - 4;
			if (ih > hcap) { ih = hcap; iw = ih * aspect; }

			// DTA_CENTEROFFSET IS THE WHOLE REASON THE SPRITES WERE MISSING.
			//
			// A Doom sprite carries baked-in offsets, and a pickup's put its
			// origin at the item's FEET -- so the draw position is not the
			// top-left of the image, it is a point somewhere below and left of
			// it. Drawing at y=11 with an offset like that puts the entire
			// sprite off the top of a hundred-pixel canvas, silently, with the
			// call succeeding.
			//
			// Overriding to the texture's middle makes the position mean what it
			// looks like it means, and lets the same coordinate work for sprites
			// whose offsets disagree with each other -- which, across a weapon
			// set, they always do.
			double cx = FACE_W * 0.5;
			double cy = ICON_TOP + ICON_BOX_H * 0.5;

			// A dark twin, offset, underneath. Weapon sprites are lit every
			// which way across a weapon set; a shadow gives all of them the same
			// weight and lifts them off the plate.
			//
			// DTA_AlphaChannel with DTA_FillColor is the pair that gives a
			// silhouette; DTA_FillColor alone stencils the colour but keeps the
			// source's own shading, which is not a shadow.
			// DTA_FLIPY AS WELL AS A FLIPPED POSITION.
			//
			// Two separate corrections and both are needed. Moving the sprite to
			// fy(cy) puts it in the right PLACE on a canvas that samples upside
			// down; flipping the image is what stops the revolver arriving
			// barrel-up once it gets there. Fix only one and it is still wrong,
			// just wrong differently.
			//
			// The shadow is offset DOWNWARD on screen, which is upward here.
			if (cv("wr_canvas_shadow", 1.0) > 0.0)
			{
				canvas.DrawTexture(icon, false, cx + 3, fy(int(cy)) - 3,
					DTA_CenterOffset, true, DTA_FlipY, true,
					DTA_DestWidth, int(iw), DTA_DestHeight, int(ih),
					DTA_FillColor, 0x000000, DTA_AlphaChannel, true,
					DTA_Alpha, 0.5);
			}

			canvas.DrawTexture(icon, false, cx, fy(int(cy)),
				DTA_CenterOffset, true, DTA_FlipY, true,
				DTA_DestWidth, int(iw), DTA_DestHeight, int(ih));
		}

		// A band behind the lower third, where the name and the count are about
		// to be drawn as billboards. Without it a bled sprite runs straight
		// under the text and the text becomes unreadable on exactly the weapons
		// whose artwork works best.
		dimFlipped(canvas, 0x000000, 0.62, 0, READOUT_TOP, FACE_W, FACE_H - READOUT_TOP);

		// AMMO AS PIPS.
		//
		// A bar answers "how full"; pips answer "how many", and for a shotgun
		// with four shells left that is the question you are actually asking. A
		// count of twelve or under gets one pip per ROUND -- literally the shots
		// you have. Above that it falls to ten pips as tenths, because forty
		// individually countable rectangles is just a worse bar.
		int rounds = ammoLeft(held);
		double frac = ammoFrac(held);

		if (cv("wr_ammo", 1.0) > 0.0 && frac >= 0.0)
		{
			int lit, total;
			if (rounds >= 0 && rounds <= PIP_LITERAL_MAX)
			{
				total = max(rounds, 1);
				let capped = ammoCap(held);
				if (capped > 0 && capped <= PIP_LITERAL_MAX) total = capped;
				lit = rounds;
			}
			else
			{
				total = PIP_TENTHS;
				lit = int(frac * PIP_TENTHS + 0.5);
			}

			int left  = BAR_INSET;
			int right = FACE_W - BAR_INSET;
			int top   = PIP_TOP;
			int bot   = top + BAR_H;

			int gap = 2;
			int pipW = max(2, ((right - left) - gap * (total - 1)) / max(total, 1));

			for (int p = 0; p < total; ++p)
			{
				int x0 = left + p * (pipW + gap);
				int x1 = x0 + pipW;
				if (x1 > right) break;

				clearFlipped(canvas, x0, top, x1, bot,
					(p < lit) ? slotColor(slot) : dim(slotColor(slot), 0.18));
			}
		}

		// SCANLINES, over everything.
		//
		// One dimmed row every three. It is the cheapest possible trick and it
		// does more than any of the above to stop the face reading as a picture
		// pasted on a card and start it reading as a lit display.
		double scan = cv("wr_canvas_scan", 0.22);
		if (scan > 0.0)
		{
			for (int y = 0; y < FACE_H; y += 3)
			{
				dimFlipped(canvas, 0x000000, scan, 0, y, FACE_W, 1);
			}
		}

		// The slot's colour as a corner chevron as well as the top stripe, so
		// the ring is eight distinguishable SHAPES and not only eight hues --
		// which is what survives being in the corner of your eye.
		canvas.DrawThickLine(-4, fy(26), 30, fy(-8), 9, slotColor(slot), 255);

		// A hairline round the outside, so the artwork has an edge even when the
		// plate behind it is switched off.
		canvas.DrawLineFrame(dim(slotColor(slot), 0.45), 0, 0, FACE_W, FACE_H);

		return TexMan.CheckForTexture(name, TexMan.Type_Any);
	}

	// Re-queue every card's artwork. See the note on paintFace for why this
	// cannot be done once at open.
	private void repaintFaces(PlayerPawn pmo)
	{
		if (cv("wr_canvas", 0.0) <= 0.0) return;

		for (int i = 0; i < mFaces.Size() && i < mTypes.Size(); ++i)
		{
			if (mFaces[i] == 0) continue;

			let held = Weapon(pmo.FindInventory(mTypes[i]));
			if (held == null) continue;

			paintFace(i, held, mCardSlots[i], ammoLeft(held) == 0);
		}
	}

	// Magazine size, for deciding whether pips can be literal.
	private static int ammoCap(Weapon w)
	{
		if (w == null || w.Ammo1 == null) return -1;
		return w.Ammo1.MaxAmount;
	}

	// Scale a colour's channels without touching its alpha. Canvas.Clear wants
	// a packed ARGB and there is no multiply on a colour in ZScript.
	private static color dim(color c, double k)
	{
		k = clamp(k, 0.0, 1.0);
		int r = int(((c >> 16) & 0xFF) * k);
		int g = int(((c >>  8) & 0xFF) * k);
		int b = int(( c        & 0xFF) * k);
		return color(255, r, g, b);
	}

	private void spawnPanels()
	{
		mIds.Clear();
		mLabels.Clear();
		mIcons.Clear();
		mAmmos.Clear();
		mAccents.Clear();
		mFaces.Clear();
		mGauges.Clear();
		mGroups.Clear();
		mBaseColor.Clear();
		mIconW.Clear();
		mIconH.Clear();
		mLabelH.Clear();

		double panelW = cv("wr_panel_w", 3.5) * cv("wr_scale", 1.0);
		double panelH = cv("wr_panel_h", 2.5) * cv("wr_scale", 1.0);

		for (int i = 0; i < mTypes.Size(); ++i)
		{
			// Position and yaw are set properly by layout() on the same tic;
			// these are placeholders so the handle exists.
			// THE HIT QUAD IS NOT THE PICTURE.
			//
			// Billboards draw 1.2x taller than they are authored -- the view
			// matrix stretches world Z and the billboard path never unstretches
			// it -- so a quad that is both the picture and the target is hittable
			// across only the middle 83% of what you can see. Add the gap the
			// text and icon need to sit inside, and the live band ends up being
			// roughly where the name is, which is exactly the complaint.
			//
			// So: an invisible quad does the hitting, generously sized, and the
			// visible plate is BBFL_NOHIT. Alpha 0 is still hittable -- documented
			// as a trap, used here on purpose.
			int id = level.AddBillboardPersistent(
				(0, 0, 0), 3.5, 2.5, 0, 0,
				LevelLocals.BBF_FIXED, LevelLocals.BB_PANEL, 0,
				COLOR_IDLE, 0, 0, "");
			level.SetBillboardAlpha(id, 0);
			mIds.Push(id);

			// A DRY WEAPON RESTS A DIFFERENT COLOUR.
			//
			// Picking an empty gun looked exactly like picking a loaded one right
			// up until the trigger did nothing, and in a firefight that is the
			// worst possible moment to find out. The colour is the resting state,
			// not a hover state, so it is readable without pointing at anything.
			let heldNow = Weapon(players[consoleplayer].mo.FindInventory(mTypes[i]));
			int rest = (cv("wr_ammo", 1.0) > 0.0 && ammoLeft(heldNow) == 0)
			         ? COLOR_DRY : COLOR_IDLE;
			mBaseColor.Push(rest);

			// SAMPLED PLATE OR SOLVED ONE, and the caller picks.
			//
			// BB_PANEL stretches one small rounded-rect texture, which is cheap
			// and blurs when a card is held close in VR. BB_SDFPANEL solves the
			// same rectangle per pixel: crisp at any size, and it can take a
			// halo, which a sampled plate structurally cannot -- a glow needs a
			// distance field to read past the shape's edge and a texture has
			// none. That is why the label could glow and the card under it
			// could not.
			//
			// Not free. Two distance tests against one texture sample, times
			// every card, so the switch stays a switch.
			int plate = level.AddBillboardPersistent(
				(0, 0, 0), 3.5, 2.5, 0, 0,
				LevelLocals.BBF_FIXED, plateKind(), plateShape(),
				rest, LevelLocals.BBFL_NOHIT, 0, "");

			// A gradient, not a flat swatch. Two colours cost one extra setter
			// and give the card a top and a bottom -- which is most of what
			// makes a rectangle read as a surface rather than as a hole.
			level.SetBillboardGradient(plate, rest == COLOR_DRY ? GRAD_DRY : GRAD_IDLE);
			mPlates.Push(plate);

			// The slot's colour, as a bar along the top edge.
			//
			// Bearings are already fixed so the ring can be learned by feel.
			// This is the same promise to the eye: slot 4 is always blue and
			// always at the same angle, so it can be found two ways.
			mAccents.Push(level.AddBillboardPersistent(
				(0, 0, 0), 3.5, 0.3, 0, 0,
				LevelLocals.BBF_FIXED, LevelLocals.BB_PANEL, 0,
				slotColor(mCardSlots[i]), LevelLocals.BBFL_NOHIT, 0, ""));

			// The weapon's name, floated just off the panel face.
			//
			// BBFL_NOHIT is not optional here: the queries return the NEAREST
			// billboard, and the label sits in front of the panel it belongs to.
			// Without it every reach would come back holding a word, and the
			// panel behind it would be permanently unreachable.
			string tag = GetDefaultByType(mTypes[i]).GetTag();
			int lid = level.AddBillboardPersistent(
				(0, 0, 0), 3.5, 2.5, 0, 0,
				LevelLocals.BBF_FIXED, LevelLocals.BB_TEXT, 0,
				COLOR_LABEL, LevelLocals.BBFL_NOHIT, 0, tag);
			mLabels.Push(lid);
			mLabelH.Push(fitLabel(tag, panelW * LABEL_FIT_FRAC, panelH));

			// The weapon's own icon. One engine call resolves it -- DI_ALTICONFIRST
			// prefers AltHudIcon and falls back to the pickup icon by itself, which
			// is the entire resolution chain, already written and native.
			//
			// applyscale is the second return and says whether the icon's own scale
			// should be honoured. It is dropped by nearly everyone -- including
			// Gearbox, which is why its icons are subtly wrong -- so it is kept
			// here and used at layout time.
			// CANVAS FACE, or the composed one.
			//
			// When the canvas carries the artwork, the separate icon and gauge
			// billboards are not created at all -- they are already painted into
			// it, and drawing both would stack two icons on one card.
			//
			// Falls back per card, not per ring: the thirteenth weapon in a set
			// larger than the pool simply gets a composed face and everything
			// keeps working.
			int fid = 0;
			bool canvasFace = false;

			if (cv("wr_canvas", 0.0) > 0.0 && heldNow != null && i < FACE_POOL)
			{
				TextureID face = paintFace(i, heldNow, mCardSlots[i], rest == COLOR_DRY);
				if (face.IsValid())
				{
					fid = level.AddBillboardPersistent(
						(0, 0, 0), 3.5, 2.5, 0, 0,
						LevelLocals.BBF_FIXED, LevelLocals.BB_TEXTURE, face.GetIndex(),
						0xFFFFFF, LevelLocals.BBFL_NOHIT, 0, "");
					canvasFace = true;
				}
			}
			mFaces.Push(fid);

			int iid = 0;
			double iw = ICON_W_FRAC, ih = ICON_H_FRAC;
			let held = heldNow;
			if (held != null && !canvasFace)
			{
				TextureID icon = iconFor(held);

				if (icon.IsValid())
				{
					// Worked out once, here, rather than every tic in layout:
					// the texture cannot change while the rig is up, and this is
					// a texture lookup per card per frame otherwise.
					[iw, ih] = fitIcon(icon, ICON_W_FRAC, ICON_H_FRAC);

					iid = level.AddBillboardPersistent(
						(0, 0, 0), 3.5, 2.5, 0, 0,
						LevelLocals.BBF_FIXED, LevelLocals.BB_TEXTURE, icon.GetIndex(),
						0xFFFFFF, LevelLocals.BBFL_NOHIT, 0, "");
				}
			}
			mIcons.Push(iid);
			mIconW.Push(iw);
			mIconH.Push(ih);

			// The count, under the name. Blank for a weapon that uses no ammo --
			// a fist with "0" under it would be a lie, and one with "--" is a
			// question nobody asked.
			// BB_SEGMENT, not BB_TEXT.
			//
			// The 16-segment readout is built from arithmetic in the shader, so
			// it needs no font lump, cannot be broken by a missing atlas, and
			// stays sharp at any size -- and it draws its own bordered plate.
			// The point is not legibility, which BB_TEXT already had: it is that
			// a number in a lit bezel reads as an INSTRUMENT, which is what a
			// thing strapped to your arm should look like.
			int aid = 0;
			int rounds = ammoLeft(held);
			if (cv("wr_ammo", 1.0) > 0.0 && rounds >= 0)
			{
				// WG13 reads its number from `data`; the other two read `text`.
				// Passing both costs nothing and means the payload can be
				// switched at spawn without a branch here.
				aid = level.AddBillboardPersistent(
					(0, 0, 0), 3.5, 2.5, 0, 0,
					LevelLocals.BBF_FIXED, readoutKind(), rounds,
					rounds > 0 ? COLOR_AMMO : COLOR_AMMO_DRY,
					LevelLocals.BBFL_NOHIT, 0, String.Format("%d", rounds));
			}

			// THE MARKER, and it does not lock anything.
			//
			// Two states worth telling apart: this weapon is in the hand you are
			// pointing WITH, or it is in your other one. The second is the
			// interesting case -- taking it swaps the hands, or finds a free _2
			// clone -- so it gets the brighter mark. Neither stops the card
			// being selected, because in both cases picking it is a reasonable
			// thing to ask for.
			int where = heldWhere(mTypes[i]);
			int mid = 0;
			if (where != 0 && cv("wr_marker", 1.0) > 0.0)
			{
				mid = level.AddBillboardPersistent(
					(0, 0, 0), 0.6, 0.6, 0, 0,
					LevelLocals.BBF_FIXED, plateKind(), 15,
					(where == 2) ? COLOR_MARK_OTHER : COLOR_MARK_MINE,
					LevelLocals.BBFL_NOHIT, 0, "");
			}
			mMarks.Push(mid);

			// The same number as a proportion, which is the reading you actually
			// take at a glance. "148" needs parsing; a bar that is nearly gone
			// does not. BB_BAR's data is a fill PERCENT, 0..100, and it grows
			// from the left edge so only the right end moves.
			int gid = 0;
			double frac = ammoFrac(held);
			if (cv("wr_ammo", 1.0) > 0.0 && frac >= 0.0 && !canvasFace)
			{
				gid = level.AddBillboardPersistent(
					(0, 0, 0), 3.5, 0.35, 0, 0,
					LevelLocals.BBF_FIXED, LevelLocals.BB_BAR, int(frac * 100.0 + 0.5),
					slotColor(mCardSlots[i]), LevelLocals.BBFL_NOHIT, 0, "");
			}
			mGauges.Push(gid);
			mAmmos.Push(aid);

			// THE CARD IS ONE OBJECT NOW.
			//
			// The header of this file used to say groups were unusable because
			// group scale moved the picture and not the hit box, and a group
			// scaled to zero stayed clickable. Both of those were real, both
			// were found BY this mod, and both are fixed -- FORK_CHANGES.md
			// section 22. The note outlived the bugs by about a fortnight.
			//
			// What it buys: the scale animation is DECLARED once and resolved by
			// the engine per FRAME. The hand-rolled version stepped at script's
			// 35Hz, which is what made it look like a value being animated
			// rather than a thing arriving.
			int grp = level.AddBillboardGroup((0, 0, 0));
			level.SetBillboardGroup(id, grp);
			level.SetBillboardGroup(plate, grp);
			level.SetBillboardGroup(mAccents[i], grp);
			level.SetBillboardGroup(lid, grp);
			if (iid != 0) level.SetBillboardGroup(iid, grp);
			if (gid != 0) level.SetBillboardGroup(gid, grp);
			if (fid != 0) level.SetBillboardGroup(fid, grp);
			if (mid != 0) level.SetBillboardGroup(mid, grp);
			if (aid != 0) level.SetBillboardGroup(aid, grp);
			mCardX.Push(0); mCardY.Push(0); mCardZ.Push(0);
			mGroups.Push(grp);
		}
	}

	//==========================================================================
	// Following the wrist
	//==========================================================================

	// 0 the instant the rig opens, 1 once it has arrived.
	//
	// Ease-out cubic. A linear grow stops dead at the ring and reads as a jump
	// cut; this decelerates into place, which is what makes it look like the
	// cards have weight rather than like a value being animated.
	private double growFactor() const
	{
		double dur = cv("wr_growtics", 6.0);
		if (dur <= 0.0) return 1.0;

		double t = clamp(mOpenTics / dur, 0.0, 1.0);
		double u = 1.0 - t;
		return 1.0 - u * u * u;
	}

	// Panels are moved by hand every tic rather than attached, because
	// AttachBillboard follows an ACTOR and the thing they need to follow is a
	// tracked hand, which is not one.
	// Geometry is read fresh every tic rather than baked at spawn, so every cvar
	// below is live: change one with the rig open and the next tic has it.
	private void layout(PlayerPawn pmo)
	{
		// THE TRAIL, and it is the whole mechanic rather than a side effect.
		//
		// A card welded to your hand can never be caught BY that hand -- it
		// moves exactly as fast as you do, so there is nothing to reach into.
		// Letting the formation lag means moving your hand pulls it ahead of the
		// cards, and sweeping back through them is the grab.
		//
		// The CENTRE lags, not the cards individually. Lag them separately and
		// they pile into one clump behind your hand and you catch whichever is
		// nearest, which is never twice the same. Lagging the centre keeps the
		// arc rigid, so every card holds its own direction -- pistol always
		// up-left, shotgun always up-right -- and the direction you sweep is the
		// choice you make.
		//
		// It also makes the tic rate stop mattering. Cards that are meant to
		// trail cannot be caught out for trailing.
		// THE GRID IS FROZEN, and that is the mechanic.
		//
		// It used to trail your hand, and the idea was that you could sweep back
		// into a lagging card. In practice that asks you to chase a moving target
		// fast enough to open a gap, which nobody does under fire.
		//
		// Nailing it to where your hand WAS when you opened it inverts that: the
		// targets hold still and your hand is the only thing moving. Eight fixed
		// cells around where you started, so the same weapon is always in the
		// same direction and your arm learns it. The centre is where your hand
		// already is, which is why the centre means "what I am holding" and
		// staying put means "no change".
		if (!mHaveAnchor)
		{
			// THE RING GOES IN FRONT OF THE HAND, not around it.
			//
			// A ring of radius 5 centred on your hand is 15cm away and wrapped
			// around you: it subtends nearly 180 degrees, so reaching a card
			// meant rotating almost ninety or physically walking your arm over
			// there. That is the thing that made it feel like miles, and no
			// amount of cursor gain could fix it -- gain multiplies a rotation
			// that was always going to be enormous.
			//
			// Pushed a metre out along the aim, the whole ring subtends about
			// twenty degrees. A flick of the wrist crosses it.
			double aimY, aimP;
			[aimY, aimP] = handAim(pmo, mRigHand);

			double cp = cos(aimP);
			Vector3 ahead = (cp * cos(aimY), cp * sin(aimY), sin(aimP));

			mAnchor     = handPos(pmo, mRigHand) + ahead * cv("wr_forward", 34.0);
			mAnchorYaw  = pmo.angle;
			mHaveAnchor = true;
		}

		Vector3 wrist = mAnchor;

		// Every one of these is guarded. GetCVar returns null for a cvar the
		// config has never seen, and calling GetFloat on that aborts the VM --
		// which kills layout() every tic and looks precisely like the rig not
		// existing. A zero radius is the same class of failure without the
		// abort: every panel stacks inside your hand.
		// One dial that grows the whole rig -- distance, card size and reach
		// together. Scaling them independently just breaks the proportions you
		// already tuned, and "make it bigger" is one thought, not four.
		double sc = cv("wr_scale", 1.0);
		if (sc < 0.05) sc = 1.0;

		double radius = cv("wr_radius",   5.0);
		double rise   = cv("wr_rise",     2.0);
		double tilt   = cv("wr_tilt",    12.0);
		double panelW = cv("wr_panel_w",  8.0);
		double panelH = cv("wr_panel_h",  6.0);

		if (radius < 0.5) radius = 5.0;
		if (panelW < 0.5) panelW = 8.0;
		if (panelH < 0.5) panelH = 6.0;

		radius *= sc;
		rise   *= sc;
		panelW *= sc;
		panelH *= sc;

		// The arc lies FLAT around the hand, at rise above it -- a fan you look
		// down at, not a bracelet standing across the forearm. The bracelet is
		// geometrically the more honest reading of "worn on the wrist" and it is
		// unusable: it centres the arc straight up from your hand, which puts
		// half the panels over your head and the rest behind your arm.
		//
		// Wrist ROLL survives from that attempt, as a rotation of the ring within
		// its own plane. Twisting your wrist spins the cards past your hand,
		// which is the one part of arm tracking that helps rather than hinders.
		//
		// It had been dead for a while: it fed the old arc's start angle, and
		// when the layout moved to fixed bearings the arc maths was left behind
		// computing values nothing read. It is added to the BEARING now, which
		// is where it always belonged -- one term, and the whole ring turns.
		//
		// OFF by default, and that is not timidity. A tracked controller reports
		// roll of ninety degrees or more just from how you hold it, so feeding
		// it in raw swings the ring somewhere behind you and looks exactly like
		// the rig failing to open.
		double handRoll = handRollOf(pmo, mRigHand) * cv("wr_roll", 0.0);

		int n = mIds.Size();

		// A GRID, not an arc.
		//
		// An arc cannot hold nine cards without pushing the radius to arm's
		// length: the arc length available is radius * span * pi/180, and nine
		// cards need nine card-widths of it. At any radius you would actually
		// want, they stack on top of each other -- which is what they were doing.
		//
		// A grid has no such ceiling. It packs, it never overlaps, and it scales
		// to a weapon set with fifty entries instead of nine.
		double viewYaw = pmo.angle;
		Vector3 viewRight = (cos(viewYaw - 90), sin(viewYaw - 90), 0);

		double cellW = panelW * 1.25;

		// Ring radius grows with the count so the cards never crowd: eight fit at
		// the tuned distance, twelve push out to keep the same gap between them.
		// The chord between neighbours is 2 * R * sin(180/N), and that wants to
		// stay above one card width.
		int ringCount = n;
		double ringR = radius;
		double minR = (cellW * 0.5) / max(sin(180.0 / max(ringCount, 2)), 0.05);
		if (minR > ringR) ringR = minR;

		Vector3 eye = pmo.Pos + (0, 0, pmo.player.viewheight);

		// The centre is left empty. That is where your hand already is and what
		// you are already holding -- so opening the rig and not moving is "keep
		// what I have", and every card on the ring is a genuine change.
		if (mCentreId != 0)
		{
			Vector3 cpos = wrist + (0, 0, rise);
			Vector3 clift = (cos(viewYaw + 180), sin(viewYaw + 180), 0) * LABEL_LIFT;

			level.MoveBillboard(mCentreId, cpos);
			level.ResizeBillboard(mCentreId, panelW, panelH);
			level.OrientBillboard(mCentreId, viewYaw + 180, tilt, LevelLocals.BBF_FIXED);

			if (mCentreIcon != 0)
			{
				level.MoveBillboard(mCentreIcon, cpos + clift + (0, 0, panelH * 0.16));
				level.ResizeBillboard(mCentreIcon, panelW * mCentreIconW,
				                                   panelH * mCentreIconH);
				level.OrientBillboard(mCentreIcon, viewYaw + 180, tilt, LevelLocals.BBF_FIXED);
			}
			if (mCentreLabel != 0)
			{
				level.MoveBillboard(mCentreLabel, cpos + clift - (0, 0, panelH * 0.30));
				level.ResizeBillboard(mCentreLabel, panelW, panelH * LABEL_HEIGHT_FRAC);
				level.OrientBillboard(mCentreLabel, viewYaw + 180, tilt, LevelLocals.BBF_FIXED);
			}
		}

		// THE CARDS GROW OUT OF YOUR WRIST.
		//
		// They used to exist all at once, which gave you no idea where they had
		// come from -- eight rectangles simply were, and the first tic of the rig
		// was spent working out what you were looking at. Sliding them out of the
		// centre in six tics says "these belong to that hand" without a word, and
		// it costs one multiply per card.
		//
		// Ease-out cubic: quick away from the wrist, settling into the ring
		// rather than stopping dead at it. Position AND size, because a card that
		// travels at full size reads as sliding rather than unfolding.
		// The SCALE of the grow-in is the group's job now, resolved per frame by
		// the engine with its own eased overshoot. What is left here is the
		// TRAVEL -- cards sliding out of the wrist to their bearings -- and the
		// tumble, neither of which a group carries.
		double grow = growFactor();

		Vector3 origin = wrist + (0, 0, rise);

		for (int i = 0; i < n; ++i)
		{
			// Position is the slot's bearing on the ring, clockwise from north
			// west. Cards you do not own still consume their place, so a slot's
			// direction never changes as you pick things up -- which is the whole
			// reason this can be learned by feel.
			double bearing = bearingForIndex(i, ringCount) + handRoll;

			Vector3 pos = wrist
			            + viewRight * (cos(bearing) * ringR)
			            + (0, 0, sin(bearing) * ringR + rise);

			if (grow < 1.0) pos = origin + (pos - origin) * grow;

			// The hovered card steps toward your eye and lights up. Colour alone
			// is a weak signal on a grid this dense -- depth reads instantly, and
			// it also makes the target physically easier to reach.
			if (mIds[i] == mHovered)
			{
				Vector3 toEye = eye - pos;
				if (toEye.Length() > 0.01) pos += toEye.Unit() * cv("wr_pop", 1.5);
			}

			// Camera-facing, so every card looks at you wherever it sits in the
			// arc -- an outward-facing card on the far side shows you its edge.
			// The probe cleared this: B passed on both aim and touch, so the bug
			// the audit predicted here does not exist.
			double faceYaw = viewYaw + 180;

			// THE CARD TUMBLES IN.
			//
			// Rolled off true on the way out of the wrist and settling to level
			// as it arrives. Roll is a real billboard axis now, and because it
			// lives in the SHARED basis the hit quad rolls with the picture --
			// so a card caught mid-tumble is pointable exactly where it looks.
			double roll = (1.0 - grow) * ARRIVE_ROLL * ((i % 2 == 0) ? 1.0 : -1.0);

			// The card you took spins as it goes. A full turn over the collapse,
			// eased so it leaves fast and slows into nothing rather than
			// stopping dead at the moment it disappears.
			if (i == mFlipCard && mFlipTics > 0 && CLOSE_TICS > 0)
			{
				double ft = 1.0 - (double(mFlipTics) / CLOSE_TICS);
				roll += (1.0 - (1.0 - ft) * (1.0 - ft)) * cv("wr_flip", 360.0);
			}

			if (i < mCardX.Size()) { mCardX[i] = pos.X; mCardY[i] = pos.Y; mCardZ[i] = pos.Z; }




			// The group carries the whole card's origin, so scale happens about
			// the card's own centre rather than about the world origin.
			if (i < mGroups.Size()) level.SetBillboardGroupOrigin(mGroups[i], pos);

			// Hit quad first, sized past the picture: 1.2 to cover the vertical
			// stretch the renderer adds, and a little more so the edges of the
			// card you can see are edges you can actually point at.
			//
			// No grow factor in the size any more -- the group scales it, and
			// scaling it here as well would square the animation.
			level.MoveBillboard(mIds[i], pos);
			level.ResizeBillboard(mIds[i], panelW * HIT_PAD,
			                               panelH * CARD_STRETCH * HIT_PAD);
			level.OrientBillboard(mIds[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
			level.RollBillboard(mIds[i], roll);

			// The hovered card BREATHES.
			//
			// A colour change is a state you have to notice; a card that is
			// moving is one you cannot miss, and motion survives being in the
			// corner of your eye where colour does not. Sine, not a ramp, so it
			// never stops or snaps -- the old SNES menu pulse.
			//
			// Everything on the card is scaled by the same factor, or the icon
			// and the name slide off a plate that grew underneath them.
			// Everything printed on the card rides a shade in front of its face.
			// The face points along (faceYaw), so stepping that way steps toward
			// the player -- any less and the two z-fight, any more and the text
			// visibly floats free of the card when seen from the side.
			Vector3 lift = (cos(faceYaw), sin(faceYaw), 0) * LABEL_LIFT;

			bool lit = (mIds[i] == mHovered);
			double pulse = 1.0;
			if (lit)
			{
				double amp = cv("wr_pulse", 0.10);
				pulse = 1.0 + amp + amp * sin(mHoverTics * PULSE_SPEED);
			}

			// FOCUS. Cards you are not pointing at step back.
			//
			// Only once something IS hovered -- dimming the whole ring the
			// moment it opens would make it look like it failed to load. Eight
			// cards competing equally for your eye is the problem; seven quiet
			// ones and a lit one is the fix, and it costs one alpha per card.
			//
			// HAS to be below lit and pulse, which is where it went wrong the
			// first time: it was written next to the position bookkeeping at the
			// top of the loop, forty lines before either of them exists.
			double cardAlpha = 1.0;
			if (mHovered != 0 && !lit) cardAlpha = clamp(cv("wr_dim", 0.55), 0.05, 1.0);

			if (i < mPlates.Size())  fade(mPlates[i], cardAlpha);
			if (i < mFaces.Size())   fade(mFaces[i], cardAlpha);
			if (i < mAccents.Size()) fade(mAccents[i], cardAlpha);
			if (i < mIcons.Size())   fade(mIcons[i], cardAlpha);
			if (i < mGauges.Size())  fade(mGauges[i], cardAlpha);
			if (i < mLabels.Size())  fade(mLabels[i], cardAlpha);
			if (i < mAmmos.Size())   fade(mAmmos[i], cardAlpha);
			if (i < mMarks.Size())   fade(mMarks[i], cardAlpha);

			// The model floats a little in FRONT of its plate, so the card backs
			// it rather than intersecting it, and it takes the same pulse and
			// the same fade as everything else on the card.
			if (i < mModels.Size() && mModels[i] != null)
			{
				double ms = cv("wr_model_scale", 0.16) * pulse;

				// Through a local: SetOrigin wants a modifiable value and an
				// expression is not one.
				Vector3 mp = pos + lift * cv("wr_model_lift", 3.0);
				mModels[i].SetOrigin(mp, true);
				mModels[i].Scale = (ms, ms);
				mModels[i].A_SetRenderStyle(cardAlpha, STYLE_Translucent);
			}

			// The held-weapon mark, pinned to the card's top-right corner.
			if (i < mMarks.Size() && mMarks[i] != 0)
			{
				level.MoveBillboard(mMarks[i],
					pos + lift * 1.5
					    + viewRight * (panelW * 0.40 * pulse)
					    + (0, 0, panelH * 0.34 * pulse));
				level.ResizeBillboard(mMarks[i], panelW * 0.10 * pulse,
				                                 panelH * 0.13 * pulse);
				level.OrientBillboard(mMarks[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
				level.RollBillboard(mMarks[i], roll);
			}

			if (i < mPlates.Size())
			{
				level.MoveBillboard(mPlates[i], pos);
				level.ResizeBillboard(mPlates[i], panelW * pulse, panelH * pulse);
				level.OrientBillboard(mPlates[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
				level.RollBillboard(mPlates[i], roll);

				// THE CARD ITSELF GLOWS NOW, not just the name on it.
				//
				// This was impossible until the plate became a distance field:
				// the halo is placed by reading the field OUTSIDE the shape,
				// and a sampled texture has nothing out there to read. On
				// BB_PANEL the call is simply ignored, so the switch needs no
				// branch here.
				double g = cv("wr_glow", 1.0);
				level.SetBillboardGlow(mPlates[i], lit ? clamp(GLOW_R * g, 0.0, 1.0) : 0.0,
				                                   lit ? GLOW_S * g : 0.0);
			}

			// The slot bar, pinned to the card's top edge.
			if (i < mAccents.Size())
			{
				level.MoveBillboard(mAccents[i],
					pos + lift + (0, 0, panelH * (0.5 - ACCENT_H_FRAC * 0.5) * pulse));
				level.ResizeBillboard(mAccents[i], panelW * pulse,
				                                   panelH * ACCENT_H_FRAC * pulse);
				level.OrientBillboard(mAccents[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
				level.RollBillboard(mAccents[i], roll);
			}

			// The painted face, filling the card and riding a shade in front of
			// the plate. Slightly inset so the SDF plate still shows as a rim
			// around it -- which is what keeps the plate's glow visible.
			if (i < mFaces.Size() && mFaces[i] != 0)
			{
				level.MoveBillboard(mFaces[i], pos + lift * 0.5);
				level.ResizeBillboard(mFaces[i], panelW * 0.92 * pulse,
				                                 panelH * 0.92 * pulse);
				level.OrientBillboard(mFaces[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
				level.RollBillboard(mFaces[i], roll);
			}

			// Sized to the icon's OWN shape rather than stamped into a fixed
			// rectangle, so a wide pickup stays wide. Centred in its box by
			// keeping the same anchor -- billboards are centre-origin.
			if (i < mIcons.Size() && mIcons[i] != 0)
			{
				level.MoveBillboard(mIcons[i], pos + lift + (0, 0, panelH * 0.17 * pulse));
				level.ResizeBillboard(mIcons[i], panelW * mIconW[i] * pulse,
				                                 panelH * mIconH[i] * pulse);
				level.OrientBillboard(mIcons[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
				level.RollBillboard(mIcons[i], roll);
			}

			if (i < mLabels.Size())
			{
				level.MoveBillboard(mLabels[i], pos + lift - (0, 0, panelH * 0.13 * pulse));
				// Height measured at spawn against this card's width, so a long
				// name is drawn smaller instead of running off both edges.
				level.ResizeBillboard(mLabels[i], panelW * pulse,
				                                  panelH * mLabelH[i] * pulse);
				level.OrientBillboard(mLabels[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
				level.RollBillboard(mLabels[i], roll);

				// Neon, and only on the one you are pointing at. A halo on every
				// card is a blur; a halo on one is the answer to "which".
				double lg = cv("wr_glow", 1.0);
				level.SetBillboardGlow(mLabels[i], lit ? clamp(GLOW_R * lg, 0.0, 1.0) : 0.0,
				                                   lit ? GLOW_S * lg : 0.0);
			}

			// The proportion, as a bar. Read before the number is.
			if (i < mGauges.Size() && mGauges[i] != 0)
			{
				level.MoveBillboard(mGauges[i], pos + lift - (0, 0, panelH * 0.26 * pulse));
				level.ResizeBillboard(mGauges[i], panelW * 0.76 * pulse,
				                                  panelH * GAUGE_H_FRAC * pulse);
				level.OrientBillboard(mGauges[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
				level.RollBillboard(mGauges[i], roll);
			}

			// The count, in its own lit bezel at the bottom of the card.
			if (i < mAmmos.Size() && mAmmos[i] != 0)
			{
				level.MoveBillboard(mAmmos[i], pos + lift - (0, 0, panelH * 0.37 * pulse));
				level.ResizeBillboard(mAmmos[i], panelW * AMMO_W_FRAC * pulse,
				                                 panelH * AMMO_H_FRAC * pulse);
				level.OrientBillboard(mAmmos[i], faceYaw, tilt, LevelLocals.BBF_FIXED);
				level.RollBillboard(mAmmos[i], roll);

				// THE READOUTS BOOT UP.
				//
				// Progress is a reveal on the segment payload, not a value: the
				// bezel is a hairline slit at 0 that opens vertically, and the
				// characters do not appear at all until 0.55. Driving it with
				// the same curve the cards arrive on means each one powers on as
				// it lands rather than arriving already lit.
				level.SetBillboardProgress(mAmmos[i], grow);
			}

			// The fan hangs off whichever card opened it, so it is placed here
			// where that card's position has just been worked out.
			if (i == mExpanded)
			{
				layoutExpansion(bearingForIndex(i, ringCount), fanSpread(ringCount),
				                pos, viewRight, faceYaw, tilt, panelW, panelH, cellW);
			}
		}
	}

	// AttackPos/OffhandPos are only written while OverrideAttackPosDir is set.
	// Without it they hold the actor's ORIGIN -- its feet -- so panels anchored
	// to them sit on the floor at ankle height and read as broken rather than
	// absent. The engine's own wheel hits this and synthesises a hand in front
	// of the camera instead; this does the same, so the rig is usable with no
	// tracked hands at all.
	private static Vector3 handPos(PlayerPawn pmo, int hand)
	{
		if (pmo.OverrideAttackPosDir)
		{
			return (hand == 1) ? pmo.OffhandPos : pmo.AttackPos;
		}

		double yaw  = pmo.angle;
		double side = (hand == 1) ? -1.0 : 1.0;

		Vector3 head = pmo.Pos + (0, 0, pmo.player.viewheight);
		Vector3 fwd  = (cos(yaw), sin(yaw), 0);
		Vector3 rt   = (cos(yaw - 90), sin(yaw - 90), 0);

		return head + fwd * 22.0 + rt * (side * 11.0) - (0, 0, 8.0);
	}

	// The engine's own convention: a hand's facing is its angle plus ninety
	// degrees, not the angle itself.
	private static double handAngle(PlayerPawn pmo, int hand)
	{
		if (!pmo.OverrideAttackPosDir) return pmo.angle;

		return ((hand == 1) ? pmo.OffhandAngle : pmo.AttackAngle) + 90;
	}

	// The direction a hand points, as a unit vector.
	//
	// The Z SIGN is the trap, and the engine's own wheel gets it wrong: it feeds
	// raw OffhandPitch into an AngleToVector whose Z is -sin(pitch), while the
	// stored convention is up-POSITIVE (hw_vrmodes.cpp negates on the way in).
	// The correct consumer is hw_weapon.cpp, which negates again and so ends up
	// with +sin. Copy that, not the wheel.
	//
	// Without tracking, point where the player looks -- pmo.pitch is down-
	// positive, hence the negation. That is also what makes this testable at a
	// desk, which the old "return 0" never was.
	private static double, double handAim(PlayerPawn pmo, int hand)
	{
		if (pmo.OverrideAttackPosDir)
		{
			return ((hand == 1) ? pmo.OffhandAngle : pmo.AttackAngle) + 90,
			       (hand == 1) ? pmo.OffhandPitch : pmo.AttackPitch;
		}
		return pmo.angle, -pmo.pitch;
	}

	private static Vector3 handDir(PlayerPawn pmo, int hand)
	{
		double y, p;

		if (pmo.OverrideAttackPosDir)
		{
			y = ((hand == 1) ? pmo.OffhandAngle : pmo.AttackAngle) + 90;
			p = (hand == 1) ? pmo.OffhandPitch : pmo.AttackPitch;
		}
		else
		{
			y = pmo.angle;
			p = -pmo.pitch;
		}

		double cp = cos(p);
		return (cp * cos(y), cp * sin(y), sin(p));
	}

	private static double handPitchOf(PlayerPawn pmo, int hand)
	{
		if (!pmo.OverrideAttackPosDir) return 0;

		return (hand == 1) ? pmo.OffhandPitch : pmo.AttackPitch;
	}

	private static double handRollOf(PlayerPawn pmo, int hand)
	{
		if (!pmo.OverrideAttackPosDir) return 0;

		return (hand == 1) ? pmo.OffhandRoll : pmo.AttackRoll;
	}

	//==========================================================================
	// Reaching in
	//==========================================================================

	override void WorldTick()
	{
		if (mWantAutoOpen)
		{
			let p = players[consoleplayer];
			if (p.mo != null && p.playerstate == PST_LIVE)
			{
				mWantAutoOpen = false;
				openRig(1);
			}
		}

		// The fold-away outlives the rig being open, so it is ticked down before
		// the early-out rather than after it.
		if (mFlipTics > 0) --mFlipTics;
		if (mClosingTics > 0 && --mClosingTics <= 0) destroyPanels();

		if (!mOpen) return;

		let pmo = players[consoleplayer].mo;
		if (pmo == null || players[consoleplayer].playerstate != PST_LIVE)
		{
			// Dying is not a moment for an animation. Take it down now.
			mHardClose = true;
			closeRig();
			mHardClose = false;
			return;
		}

		// The lock expires. A rig that stays up until you deal with it is a modal
		// dialog in a firefight; one that quietly folds away if you did not mean
		// to open it costs nothing. Hovering resets it, because a hand on a card
		// is someone who is still deciding.
		if (--mLockTics <= 0)
		{
			closeRig();
			return;
		}

		++mOpenTics;

		// Before layout, so the artwork is queued for the same frame the cards
		// are placed in.
		repaintFaces(pmo);

		// RE-ASSERT THE FIST, EVERY TIC.
		//
		// This is not belt and braces. A_WeaponReady runs in the weapon's Ready
		// state every single tic and writes the psprite's sprite and frame back
		// to the real gun, so a swap applied once at open survives for exactly
		// one tic and is then gone. It has to happen HERE, after the playsim has
		// ticked the psprite, which is what WorldTick is -- doing it any earlier
		// just gets overwritten again.
		//
		// The design said so from the start and the call was never wired in,
		// which is why the hand has never once been visible.

		layout(pmo);

		// CURSOR GAIN.
		//
		// The cards sit at a real distance in the world, so reaching them meant
		// physically moving your arm that far -- fine once, exhausting to browse
		// with. Multiplying displacement from where the rig opened means a few
		// inches of hand covers the whole ring, while the cards stay at a size
		// and distance that is comfortable to READ.
		//
		// Measured from the anchor rather than from last tic, so it never drifts:
		// bring your hand back where it started and the cursor is back in the
		// centre, exactly.
		// POINTING, not reaching.
		//
		// Touch made you carry your hand to every card, which is why browsing the
		// ring felt like a mile of arm. A ray costs a wrist rotation instead, and
		// it is the only query of the three that is geometrically sound anyway:
		// AimBillboard resolves its basis at the ray origin but tests the
		// intersection point, so its bounds check is live code. TouchBillboard
		// tests the same vector its basis came from, and on a turning card that
		// term is algebraically zero.
		// One to one, both position and aim.
		//
		// There was hand acceleration here and it is gone. It existed because the
		// ring used to be wrapped around the hand, where reaching a card was a
		// genuine arm move -- once the ring sits a metre out in front, the beam
		// leaves along the barrel and a normal wrist movement already crosses it.
		// Amplifying on top of that only breaks the one thing that makes a laser
		// legible: that it goes where the gun is pointing.
		Vector3 org = handPos(pmo, mPokeHand);

		// Aim is one-to-one. There was an angular gain here and it is gone: it
		// multiplied hand tremor exactly as much as intent, which is what made
		// the beam unusable, and once the ring moved out in front of the hand and
		// reach was amplified it was solving a problem that no longer existed.
		Vector3 dir = handDir(pmo, mPokeHand);

		int hit;
		Vector2 uv;
		// Finite range on purpose: unlimited means the ray leaves the room and
		// can find another mod's billboard through a wall.
		[hit, uv] = level.AimBillboard(org, dir, POINTER_RANGE);

		// STICK SELECTION, for anyone who would rather not aim.
		//
		// The ring has fixed bearings, so a stick direction maps straight to a
		// slot: push toward the one you want. No precision, no steadiness, works
		// while you are being shot at. It overrides the ray whenever the stick
		// is actually deflected, and gets out of the way when it is not.
		int stickHit = stickPick(pmo);
		if (stickHit != 0) hit = stickHit;

		// TOUCH WINS OVER BEAM.
		//
		// Two ways in, and they are not rivals: the beam is for reaching a card
		// across the ring, the hand is for the one you are already at. When both
		// answer, the hand is the more deliberate act -- you had to put it there
		// -- so it takes precedence over wherever the beam happened to be
		// pointing past it.
		// wr_touch 0 turns reaching off outright and leaves the beam as the only
		// way in. Skipped rather than called with a zero radius, because "no
		// radius" and "do not ask" are different things and only one of them is
		// free.
		double touchR = cv("wr_touch", 7.0) * cv("wr_scale", 1.0);
		mTouching = false;

		if (touchR > 0.0)
		{
			int touched;
			Vector2 tuv;
			double tdist;
			[touched, tuv, tdist] = level.TouchBillboard(org, touchR);

			mTouching = (touched != 0);
			if (mTouching) hit = touched;
		}

		updateHover(hit);

		// The beam, and the dot where it lands.
		//
		// Without them you are aiming something invisible: the ray leaves your
		// hand at an angle you cannot see, and the first feedback would be a card
		// lighting up somewhere you were not looking.
		double reach = POINTER_RANGE;
		if (hit != 0)
		{
			// Stop the beam at the card it found, so it reads as touching rather
			// than passing through.
			reach = distanceToHit(org, dir, hit);
		}
		else
		{
			reach = cv("wr_radius", 5.0) * cv("wr_scale", 1.0) * 1.6;
		}

		// Only the dot is ours now; the beam is the engine laser.
		// Tell the engine laser where to stop. Its own trace cannot see a
		// billboard, so without this the beam goes through the card and lands on
		// the wall behind -- which reads as the laser ignoring the thing it is
		// selecting. Republished every tic; a stale value would clamp the
		// player's laser forever.
		level.SetVRLaserRange(hit != 0 ? reach : 0);

		decor(pmo, org, dir, reach, hit != 0);
		cardLight(pmo);


		// Committing is driven from InputProcess instead, so the fire press can
		// be swallowed before it reaches the weapon. Reading cmd.buttons here
		// would see the press but not be able to stop the shot.
	}

	// How far along the ray the hit card sits.
	//
	// AimBillboard reports which card and where on its face, but not the range,
	// so this walks the same ray until it stops finding that card. Coarse on
	// purpose -- the beam only has to END at the card, not to the millimetre.
	private double distanceToHit(Vector3 org, Vector3 dir, int wanted) const
	{
		double lo = 0.0, hi = POINTER_RANGE;

		for (int i = 0; i < 12; ++i)
		{
			double mid = (lo + hi) * 0.5;
			int probe;
			Vector2 puv;
			[probe, puv] = level.AimBillboard(org, dir, mid);

			if (probe == wanted) hi = mid;
			else                 lo = mid;
		}
		return hi;
	}

	// A thin quad lying along the ray, plus a dot on the end.
	//
	// A billboard is a quad with a yaw and a tilt, which is exactly enough to
	// lie one down along a direction: width becomes length, height becomes
	// thickness, and the centre goes at the midpoint.
	// The ENGINE's laser, not one made of billboards.
	//
	// It already draws a proper per-hand beam with glow, width, alpha, taper and
	// colour, all cvar-driven and all tuned by whoever set those defaults. The
	// version built here out of fourteen slivers was strictly worse than the one
	// sitting in the renderer.
	//
	// vr_laser_hide_on_wheel only hides it for the ENGINE's wheel -- it tests
	// VRWheel_ShouldSuppressHandInput, which this mod never sets -- so ours is
	// left alone.
	//
	// The previous value is saved rather than assumed off: plenty of people play
	// with a laser sight on permanently, and switching it off for them when the
	// wheel closed would be its own bug.
	private void engineLaser(bool on)
	{
		// An engine override, not a cvar write. The VM refuses writes to archived
		// cvars outside menu code -- correctly -- and this wants the laser for four
		// seconds, not a change to what the player has saved.
		//
		// Named to the rig hand, so the hand still holding a gun is not given a
		// second beam clamped to the ring's distance. Naming the hand is also what
		// gets a cursor onto an EMPTY off hand at all: the engine skips the laser
		// for a hand with no weapon in it unless a script has claimed that hand.
		level.ForceVRLaser(on, on ? mRigHand : -1);
		if (!on) level.SetVRLaserRange(0);
	}

	// Sound and haptics together, because they are one event.
	//
	// A menu you can only SEE is a menu you have to look at, and in VR looking at
	// your wrist is looking away from the thing shooting you. A tick in the
	// controller and a click in the ear both say "that registered" without
	// costing you the room.
	//
	// The rig has its own sounds rather than borrowing the engine's menu aliases.
	// menu/cursor and menu/choose are the flat beeps of whichever game is loaded
	// and they say "pause menu", which is the one thing this is not. See
	// sndinfo.txt.
	//
	// CHANF_UI keeps them out of the world: no falloff, no occlusion, and not a
	// noise in the level that a monster could be thought to have made.
	//
	// Haptics go to the POKE hand, which is the hand that did the thing. Buzzing
	// the hand wearing the cards when the other one selected would be feedback
	// arriving at the wrong wrist.
	// Takes a Sound, not a string. The conversion from a string LITERAL to a
	// Sound is done by the compiler; handing S_StartSound a runtime string
	// variable is a different question with a worse answer, and every call site
	// here knows its sound at compile time anyway.
	private void feedback(Sound snd, double amp, double ms)
	{
		if (cv("wr_sound", 1.0) > 0.0)
		{
			S_StartSound(snd, CHAN_VOICE, CHANF_UI, cv("wr_volume", 0.65), ATTN_NONE);
		}

		double gain = cv("wr_haptics", 1.0);
		if (amp > 0.0 && gain > 0.0)
		{
			// vr_enable_haptics is still checked engine-side, so someone who has
			// turned haptics off globally is not overridden by a mod cvar.
			level.VRHaptic(mPokeHand, amp * gain, ms);
		}
	}

	// The slot colour of whatever is under the pointer, or the ring's own idle
	// colour when nothing is.
	private color hoverColor() const
	{
		int card = cardIndexOf(mHovered);
		if (card >= 0 && card < mCardSlots.Size()) return slotColor(mCardSlots[card]);
		return COLOR_BEAM_IDLE;
	}

	// THE ROOM REACTS.
	//
	// Everything above this line dresses the CARDS. This dresses the space they
	// are in, which is where the remaining difference was: a ring that lights
	// the wall behind it reads as an object in the room, and a ring that does
	// not reads as a picture pasted over one.
	//
	// All three are SINGLE GLOBAL SLOTS with no getters, so this cannot read
	// what a co-loaded mod put there and politely put it back. What makes that
	// survivable is the engine's own contract for them -- "publish it each tic
	// while the light is on" -- so anything else using them is re-publishing
	// every tic too and recovers by itself the moment the rig lets go. It is
	// still someone else's slot, so every one of these is behind its own cvar.
	private void decor(PlayerPawn pmo, Vector3 org, Vector3 dir, double reach, bool onCard)
	{
		color tint = hoverColor();

		// The same arrival curve the cards ride, so the room and the ring agree
		// about when the rig has finished opening.
		double grow = growFactor();

		// THE ROOM'S OWN LIGHT RIPPLES.
		//
		// This one does not create light -- it modulates the glows a map
		// already has, per pixel, with separate phases for wall top, wall
		// bottom, floor and ceiling so a wave can climb a room rather than
		// pulsing it uniformly. Anchored at the ring, so the level appears to
		// react to the rig being open.
		//
		// Worth knowing before turning it on: in a map with NO glowing surfaces
		// it does exactly nothing. Its whole effect is a function of the level
		// you happen to be standing in, which is why it is off by default and
		// not a bug when it seems dead.
		double wave = cv("wr_wave", 0.0);
		if (wave > 0.0)
		{
			level.SetGlowWaveOrigin(mAnchor);
			level.SetGlowWave(cv("wr_wave_len", 120.0),
			                  cv("wr_wave_speed", 1.6),
			                  cv("wr_wave_sharp", 1.4), 1);
			level.SetGlowWaveDepth(wave, wave * 0.8, wave * 0.5, 0.15, 3.0);

			// Offset per channel so the wave CLIMBS instead of flashing the
			// whole room at once -- which is the entire difference between this
			// and a screen-wide brightness pulse.
			level.SetGlowWavePhase(0.0, 0.35, 0.7, 1.05);
			mWaveHeld = true;
		}
		else if (mWaveHeld)
		{
			level.SetGlowWave(0.0, 0.0, 0.0, 0);   // wavelength 0 = off
			mWaveHeld = false;
		}

		// THE LASER GETS AIR IN IT.
		//
		// The engine laser is still the pointer -- it does the hit maths and
		// terminates on the card. This is a raymarched cone laid along the same
		// ray, so the beam has dust drifting through it instead of being a line
		// with nothing between it and the wall.
		if (cv("wr_vbeam", 1.0) > 0.0)
		{
			// inner is the hot core, outer where it has faded to nothing;
			// falloff above 1 concentrates the light near the lens, which is
			// what stops a long beam looking like a strip light.
			level.SetVolumetricBeam(org, dir, tint,
				cv("wr_vbeam_inner", 1.2),
				cv("wr_vbeam_outer", 5.0),
				reach,
				cv("wr_vbeam_density", 0.55) * (onCard ? 1.35 : 1.0),
				2.2,
				cv("wr_vbeam_dust", 0.5), 0.035, 0.4);
			mBeamHeld = true;
		}
		else if (mBeamHeld)
		{
			// Switched off with the rig still open. Every cvar here is live, so
			// each of these needs its own way back out.
			level.ClearVolumetricBeam();
			mBeamHeld = false;
		}

		// A RING OF LIGHT WASHES THE ROOM WHEN IT OPENS.
		//
		// Mode 1 is a cylinder from the origin, tested per pixel against world
		// position on every surface -- so it crosses floor, wall and ceiling as
		// one unbroken line rather than lighting sectors. Nothing per-sector can
		// do that, and it is the reason this reads as the rig emitting rather
		// than as a screen effect.
		//
		// It runs once, on open, and gets out of the way.
		double sweepTics = cv("wr_sweep", 14.0);
		if (sweepTics > 0.0)
		{
			if (mOpenTics <= sweepTics)
			{
				double t = mOpenTics / sweepTics;

				level.SetSweepOrigin(1, pmo.Pos + (0, 0, pmo.height * 0.5), 1);
				level.SetSweepBand(0,
					t * cv("wr_sweep_reach", 340.0),   // radius, outward
					18.0 + t * 40.0,                   // thickness, spreading
					0.55,
					tint,
					(1.0 - t) * (1.0 - t) * cv("wr_sweep_bright", 1.4));
				mSweepHeld = true;
			}
			else if (mSweepHeld)
			{
				// Let go the tic after it finishes rather than holding a dead
				// band at zero intensity for as long as the rig is up.
				level.ClearSweep();
				mSweepHeld = false;
			}
		}
		else if (mSweepHeld)
		{
			level.ClearSweep();
			mSweepHeld = false;
		}

		// A MARK ON THE FLOOR UNDER YOU.
		//
		// One shape slot, repeated radially. SetShapeRepeat FOLDS THE
		// COORDINATE rather than drawing N copies -- the engine's own note says
		// eight and eight hundred cost the same -- so a full ring of marks is
		// one shape's worth of work. It spins, and its seam splits each mark
		// down the middle as the rig arrives, which is what ties the floor to
		// the cards instead of just decorating under them.
		double floorSize = cv("wr_floor", 0.0);
		if (floorSize > 0.0)
		{
			if (mShapeSlot < 0)
			{
				mShapeSlot = level.AddShape(
					int(cv("wr_floor_kind", 5.0)),   // 5 = cross
					0,                                // floors only
					pmo.Pos.X, pmo.Pos.Y, pmo.floorz,
					floorSize, 0.0, cv("wr_floor_thick", 0.18),
					tint, cv("wr_floor_bright", 1.2), 0.0);
			}

			if (mShapeSlot >= 0)
			{
				level.MoveShape(mShapeSlot, pmo.Pos.X, pmo.Pos.Y, pmo.floorz);
				level.SetShapeRepeat(mShapeSlot, 1,
					cv("wr_floor_count", 8.0),
					cv("wr_floor_space", 46.0),
					cv("wr_floor_spin", 14.0));

				// Splits open as the ring does, then holds. seamRate 0 keeps
				// the caller owning the animation, same as everything else here.
				level.SetShapeMotion(mShapeSlot, grow * cv("wr_floor_seam", 0.5), 0.0, 0.0);
			}
		}
		else if (mShapeSlot >= 0)
		{
			level.RemoveShape(mShapeSlot);
			mShapeSlot = -1;
		}

		// MIST THE CARDS SIT IN, off by default.
		//
		// This is the one that is genuinely rude: a map or another mod may have
		// authored its own fog slab, and taking it means their mist changes for
		// as long as the rig is open. Worth having, not worth defaulting to.
		double fog = cv("wr_fog", 0.0);
		if (fog > 0.0)
		{
			level.SetFogSlab(mAnchor.Z + cv("wr_fog_rise", 6.0), fog, 0.6,
			                 cv("wr_fog_scatter", 0.8), tint);
			mFogHeld = true;
		}
		else if (mFogHeld)
		{
			level.ClearFogSlab();
			mFogHeld = false;
		}
	}

	// Hands back only what was actually TAKEN.
	//
	// The first version cleared all three unconditionally, which is wrong in a
	// specific and rude way: with wr_sweep off, the rig never touches the sweep
	// slot, and clearing it on close would delete a co-loaded mod's sweep that
	// this had nothing to do with. There is no getter to check with, so the
	// flags are the only record of what is ours.
	private void releaseDecor()
	{
		if (mBeamHeld)  { level.ClearVolumetricBeam(); mBeamHeld = false; }
		if (mSweepHeld) { level.ClearSweep();          mSweepHeld = false; }
		if (mFogHeld)   { level.ClearFogSlab();        mFogHeld = false; }

		// RemoveShape, not ClearShapes: ours is one slot out of a shared pool
		// and clearing the pool would take everyone else's with it.
		if (mShapeSlot >= 0) { level.RemoveShape(mShapeSlot); mShapeSlot = -1; }
		if (mLight != null)  { mLight.Destroy(); mLight = null; }
		clearCardModels();
		if (mWaveHeld)  { level.SetGlowWave(0.0, 0.0, 0.0, 0); mWaveHeld = false; }
	}

	// Which payload the ammo bezel is drawn with.
	//
	//   0  BB_SEGMENT -- dark bed, glowing segments. An LED.
	//   1  BB_SEGLCD  -- lit plate with the characters punched out dark. An LCD.
	//   2  BB_WG13    -- GITD's lozenge badge, digits knocked out of the plate.
	//
	// Pick by which reads better against the room rather than by which is more
	// correct: LED wins in the dark, LCD wins against a bright wall.
	private static int readoutKind()
	{
		switch (int(cv("wr_readout", 0.0)))
		{
			case 1:  return LevelLocals.BB_SEGLCD;
			case 2:  return LevelLocals.BB_WG13;
			default: return LevelLocals.BB_SEGMENT;
		}
	}

	// WG13 is DIGITS ONLY -- it takes its number in `data`, not as text -- and
	// it wants a lozenge, not a circle. The original's rule is halfH 46 with
	// halfW = halfH * (0.60 + digits * 0.42); this is that ratio, so a
	// three-digit count gets a wider badge than a one-digit one instead of both
	// being stretched into the same box.
	private static double readoutAspect(int rounds)
	{
		if (readoutKind() != LevelLocals.BB_WG13) return AMMO_W_FRAC;

		int digits = 1;
		if (rounds >= 10)  digits = 2;
		if (rounds >= 100) digits = 3;

		return AMMO_H_FRAC * CARD_STRETCH * (0.60 + digits * 0.42) * 2.0;
	}

	// Which hand, if any, already has this weapon.
	//
	//   0  nobody
	//   1  this hand -- taking it changes nothing
	//   2  the other hand -- taking it swaps, or finds a free clone
	//
	// Informational ONLY. The card stays fully selectable in both cases: the
	// whole point of the swap and the _2 lookup is that picking your other
	// hand's gun is a reasonable thing to ask for, and a marker that greyed it
	// out would be undoing that.
	private int heldWhere(Class<Weapon> type) const
	{
		if (type == null) return 0;

		let mine  = (mRigHand == 1) ? players[consoleplayer].OffhandWeapon
		                            : players[consoleplayer].ReadyWeapon;
		let other = otherHandWeapon();

		if (mine  != null && mine.GetClass()  == type) return 1;
		if (other != null && other.GetClass() == type) return 2;
		return 0;
	}

	// What colour the burst comes out.
	//
	//   0  the slot's colour -- the burst names what you just took
	//   1  white hot
	//   2  rainbow, cycling per particle
	//
	// Rainbow is not the default because the slot colour is doing a JOB: it is
	// the same hue as the card, the accent and the beam, so the burst confirms
	// which one you hit. Rainbow is prettier and says nothing. Both are worth
	// having and only one of them is information.
	private color sparkColor(int card)
	{
		int mode = int(cv("wr_spark_color", 0.0));

		if (mode == 1) return 0xFFF0D8;
		if (mode == 2) return 0;              // per-particle, see sparks()

		if (card >= 0 && card < mCardSlots.Size()) return slotColor(mCardSlots[card]);
		return COLOR_BEAM_IDLE;
	}

	// Full-saturation hue by index, for the rainbow mode. Six linear ramps
	// rather than a proper HSV conversion -- the endpoints are the only thing
	// the eye reads at this size and this is a fraction of the arithmetic.
	private static color hueOf(int i, int n)
	{
		double h = 6.0 * (double(i % max(n, 1)) / max(n, 1));
		int seg = int(h);
		int t = int((h - seg) * 255.0);

		switch (seg)
		{
			case 0:  return color(255, 255, t, 0);
			case 1:  return color(255, 255 - t, 255, 0);
			case 2:  return color(255, 0, 255, t);
			case 3:  return color(255, 0, 255 - t, 255);
			case 4:  return color(255, t, 0, 255);
			default: return color(255, 255, 0, 255 - t);
		}
	}

	// A burst off the card you just took, in that slot's colour.
	//
	// Thrown along the card's own outward bearing rather than sprayed evenly, so
	// it reads as the card breaking apart in the direction it was sitting rather
	// than as a firework going off in mid-air. Gravity on, so they fall.
	private void sparks(Vector3 at, color tint, double amount)
	{
		int count = int(clamp(cv("wr_sparks", 18.0) * amount, 0.0, 200.0));
		if (count <= 0) return;

		double spread = cv("wr_sparks_speed", 1.4);

		for (int i = 0; i < count; ++i)
		{
			FSpawnParticleParams p;

			// A zero tint is the rainbow flag from sparkColor -- no colour is a
			// value nothing legitimately wants, so it costs no extra argument.
			p.color1     = (tint == 0) ? hueOf(i, count) : tint;
			p.style      = STYLE_Add;
			p.lifetime   = 18 + (i * 7) % 22;
			p.size       = 1.6 + (i % 5) * 0.5;
			p.sizestep   = -0.06;
			p.pos        = at;

			// No Math.Random here -- the rig runs in the playsim and a
			// client-side visual must not touch the shared RNG, or two machines
			// disagree about the game state over a spark.
			double a = i * 137.508;                 // golden angle, so no clumps
			double r = 0.35 + (i % 7) * 0.14;

			p.vel = (cos(a) * r, sin(a) * r, 0.55 + (i % 4) * 0.22) * spread;
			p.accel = (0, 0, -0.06);

			p.startalpha = 1.0;
			p.fadestep   = -1.0;                     // engine picks from lifetime

			level.SpawnParticle(p);
		}
	}

	// A REAL MODEL AT EACH CARD.
	//
	// MODELDEF binds a model to a CLASS -- `Model Vanilla_BFG9000 { ... }` --
	// so there is no way to hand a generic carrier somebody else's model. That
	// is the same wall the hand model hit. The way through it is not to copy
	// anything: spawn the weapon's OWN class and the engine resolves its model
	// by itself, which means this works for any model-based weapon set rather
	// than a list of ones we knew about.
	//
	// A billboard cannot do this at all. There is no model payload -- a
	// billboard is a quad -- and rendering a model into a card via a camera
	// texture costs a full RenderViewpoint per card per frame, doubled again for
	// stereo. A real actor costs one model draw and, unlike a picture of a gun
	// on a flat card, it has actual stereo depth and catches the card light.
	//
	// DEFANGED ON SPAWN, and every one of these matters:
	//   bSpecial off   -- an Inventory actor in the world is picked up on touch,
	//                     and a display prop that vanishes into your backpack
	//                     when you reach for its card is worse than no prop.
	//   NOBLOCKMAP     -- never enters the blockmap, so nothing can collide with
	//                     it or even test against it.
	//   NOGRAVITY      -- it hangs where layout() puts it.
	//   NOTONAUTOMAP   -- eight guns should not appear on the map.
	//
	// NOT +NOINTERACTION, and that was a bug. It stops the actor THINKING, and a
	// weapon set is entitled to make its pickup appearance a decision rather
	// than a sprite. VanillaVRPlus does exactly that:
	//
	//     Spawn:
	//         TNT1 A 0 A_JumpIf(GetCVAR("evw_pickupmodel")==1, "Spawn.Model")
	//         BFUG A 1
	//
	// A frozen actor never runs that jump, so it sat on a zero-duration TNT1
	// forever and drew nothing at all. Letting it tick is also just the honest
	// general answer: whatever a weapon set does for its own world pickup is
	// what its card should show, and that is a state machine, not a lookup.
	//
	// Degrades honestly: a weapon with no MODELDEF entry shows its pickup
	// SPRITE in the world instead, which still has depth and still beats a flat
	// icon.
	private void spawnCardModels(PlayerPawn pmo)
	{
		clearCardModels();
		if (cv("wr_models", 0.0) <= 0.0) return;

		double sc = cv("wr_model_scale", 0.16);

		for (int i = 0; i < mTypes.Size(); ++i)
		{
			let a = Actor.Spawn(mTypes[i], pmo.Pos, NO_REPLACE);
			if (a == null) { mModels.Push(null); continue; }

			a.bSpecial      = false;
			a.bNoBlockmap   = true;
			a.bNoGravity    = true;
			a.bNoTonAutomap = true;
			a.bThruActors   = true;
			a.bCountItem    = false;
			a.bNoTrigger    = true;
			a.Vel           = (0, 0, 0);

			a.Scale = (sc, sc);
			a.SetStateLabel('Spawn');

			mModels.Push(a);
		}
	}

	private void clearCardModels()
	{
		for (int i = 0; i < mModels.Size(); ++i)
		{
			if (mModels[i] != null) mModels[i].Destroy();
		}
		mModels.Clear();
	}

	// Guarded so a zero handle is a no-op rather than a call into nothing --
	// half these billboards are optional and the caller should not have to know
	// which ones this time.
	private void fade(int id, double alpha)
	{
		if (id != 0) level.SetBillboardAlpha(id, alpha);
	}

	// Reassembles a card's position from the three arrays it has to live in.
	// Bounds-checked because every caller is already asking "is there a card
	// there", and returning a zero vector is a visible wrong answer rather than
	// an abort.
	private Vector3 cardPos(int i) const
	{
		if (i < 0 || i >= mCardX.Size()) return (0, 0, 0);
		return (mCardX[i], mCardY[i], mCardZ[i]);
	}

	// ONE LIGHT, ON THE CARD YOU ARE POINTING AT.
	//
	// Not one per card, and that is the optimisation that matters: dynamic
	// lights cost per light per surface they touch, so eight of them sitting in
	// a ring a metre from your face is eight overlapping volumes lighting the
	// same wall. Only one card is ever the answer to "which", so only one card
	// needs to say so.
	//
	// The colour is the slot's, so the light, the card, the beam and the burst
	// all agree -- and the radius breathes on the same pulse the card does, so
	// the room brightens and settles with it rather than being a lamp that
	// switched on.
	private void cardLight(PlayerPawn pmo)
	{
		bool want = cv("wr_light", 1.0) > 0.0 && mHovered != 0;

		int card = cardIndexOf(mHovered);
		if (card < 0 || card >= mCardX.Size()) want = false;

		if (!want)
		{
			if (mLight != null) { mLight.Destroy(); mLight = null; }
			return;
		}

		if (mLight == null)
		{
			// Through a local, not straight from cardPos(): SetOrigin and Spawn
			// want a modifiable value, and a function's return is not one.
			Vector3 lp = cardPos(card);
			mLight = Actor(Actor.Spawn("WR_CardLight", lp, NO_REPLACE));
			if (mLight == null) return;
		}

		Vector3 here = cardPos(card);
		mLight.SetOrigin(here, true);

		double breathe = 1.0 + 0.12 * sin(mHoverTics * PULSE_SPEED);
		int r1 = int(cv("wr_light_size", 44.0) * breathe);

		// Re-attached under the same id every tic, which is how the colour and
		// radius change at all -- A_AttachLight replaces a light with a matching
		// id rather than stacking a second one on top.
		mLight.A_AttachLight('wrcard', DynamicLight.PointLight,
			slotColor(mCardSlots[card]), r1, int(r1 * 0.35),
			DynamicLight.LF_ATTENUATE);
	}

	private void updateHover(int hit)
	{
		// Dwell, not instant. Sweeping across a row on the way somewhere else
		// would otherwise open and shut four fans in a third of a second.
		if (hit == mHovered)
		{
			if (mHovered == 0) return;

			++mHoverTics;
			++mDwellTics;

			// Nothing to unfold when every weapon already has its own card --
			// the fan would be a duplicate of cards already on the ring.
			if (mDwellTics == DWELL_TO_EXPAND && !belongsToExpansion(hit)
			    && cv("wr_subcards", 1.0) > 0.0)
			{
				let pmo = players[consoleplayer].mo;
				if (pmo != null)
				{
					int before = mSubIds.Size();
					expandSlot(pmo, cardIndexOf(hit));
					// Only if a fan actually opened. A one-weapon slot does not
					// expand, and announcing an event that did not happen is
					// worse than silence.
					if (mSubIds.Size() > before) feedback(Sound("wristrig/tick"), 0.30, 45);
				}
			}
			return;
		}

		// Pointing at NOTHING does not close the fan.
		//
		// This is what made the subcards unreachable: between the parent card and
		// its fan there is empty space, so travelling from one to the other put
		// hit at 0 for a few tics -- and treating 0 as "left the fan" collapsed it
		// before you ever arrived. Only landing on some OTHER card counts as
		// leaving. Getting bored is handled by the lock timer, which is already
		// the thing that closes a rig you have stopped using.
		if (mExpanded >= 0 && hit != 0 && !belongsToExpansion(hit)) collapseSlot();
		mDwellTics = 0;

		// Recolour the PLATE, not the thing that was hit -- the hit quad is
		// invisible, so tinting it changes nothing anyone can see. Subcards are
		// their own visible billboard and recolour directly.
		tintCard(mHovered, false);
		tintCard(hit, true);

		// Landing on a card, not leaving one. Firing on the way OUT as well would
		// double every crossing, and sweeping the ring would sound like a zip.
		if (hit != 0) feedback(Sound("wristrig/move"), 0.22, 30);

		mHovered   = hit;
		mHoverTics = 0;
		if (hit != 0) mLockTics = int(cv("wr_locktics", 140));
	}

	// Straight into the hand, no lower and no raise.
	//
	// MoveWeaponToHand is the correct engine call and it is NOT usable here: it
	// ends in DropWeapon, which starts the deselect animation, so the gun you
	// asked for arrives half a second after you asked. In a menu you have
	// already spent time in, that reads as the pick not registering.
	//
	// So this does what BringUpWeapon does minus the raise -- sets the hand's
	// weapon and puts its psprite straight into the ready state. The two things
	// MoveWeaponToHand does that actually matter are kept: the hand flag is
	// mirrored onto the sister weapon, or a powered-up Tome variant ends up
	// pointing at the wrong hand; and bNoHandSwitch is honoured rather than
	// quietly overridden.
	private void equipInstantly(PlayerPawn pmo, Weapon weap, int hand)
	{
		let player = pmo.player;
		if (player == null || weap == null) return;

		bool wantOffhand = (hand == 1);

		if (weap.bNoHandSwitch && weap.bOffhandWeapon != wantOffhand) return;

		// Coming out of the other hand: empty it first, or the same weapon is
		// held twice and the engine's own bookkeeping disagrees with itself.
		if (wantOffhand && player.ReadyWeapon == weap)  player.ReadyWeapon  = null;
		if (!wantOffhand && player.OffhandWeapon == weap) player.OffhandWeapon = null;

		weap.bOffhandWeapon = wantOffhand;
		if (weap.SisterWeapon != null) weap.SisterWeapon.bOffhandWeapon = wantOffhand;

		if (wantOffhand) player.OffhandWeapon = weap;
		else             player.ReadyWeapon   = weap;

		player.PendingWeapon = WP_NOCHANGE;

		int layer = wantOffhand ? PSP_OFFHANDWEAPON : PSP_WEAPON;
		player.SetPsprite(layer, weap.GetReadyState());

		// NO SCALE BOOKKEEPING HERE. It is commit()'s job, and it has to happen
		// BEFORE any of this runs -- see the note there. Dropping the flag at
		// this point without putting the scale back is what shrank the weapon by
		// half on every single use.
	}

	// Which weapon the OTHER hand is holding, or null.
	private Weapon otherHandWeapon() const
	{
		return (mRigHand == 1) ? players[consoleplayer].ReadyWeapon
		                       : players[consoleplayer].OffhandWeapon;
	}

	// The family root of a cloned weapon: RS_PlasmaRifle_3 -> RS_PlasmaRifle.
	//
	// The convention is a mod one, not an engine one -- a weapon set that wants
	// two of the same gun cannot use the same class twice, so it ships numbered
	// subclasses with their own tags and selection numbers. Stripping the suffix
	// is what lets the rig recognise those as siblings rather than as unrelated
	// weapons that happen to look alike.
	private static string familyRoot(string name)
	{
		int n = name.Length();
		if (n < 3) return name;

		// Only a single trailing digit after an underscore. _10 is not a thing
		// anyone ships, and being greedy here would fold BFG_9000 into BFG_900.
		//
		// ByteAt rather than comparing one-character strings: ZScript's string
		// operators are equality only, so '<' on a string is not the ordering
		// test it looks like.
		int last = name.ByteAt(n - 1);
		if (name.ByteAt(n - 2) != 0x5F) return name;   // '_'
		if (last < 0x32 || last > 0x39) return name;   // '2'..'9'

		return name.Left(n - 2);
	}

	// A sibling of this weapon that the player owns and NEITHER hand is holding.
	//
	// This is the good outcome when you pick the gun your other hand already
	// has: a mod that ships _2 through _6 clones did so precisely so you could
	// hold two, and taking the clone gives you what you clearly meant -- one in
	// each hand -- rather than shuffling the single copy back and forth.
	private Weapon freeTwinOf(PlayerPawn pmo, Class<Weapon> want) const
	{
		// Assigned to a string first: GetClassName returns a Name, and relying on
		// an implicit conversion inside an argument list is the kind of thing
		// that reports as an unrelated error two lines away.
		string cn = want.GetClassName();
		string root = familyRoot(cn);

		let inHand  = otherHandWeapon();
		let inMine  = (mRigHand == 1) ? players[consoleplayer].OffhandWeapon
		                              : players[consoleplayer].ReadyWeapon;

		// The root itself first, then _2 upward, so picking a clone can fall back
		// to the original as readily as the other way round.
		for (int i = 0; i <= 8; ++i)
		{
			string candidate = (i == 0) ? root : String.Format("%s_%d", root, i + 1);

			Class<Weapon> cls = (class<Weapon>)(candidate);
			if (cls == null || cls == want) continue;

			let twin = Weapon(pmo.FindInventory(cls));
			if (twin == null) continue;
			if (twin == inHand || twin == inMine) continue;

			// No point handing this hand something it is forbidden to hold.
			if (twin.bNoHandSwitch && twin.bOffhandWeapon != (mRigHand == 1)) continue;

			return twin;
		}
		return null;
	}

	private void commit(PlayerPawn pmo)
	{
		// A card from the fan names one specific weapon; a slot card names that
		// slot's first. Checking the fan first matters -- while a fan is open its
		// parent card is still hittable, and the fan is the more specific answer.
		Class<Weapon> want = null;

		int sub = subIndexOf(mHovered);
		if (sub >= 0 && sub < mSubTypes.Size())
		{
			want = mSubTypes[sub];
		}
		else
		{
			int index = cardIndexOf(mHovered);
			if (index < 0 || index >= mTypes.Size()) return;
			want = mTypes[index];
		}

		let weap = Weapon(pmo.FindInventory(want));
		if (weap == null) { closeRig(); return; }

		// PICKING THE GUN YOUR OTHER HAND IS ALREADY HOLDING.
		//
		// It used to be taken literally: the weapon moved across, and the hand it
		// came from was left empty. That is almost never what the ask meant. Two
		// better answers, in order:
		//
		//   1. A FREE TWIN. A weapon set that ships _2 through _6 clones did so
		//      specifically so you could hold two. Take the clone and you end up
		//      with one in each hand, which is the thing you were reaching for.
		//
		//   2. A SWAP. No clone to take, so the hands trade: what you picked
		//      comes here, what was here goes there. Nothing is put down, and
		//      the move is reversible by doing it again -- which is the property
		//      that makes it safe to try mid-fight.
		//
		// Order matters. Swapping first would be a worse outcome reached faster.
		bool swapped = false;
		if (weap == otherHandWeapon())
		{
			let twin = freeTwinOf(pmo, want);
			if (twin != null)
			{
				weap = twin;
			}
			else
			{
				// Read BEFORE the first equip: equipInstantly rewrites both
				// hands' pointers, so afterwards there is nothing left to move.
				let mine = (mRigHand == 1) ? players[consoleplayer].OffhandWeapon
				                           : players[consoleplayer].ReadyWeapon;

				equipInstantly(pmo, weap, mRigHand);

				// Not guaranteed to land: a bNoHandSwitch weapon refuses the
				// other hand, and equipInstantly returns without doing anything.
				// That leaves the other hand empty, which is still a better
				// outcome than refusing the pick the player actually made.
				if (mine != null && mine != weap)
				{
					equipInstantly(pmo, mine, mRigHand == 1 ? 0 : 1);
				}
				swapped = true;
			}
		}

		// The confirm, and it is deliberately the biggest thing the rig does:
		// twice the hover pulse and three times as long. This is the one moment
		// worth being unmistakable, because it is the one that changes the game
		// state, and it fires BEFORE closeRig so it is not lost to the teardown.
		//
		// A DRY PICK SOUNDS WRONG ON PURPOSE. It still equips -- you asked for
		// it and you may well have meant it -- but you find out now, from the
		// wrist, rather than at the trigger with something walking at you. The
		// pulse is shorter and weaker too: the hand agrees with the ear.
		bool dry = (ammoLeft(weap) == 0);
		if (dry) feedback(Sound("wristrig/nope"), 0.35, 60);
		else     feedback(Sound("wristrig/lock"), 0.75, 90);

		// THE CARD COMES APART.
		//
		// Fired from where the card actually is, which is why it happens here
		// and not after closeRig -- the ring is torn down on the next line and
		// the position goes with it.
		//
		// A dry pick gets a smaller, sadder burst. The rig says the same thing
		// three ways at that moment -- a different sound, a weaker pulse, fewer
		// sparks -- because it is the one outcome you might genuinely not have
		// meant.
		int hitCard = cardIndexOf(mHovered);
		if (hitCard >= 0 && hitCard < mCardX.Size())
		{
			Vector3 burstAt = cardPos(hitCard);
			sparks(burstAt, sparkColor(hitCard), dry ? 0.4 : 1.0);

			// And it flips as it folds away. Roll is a real axis now, and the
			// group collapse keeps the billboards alive long enough to see it.
			mFlipCard = hitCard;
			mFlipTics = CLOSE_TICS;
		}

		// The swap already did its own equipping, above, because it needed to
		// read the outgoing weapon before anything moved.
		if (!swapped) equipInstantly(pmo, weap, mRigHand);
		closeRig(true);
	}

	const PANEL_TILT  = 12.0;
	const COLOR_IDLE  = 0x2E3440;
	const COLOR_HOVER = 0xEF9F27;
	const COLOR_LABEL = 0xD8DEE9;
	const COLOR_CENTRE      = 0x1C2029;
	const COLOR_CENTRE_TEXT = 0x7A8494;
	const COLOR_SUB         = 0x4A3A20;
	const HIT_PAD           = 1.12;
	const PULSE_SPEED       = 14.0;   // degrees per tic
	const POINTER_RANGE     = 200.0;
	const DWELL_TO_EXPAND   = 7;    // tics on a slot before its fan opens
	const GLOW_RADIUS   = 3.0;
	const GLOW_STRENGTH = 1.4;

	const LABEL_LIFT        = 0.6;
	const LABEL_HEIGHT_FRAC = 0.34;

	// A card with nothing left in it. Dark red rather than grey: grey reads as
	// disabled, and this weapon is not disabled -- you can absolutely select it,
	// it just will not fire.
	// What the beam, the sweep and the mist are tinted when the pointer is on
	// nothing. Cool and dim on purpose: every slot colour is warmer or brighter
	// than this, so landing on a card always reads as a step UP.
	const COLOR_BEAM_IDLE = 0x5A6C7A;

	const COLOR_DRY      = 0x3A2226;
	const COLOR_AMMO     = 0x8C97A8;
	const COLOR_AMMO_DRY = 0xC65C5C;

	// The held-weapon mark. The OTHER hand gets the brighter one: that is the
	// case where taking the card actually does something -- a swap, or a free
	// clone -- and the dim one just says "you are already holding this".
	const COLOR_MARK_MINE  = 0x6E7684;
	const COLOR_MARK_OTHER = 0xEFC94C;

	// Billboards render 1.2x taller than authored -- world Z is stretched by the
	// view matrix and the billboard path never unstretches it.
	const CARD_STRETCH = 1.2;

	// CANVAS FACES. Pixel coordinates, matching the ANIMDEFS declarations --
	// change one and the other has to move with it.
	const FACE_W      = 140;
	const FACE_H      = 100;
	const FACE_POOL   = 12;    // how many WRFACEnn textures are declared
	const FACE_BANDS  = 5;     // gradient steps
	const FACE_ACCENT = 6;     // slot stripe height
	const ICON_BOX_W  = 96.0;
	const ICON_BOX_H  = 32.0;
	const ICON_TOP    = 22.0;
	// CANVAS LAYOUT, top to bottom, and it has to dodge the billboards.
	//
	// The name and the segment readout are drawn as separate field billboards
	// IN FRONT of the canvas, at fixed fractions of the card. So the painted
	// artwork does not get the whole face -- it gets everything above them, and
	// anything it puts in the bottom third lands underneath a label.
	//
	// Hence pips at the TOP, under the accent, rather than in the natural place
	// at the bottom: the bottom is spoken for.
	const PIP_TOP     = 11;
	const BAR_INSET   = 10;
	const BAR_H       = 8;

	// Where the label and segment land in canvas pixels, from their billboard
	// fractions. Kept as constants so the dim band below tracks them instead of
	// being a number tuned by eye.
	const READOUT_TOP = 56;

	// At or under this many rounds, one pip means one SHOT. Above it, ten pips
	// mean tenths -- forty countable rectangles is just a worse bar.
	const PIP_LITERAL_MAX = 12;
	const PIP_TENTHS      = 10;

	// The box an icon is fitted into, as a fraction of the card.
	const ICON_W_FRAC = 0.72;
	const ICON_H_FRAC = 0.46;
	const AMMO_H_FRAC = 0.22;
	const AMMO_W_FRAC = 0.52;
	const GAUGE_H_FRAC = 0.07;
	const ACCENT_H_FRAC = 0.075;

	// How much of the card's width a name may use before it is shrunk to fit.
	const LABEL_FIT_FRAC = 0.90;

	// The far end of each plate's gradient. Darker than the near end in both
	// cases, so the card has a lit top and a shaded bottom.
	const GRAD_IDLE = 0xFF11141B;
	const GRAD_DRY  = 0xFF1E1013;
	const GRAD_HOVER = 0xFF8A5A12;
	const GRAD_CENTRE = 0xFF0E1116;

	// Neon on the hovered name. radius is a fraction of the atlas spread, so 1
	// is the practical maximum -- past the spread there is no field left and the
	// halo clips square at the glyph cell.
	const GLOW_R = 0.75;
	const GLOW_S = 0.9;

	// Tics the ring takes to fold away. The billboards outlive closeRig by this
	// much so it can collapse rather than blink out.
	const CLOSE_TICS = 7;

	// How far a card tumbles on its way in, in degrees of roll.
	const ARRIVE_ROLL = 26.0;
}

// Test loadout -- everything, immediately, so the rig can be looked at with a
// full arc instead of a fist and a pistol.
//
// Pick "Rig Test" in Player Setup. Deliberately a separate class rather than
// giving weapons on level start: this leaves a normal game normal, and it
// survives map changes and saves without any code watching for them.
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


// Carrier for the hovered card's light.
//
// An actor only because A_AttachLight is an actor method -- there is no way to
// hang a dynamic light on a billboard, which is what this actually wants to be.
// Nothing about it participates in the world: no collision, no gravity, no
// thinking, nothing drawn.
class WR_CardLight : Actor
{
	Default
	{
		+NOINTERACTION;
		+NOBLOCKMAP;
		+NOGRAVITY;
		+NOTONAUTOMAP;
		+DONTSPLASH;
		RenderStyle "None";
	}

	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	}
}
