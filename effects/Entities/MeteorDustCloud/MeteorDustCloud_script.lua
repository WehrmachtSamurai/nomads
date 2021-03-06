local EmitterProjectile = import('/lua/sim/defaultprojectiles.lua').EmitterProjectile
local NomadsEffectTemplate = import('/lua/nomadeffecttemplate.lua')

MeteorDustCloud = Class(EmitterProjectile) {
    FxTrails = NomadsEffectTemplate.MeteorSmokeRing,
}

TypeClass = MeteorDustCloud