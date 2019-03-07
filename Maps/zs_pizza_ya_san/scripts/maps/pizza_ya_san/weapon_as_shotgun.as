/* 
 * HLベース改造ショットガン
 * 
 * fgdファイルに下記を追加して、エンティティとしてマップに仕込むこと。
 * @PointClass base(Weapon, Targetx, ExclusiveHold) studio("models/pizza_ya_san/w_shotgun_shorty.mdl") = weapon_as_shotgun : "custom shotgun" []
 */

const Vector VECTOR_CONE_DM_SHOTGUN( 0.13074, 0.13074, 0.00  );		// 15 degrees

const int SHOTGUN_DEFAULT_AMMO 	= 12;
const int SHOTGUN_MAX_CARRY 	= 125;
const int SHOTGUN_MAX_CLIP 		= 4;
const int SHOTGUN_WEIGHT 		= 15;

const uint SHOTGUN_PELLETCOUNT = 9;

enum ShotgunAnimation
{
	SHOTGUN_IDLE = 0,
	SHOTGUN_FIRE,
	SHOTGUN_FIRE2,
	SHOTGUN_RELOAD,
	SHOTGUN_PUMP,
	SHOTGUN_START_RELOAD,
	SHOTGUN_DRAW,
	SHOTGUN_HOLSTER,
	SHOTGUN_IDLE4,
	SHOTGUN_IDLE_DEEP
};

class weapon_as_shotgun : ScriptBasePlayerWeaponEntity
{
	private CBasePlayer@ m_pPlayer = null;


	float m_flNextReload;
	int m_iShell;
	float m_flPumpTime;
	bool m_fPlayPumpSound;
	bool m_fShotgunReload;

	void Spawn()
	{
		Precache();
		g_EntityFuncs.SetModel( self, "models/pizza_ya_san/w_shotgun_shorty.mdl" );
		
		self.m_iDefaultAmmo = SHOTGUN_DEFAULT_AMMO;

		self.FallInit();// get ready to fall
	}

	void Precache()
	{
		self.PrecacheCustomModels();
		g_Game.PrecacheModel( "models/pizza_ya_san/v_shotgun_shorty.mdl" );
		g_Game.PrecacheModel( "models/pizza_ya_san/w_shotgun_shorty.mdl" );
		g_Game.PrecacheModel( "models/pizza_ya_san/p_shotgun_shorty.mdl" );

		m_iShell = g_Game.PrecacheModel( "models/shotgunshell.mdl" );// shotgun shell

		g_SoundSystem.PrecacheSound( "items/9mmclip1.wav" );              

		g_SoundSystem.PrecacheSound( "weapons/dbarrel1.wav" );//shotgun
		g_SoundSystem.PrecacheSound( "weapons/sbarrel1.wav" );//shotgun

		g_SoundSystem.PrecacheSound( "weapons/reload1.wav" );	// shotgun reload
		g_SoundSystem.PrecacheSound( "weapons/reload3.wav" );	// shotgun reload

		g_SoundSystem.PrecacheSound("weapons/sshell1.wav");	// shotgun reload
		g_SoundSystem.PrecacheSound("weapons/sshell3.wav");	// shotgun reload
		
		g_SoundSystem.PrecacheSound( "weapons/357_cock1.wav" ); // gun empty sound
		g_SoundSystem.PrecacheSound( "weapons/scock1.wav" );	// cock gun
	}

	bool AddToPlayer( CBasePlayer@ pPlayer )
	{
		if(!BaseClass.AddToPlayer( pPlayer ) )
			return false;

		@m_pPlayer = pPlayer;

		NetworkMessage message( MSG_ONE, NetworkMessages::WeapPickup, pPlayer.edict() );
			message.WriteLong( g_ItemRegistry.GetIdForName("weapon_as_shotgun") );
		message.End();
		return true;
	}
	
	bool PlayEmptySound()
	{
		self.m_bPlayEmptySound = false;
			
		g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, "weapons/357_cock1.wav", 0.8, ATTN_NORM, 0, PITCH_NORM );
		
		
		return false;
	}

	bool GetItemInfo( ItemInfo& out info )
	{
		info.iMaxAmmo1 	= SHOTGUN_MAX_CARRY;
		info.iMaxAmmo2 	= -1;
		info.iMaxClip 	= SHOTGUN_MAX_CLIP;
		info.iSlot 		= 2;
		info.iPosition 	= 5;
		info.iFlags 	= 0;
		info.iWeight 	= SHOTGUN_WEIGHT;

		return true;
	}

	bool Deploy()
	{
		return self.DefaultDeploy( self.GetV_Model( "models/pizza_ya_san/v_shotgun_shorty.mdl" ), self.GetP_Model( "models/pizza_ya_san/p_shotgun_shorty.mdl" ), SHOTGUN_DRAW, "shotgun" );
	}
	
	void Holster( int skipLocal = 0 )
	{
		m_fShotgunReload = false;
		
		BaseClass.Holster( skipLocal );
	}

	void ItemPostFrame()
	{
		if( m_flPumpTime != 0 && m_flPumpTime < g_Engine.time && m_fPlayPumpSound )
		{
			// play pumping sound
			g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_ITEM, "weapons/scock1.wav", 1, ATTN_NORM, 0, 95 + Math.RandomLong( 0,0x1f ) );

			m_fPlayPumpSound = false;
		}

		BaseClass.ItemPostFrame();
	}
	
	void CreatePelletDecals( const Vector& in vecSrc, const Vector& in vecAiming, const Vector& in vecSpread, const uint uiPelletCount )
	{
		TraceResult tr;
		
		float x, y;
		
		for( uint uiPellet = 0; uiPellet < uiPelletCount; ++uiPellet )
		{
			g_Utility.GetCircularGaussianSpread( x, y );
			
			Vector vecDir = vecAiming 
							+ x * vecSpread.x * g_Engine.v_right 
							+ y * vecSpread.y * g_Engine.v_up;

			Vector vecEnd	= vecSrc + vecDir * 2048;
			
			g_Utility.TraceLine( vecSrc, vecEnd, dont_ignore_monsters, m_pPlayer.edict(), tr );
			
			if( tr.flFraction < 1.0 )
			{
				if( tr.pHit !is null )
				{
					CBaseEntity@ pHit = g_EntityFuncs.Instance( tr.pHit );
					
					if( pHit is null || pHit.IsBSPModel() )
						g_WeaponFuncs.DecalGunshot( tr, BULLET_PLAYER_BUCKSHOT );
				}
			}
		}
	}

	void PrimaryAttack()
	{
		// don't fire underwater
		if( m_pPlayer.pev.waterlevel == WATERLEVEL_HEAD )
		{
			self.PlayEmptySound();
			self.m_flNextPrimaryAttack = g_Engine.time + 0.15;
			return;
		}

		if( self.m_iClip <= 0 )
		{
			self.m_flNextPrimaryAttack = self.m_flTimeWeaponIdle = g_Engine.time + 0.75;
			self.Reload();
			self.PlayEmptySound();
			return;
		}

		self.SendWeaponAnim( SHOTGUN_FIRE, 0, 0 );
		
		g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, "weapons/sbarrel1.wav", Math.RandomFloat( 0.95, 1.0 ), ATTN_NORM, 0, 93 + Math.RandomLong( 0, 0x1f ) );
		
		m_pPlayer.m_iWeaponVolume = LOUD_GUN_VOLUME;
		m_pPlayer.m_iWeaponFlash = NORMAL_GUN_FLASH;

		--self.m_iClip;

		// player "shoot" animation
		m_pPlayer.SetAnimation( PLAYER_ATTACK1 );

		Vector vecSrc	 = m_pPlayer.GetGunPosition();
		Vector vecAiming = m_pPlayer.GetAutoaimVector( AUTOAIM_5DEGREES );

		m_pPlayer.FireBullets( SHOTGUN_PELLETCOUNT, vecSrc, vecAiming, VECTOR_CONE_DM_SHOTGUN, 2048, BULLET_PLAYER_BUCKSHOT, 0 );
	    
	    //Shell ejection
		Math.MakeVectors( m_pPlayer.pev.v_angle );
		
		Vector	vecShellVelocity = m_pPlayer.pev.velocity 
							 + g_Engine.v_right * Math.RandomFloat(50, 70) 
							 + g_Engine.v_up* Math.RandomFloat(100, 150) 
							 + g_Engine.v_forward * 25;
		
		g_EntityFuncs.EjectBrass(vecSrc + m_pPlayer.pev.view_ofs + g_Engine.v_up * -34 + g_Engine.v_forward * 14 + g_Engine.v_right * 6, vecShellVelocity, m_pPlayer.pev.angles.y, m_iShell, TE_BOUNCE_SHELL);
	    
		if( self.m_iClip == 0 && m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) <= 0 )
			// HEV suit - indicate out of ammo condition
			m_pPlayer.SetSuitUpdate( "!HEV_AMO0", false, 0 );

		if( self.m_iClip != 0 )
			m_flPumpTime = g_Engine.time + 0.5;
			
		m_pPlayer.pev.punchangle.x = -5.0;

		self.m_flNextPrimaryAttack = g_Engine.time + 0.65;
		self.m_flNextSecondaryAttack = g_Engine.time + 0.65;

		if( self.m_iClip != 0 )
			self.m_flTimeWeaponIdle = g_Engine.time + 5.0;
		else
			self.m_flNextPrimaryAttack = self.m_flTimeWeaponIdle = g_Engine.time + 0.75;

		m_fShotgunReload = false;
		m_fPlayPumpSound = true;
		
		CreatePelletDecals( vecSrc, vecAiming, VECTOR_CONE_DM_SHOTGUN, SHOTGUN_PELLETCOUNT );
	}

	void SecondaryAttack()
	{
	    PrimaryAttack();
		self.SendWeaponAnim( SHOTGUN_FIRE2, 0, 0 );
		self.m_flNextPrimaryAttack = g_Engine.time + 1.7;
		self.m_flNextSecondaryAttack = g_Engine.time + 1.7;
	    self.m_flTimeWeaponIdle = g_Engine.time + 1.0;
		m_fShotgunReload = true;
		m_fPlayPumpSound = false;
	    
	}

	void Reload()
	{
		if( m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) <= 0 || self.m_iClip == SHOTGUN_MAX_CLIP )
			return;

		if( m_flNextReload > g_Engine.time )
			return;

		// don't reload until recoil is done
		if( self.m_flNextPrimaryAttack > g_Engine.time && !m_fShotgunReload )
			return;

		// check to see if we're ready to reload
		if( !m_fShotgunReload )
		{
			self.SendWeaponAnim( SHOTGUN_START_RELOAD, 0, 0 );
		    	m_pPlayer.m_flNextAttack 	= 0.3;
			self.m_flTimeWeaponIdle			= g_Engine.time + 0.3;
			self.m_flNextPrimaryAttack 		= g_Engine.time + 0.5;
			self.m_flNextSecondaryAttack	= g_Engine.time + 0.5;
			m_fShotgunReload = true;
			return;
		}
		else if( m_fShotgunReload )
		{
			if( self.m_flTimeWeaponIdle > g_Engine.time )
				return;

			if( self.m_iClip == SHOTGUN_MAX_CLIP )
			{
				m_fShotgunReload = false;
				return;
			}

			self.SendWeaponAnim( SHOTGUN_RELOAD, 0 );
		    m_flNextReload 					= g_Engine.time + 0.25;
			self.m_flNextPrimaryAttack 		= g_Engine.time + 0.25;
			self.m_flNextSecondaryAttack 	= g_Engine.time + 0.25;
			self.m_flTimeWeaponIdle 		= g_Engine.time + 0.25;
				
				
			// Add them to the clip
			self.m_iClip += 1;
			m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType, m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) - 1 );
			
			switch( Math.RandomLong( 0, 1 ) )
			{
			case 0:
				g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_ITEM, "weapons/reload1.wav", 1, ATTN_NORM, 0, 85 + Math.RandomLong( 0, 0x1f ) );
				break;
			case 1:
				g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_ITEM, "weapons/reload3.wav", 1, ATTN_NORM, 0, 85 + Math.RandomLong( 0, 0x1f ) );
				break;
			}
		}

		BaseClass.Reload();
	}

	void WeaponIdle()
	{
		self.ResetEmptySound();

		m_pPlayer.GetAutoaimVector( AUTOAIM_5DEGREES );

		if( self.m_flTimeWeaponIdle < g_Engine.time )
		{
			if( self.m_iClip == 0 && !m_fShotgunReload && m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) != 0 )
			{
				self.Reload();
			}
			else if( m_fShotgunReload )
			{
				if( self.m_iClip != SHOTGUN_MAX_CLIP && m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) > 0 )
				{
					self.Reload();
				}
				else
				{
					// reload debounce has timed out
					self.SendWeaponAnim( SHOTGUN_PUMP, 0, 0 );

					g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_ITEM, "weapons/scock1.wav", 1, ATTN_NORM, 0, 95 + Math.RandomLong( 0,0x1f ) );
					m_fShotgunReload = false;
					self.m_flTimeWeaponIdle = g_Engine.time + 1.5;
				}
			}
			else
			{
				int iAnim;
				float flRand = g_PlayerFuncs.SharedRandomFloat( m_pPlayer.random_seed, 0, 1 );
				if( flRand <= 0.8 )
				{
					iAnim = SHOTGUN_IDLE_DEEP;
					self.m_flTimeWeaponIdle = g_Engine.time + (60.0/12.0);// * RANDOM_LONG(2, 5);
				}
				else if( flRand <= 0.95 )
				{
					iAnim = SHOTGUN_IDLE;
					self.m_flTimeWeaponIdle = g_Engine.time + (20.0/9.0);
				}
				else
				{
					iAnim = SHOTGUN_IDLE4;
					self.m_flTimeWeaponIdle = g_Engine.time+ (20.0/9.0);
				}
				self.SendWeaponAnim( iAnim, 1, 0 );
			}
		}
	}
}

string GetASShotgunName()
{
	return "weapon_as_shotgun";
}

void RegisterASShotgun()
{
	g_CustomEntityFuncs.RegisterCustomEntity( "weapon_as_shotgun", GetASShotgunName() );
	g_ItemRegistry.RegisterWeapon( GetASShotgunName(), "pizza_ya_san", "buckshot" );
}
