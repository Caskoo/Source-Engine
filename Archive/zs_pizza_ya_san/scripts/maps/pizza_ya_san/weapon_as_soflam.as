/*  
 * SOFLAM - AirStrike
* (** Refeneced: Nero's AirStrike plugin)
 */
enum SoflamAnimation {
    SOFLAM_IDLE1 = 0,
    SOFLAM_DRAW,
    SOFLAM_SHOOT,
    SOFLAM_SHOOT2
};

const int SOFLAM_DEFAULT_GIVE  = 5;
const int SOFLAM_MAX_AMMO      = 5;
const int SOFLAM_MAX_CLIP      = -1;
const int SOFLAM_WEIGHT        = 5;

const float SOFLAM_DELAY = 15.0;    // 爆撃後の再攻撃可能時間
const float STRIKE_CNT = 8;         // 砲弾数
const float STRIKE_INTERVAL = 0.75; // 砲弾落下感覚
const float STRIKE_BEFORE = 5.0;    // 要請後のDelay
const float BONUS_RANGE = 120.0;


class weapon_as_soflam : ScriptBasePlayerWeaponEntity {
    private CBasePlayer@ m_pPlayer = null;


    float m_flNextAnimTime;
    int m_gDotSprite;   // レーザーポインタ
    int m_gLaserSprite; // レーザー
    float m_lastRequested;
    
    int m_strikeStatus = -1;
    Vector m_strikeAbovePos = Vector(0, 0, 0);
    Vector m_strikeHitPos = Vector(0, 0, 0);
    float m_lastStrike = 0;
    int m_strikeType = 0;
    
    
    void Spawn() {
        Precache();
        g_EntityFuncs.SetModel( self, "models/pizza_ya_san/w_soflam.mdl" );
        self.m_iDefaultAmmo = SOFLAM_DEFAULT_GIVE;
        self.FallInit();
    }

    void Precache() {
        self.PrecacheCustomModels();
        g_Game.PrecacheModel( "models/pizza_ya_san/v_soflam.mdl" );
        g_Game.PrecacheModel( "models/pizza_ya_san/w_soflam.mdl" );
        g_Game.PrecacheModel( "models/pizza_ya_san/p_soflam.mdl" );

        g_Game.PrecacheModel( "models/w_9mmARclip.mdl" );
        g_SoundSystem.PrecacheSound( "items/9mmclip1.wav" );
        g_SoundSystem.PrecacheSound( "hl/weapons/357_cock1.wav" );
        
        // mortar
        g_Game.PrecacheModel( "models/mortarshell.mdl" );
        g_SoundSystem.PrecacheSound( "weapons/ofmortar.wav" );
        
        // ラジオ用
        g_SoundSystem.PrecacheSound( "hgrunt/yessir.wav" );        
        g_SoundSystem.PrecacheSound( "hgrunt/affirmative.wav" );
        g_SoundSystem.PrecacheSound( "hgrunt/roger.wav" );
        g_SoundSystem.PrecacheSound( "hgrunt/negative.wav" );
        
        // レーザーポインタ
        m_gDotSprite = g_Game.PrecacheModel("sprites/red.spr");
        m_gLaserSprite = g_Game.PrecacheModel("sprites/laserbeam.spr");
    }

    bool GetItemInfo( ItemInfo& out info ) {
        info.iMaxAmmo1 = SOFLAM_MAX_AMMO;
        info.iMaxAmmo2 = -1;
        info.iMaxClip  = SOFLAM_MAX_CLIP;
        info.iSlot     = 3;
        info.iPosition = 5;
        info.iFlags    = 0;
        info.iWeight   = SOFLAM_WEIGHT;
        return true;
    }

    bool AddToPlayer( CBasePlayer@ pPlayer ) {
        if(!BaseClass.AddToPlayer( pPlayer ) )
		return false;

	@m_pPlayer = pPlayer;

	NetworkMessage message( MSG_ONE, NetworkMessages::WeapPickup, pPlayer.edict() );
		message.WriteLong( g_ItemRegistry.GetIdForName("weapon_as_soflam") );
	message.End();
	return true;
    }
    
    bool PlayEmptySound() {
        if (self.m_bPlayEmptySound ) {
            self.m_bPlayEmptySound = false;
            g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, "hl/weapons/357_cock1.wav", 0.8, ATTN_NORM, 0, PITCH_NORM );
        }
        return false;
    }

    bool Deploy() {
        m_strikeStatus = -1;
        m_lastRequested = 0.0;
        self.m_flNextPrimaryAttack = WeaponTimeBase() + 1.0;
        self.m_flNextSecondaryAttack = WeaponTimeBase() + 1.0;
        return self.DefaultDeploy( self.GetV_Model( "models/pizza_ya_san/v_soflam.mdl" ), self.GetP_Model( "models/pizza_ya_san/p_soflam.mdl" ), SOFLAM_DRAW, "trip" );
    }
    
    float WeaponTimeBase() {
        return g_Engine.time; //g_WeaponFuncs.WeaponTimeBase();
    }

    // プライマリアタック
    void PrimaryAttack() {
        AirStrikeAttack(0);
    }
    
    // セカンダリアタック
    void SecondaryAttack() {
        AirStrikeAttack(1);
    }
    
    void AirStrikeAttack(int &in strikeType) {
        // No Ammo なら終了
        if ( m_pPlayer.m_rgAmmo(self.m_iPrimaryAmmoType) <= 0 ) {
            self.PlayEmptySound();
            self.m_flNextPrimaryAttack = WeaponTimeBase() + 0.15;
            self.m_flNextSecondaryAttack = WeaponTimeBase() + 0.15;
            return;
        }
        
        // 攻撃モーション
        m_pPlayer.SetAnimation( PLAYER_ATTACK1 );
        if (strikeType == 0) {
            self.SendWeaponAnim(SOFLAM_SHOOT);
        } else {
            self.SendWeaponAnim(SOFLAM_SHOOT2);
        }

        // チェック
        bool ret = CheckAirStrike();
                
        // 成功している場合
        if (ret) { 
            self.m_flNextPrimaryAttack = WeaponTimeBase() + SOFLAM_DELAY;
            self.m_flNextSecondaryAttack = WeaponTimeBase() + SOFLAM_DELAY;
            
            int randRadio = Math.RandomLong(0, 2);
            string radioType;
            switch (randRadio){
                case 1:  radioType = "hgrunt/yessir.wav";       break;
                case 2:  radioType = "hgrunt/affirmative.wav";  break;
                default: radioType = "hgrunt/roger.wav";        break;
            }
            g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, radioType, 1.0, ATTN_NORM, 0, 95 + Math.RandomLong( 0, 10 ) );
            
            m_lastRequested = WeaponTimeBase();
            
            m_strikeType = strikeType;
            m_strikeStatus = 0;
            m_lastStrike = WeaponTimeBase() + STRIKE_BEFORE;
            
            if (strikeType == 0) {
                g_PlayerFuncs.ClientPrint(m_pPlayer, HUD_PRINTCENTER, "Fire support was requested!!\n\nTake cover!!");
            } else {
                g_PlayerFuncs.ClientPrint(m_pPlayer, HUD_PRINTCENTER, "Wide range fire support was requested!!\n\nTake cover!!");
            }
        
        // 天井などで失敗している場合
        } else { 
            g_SoundSystem.EmitSoundDyn(m_pPlayer.edict(), CHAN_WEAPON, "hgrunt/negative.wav", 1.0, ATTN_NORM, 0, 95 + Math.RandomLong( 0, 10 ) );
        
            self.m_flNextPrimaryAttack = WeaponTimeBase() + 1.0;
            self.m_flNextSecondaryAttack = WeaponTimeBase() + 1.0;
            
            g_PlayerFuncs.ClientPrint(m_pPlayer, HUD_PRINTCENTER, "Can not execute fire support to there!!");
        }
    }
    
    bool CheckAirStrike() {
        TraceResult tr;
        Vector vecSrc = m_pPlayer.GetGunPosition();

        // ■実行チェック
        Math.MakeVectors( m_pPlayer.pev.v_angle );
        g_Utility.TraceLine( vecSrc, vecSrc + g_Engine.v_forward * 8192,
                ignore_monsters, m_pPlayer.edict(), tr );
        
        // 注視点がSKYテクスチャなら、終了
        if (g_EngineFuncs.PointContents(tr.vecEndPos) == CONTENTS_SKY ) {
            return false;
            
        // 注視点が壁
        } else {
            vecSrc = tr.vecEndPos;
            
            // ヒット地点上空がSKYではないなら、終了
            g_Utility.TraceLine( vecSrc,
                    vecSrc + Vector( 0, 0, 180 ) * 8192, ignore_monsters, m_pPlayer.edict(), tr );
            
            if ( g_EngineFuncs.PointContents( tr.vecEndPos ) != CONTENTS_SKY ) {
                return false;
            }
            
            m_strikeHitPos = vecSrc;
            m_strikeAbovePos = tr.vecEndPos;
        }

        return true;
    }
    
    void WeaponIdle() {
        self.ResetEmptySound();
        
        bool isPointBonus = false;
        
        // レーザーポインタ（発射可能なら発光）
        if (((m_lastRequested == 0) || (WeaponTimeBase() > m_lastRequested + SOFLAM_DELAY)
            || (m_strikeStatus != -1))
        ) {
            TraceResult tr;
            Vector vecSrc = m_pPlayer.GetGunPosition();
   
            Math.MakeVectors(m_pPlayer.pev.v_angle );
            g_Utility.TraceLine(vecSrc, vecSrc + g_Engine.v_forward * 8192,
                    ignore_monsters, m_pPlayer.edict(), tr );
            
            // 点
            uint8 alpha = 255;
            NetworkMessage m(MSG_BROADCAST, NetworkMessages::SVC_TEMPENTITY, null);
            m.WriteByte(TE_GLOWSPRITE);
            m.WriteCoord(tr.vecEndPos.x);
            m.WriteCoord(tr.vecEndPos.y);
            m.WriteCoord(tr.vecEndPos.z);
            m.WriteShort(m_gDotSprite);
            m.WriteByte(1);  // life
            m.WriteByte(3); // scale
            m.WriteByte(alpha); // alpha
            m.End();

            // レーザー
            uint8 r, g, b;
            
            r = 192;
            g = 0;
            b = 0;
            
            // 爆撃地点を照射中
            if ((m_strikeStatus != -1) && ((tr.vecEndPos - m_strikeHitPos).Length() < BONUS_RANGE)) {
                r = 0;
                g = 255;
                b = 255;
                isPointBonus = true;
            }
            
            vecSrc = vecSrc + g_Engine.v_forward * 30 - g_Engine.v_up * 6 + g_Engine.v_right * 4;
            
            NetworkMessage ml(MSG_BROADCAST, NetworkMessages::SVC_TEMPENTITY, null);
            ml.WriteByte(TE_BEAMPOINTS);
            ml.WriteCoord(vecSrc.x);
            ml.WriteCoord(vecSrc.y);
            ml.WriteCoord(vecSrc.z);
            ml.WriteCoord(tr.vecEndPos.x);
            ml.WriteCoord(tr.vecEndPos.y);
            ml.WriteCoord(tr.vecEndPos.z);
            ml.WriteShort(m_gLaserSprite);
            ml.WriteByte(0);   // frame start
            ml.WriteByte(100); // frame end
            ml.WriteByte(1);   // life
            ml.WriteByte(4);  // width
            ml.WriteByte(0);   // noise
            ml.WriteByte(r);
            ml.WriteByte(g);
            ml.WriteByte(b);
            ml.WriteByte(alpha);   // actually brightness
            ml.WriteByte(32);  // scroll
            ml.End();
            
        }
        
            
        // ■爆撃処理
        if (m_strikeStatus >= STRIKE_CNT) {
            m_strikeStatus = -1;
        }
        if ((m_strikeStatus != -1) && (WeaponTimeBase() > m_lastStrike + STRIKE_INTERVAL)) {
            CBaseEntity@ pRocket;
            
            if (m_strikeStatus == 0) {
                m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType, m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) - 1 );
            }
            
            int spreadMin = (m_strikeType == 0) ? -150 : -500;
            int spreadMax = (m_strikeType == 0) ?  150 :  500;

            Vector vecStrike = m_strikeAbovePos + Vector( 0, 0, -20 );
            
            // 爆撃地点照射中ならボーナス
            int count = (isPointBonus) ? 2 : 1;
            for (int i = 0; i < count; i++) {
                @pRocket = g_EntityFuncs.ShootMortar(m_pPlayer.pev,
                        vecStrike + Vector( Math.RandomLong( spreadMin, spreadMax ), Math.RandomLong( spreadMin, spreadMax ), 0 ),
                        Vector(0,0,0) );
                
                pRocket.pev.velocity = Vector(
                        Math.RandomLong( -50, 50 ),
                        Math.RandomLong( -50, 50 ),
                        Math.RandomLong( -400, -250 ));
            }
            
            m_strikeStatus++;
            m_lastStrike = WeaponTimeBase();
        }
        
        
        if (self.m_flTimeWeaponIdle > WeaponTimeBase()) {
            return;
        }

        self.SendWeaponAnim(SOFLAM_IDLE1);

        self.m_flTimeWeaponIdle = WeaponTimeBase() + g_PlayerFuncs.SharedRandomFloat( m_pPlayer.random_seed,  10, 15 );// how long till we do this again.
    }
}

string GetSoflamName() {
    return "weapon_as_soflam";
}

void RegisterSoflam() {
    g_CustomEntityFuncs.RegisterCustomEntity( "weapon_as_soflam", GetSoflamName() );
    g_ItemRegistry.RegisterWeapon( GetSoflamName(), "pizza_ya_san", "rockets" );
}
