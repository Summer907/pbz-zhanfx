local C = require("zhanfx.constants")
local Fake = {}
function Fake.new()
    local f={objects={},hooks={},registrations={},clock=1,serial=100,timers={},widgets={},draws=0,logs={},keys={},queued={}}
    function f:object(path,extra)
        self.serial=self.serial+1
        local o={path=path,address=self.serial,valid=true,classes={}}
        function o:IsValid() return self.valid end
        function o:GetFullName() return "Object "..self.path end
        function o:GetAddress() return self.address end
        function o:IsA(path) return self.classes[path] == true end
        for k,v in pairs(extra or {}) do o[k]=v end
        self.objects[path]=o;return o
    end
    function f:emit(path,...)
        local h=assert(self.hooks[path],"hook absent: "..path)
        return h.pre(...)
    end
    function f:remote(v) return {get=function() return v end} end
    function f:install()
        _G.StaticFindObject=function(path) return self.objects[path] end
        _G.LoadAsset=function(path) return self.objects[path] end
        _G.FName=function(s) return s end
        _G.FText=function(s) return s end
        _G.FindAllOf=function(name)
            if name=="PlayerController" then return {self.pc} end
            if name=="W_BossDead_C" then return self.widgets end
            if name=="W_BossDead_Red_C" then return {} end
            return {}
        end
        _G.RegisterHook=function(path,pre,post)
            self.registrations[#self.registrations+1]={path=path,pre=pre,post=post}
            self.hooks[path]={pre=pre,post=post};return #self.registrations,#self.registrations+1000
        end
        _G.UnregisterHook=function(path) self.hooks[path]=nil end
        _G.LoopInGameThreadWithDelay=function(_,fn) self.timers[1]=fn;return 1 end
        _G.CancelDelayedAction=function(id) self.timers[id]=nil end
        _G.RegisterConsoleCommandHandler=function(_,fn) self.command=fn end
        _G.Key={F11="F11",F5="F5",F6="F6",F7="F7",F8="F8",F9="F9",F10="F10"}
        _G.ModifierKey={CONTROL="control",ALT="alt",SHIFT="shift"}
        _G.RegisterKeyBind=function(key,modifiers,fn) assert(modifiers[1]=="alt" and #modifiers==1);self.keys[key]=fn end
        _G.RestartCurrentMod=function() self.restarts=(self.restarts or 0)+1 end
        _G.ExecuteInGameThread=function(fn) self.queued[#self.queued+1]=fn end
        _G.print=function(line) self.logs[#self.logs+1]=line end
    end
    f.world=f:object("/World")
    f.player=f:object("/World.Player",{tags={}})
    f.pc=f:object("/World.PC",{Pawn=f.player,IsLocalController=function() return true end,GetWorld=function() return f.world end})
    f:object("/Script/Engine.Default__GameplayStatics",{GetTimeSeconds=function() return f.clock end,
        GetRealTimeSeconds=function() return f.real_clock or f.clock end})
    f.language = "zh-Hans"
    f.language_reads = 0
    f:object("/Script/Engine.Default__KismetInternationalizationLibrary", {GetCurrentLanguage=function()
        f.language_reads = f.language_reads + 1
        return f.language
    end})
    f.notices={}
    f:object("/Game/PBZContent/UI/InGame/SwitchUI/WB_TipsText.WB_TipsText_C")
    f:object("/Script/UMG.Default__WidgetBlueprintLibrary",{Create=function(_,world,class,pc)
        assert(world==f.player and pc==f.pc)
        local widget=f:object("/Notice."..f.serial,{SetText=function(self,text) self.text=text end,
            AddToViewport=function(self,z) self.on_screen=true;self.z=z end,
            SetVisibility=function(self,v) self.visibility=v end,
            RemoveFromParent=function(self) self.on_screen=false end})
        f.notices[#f.notices+1]=widget;return widget
    end})
    f:object("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary",{GetAbilitySystemComponent=function(_,actor)
        local attributes={ForEach=function(_,callback)
            local set=f:object("/AttributeSet."..actor.address,{Health={CurrentValue=actor.health or (actor.dead and 0 or 100)}})
            set.classes["/Script/CharacterBasics.BasicAttributeSet"]=true
            callback(0,f:remote(set))
        end}
        return f:object("/ASC."..actor.address,{SpawnedAttributes=attributes,
            HasMatchingGameplayTag=function(_,tag) return actor.tags and actor.tags[tag.TagName] == true end})
    end})
    f:object("/Script/SGameCombatSystem.Default__FactionUtils",{GetFactionRelation=function(_,target) return target.attitude or 2 end})
    for _,path in ipairs({C.CombatBase,C.SimpleBase,C.DeathClass,C.HelperClass,C.Widgets[1],C.Widgets[2]}) do f:object(path) end
    for _,path in ipairs({"/Script/LegoAbility.LegoAbility:PlayTimeline",
        "/Script/SGameCombatSystem.BulletAttackModule:DealDamageToAvatar",
        "/Script/SGameAttributes.AttributeComponent:TakeDamage",
        "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:SendGameplayEventToActor",
        C.CombatBase..":K2_OnEndAbility",C.SimpleBase..":K2_OnEndAbility",C.DeathClass..":On Death",C.HelperFunction,
        C.Widgets[1]..":BP_OnActivated",C.Widgets[1]..":BP_OnDeactivated",C.Widgets[2]..":BP_OnActivated",C.Widgets[2]..":BP_OnDeactivated"}) do f:object(path) end
    f.helper=f:object("/HelperCDO",{CallFunction=function(_,fn,red,pawn)
        assert(fn==f.objects[C.HelperFunction]);assert(red==false);assert(pawn==f.player)
        f.draws=f.draws+1
        local widget=f:object("/World.UI"..f.draws,{activated=true,IsActivated=function(self) return self.activated end})
        f.widgets[#f.widgets+1]=widget
        f:emit(C.Widgets[1]..":BP_OnActivated",f:remote(widget))
        f:emit(C.HelperFunction,f:remote(f.helper),f:remote(false),f:remote(f.player))
    end})
    f.objects[C.HelperClass].GetCDO=function() return f.helper end
    function f:enemy(name)
        local controller=self:object("/Controller."..name)
        controller.classes["/Script/AIModule.AIController"]=true
        local actor=self:object("/World."..name,{tags={},dead=false,GetController=function() return controller end})
        local death=self:object("/Death."..name,{GetOwner=function() return actor end,["Is Dead"]=function() return actor.dead end})
        actor.GetComponentByClass=function(_,class) assert(class==f.objects[C.DeathClass]);return death end
        actor.death=death;return actor
    end
    function f:ability(target,kind)
        local a=self:object("/Ability."..self.serial,{["Execution Info"]={IsTarget=false,Executor=self.player,Target=target,ExecutionHandle={Handle=self.serial}},
            GetAvatarActorFromActorInfo=function() return f.player end})
        if kind=="simple" then a.classes[C.SimpleBase]=true;a.ExecutionTarget=target
        else a.classes[C.Classes.combat[1]]=true end
        return a
    end
    function f:begin(a) return self:emit("/Script/LegoAbility.LegoAbility:PlayTimeline",self:remote(a)) end
    function f:taken(a,target,tag,override)
        local payload=self:object("/Payload."..self.serial,{TargetActor=target,GetDamageSourceAbility=function() return override or a end})
        return self:emit("/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:SendGameplayEventToActor",self:remote(nil),self:remote(target),self:remote({TagName=tag or "GameplayEvent.Damage.Taken"}),self:remote({OptionalObject=payload}))
    end
    function f:die(target) target.dead=true;return self:emit(C.DeathClass..":On Death",self:remote(target.death)) end
    function f:finish(a,cancelled,kind) return self:emit((kind=="simple" and C.SimpleBase or C.CombatBase)..":K2_OnEndAbility",self:remote(a),self:remote(cancelled)) end
    function f:close_ui()
        for _,w in ipairs(self.widgets) do
            if w.activated then w.activated=false;self:emit(C.Widgets[1]..":BP_OnDeactivated",self:remote(w)) end
        end
    end
    function f:drain()
        local pending=self.queued;self.queued={}
        for _,callback in ipairs(pending) do callback() end
    end
    return f
end
return Fake
