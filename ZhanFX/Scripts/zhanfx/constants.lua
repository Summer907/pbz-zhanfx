return {
    Version = "0.1.0",
    GameBuild = "26266538 / CL-301524_JKS-17219",
    UE4SSCommit = "f885e8d2",
    -- Provisional game-time bounds. They are NOT live-calibrated defaults.
    EndGrace = 1.0,
    AttributionWindow = 0.10,
    ActiveTTL = 30.0,
    MaxSessions = 32,
    PollMs = 100,
    PresentationSeconds = 2.5,
    HelperClass = "/Game/PBZContent/Blueprint/BP_GameplayHelper.BP_GameplayHelper_C",
    HelperFunction = "/Game/PBZContent/Blueprint/BP_GameplayHelper.BP_GameplayHelper_C:Push BossDeadUI",
    CombatBase = "/SGameExecution/GA/GA_ExecutionAbilityBase.GA_ExecutionAbilityBase_C",
    SimpleBase = "/PBZCombatAsset/Prototypes/Abilities/Base/GA_SimpleExecution_Base.GA_SimpleExecution_Base_C",
    DeathClass = "/MagDeath/BP_DeathComponent.BP_DeathComponent_C",
    Widgets = {
        "/Game/PBZContent/UI/InGame/Dead/W_BossDead.W_BossDead_C",
        "/Game/PBZContent/UI/InGame/Dead/W_BossDead_Red.W_BossDead_Red_C",
    },
    Classes = {
        shachi = { "/PBZCombatAsset/Prototypes/Abilities/Base/PBZ_ShachiWeaponExecutionBase.PBZ_ShachiWeaponExecutionBase_C" },
        air = {
            "/SGameExecution/GA/GA_ExecutionAbilityBase_Air.GA_ExecutionAbilityBase_Air_C",
            "/PBZCombatAsset/Prototypes/Abilities/Base/Execution/PBZ_StealthExecutionAbility_Air_Base.PBZ_StealthExecutionAbility_Air_Base_C",
            "/SGameCombatSystem/Weapon/Abilities/BP_StealthExecutionAbility_Air_Base.BP_StealthExecutionAbility_Air_Base_C",
        },
        stealth = {
            "/PBZCombatAsset/Prototypes/Abilities/Base/Execution/PBZ_StealthExecutionAbilityBase.PBZ_StealthExecutionAbilityBase_C",
            "/SGameCombatSystem/Weapon/Abilities/BP_StealthExecutionAbilityBase.BP_StealthExecutionAbilityBase_C",
        },
        grab = { "/SGameExecution/GA/GA_ExecutionAbilityBase_Grab.GA_ExecutionAbilityBase_Grab_C" },
        combat = { "/PBZCombatAsset/Prototypes/Abilities/Base/Execution/PBZ_CombatExecutionAbilityBase.PBZ_CombatExecutionAbilityBase_C",
            "/SGameCombatSystem/Weapon/Abilities/BP_CombatExecutionAbilityBase.BP_CombatExecutionAbilityBase_C" },
    },
}
