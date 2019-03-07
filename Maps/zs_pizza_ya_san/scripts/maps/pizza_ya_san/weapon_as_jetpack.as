/*  
 * Jetpack & Glock18
 * (Refeneced: The original Half-Life version of the mp5)
 */
enum GlockAnimation {
    GLOCK_IDLE1 = 0,
    GLOCK_IDLE2,
    GLOCK_IDLE3,
    GLOCK_SHOOT,
    GLOCK_SHOOT_EMPTY,
    GLOCK_RELOAD,
    GLOCK_RELOAD_NOT_EMPTY,
    GLOCK_DRAW,
    GLOCK_HOLSTER,
    GLOCK_ADD_SILENCER
};

const int MP5_DEFAULT_GIVE  = 100;
const int MP5_MAX_AMMO      = 250;
const int MP5_MAX_AMMO2     = 100;
const int MP5_MAX_CLIP      = 10;
const int MP5_WEIGHT        = 5;

const float LOW_GRAVITY    = 0.3;
const float NORMAL_GRAVITY = 1.0;

const int FUEL_CYCLE = 60;

class weapon_as_jetpack : ScriptBasePlayerWeaponEntity {
    private CBasePlayer@ m_pPlayer = null;

    float m_flNextAnimTime;
    int m_iShell;
    int m_iSecondaryAmmo;
    int m_iFuel; // 燃料
    // 爆発＆スモーク用
    int m_iBurnSound;
    int m_gBurnSprite;
    int m_gSmokeSprite;
    
    float m_gravityLowTime; // 重力軽減時間用
    
    void Spawn() {
        Precache();
        g_EntityFuncs.SetModel( self, "models/pizza_ya_san/w_glock18jet.mdl" );

        self.m_iDefaultAmmo = MP5_DEFAULT_GIVE;
        self.m_iSecondaryAmmoType = 0;
        self.FallInit();
        self.m_iClip = 3;
    }

    void Precache() {
        self.PrecacheCustomModels();
        g_Game.PrecacheModel( "models/pizza_ya_san/v_glock18jet.mdl" );
        g_Game.PrecacheModel( "models/pizza_ya_san/w_glock18jet.mdl" );
        g_Game.PrecacheModel( "models/pizza_ya_san/p_glock18jet.mdl" );

        m_iShell = g_Game.PrecacheModel( "models/shell.mdl" );

        g_Game.PrecacheModel( "models/w_9mmARclip.mdl" );
        g_SoundSystem.PrecacheSound( "items/9mmclip1.wav" );

        //These are played by the model, needs changing there
        g_SoundSystem.PrecacheSound( "hl/items/clipinsert1.wav" );
        g_SoundSystem.PrecacheSound( "hl/items/cliprelease1.wav" );
        g_SoundSystem.PrecacheSound( "hl/items/guncock1.wav" );

        g_SoundSystem.PrecacheSound( "/weapons/hks1.wav" );
        g_SoundSystem.PrecacheSound( "hl/weapons/357_cock1.wav" );
        
        // 噴射サウンド
        g_SoundSystem.PrecacheSound("ambience/steamburst1.wav");
        // 噴射
        m_gBurnSprite  = g_Game.PrecacheModel("sprites/xflare2.spr");
        m_gSmokeSprite = g_Game.PrecacheModel("sprites/boom3.spr");
    }

    bool GetItemInfo( ItemInfo& out info ) {
        info.iMaxAmmo1 = MP5_MAX_AMMO;
        info.iMaxAmmo2 = MP5_MAX_AMMO2;
        info.iMaxClip  = MP5_MAX_CLIP;
        info.iSlot     = 2;
        info.iPosition = 4;
        info.iFlags    = 0;
        info.iWeight   = MP5_WEIGHT;
        return true;
    }

    bool AddToPlayer( CBasePlayer@ pPlayer ) {
        if(!BaseClass.AddToPlayer( pPlayer ) )
		return false;

	@m_pPlayer = pPlayer;

	NetworkMessage message( MSG_ONE, NetworkMessages::WeapPickup, pPlayer.edict() );
		message.WriteLong( g_ItemRegistry.GetIdForName("weapon_as_jetpack") );
	message.End();
	return true;
    }
    
    bool PlayEmptySound() {
        if( self.m_bPlayEmptySound ) {
            self.m_bPlayEmptySound = false;
            g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, "hl/weapons/357_cock1.wav", 0.8, ATTN_NORM, 0, PITCH_NORM );
        }
        return false;
    }

    bool Deploy() {
        m_iFuel = 0;
        m_iBurnSound = 0;
        return self.DefaultDeploy( self.GetV_Model( "models/pizza_ya_san/v_glock18jet.mdl" ), self.GetP_Model( "models/pizza_ya_san/p_glock18jet.mdl" ), GLOCK_DRAW, "onehanded" );
    }
    
    void Holster( int skiplocal ){
        
        m_pPlayer.pev.gravity = NORMAL_GRAVITY;
    }
    
    float WeaponTimeBase() {
        return g_Engine.time; //g_WeaponFuncs.WeaponTimeBase();
    }

    // プライマリアタック
    void PrimaryAttack() {
        // 水中は射撃不可、弾薬なし
        if ((m_pPlayer.pev.waterlevel == WATERLEVEL_HEAD )
            || ( m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) <= 0 )
        ) {
            self.PlayEmptySound();
            self.m_flNextPrimaryAttack = WeaponTimeBase() + 0.15;
            return;
        }

        m_pPlayer.m_iWeaponVolume = NORMAL_GUN_VOLUME;
        m_pPlayer.m_iWeaponFlash = NORMAL_GUN_FLASH;

        m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType, m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) - 1 );
        
        // 弾薬があるなら
        if (m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) > 1) {
            self.SendWeaponAnim( GLOCK_SHOOT, 0, 0 ); 
        } else {
            self.SendWeaponAnim( GLOCK_SHOOT_EMPTY, 0, 0 ); 
        }
        
        g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, "/weapons/hks1.wav", 1.0, ATTN_NORM, 0, 95 + Math.RandomLong( 0, 10 ) );

        m_pPlayer.SetAnimation( PLAYER_ATTACK1 );

        // 弾丸の処理
        Vector vecSrc     = m_pPlayer.GetGunPosition();
        Vector vecAiming = m_pPlayer.GetAutoaimVector( AUTOAIM_5DEGREES );
        m_pPlayer.FireBullets( 1, vecSrc, vecAiming, VECTOR_CONE_6DEGREES, 8192, BULLET_PLAYER_MP5, 2 );

        // 薬莢
        Math.MakeVectors( m_pPlayer.pev.v_angle );
        
        Vector vecShellVelocity = m_pPlayer.pev.velocity 
                             + g_Engine.v_right * Math.RandomFloat(50, 70) 
                             + g_Engine.v_up* Math.RandomFloat(100, 150) 
                             + g_Engine.v_forward * 25;
        g_EntityFuncs.EjectBrass(vecSrc
                            + m_pPlayer.pev.view_ofs
                                + g_Engine.v_up * -34
                                    + g_Engine.v_forward * 14 + g_Engine.v_right * 6,
                            vecShellVelocity,
                            m_pPlayer.pev.angles.y,
                            m_iShell,
                            TE_BOUNCE_SHELL);
        
        m_pPlayer.pev.punchangle.x = Math.RandomLong( -2, 2 );

        self.m_flNextPrimaryAttack = self.m_flNextPrimaryAttack + 0.05;
        if (self.m_flNextPrimaryAttack < WeaponTimeBase() ) {
            self.m_flNextPrimaryAttack = WeaponTimeBase() + 0.05;
        }

        self.m_flTimeWeaponIdle = WeaponTimeBase() + g_PlayerFuncs.SharedRandomFloat( m_pPlayer.random_seed,  10, 15 );
        
        TraceResult tr;        
        float x, y;        
        g_Utility.GetCircularGaussianSpread( x, y );
        
        Vector vecDir = vecAiming 
                        + x * VECTOR_CONE_6DEGREES.x * g_Engine.v_right 
                        + y * VECTOR_CONE_6DEGREES.y * g_Engine.v_up;

        Vector vecEnd    = vecSrc + vecDir * 4096;

        g_Utility.TraceLine( vecSrc, vecEnd, dont_ignore_monsters, m_pPlayer.edict(), tr );
        
        if( tr.flFraction < 1.0 ) {
            if ( tr.pHit !is null ) {
                CBaseEntity@ pHit = g_EntityFuncs.Instance( tr.pHit );
                if( pHit is null || pHit.IsBSPModel() ) {
                    g_WeaponFuncs.DecalGunshot( tr, BULLET_PLAYER_MP5 );
                }
            }
        }
    }

    // セカンダリアタック
    void SecondaryAttack() {
        // 水中は飛行不可、また燃料なしは飛ばない
        if ((m_pPlayer.pev.waterlevel == WATERLEVEL_HEAD )
            || (m_pPlayer.m_rgAmmo( self.m_iSecondaryAmmoType ) <= 0)) {
            self.PlayEmptySound();
            self.m_flNextSecondaryAttack = WeaponTimeBase() + 0.15;
            return;
        }
        
        m_pPlayer.pev.gravity = LOW_GRAVITY;
        m_gravityLowTime = WeaponTimeBase();

        self.m_flNextSecondaryAttack = WeaponTimeBase() + 0.01;
        
        // 加速
        float accX = m_pPlayer.pev.velocity.x;
        accX = (accX < 10) ? 0 : 0.15;
        float accY = m_pPlayer.pev.velocity.y;
        accY = (accY < 10) ? 0 : 0.15;
        
        // clipをPowerLevelにしている。つまり、これによって出力調整
        m_pPlayer.pev.velocity = m_pPlayer.pev.velocity
                + 10 * Vector(accX, accY, 1)
                + (3 * self.m_iClip) * Vector(0, 0, 1);
        
        // 燃料減
        m_iFuel++;
        m_iFuel %= FUEL_CYCLE;
        if (m_iFuel == 1) {
            m_pPlayer.m_rgAmmo( self.m_iSecondaryAmmoType, m_pPlayer.m_rgAmmo( self.m_iSecondaryAmmoType ) - 1 );
        }
        
        // 発射音＆スプライト
        m_iBurnSound++;
        m_iBurnSound %= (FUEL_CYCLE / 2);
        if (m_iBurnSound == 1) {
            g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON,
                "ambience/steamburst1.wav", 0.8, ATTN_NORM, 0, 95 + Math.RandomLong( 0, 10 ) );
            
            uint8 alpha = 192;
            uint8 scale = 150;
          
            // 爆発
            NetworkMessage m(MSG_BROADCAST, NetworkMessages::SVC_TEMPENTITY, null);
            m.WriteByte(TE_EXPLOSION);
            m.WriteCoord(m_pPlayer.pev.origin.x);
            m.WriteCoord(m_pPlayer.pev.origin.y);
            m.WriteCoord(m_pPlayer.pev.origin.z);
            m.WriteShort(m_gBurnSprite);
            m.WriteByte(15); // sacle
            m.WriteByte(50); // framerate
            m.WriteByte(4);  // flag 1=不透明、2=発光なし、4=音なし、8=パーティクルなし
            m.End();
            
            // 煙
            NetworkMessage mSmoke(MSG_BROADCAST, NetworkMessages::SVC_TEMPENTITY, null);
            mSmoke.WriteByte(TE_SMOKE);
            mSmoke.WriteCoord(m_pPlayer.pev.origin.x);
            mSmoke.WriteCoord(m_pPlayer.pev.origin.y);
            mSmoke.WriteCoord(m_pPlayer.pev.origin.z);
            mSmoke.WriteShort(m_gSmokeSprite);
            mSmoke.WriteByte(scale);    // scale
            mSmoke.WriteByte(10); // framerate
            mSmoke.End();
            
        }
    }
    
    void Reload() {
        // リロードといいつつ、出力レベル調整。clipが出力レベル
        if ((WeaponTimeBase() > self.m_flNextPrimaryAttack) 
            && (WeaponTimeBase() > self.m_flNextSecondaryAttack)
        ) {
            // しゃがみ中で-1、立ち状態で+1
            int pitch = 100;
            if( ( m_pPlayer.pev.button & IN_DUCK ) != 0 ) {
                self.m_iClip--;
                self.m_iClip = (self.m_iClip < 1) ? MP5_MAX_CLIP : self.m_iClip;
                pitch = 90;
            } else {
                self.m_iClip++;
                self.m_iClip = (self.m_iClip > MP5_MAX_CLIP) ? 1 : self.m_iClip;
                pitch = 110;
            }
            g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, "hl/weapons/357_cock1.wav", 1.0, ATTN_NORM, 0, pitch);
            
            self.m_flNextPrimaryAttack   = WeaponTimeBase() + 0.5;
            self.m_flNextSecondaryAttack = WeaponTimeBase() + 0.5;
            
            g_PlayerFuncs.ClientPrint(m_pPlayer, HUD_PRINTCENTER, "Boost Level: " + self.m_iClip);
        }
    }
    
    void WeaponIdle() {
        
        if (WeaponTimeBase() > m_gravityLowTime + 1.0) {
            m_pPlayer.pev.gravity = NORMAL_GRAVITY;
        }        
        
        self.ResetEmptySound();
        m_pPlayer.GetAutoaimVector( AUTOAIM_5DEGREES );

        if( self.m_flTimeWeaponIdle > WeaponTimeBase() ) {
            return;
        }

        int iAnim;
        switch( g_PlayerFuncs.SharedRandomLong( m_pPlayer.random_seed,  0, 1 ) ) {
            case 0:  iAnim = GLOCK_IDLE1; break;
            case 1:  iAnim = GLOCK_IDLE2; break;
            default: iAnim = GLOCK_IDLE3; break;
        }

        self.SendWeaponAnim( iAnim );
        self.m_flTimeWeaponIdle = WeaponTimeBase() + g_PlayerFuncs.SharedRandomFloat( m_pPlayer.random_seed,  10, 15 );// how long till we do this again.
    }
}

string GetJetPackName() {
    return "weapon_as_jetpack";
}

void RegisterJetPack() {
    g_CustomEntityFuncs.RegisterCustomEntity( "weapon_as_jetpack", GetJetPackName() );
    g_ItemRegistry.RegisterWeapon( GetJetPackName(), "pizza_ya_san", "9mm", "uranium" );
}
