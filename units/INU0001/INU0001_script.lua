-- Nomads ACU

local Entity = import('/lua/sim/Entity.lua').Entity
local Buff = import('/lua/sim/Buff.lua')
local EffectTemplate = import('/lua/EffectTemplates.lua')
local Utilities = import('/lua/utilities.lua')
local NomadEffectUtil = import('/lua/nomadeffectutilities.lua')

local AddRapidRepair = import('/lua/nomadutils.lua').AddRapidRepair
local AddRapidRepairToWeapon = import('/lua/nomadutils.lua').AddRapidRepairToWeapon
local AddCapacitorAbility = import('/lua/nomadutils.lua').AddCapacitorAbility
local AddCapacitorAbilityToWeapon = import('/lua/nomadutils.lua').AddCapacitorAbilityToWeapon

local NWalkingLandUnit = import('/lua/nomadunits.lua').NWalkingLandUnit
local APCannon1 = import('/lua/nomadweapons.lua').APCannon1
local APCannon1_Overcharge = import('/lua/nomadweapons.lua').APCannon1_Overcharge
local DeathNuke = import('/lua/nomadweapons.lua').DeathNuke

NWalkingLandUnit = AddCapacitorAbility(AddRapidRepair(NWalkingLandUnit))
APCannon1 = AddCapacitorAbilityToWeapon(APCannon1)
APCannon1_Overcharge = AddCapacitorAbilityToWeapon(APCannon1_Overcharge)


INU0001 = Class(NWalkingLandUnit) {

    Weapons = {
        MainGun = Class(AddRapidRepairToWeapon(APCannon1)) {
            CreateProjectileAtMuzzle = function(self, muzzle)
                if self.unit.DoubleBarrels then
                    APCannon1.CreateProjectileAtMuzzle(self, 'right_arm_upgrade_muzzle')
                end
                return APCannon1.CreateProjectileAtMuzzle(self, muzzle)
            end,

            CapGetWepAffectingEnhancementBP = function(self)
                if self.unit:HasEnhancement('DoubleGuns') then
                    return self.unit:GetBlueprint().Enhancements['DoubleGuns']
                elseif self.unit:HasEnhancement('GunUpgrade') then
                    return self.unit:GetBlueprint().Enhancements['GunUpgrade']
                else
                    return {}
                end
            end,
        },
        OverCharge = Class(AddRapidRepairToWeapon(APCannon1_Overcharge)) {

            OnCreate = function(self)
                APCannon1_Overcharge.OnCreate(self)
                self:SetWeaponEnabled(false)
                self.AimControl:SetEnabled(false)
                self.AimControl:SetPrecedence(0)
                self.unit:SetOverchargePaused(false)
            end,

            GetWeaponEnergyRequired = function(self)
                local e = APCannon1_Overcharge.GetWeaponEnergyRequired(self)
                if self.unit.DoubleBarrels then
                    e = e * 2
                end
                return e
            end,

            OnEnableWeapon = function(self)
                self:SetWeaponEnabled(true)
                self.unit:SetWeaponEnabledByLabel('MainGun', false)
                self.unit:ResetWeaponByLabel('MainGun')
                self.unit:BuildManipulatorSetEnabled(false)
                self.AimControl:SetEnabled(true)
                self.AimControl:SetPrecedence(20)
                self.unit.BuildArmManipulator:SetPrecedence(0)
                self.AimControl:SetHeadingPitch( self.unit:GetWeaponManipulatorByLabel('MainGun'):GetHeadingPitch() )
            end,

            OnWeaponFired = function(self)
                APCannon1_Overcharge.OnWeaponFired(self)
                self:OnDisableWeapon()
                self:ForkThread(self.PauseOvercharge)
            end,
            
            OnDisableWeapon = function(self)
                self:SetWeaponEnabled(false)
                self.unit:SetWeaponEnabledByLabel('MainGun', true)
                self.unit:BuildManipulatorSetEnabled(false)
                self.AimControl:SetEnabled(false)
                self.AimControl:SetPrecedence(0)
                self.unit.BuildArmManipulator:SetPrecedence(0)
                self.unit:GetWeaponManipulatorByLabel('MainGun'):SetHeadingPitch( self.AimControl:GetHeadingPitch() )
            end,

            PlayFxMuzzleSequence = function(self, muzzle)
                APCannon1_Overcharge.PlayFxMuzzleSequence(self, muzzle)

                -- create extra effect
                local bone = self:GetBlueprint().RackBones[1]['RackBone']
                for k, v in EffectTemplate.TCommanderOverchargeFlash01 do
                    CreateAttachedEmitter(self.unit, bone, self.unit:GetArmy(), v):ScaleEmitter(self.FxMuzzleFlashScale)
                end
            end,

            CreateProjectileAtMuzzle = function(self, muzzle)
                if self.unit.DoubleBarrelOvercharge then
                    APCannon1_Overcharge.CreateProjectileAtMuzzle(self, 'right_arm_upgrade_muzzle')
                end
                return APCannon1_Overcharge.CreateProjectileAtMuzzle(self, muzzle)
            end,

            PauseOvercharge = function(self)
                if not self.unit:IsOverchargePaused() then
                    self.unit:SetOverchargePaused(true)
                    WaitSeconds(1/self:GetBlueprint().RateOfFire)
                    self.unit:SetOverchargePaused(false)
                end
            end,
            
            OnFire = function(self)
                if not self.unit:IsOverchargePaused() then
                    APCannon1_Overcharge.OnFire(self)
                end
            end,

            IdleState = State(APCannon1_Overcharge.IdleState) {

                OnGotTarget = function(self)
                    if not self.unit:IsOverchargePaused() then
                        APCannon1_Overcharge.IdleState.OnGotTarget(self)
                    end
                end,

                OnFire = function(self)
                    if not self.unit:IsOverchargePaused() then
                        ChangeState(self, self.RackSalvoFiringState)
                    end
                end,
            },

            RackSalvoFireReadyState = State(APCannon1_Overcharge.RackSalvoFireReadyState) {

                OnFire = function(self)
                    if not self.unit:IsOverchargePaused() then
                        APCannon1_Overcharge.RackSalvoFireReadyState.OnFire(self)
                    end
                end,
            },
        },
        DeathWeapon = Class(DeathNuke) {},
    },

    -- =====================================================================================================================
    -- CREATION AND FIRST SECONDS OF GAMEPLAY

    CapFxBones = { 'torso_thingy_left', 'torso_thingy_right', },

    OnCreate = function(self)
        NWalkingLandUnit.OnCreate(self)

        local bp = self:GetBlueprint()

        -- vars
        self.DoubleBarrels = false
        self.DoubleBarrelOvercharge = false
        self.EnhancementBoneEffectsBag = {}
        self.BuildBones = bp.General.BuildBones.BuildEffectBones
        self.HeadRotationEnabled = false -- disable head rotation to prevent initial wrong rotation
        self.AllowHeadRotation = false
        self.UseRunWalkAnim = false

        -- model
        self:HideBone('right_arm_upgrade_muzzle', true)
        self:HideBone('left_arm_upgrade_muzzle', true)
        self:HideBone('upgrade_back', true)

        self.HeadRotManip = CreateRotator(self, 'head', 'y', nil):SetCurrentAngle(0)
        self.Trash:Add(self.HeadRotManip)

        -- properties
        self:SetCapturable(false)
        self:SetupBuildBones()

        -- enhancements
        self:RemoveToggleCap('RULEUTC_SpecialToggle')
        self:AddBuildRestriction( categories.NOMAD * (categories.BUILTBYTIER2COMMANDER + categories.BUILTBYTIER3COMMANDER) )
        self:SetRapidRepairParams( 'NomadACURapidRepair', bp.Enhancements.RapidRepair.RepairDelay, bp.Enhancements.RapidRepair.InterruptRapidRepairByWeaponFired)

        self.Sync.Abilities = self:GetBlueprint().Abilities
    end,

    OnStopBeingBuilt = function(self, builder, layer)
        NWalkingLandUnit.OnStopBeingBuilt(self, builder, layer)

        self:BuildManipulatorSetEnabled(false)
        self:SetWeaponEnabledByLabel('MainGun', true)
        self:ForkThread(self.GiveInitialResources)
        self:ForkThread(self.HeadRotationThread)

        self:ForkThread(self.DoMeteorAnim)
    end,

    GiveInitialResources = function(self)
        WaitTicks(5)
        self:GetAIBrain():GiveResource('Energy', self:GetBlueprint().Economy.StorageEnergy)
        self:GetAIBrain():GiveResource('Mass', self:GetBlueprint().Economy.StorageMass)
    end,

    -- =====================================================================================================================
    -- UNIT DEATH

    OnKilled = function(self, instigator, type, overkillRatio)
        self:SetOrbitalBombardEnabled(false)
        self:SetIntelProbeEnabled(true, false)
        self:SetIntelProbeEnabled(false, false)
        NWalkingLandUnit.OnKilled(self, instigator, type, overkillRatio)
    end,

    DeathThread = function( self, overkillRatio, instigator)
        -- since we're spawning a black hole the ACU disappears right away
        self:Destroy()
    end,

    -- =====================================================================================================================
    -- GENERIC

    OnMotionHorzEventChange = function( self, new, old )
        if old == 'Stopped' and self.UseRunWalkAnim then
            local bp = self:GetBlueprint()
            if bp.Display.AnimationRun then
                if not self.Animator then
                    self.Animator = CreateAnimator(self, true)
                end
                self.Animator:PlayAnim(bp.Display.AnimationRun, true)
                self.Animator:SetRate(bp.Display.AnimationRunRate or 1)
            else
                NWalkingLandUnit.OnMotionHorzEventChange(self, new, old)
            end
        else
            NWalkingLandUnit.OnMotionHorzEventChange(self, new, old)
        end
    end,

    -- =====================================================================================================================
    -- BUILDING STUFF

    OnPrepareArmToBuild = function(self)
        NWalkingLandUnit.OnPrepareArmToBuild(self)
        self:BuildManipulatorSetEnabled(true)
        self.BuildArmManipulator:SetPrecedence(20)
        self:SetWeaponEnabledByLabel('MainGun', false)
        self:SetWeaponEnabledByLabel('OverCharge', false)
        self.BuildArmManipulator:SetHeadingPitch( self:GetWeaponManipulatorByLabel('MainGun'):GetHeadingPitch() )
    end,

    OnStartBuild = function(self, unitBeingBuilt, order)

       local bp = self:GetBlueprint()

       if order ~= 'Upgrade' or bp.Display.ShowBuildEffectsDuringUpgrade then

            -- If we are assisting an upgrading unit, or repairing a unit, play seperate effects
            local UpgradesFrom = unitBeingBuilt:GetBlueprint().General.UpgradesFrom
            if (order == 'Repair' and not unitBeingBuilt:IsBeingBuilt()) or (UpgradesFrom and UpgradesFrom ~= 'none' and self:IsUnitState('Guarding')) or (order == 'Repair'  and self:IsUnitState('Guarding') and not unitBeingBuilt:IsBeingBuilt()) then
                self:ForkThread( NomadEffectUtil.CreateRepairBuildBeams, unitBeingBuilt, self.BuildBones, self.BuildEffectsBag )
            else
                self:ForkThread( NomadEffectUtil.CreateNomadBuildSliceBeams, unitBeingBuilt, self.BuildBones, self.BuildEffectsBag )   
            end
        end

        self:DoOnStartBuildCallbacks(unitBeingBuilt)
        self:SetActiveConsumptionActive()
        self:PlayUnitSound('Construct')
        self:PlayUnitAmbientSound('ConstructLoop')
        if bp.General.UpgradesTo and unitBeingBuilt:GetUnitId() == bp.General.UpgradesTo and order == 'Upgrade' then
            unitBeingBuilt.DisallowCollisions = true
        end
        
        if unitBeingBuilt:GetBlueprint().Physics.FlattenSkirt and not unitBeingBuilt:HasTarmac() then
            if self.TarmacBag and self:HasTarmac() then
                unitBeingBuilt:CreateTarmac(true, true, true, self.TarmacBag.Orientation, self.TarmacBag.CurrentBP )
            else
                unitBeingBuilt:CreateTarmac(true, true, true, false, false)
            end
        end           

        self.UnitBeingBuilt = unitBeingBuilt
        self.UnitBuildOrder = order
        self.BuildingUnit = true
    end,

    OnFailedToBuild = function(self)
        NWalkingLandUnit.OnFailedToBuild(self)
        self:BuildManipulatorSetEnabled(false)
        self.BuildArmManipulator:SetPrecedence(0)
        self.BuildArmManipulator:SetAimingArc(-180, 180, 360, -180, 180, 360)
        self:SetWeaponEnabledByLabel('MainGun', true)
        self:SetWeaponEnabledByLabel('OverCharge', false)
        self:GetWeaponManipulatorByLabel('MainGun'):SetHeadingPitch( self.BuildArmManipulator:GetHeadingPitch() )
    end,

    OnStopBuild = function(self, unitBeingBuilt)
        NWalkingLandUnit.OnStopBuild(self, unitBeingBuilt)
        self:BuildManipulatorSetEnabled(false)
        self.BuildArmManipulator:SetPrecedence(0)
        self.BuildArmManipulator:SetAimingArc(-180, 180, 360, -180, 180, 360)
        self:SetWeaponEnabledByLabel('MainGun', true)
        self:SetWeaponEnabledByLabel('OverCharge', false)
        self:GetWeaponManipulatorByLabel('MainGun'):SetHeadingPitch( self.BuildArmManipulator:GetHeadingPitch() )
        self.UnitBeingBuilt = nil
        self.UnitBuildOrder = nil
        self.BuildingUnit = false
    end,

    OnPaused = function(self)
        NWalkingLandUnit.OnPaused(self)
        if self.BuildingUnit then
            NWalkingLandUnit.StopBuildingEffects(self, self:GetUnitBeingBuilt())
        end    
    end,
    
    OnUnpaused = function(self)
        if self.BuildingUnit then
            NWalkingLandUnit.StartBuildingEffects(self, self:GetUnitBeingBuilt(), self.UnitBuildOrder)
        end
        NWalkingLandUnit.OnUnpaused(self)
    end,

    -- =====================================================================================================================
    -- CAPTURING STUFF

    OnStopCapture = function(self, target)
        NWalkingLandUnit.OnStopCapture(self, target)
        self:BuildManipulatorSetEnabled(false)
        self.BuildArmManipulator:SetPrecedence(0)
        self:SetWeaponEnabledByLabel('MainGun', true)
        self:SetWeaponEnabledByLabel('OverCharge', false)
        self:GetWeaponManipulatorByLabel('MainGun'):SetHeadingPitch( self.BuildArmManipulator:GetHeadingPitch() )
    end,

    OnFailedCapture = function(self, target)
        NWalkingLandUnit.OnFailedCapture(self, target)
        self:BuildManipulatorSetEnabled(false)
        self.BuildArmManipulator:SetPrecedence(0)
        self:SetWeaponEnabledByLabel('MainGun', true)
        self:SetWeaponEnabledByLabel('OverCharge', false)
        self:GetWeaponManipulatorByLabel('MainGun'):SetHeadingPitch( self.BuildArmManipulator:GetHeadingPitch() )
    end,

    -- =====================================================================================================================
    -- RECLAIMING STUFF

    OnStopReclaim = function(self, target)
        NWalkingLandUnit.OnStopReclaim(self, target)
        self:BuildManipulatorSetEnabled(false)
        self.BuildArmManipulator:SetPrecedence(0)
        self:SetWeaponEnabledByLabel('MainGun', true)
        self:SetWeaponEnabledByLabel('OverCharge', false)
        self:GetWeaponManipulatorByLabel('MainGun'):SetHeadingPitch( self.BuildArmManipulator:GetHeadingPitch() )
    end,

    -- =====================================================================================================================
    -- EFFECTS AND ANIMATIONS

    -------- INITIAL ANIM --------

    DoMeteorAnim = function(self)  -- part of initial dropship animation

        self.PlayCommanderWarpInEffectFlag = false
        self:HideBone(0, true)
        self:SetWeaponEnabledByLabel('MainGun', false)
        self:CapDestroyFx()
        self.CapDoPlayFx = false

        local meteor = self:CreateProjectile('/effects/Entities/NomadACUDropMeteor/NomadACUDropMeteor_proj.bp')
        self.Trash:Add(meteor)
        meteor:Start(self:GetPosition(), 3)

        WaitTicks(35) -- time before meteor opens

        self:ShowBone(0, true)
        self:HideBone('right_arm_upgrade_muzzle', true)
        self:HideBone('left_arm_upgrade_muzzle', true)
        self:HideBone('upgrade_back', true)

        local totalBones = self:GetBoneCount() - 1
        local army = self:GetArmy()
        for k, v in EffectTemplate.UnitTeleportSteam01 do
            for bone = 1, totalBones do
                CreateAttachedEmitter(self,bone,army, v)
            end
        end

        self.CapDoPlayFx = true
        if self:CapIsFull() then
            self:CapPlayFx('Full')
        else
            self:CapPlayFx('Charging')
        end

        WaitTicks(5)

        -- TODO: play some kind of animation here?
        self.AllowHeadRotation = true
        self.PlayCommanderWarpInEffectFlag = nil

        WaitTicks(12)  -- waiting till tick 50 to enable ACU. Same as other ACU's.

        self:SetWeaponEnabledByLabel('MainGun', true)
        self:SetUnSelectable(false)
        self:SetBusy(false)
        self:SetBlockCommandQueue(false)

--self:CreateEnhancement('OrbitalBombardment')
--self:CreateEnhancement('IntelProbe')
    end,

    PlayCommanderWarpInEffect = function(self)  -- part of initial dropship animation
        self:SetUnSelectable(true)
        self:SetBusy(true)
        self:SetBlockCommandQueue(true)
        self.PlayCommanderWarpInEffectFlag = true
    end,

    HeadRotationThread = function(self)
        -- keeps the head pointed at the current target (position)

        local nav = self:GetNavigator()
        local maxRot = self:GetBlueprint().Display.MovementEffects.HeadRotationMax or 10
        local wep = self:GetWeaponByLabel('MainGun')
        local GoalAngle = 0
        local target, torsoDir, torsoX, torsoY, torsoZ, MyPos

        while not self:IsDead() do

            -- don't rotate if we're not allowed to
            while not self.HeadRotationEnabled do
                WaitSeconds(0.2)
            end

            -- get a location of interest. This is the unit we're currently firing on or, alternatively, the position we're moving to
            target = wep:GetCurrentTarget()
            if target and target.GetPosition then
                target = target:GetPosition()
            else
                target = wep:GetCurrentTargetPos() or nav:GetCurrentTargetPos()
            end

            -- calculate the angle for the head rotation. The rotation of the torso is taken into account
            MyPos = self:GetPosition()
            target.y = 0
            target.x = target.x - MyPos.x
            target.z = target.z - MyPos.z
            target = Utilities.NormalizeVector(target)
            torsoX, torsoY, torsoZ = self:GetBoneDirection('torso')
            torsoDir = Utilities.NormalizeVector( Vector( torsoX, 0, torsoZ) )
            GoalAngle = ( math.atan2( target.x, target.z ) - math.atan2( torsoDir.x, torsoDir.z ) ) * 180 / math.pi

            -- rotation limits, sometimes the angle is more than 180 degrees which causes a bad rotation.
            if GoalAngle > 180 then
                GoalAngle = GoalAngle - 360
            elseif GoalAngle < -180 then
                GoalAngle = GoalAngle + 360
            end
            GoalAngle = math.max( -maxRot, math.min( GoalAngle, maxRot ) )

            self.HeadRotManip:SetSpeed(60):SetGoal(GoalAngle)

            WaitSeconds(0.2)
        end
    end,

    AddEnhancementEmitterToBone = function(self, add, bone)

        -- destroy effect, if any
        if self.EnhancementBoneEffectsBag[ bone ] then
            self.EnhancementBoneEffectsBag[ bone ]:Destroy()
        end

        -- add the effect if desired
        if add then
            local emitBp = self:GetBlueprint().Display.EnhancementBoneEmitter
            local emit = CreateAttachedEmitter( self, bone, self:GetArmy(), emitBp )
            self.EnhancementBoneEffectsBag[ bone ] = emit
            self.Trash:Add( self.EnhancementBoneEffectsBag[ bone ] )
        end
    end,

    UpdateMovementEffectsOnMotionEventChange = function( self, new, old )
        self.HeadRotationEnabled = self.AllowHeadRotation
        NWalkingLandUnit.UpdateMovementEffectsOnMotionEventChange( self, new, old )
    end,

    -- =====================================================================================================================
    -- ORBITAL ENHANCEMENTS

    SetOrbitalBombardEnabled = function(self, enable)
        local brain = self:GetAIBrain()
        brain:EnableSpecialAbility( 'NomadAreaBombardment', (enable == true) )
    end,

    SetIntelProbeEnabled = function(self, adv, enable)
        local brain = self:GetAIBrain()
        if enable then
            local EnAbil, DisAbil = 'NomadIntelProbe', 'NomadIntelProbeAdvanced'
            if adv then
                EnAbil = 'NomadIntelProbeAdvanced'
                DisAbil = 'NomadIntelProbe'
            end
            brain:EnableSpecialAbility( DisAbil, false )
            brain:EnableSpecialAbility( EnAbil, true )
        else
            brain:EnableSpecialAbility( 'NomadIntelProbeAdvanced', false )
            brain:EnableSpecialAbility( 'NomadIntelProbe', false )
        end
    end,

    -- =====================================================================================================================
    -- ENHANCEMENTS

    CreateEnhancement = function(self, enh)
        NWalkingLandUnit.CreateEnhancement(self, enh)

        local bp = self:GetBlueprint().Enhancements[enh]
        if not bp then return end

        -- ---------------------------------------------------------------------------------------
        -- INTEL PROBE
        -- ---------------------------------------------------------------------------------------

        if enh == 'IntelProbe' then
            self:AddEnhancementEmitterToBone( true, 'right_shoulder_pod' )
            self:SetIntelProbeEnabled( false, true )

        elseif enh == 'IntelProbeRemove' then
            self:AddEnhancementEmitterToBone( false, 'right_shoulder_pod' )
            self:SetIntelProbeEnabled( false, false )

        -- ---------------------------------------------------------------------------------------
        -- ADVANCED INTEL PROBE
        -- ---------------------------------------------------------------------------------------

        elseif enh == 'IntelProbeAdv' then
--            self:AddEnhancementEmitterToBone( true, 'right_shoulder_pod' )
            self:SetIntelProbeEnabled( true, true )

        elseif enh == 'IntelProbeAdvRemove' then
            self:AddEnhancementEmitterToBone( false, 'right_shoulder_pod' )
            self:SetIntelProbeEnabled( true, false )

        -- ---------------------------------------------------------------------------------------
        -- MAIN WEAPON UPGRADE
        -- ---------------------------------------------------------------------------------------

        elseif enh == 'GunUpgrade' then

            local wep = self:GetWeaponByLabel('MainGun')
            local wbp = wep:GetBlueprint()

            if bp.RateOfFireMulti then
                if not Buffs['NOMADACUGunUpgrade'] then
                    BuffBlueprint {
                        Name = 'NOMADACUGunUpgrade',
                        DisplayName = 'NOMADACUGunUpgrade',
                        BuffType = 'ACUGUNUPGRADE',
                        Stacks = 'ADD',
                        Duration = -1,
                        Affects = {
                            RateOfFireSpecifiedWeapons = {
                                Mult = 1 / (bp.RateOfFireMulti or 1), -- here a value of 0.5 is actually doubling ROF
                            },
                        },
                    }
                end
                if Buff.HasBuff( self, 'NOMADACUGunUpgrade' ) then
                    Buff.RemoveBuff( self, 'NOMADACUGunUpgrade' )
                end
                Buff.ApplyBuff(self, 'NOMADACUGunUpgrade')
            end

            -- adjust main gun
            wep:AddDamageMod( (bp.NewDamage or wbp.Damage) - wbp.Damage )
            wep:ChangeMaxRadius(bp.NewMaxRadius or wbp.MaxRadius)

            -- adjust overcharge gun
            local oc = self:GetWeaponByLabel('OverCharge')
            oc:ChangeMaxRadius( bp.NewMaxRadius or wbp.MaxRadius )

        elseif enh =='GunUpgradeRemove' then
            Buff.RemoveBuff( self, 'NOMADACUGunUpgrade' )

            -- adjust main gun
            local wep = self:GetWeaponByLabel('MainGun')
            local wbp = wep:GetBlueprint()
            wep:AddDamageMod( -((bp.NewDamage or wbp.Damage) - wbp.Damage) )
            wep:ChangeMaxRadius(wbp.MaxRadius)

            -- adjust overcharge gun
            local oc = self:GetWeaponByLabel('OverCharge')
            oc:ChangeMaxRadius( wbp.MaxRadius )

        -- ---------------------------------------------------------------------------------------
        -- MAIN WEAPON UPGRADE 2
        -- ---------------------------------------------------------------------------------------

        elseif enh =='DoubleGuns' then
            -- this one should not change weapon damage, range, etc. The weapon script can't cope with that.
            self.DoubleBarrels = true
            self.DoubleBarrelOvercharge = bp.OverchargeIncluded

        elseif enh =='DoubleGunsRemove' then
            self.DoubleBarrels = false
            self.DoubleBarrelOvercharge = false

            Buff.RemoveBuff( self, 'NOMADACUGunUpgrade' )

            -- adjust main gun
            local ubp = self:GetBlueprint()
            local wep = self:GetWeaponByLabel('MainGun')
            local wbp = wep:GetBlueprint()
            wep:AddDamageMod( -((ubp.Enhancements['GunUpgrade'].NewDamage or wbp.Damage) - wbp.Damage) )
            wep:ChangeMaxRadius(wbp.MaxRadius)

            -- adjust overcharge gun
            local oc = self:GetWeaponByLabel('OverCharge')
            oc:ChangeMaxRadius( wbp.MaxRadius )

        -- ---------------------------------------------------------------------------------------
        -- LOCOMOTOR UPGRADE
        -- ---------------------------------------------------------------------------------------

        elseif enh == 'MovementSpeedIncrease' then
            self:SetSpeedMult( bp.SpeedMulti or 1.1 )
            self.UseRunWalkAnim = true

        elseif enh == 'MovementSpeedIncreaseRemove' then
            self:SetSpeedMult( 1 )
            self.UseRunWalkAnim = false

        -- ---------------------------------------------------------------------------------------
        -- RESOURCE ALLOCATION
        -- ---------------------------------------------------------------------------------------

        elseif enh =='ResourceAllocation' then

            local bpEcon = self:GetBlueprint().Economy
            self:SetProductionPerSecondEnergy(bp.ProductionPerSecondEnergy + bpEcon.ProductionPerSecondEnergy or 0)
            self:SetProductionPerSecondMass(bp.ProductionPerSecondMass + bpEcon.ProductionPerSecondMass or 0)

            -- capacitor upgrades
            if bp.CapacitorNewEnergyDrainPerSecond then
                self:CapSetEnergyDrainPerSecond(bp.CapacitorNewEnergyDrainPerSecond)
            end
            if bp.CapacitorNewDuration then
                self:CapSetDuration(bp.CapacitorNewDuration)
            end
            if bp.CapacitorNewChargeTime then
                self:CapSetChargeTime(bp.CapacitorNewChargeTime)
            end

        elseif enh == 'ResourceAllocationRemove' then

            local bpEcon = self:GetBlueprint().Economy
            self:SetProductionPerSecondEnergy(bpEcon.ProductionPerSecondEnergy or 0)
            self:SetProductionPerSecondMass(bpEcon.ProductionPerSecondMass or 0)

            -- removing capacitor upgrades
            local orgBp = self:GetBlueprint()
            local obp = orgBp.Enhancements.ResourceAllocation
            if obp.CapacitorNewEnergyDrainPerSecond then
                self:CapSetEnergyDrainPerSecond(orgBp.Capacitor.EnergyDrainPerSecond)
            end
            if obp.CapacitorNewDuration then
                self:CapSetDuration(orgBp.Capacitor.Duration)
            end
            if obp.CapacitorNewChargeTime then
                self:CapSetChargeTime(orgBp.Capacitor.ChargeTime)
            end

        -- ---------------------------------------------------------------------------------------
        -- RAPID REPAIR
        -- ---------------------------------------------------------------------------------------

        elseif enh == 'RapidRepair' then

            if not Buffs['NomadACURapidRepair'] then
                BuffBlueprint {
                    Name = 'NomadACURapidRepair',
                    DisplayName = 'NomadACURapidRepair',
                    BuffType = 'NOMADACURAPIDREPAIRREGEN',
                    Stacks = 'ALWAYS',
                    Duration = -1,
                    Affects = {
                        Regen = {
                            Add = bp.RepairRate or 15,
                            Mult = 1.0,
                        },
                    },
                }
            end
            if not Buffs['NomadACURapidRepairPermanentHPboost'] and bp.AddHealth > 0 then
                BuffBlueprint {
                    Name = 'NomadACURapidRepairPermanentHPboost',
                    DisplayName = 'NomadACURapidRepairPermanentHPboost',
                    BuffType = 'NOMADACURAPIDREPAIRREGENPERMHPBOOST',
                    Stacks = 'ALWAYS',
                    Duration = -1,
                    Affects = {
                        MaxHealth = {
                           Add = bp.AddHealth or 0,
                           Mult = 1.0,
                        },
                    },
                }
            end
            if bp.AddHealth > 0 then
                Buff.ApplyBuff(self, 'NomadACURapidRepairPermanentHPboost')
            end
            self:EnableRapidRepair(true)

        elseif enh == 'RapidRepairRemove' then

            -- keep in sync with same code in PowerArmorRemove
            self:EnableRapidRepair(false)
            if Buff.HasBuff( self, 'NomadACURapidRepairPermanentHPboost' ) then
                Buff.RemoveBuff( self, 'NomadACURapidRepair' )
                Buff.RemoveBuff( self, 'NomadACURapidRepairPermanentHPboost' )
            end

        -- ---------------------------------------------------------------------------------------
        -- POWER ARMOR
        -- ---------------------------------------------------------------------------------------

        elseif enh =='PowerArmor' then

            if not Buffs['NomadACUPowerArmor'] then
               BuffBlueprint {
                    Name = 'NomadACUPowerArmor',
                    DisplayName = 'NomadACUPowerArmor',
                    BuffType = 'NACUUPGRADEHP',
                    Stacks = 'ALWAYS',
                    Duration = -1,
                    Affects = {
                        MaxHealth = {
                            Add = bp.AddHealth,
                            Mult = 1.0,
                        },
                        Regen = {
                            Add = bp.AddRegenRate,
                            Mult = 1.0,
                        },
                    },
                }
            end
            if Buff.HasBuff( self, 'NomadACUPowerArmor' ) then
                Buff.RemoveBuff( self, 'NomadACUPowerArmor' )
            end
            Buff.ApplyBuff(self, 'NomadACUPowerArmor')

            if bp.Mesh then
                self:SetMesh( bp.Mesh, true)
            end

        elseif enh == 'PowerArmorRemove' then

            local ubp = self:GetBlueprint()
            if bp.Mesh then
                self:SetMesh( ubp.Display.MeshBlueprint, true)
            end
            if Buff.HasBuff( self, 'NomadACUPowerArmor' ) then
                Buff.RemoveBuff( self, 'NomadACUPowerArmor' )
            end

            -- keep in sync with same code above
            self:EnableRapidRepair(false)
            if Buff.HasBuff( self, 'NomadACURapidRepairPermanentHPboost' ) then
                Buff.RemoveBuff( self, 'NomadACURapidRepair' )
                Buff.RemoveBuff( self, 'NomadACURapidRepairPermanentHPboost' )
            end

        -- ---------------------------------------------------------------------------------------
        -- TECH 2 SUITE
        -- ---------------------------------------------------------------------------------------

        elseif enh =='AdvancedEngineering' then

            -- new build FX bone available
            table.insert( self.BuildBones, 'left_arm_upgrade_muzzle' )

            -- make new structures available
            local cat = ParseEntityCategory(bp.BuildableCategoryAdds)
            self:RemoveBuildRestriction(cat)

            -- add buff
            if not Buffs['NOMADACUT2BuildRate'] then
                BuffBlueprint {
                    Name = 'NOMADACUT2BuildRate',
                    DisplayName = 'NOMADACUT2BuildRate',
                    BuffType = 'ACUBUILDRATE',
                    Stacks = 'REPLACE',
                    Duration = -1,
                    Affects = {
                        BuildRate = {
                            Add =  bp.NewBuildRate - self:GetBlueprint().Economy.BuildRate,
                            Mult = 1,
                        },
                        MaxHealth = {
                            Add = bp.NewHealth,
                            Mult = 1.0,
                        },
                        Regen = {
                            Add = bp.NewRegenRate,
                            Mult = 1.0,
                        },
                    },
                }
            end
            Buff.ApplyBuff(self, 'NOMADACUT2BuildRate')

        elseif enh =='AdvancedEngineeringRemove' then

            -- remove extra build bone
            table.removeByValue( self.BuildBones, 'left_arm_upgrade_muzzle' )

            -- buffs
            if Buff.HasBuff( self, 'NOMADACUT2BuildRate' ) then
                Buff.RemoveBuff( self, 'NOMADACUT2BuildRate' )
            end

            -- restore build restrictions
            self:RestoreBuildRestrictions()
            self:AddBuildRestriction( categories.NOMAD * (categories.BUILTBYTIER2COMMANDER + categories.BUILTBYTIER3COMMANDER) )

        -- ---------------------------------------------------------------------------------------
        -- TECH 3 SUITE
        -- ---------------------------------------------------------------------------------------

        elseif enh =='T3Engineering' then

            -- make new structures available
            local cat = ParseEntityCategory(bp.BuildableCategoryAdds)
            self:RemoveBuildRestriction(cat)

            -- add buff
            if not Buffs['NOMADACUT3BuildRate'] then
                BuffBlueprint {
                    Name = 'NOMADACUT3BuildRate',
                    DisplayName = 'NOMADCUT3BuildRate',
                    BuffType = 'ACUBUILDRATE',
                    Stacks = 'REPLACE',
                    Duration = -1,
                    Affects = {
                        BuildRate = {
                            Add =  bp.NewBuildRate - self:GetBlueprint().Economy.BuildRate,
                            Mult = 1,
                        },
                        MaxHealth = {
                            Add = bp.NewHealth,
                            Mult = 1.0,
                        },
                        Regen = {
                            Add = bp.NewRegenRate,
                            Mult = 1.0,
                        },
                    },
                }
            end
            Buff.ApplyBuff(self, 'NOMADACUT3BuildRate')

        elseif enh =='T3EngineeringRemove' then

            -- remove buff
            if Buff.HasBuff( self, 'NOMADACUT3BuildRate' ) then
                Buff.RemoveBuff( self, 'NOMADACUT3BuildRate' )
            end

            -- reset build restrictions
            self:RestoreBuildRestrictions()
            self:AddBuildRestriction( categories.NOMAD * ( categories.BUILTBYTIER2COMMANDER + categories.BUILTBYTIER3COMMANDER) )

        -- ---------------------------------------------------------------------------------------
        -- ORBITAL BOMBARDMENT
        -- ---------------------------------------------------------------------------------------

        elseif enh == 'OrbitalBombardment' then
            self:SetOrbitalBombardEnabled(true)
            self:AddEnhancementEmitterToBone( true, 'left_shoulder_pod' )

        elseif enh == 'OrbitalBombardmentRemove' then
            self:SetOrbitalBombardEnabled(false)
            self:AddEnhancementEmitterToBone( false, 'left_shoulder_pod' )

        else
            WARN('Enhancement '..repr(enh)..' has no script support.')
	end
    end,
}

TypeClass = INU0001