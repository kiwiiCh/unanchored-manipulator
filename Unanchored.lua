-- ============================================================
-- UNANCHORED MANIPULATOR KII v9 -- DELTA EXECUTOR
-- Fixes: car joystick touchable (frame InputBegan, no proc check)
-- DE Shrine: 100% unanchored sweep, blocks go underground until
--   domain closes, shrine + slashes = grabbed blocks, animations.
-- Gojo Mode: Max Blue / Reversal Red / Hollow Purple / DE:Infinity
-- All vehicle BP movers stripped (no flying), Stepped loop.
-- ============================================================
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Debris           = game:GetService("Debris")
local TweenService     = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ── Edge/corner draggable ─────────────────────────────────────
local EDGE_MARGIN = 36
local function makeDraggable(handle, panel, edgeOnly)
    local dragging=false; local dragStartM=Vector2.zero; local dragStartPos=UDim2.new()
    local conC,conE
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType~=Enum.UserInputType.MouseButton1 and inp.UserInputType~=Enum.UserInputType.Touch then return end
        if edgeOnly then
            local p=Vector2.new(inp.Position.X,inp.Position.Y); local ap=panel.AbsolutePosition; local as=panel.AbsoluteSize
            if not(p.X-ap.X<EDGE_MARGIN or ap.X+as.X-p.X<EDGE_MARGIN or p.Y-ap.Y<EDGE_MARGIN or ap.Y+as.Y-p.Y<EDGE_MARGIN) then return end
        end
        dragging=true; dragStartM=Vector2.new(inp.Position.X,inp.Position.Y); dragStartPos=panel.Position
    end)
    conC=UserInputService.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType~=Enum.UserInputType.MouseMovement and inp.UserInputType~=Enum.UserInputType.Touch then return end
        local d=Vector2.new(inp.Position.X,inp.Position.Y)-dragStartM
        panel.Position=UDim2.new(dragStartPos.X.Scale,dragStartPos.X.Offset+d.X,dragStartPos.Y.Scale,dragStartPos.Y.Offset+d.Y)
    end)
    conE=UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)
    panel.AncestryChanged:Connect(function(_,par)
        if not par then pcall(function()conC:Disconnect()end);pcall(function()conE:Disconnect()end) end
    end)
end

local function main()
    print("[ManipKii v9] "..player.Name)

    -- ── Core state ────────────────────────────────────────────
    local isActivated=false; local activeMode="none"; local lastMode="none"
    local scriptAlive=true; local radius=7; local detectionRange=math.huge
    local pullStrength=50000; local spinSpeed=0; local spinAngle=0

    local function applyStrengthToAll()
        local p=math.max(1,pullStrength); local d=math.max(50,p*0.05)
        for _,data in pairs(controlled) do
            pcall(function()
                if data.bp and data.bp.Parent then data.bp.P=p;data.bp.D=d;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)end
                if data.bg and data.bg.Parent then data.bg.P=p;data.bg.D=d;data.bg.MaxTorque=Vector3.new(1e12,1e12,1e12)end
            end)
        end
    end

    -- ── Snake / Gaster / Sphere / SphereBender state ──────────
    local snakeT=0; local snakeHistory={}; local SNAKE_HIST_MAX=600; local SNAKE_GAP=8
    local gasterAnim="pointing"; local gasterT=0; local gasterSubGui=nil
    local sphereSubGui=nil; local sphereMode="orbit"
    local spherePos=Vector3.new(0,0,0); local sphereVel=Vector3.new(0,0,0); local sphereOrbitAngle=0
    local SPHERE_RADIUS=6; local SPHERE_SPEED=1.2; local SPHERE_SPRING=8; local SPHERE_DAMP=4
    local sbSubGui=nil; local sbSpheres={}
    local function newSBSphere(p) return{pos=p or Vector3.zero,vel=Vector3.zero,orbitAngle=0,mode="orbit",stopped=false,selected=false}end

    -- ── Humanoid freeze/thaw ─────────────────────────────────
    local savedWS=16; local savedJP=50; local savedAR=true
    local function freezePlayer(anchorCF)
        local char=player.Character; if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid"); local hrp=char:FindFirstChild("HumanoidRootPart")
        if hum then savedWS=hum.WalkSpeed;savedJP=hum.JumpPower;savedAR=hum.AutoRotate;hum.WalkSpeed=0;hum.JumpPower=0;hum.AutoRotate=false;pcall(function()hum:ChangeState(Enum.HumanoidStateType.PlatformStanding)end)end
        if hrp then hrp.Anchored=true;if anchorCF then hrp.CFrame=anchorCF end end
        for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=false end)end end
    end
    local function thawPlayer(exitCF)
        local char=player.Character; if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid"); local hrp=char:FindFirstChild("HumanoidRootPart")
        if hum then hum.WalkSpeed=savedWS;hum.JumpPower=savedJP;hum.AutoRotate=savedAR;pcall(function()hum:ChangeState(Enum.HumanoidStateType.GettingUp)end)end
        if hrp then hrp.Anchored=false;if exitCF then hrp.CFrame=exitCF end end
        for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=true end)end end
    end

    -- ── Tank state ────────────────────────────────────────────
    local tankSubGui=nil; local tankActive=false
    local cameraOrbitAngle=0; local cameraPitchAngle=math.rad(25)
    local CAM_PITCH_MIN=math.rad(8); local CAM_PITCH_MAX=math.rad(70)
    local CAMERA_DIST=24; local frozenTankCF=nil
    local CAM_ORBIT_SENS=3.0; local CAM_PITCH_SENS=2.0
    local tks={forward=0,turn=0,hatchOpen=false,insideTank=false,tankBase=nil,turretPart=nil,barrelPart=nil,turretPartIdx=nil,barrelPartIdx=nil,tankParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0,tankHatch=nil}
    local TANK_H=5; local TANK_W=12; local TANK_L=16; local TANK_INTERIOR_Y=TANK_H/2+2.5
    local TANK_SPEED=35; local TANK_TURN=2.2; local TANK_ACCEL=12; local TANK_FRIC=0.88
    local SHOOT_CD=1.5; local lastShot=0; local PROJ_SPEED=650
    local rightJoy={active=false,origin=Vector2.zero,current=Vector2.zero,radius=55,deadzone=10,touchId=nil}
    local tankRayParams=RaycastParams.new(); tankRayParams.FilterType=Enum.RaycastFilterType.Exclude

    -- ── Car state ─────────────────────────────────────────────
    local carSubGui=nil; local carActive=false; local frozenCarCF=nil
    local cs={doorOpen=false,carBase=nil,carDoor=nil,carParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0}
    local CAR_H=2.8; local CAR_INTERIOR_Y=CAR_H/2+1.8
    local CAR_SPEED=48; local CAR_TURN=2.8; local CAR_ACCEL=20; local CAR_FRIC=0.88
    local carJoy={active=false,origin=Vector2.zero,current=Vector2.zero,radius=70,deadzone=8,touchId=nil,forward=0,turn=0}
    local carRayParams=RaycastParams.new(); carRayParams.FilterType=Enum.RaycastFilterType.Exclude

    -- ── DE Shrine state ───────────────────────────────────────
    local shrineSubGui=nil; local shrineActive=false
    -- Phase: "inactive" / "underground" / "closing" / "closed" / "opening"
    local shrinePhase="inactive"
    local shrineCenter=Vector3.zero
    local shrineTimer=0
    local SHRINE_CLOSE_TIME=3.5   -- seconds for closing animation
    local SHRINE_OPEN_TIME=2.5    -- seconds for opening animation
    local DOMAIN_RADIUS=30
    local SLASH_SPEED=290
    -- Part role assignments (indices into the sorted part list)
    local shrineStructOffsets = {  -- offsets from shrineCenter for shrine structure parts
        CFrame.new(0,0.25,0),    -- [1] base stone tier 1
        CFrame.new(0,0.75,0),    -- [2] base stone tier 2
        CFrame.new(0,1.25,0),    -- [3] base stone tier 3
        CFrame.new(0,1.75,0),    -- [4] base wood tier
        CFrame.new(0,4,0),       -- [5] shrine pillar
        CFrame.new(0,6.25,0),    -- [6] shrine top
        CFrame.new(0,6.6,0)*CFrame.Angles(0,0,0),  -- [7] roof beam
        CFrame.new(0,7,0),       -- [8] roof
        CFrame.new(-3,2.5,6.5),  -- [9] torii L pillar
        CFrame.new(3,2.5,6.5),   -- [10] torii R pillar
        CFrame.new(0,5,6.5),     -- [11] torii top beam
        CFrame.new(0,4.2,6.5),   -- [12] torii lower beam
        CFrame.new(0,9,0)*CFrame.Angles(0,0,math.rad(30)), -- [13] curse eye
        CFrame.new(-1.8,2.5+0.25,0),  -- [14] lantern L front
        CFrame.new(1.8,2.5+0.25,0),   -- [15] lantern R front
        CFrame.new(0,2.5+0.25,-1.8),  -- [16] lantern back L
        CFrame.new(0,2.5+0.25,1.8),   -- [17] lantern back R
        CFrame.new(0,0.02,4),    -- [18] curse mark line 1
        CFrame.new(0,0.02,4)*CFrame.Angles(0,math.rad(60),0), -- [19] curse line 2
        CFrame.new(0,0.02,4)*CFrame.Angles(0,math.rad(120),0),-- [20] curse line 3
    }
    local STRUCT_COUNT = #shrineStructOffsets
    local SLASH_COUNT  = 6
    local shrineWallIndices  = {}  -- indices of sphere wall parts
    local shrineStructParts  = {}  -- parts[1..STRUCT_COUNT]
    local shrineSlashParts   = {}  -- parts[STRUCT_COUNT+1..STRUCT_COUNT+SLASH_COUNT]
    local slashVelocities    = {}
    local shrinePartList     = {}  -- sorted list of all controlled parts

    -- Assign parts: biggest 20 → shrine structure, next 6 → slashes, rest → sphere wall
    local function assignShrineParts()
        shrinePartList={}
        for part,_ in pairs(controlled) do if part and part.Parent then table.insert(shrinePartList,part) end end
        table.sort(shrinePartList,function(a,b)return a.Size.Magnitude>b.Size.Magnitude end)
        shrineStructParts={}; shrineSlashParts={}; shrineWallIndices={}
        for i,part in ipairs(shrinePartList) do
            if i<=STRUCT_COUNT then table.insert(shrineStructParts,part)
            elseif i<=STRUCT_COUNT+SLASH_COUNT then table.insert(shrineSlashParts,part)
            else table.insert(shrineWallIndices,i) end
        end
    end

    local UNDERGROUND_Y = -600  -- far below any map

    -- Move a part to its underground holding position
    local function setUnderground(part, idx)
        local data=controlled[part]; if not data then return end
        if data.bp and data.bp.Parent then
            data.bp.P=80000; data.bp.D=4000
            data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
            data.bp.Position=Vector3.new(
                shrineCenter.X + (idx%20)*3,
                UNDERGROUND_Y,
                shrineCenter.Z + math.floor(idx/20)*3)
        end
        if data.bg and data.bg.Parent then
            data.bg.P=80000; data.bg.D=4000
            data.bg.CFrame=CFrame.new(shrineCenter.X+(idx%20)*3,UNDERGROUND_Y,shrineCenter.Z+math.floor(idx/20)*3)
        end
    end

    -- Get target CFrame on sphere surface for wall part index
    local function getSphereWallCF(idx, total)
        local phi=(1+math.sqrt(5))/2; local i=idx-1; local s=math.max(total,1)
        local theta=math.acos(math.clamp(1-2*(i+0.5)/s,-1,1)); local ang=2*math.pi*i/phi
        local r=DOMAIN_RADIUS
        return Vector3.new(shrineCenter.X+r*math.sin(theta)*math.cos(ang),shrineCenter.Y+r*math.sin(theta)*math.sin(ang),shrineCenter.Z+r*math.cos(theta))
    end

    -- ── Gojo state ────────────────────────────────────────────
    local gojoSubGui=nil; local gojoActive=false
    -- "idle" / "blue_hold" / "red_charge" / "red_fire" / "purple_split" / "purple_fire" / "de_infinity"
    local gojoState="idle"
    local gojoOrbitAngle=0
    local gojoInfinityRadius=28
    local gojoInfinityAngle=0
    local RED_PART_COUNT=10  -- how many parts reversal red uses

    -- ── Mode tables ───────────────────────────────────────────
    local CFRAME_MODES={heart=true,rings=true,wall=true,box=true,gasterhand=true,gaster2hands=true,wings=true,sphere=true,spherebender=true,tank=true,car=true,de_shrine=true,gojo=true,pet=true}
    local GASTER_MODES={gasterhand=true,gaster2hands=true}; local SPHERE_MODES={sphere=true}
    local SPHERE_BENDER_MODES={spherebender=true}; local TANK_MODES={tank=true}
    local CAR_MODES={car=true}; local SHRINE_MODES={de_shrine=true}; local GOJO_MODES={gojo=true}
    local PET_MODES={pet=true}

    -- ── Lock blocks state ─────────────────────────────────────
    -- When enabled: every controlled part has MaxForce cranked to 1e14,
    -- SetNetworkOwner(player) re-asserted each sweep, and CanCollide=false
    -- so nobody can physically shove them.  The BP/BG already resist movement;
    -- the extra MaxForce and ownership re-claim make them immovable.
    local lockedBlocks = false

    -- ── Pet mode state ────────────────────────────────────────
    local petSubGui      = nil
    local petActive      = false
    local petOwners      = {}   -- { [playerName] = true }
    local petOwnerList   = {}   -- ordered list for display
    local petState       = "idle"   -- idle/follow/stay/dance/orbit/wall/split/ring/stop
    local petOrbitDist   = 8
    local petDanceT      = 0
    local petDancePhase  = 0
    local petSplitOwners = {}   -- for split: {[ownerName]={parts={}}}
    local petGuiUpdateFn = nil  -- set by createPetGui, called to refresh owner list

    -- ── Gaster/Wing data (compact) ────────────────────────────
    local HAND_SCALE=2.8
    local HAND_SLOTS={{x=-4,y=5},{x=-4,y=4},{x=-4,y=3},{x=-4,y=2},{x=-2,y=6},{x=-2,y=5},{x=-2,y=4},{x=-2,y=3},{x=0,y=7},{x=0,y=6},{x=0,y=5},{x=0,y=4},{x=0,y=3},{x=2,y=6},{x=2,y=5},{x=2,y=4},{x=2,y=3},{x=5,y=2},{x=5,y=1},{x=5,y=0},{x=-4,y=1},{x=-2,y=1},{x=0,y=1},{x=2,y=1},{x=-4,y=0},{x=-2,y=0},{x=0,y=0},{x=2,y=0},{x=4,y=0},{x=-2,y=-1},{x=0,y=-1},{x=2,y=-1}}
    local PALM_SLOTS={{x=-3,y=2},{x=-1,y=2},{x=1,y=2},{x=3,y=2},{x=-3,y=1},{x=-1,y=1},{x=1,y=1},{x=3,y=1},{x=-3,y=0},{x=-1,y=0},{x=1,y=0},{x=3,y=0},{x=-2,y=-1},{x=0,y=-1},{x=2,y=-1},{x=-2,y=-2},{x=0,y=-2},{x=2,y=-2}}
    local ALL_HAND_SLOTS={}
    for _,s in ipairs(HAND_SLOTS)do table.insert(ALL_HAND_SLOTS,{x=s.x,y=s.y,isPalm=false})end
    for _,s in ipairs(PALM_SLOTS)do table.insert(ALL_HAND_SLOTS,{x=s.x,y=s.y,isPalm=true})end
    local HAND_SLOTS_COUNT=#ALL_HAND_SLOTS
    local POINTING_BIAS={[1]=-5,[2]=-5,[3]=-5,[4]=-5,[5]=-4.5,[6]=-4.5,[7]=-4.5,[8]=-4.5,[9]=-5.5,[10]=-5,[11]=-4,[12]=-2.5,[13]=-1.2,[18]=-0.6,[19]=-1.2,[20]=-1.2}
    local PUNCH_BIAS={[1]=-3,[2]=-2.5,[3]=-1.5,[4]=-0.5,[5]=-3,[6]=-2.5,[7]=-1.5,[8]=-0.5,[9]=-3.5,[10]=-3,[11]=-2,[12]=-1,[13]=-0.3,[14]=-3,[15]=-2.5,[16]=-1.5,[17]=-0.5,[18]=-0.8,[19]=-1.4,[20]=-1.4}
    local HAND_RIGHT=Vector3.new(9,2,1); local HAND_LEFT=Vector3.new(-9,2,1)
    local WING_POINTS={}; local WING_SR=Vector3.new(1,1.8,0.6); local WING_SL=Vector3.new(-1,1.8,0.6)
    local WING_OA=math.rad(82); local WING_CA=math.rad(22); local WING_FS=1.8; local WING_SPAN=14
    for _,f in ipairs({{0.15,2.2,0.4},{0.28,2.8,0.5},{0.4,3,0.6},{0.52,2.8,0.6},{0.63,2.2,0.5},{0.73,1.2,0.4},{0.82,-0.2,0.3},{0.9,-1.8,0.2},{0.97,-3.5,0.1}})do for seg=1,4 do local t2=(seg-1)/3; table.insert(WING_POINTS,{outX=f[1]*WING_SPAN+t2*0.6,upY=f[2]-t2*2,backZ=f[3]+t2*0.2,layer=1})end end
    for _,f in ipairs({{0.12,3.5,0.6},{0.22,4.4,0.7},{0.33,5,0.8},{0.44,5,0.8},{0.54,4.4,0.7},{0.62,3.4,0.6}})do for seg=1,3 do local t2=(seg-1)/2; table.insert(WING_POINTS,{outX=f[1]*WING_SPAN+t2*0.4,upY=f[2]-t2*1.2,backZ=f[3],layer=2})end end
    for _,f in ipairs({{0.04,1.5,0.5},{0.08,2.2,0.6},{0.12,2.8,0.7},{0.18,3,0.7},{0.04,0.6,0.5},{0.08,1,0.6},{0.14,1.2,0.6},{0.2,1,0.5}})do table.insert(WING_POINTS,{outX=f[1]*WING_SPAN,upY=f[2],backZ=f[3],layer=3})end
    local WING_POINT_COUNT=#WING_POINTS

    -- ── Part tracking ─────────────────────────────────────────
    local controlled={}; local partCount=0

    -- ── Forward declarations ──────────────────────────────────
    local sweepMap,fullSweep,rebuildSBGui
    local destroyTank,destroyTankGui,destroyCar,destroyCarGui
    local destroyShrine,destroyShrineGui,destroyGojo,destroyGojoGui
    local destroyPet,destroyPetGui

    -- ── Validation ────────────────────────────────────────────
    local function isValid(obj)
        if not obj then return false end
        local ok=pcall(function()if not obj.Parent then error()end end)
        if not ok or not obj.Parent then return false end
        if not obj:IsA("BasePart")then return false end
        if obj.Anchored then return false end
        if obj.Size.Magnitude<0.2 then return false end
        if obj.Transparency>=1 then return false end
        local p=obj.Parent
        while p and p~=workspace do if p:FindFirstChildOfClass("Humanoid")then return false end; p=p.Parent end
        return true
    end

    -- ── Part grab / release ───────────────────────────────────
    local function grabPart(part)
        if controlled[part]then return end
        if not isValid(part)then return end
        local char=player.Character; local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local effectiveRange=(pullStrength>=5000) and math.huge or detectionRange
        if root and(part.Position-root.Position).Magnitude>effectiveRange then return end
        local origCC=part.CanCollide; local origAnch=part.Anchored
        pcall(function()part.CanCollide=false end)
        local p=math.max(1,pullStrength); local d=math.max(50,p*0.05)
        local bp=Instance.new("BodyPosition"); bp.MaxForce=Vector3.new(1e12,1e12,1e12); bp.P=p; bp.D=d; bp.Position=part.Position; bp.Parent=part
        local bg=Instance.new("BodyGyro"); bg.MaxTorque=Vector3.new(1e12,1e12,1e12); bg.P=p; bg.D=d; bg.CFrame=part.CFrame; bg.Parent=part
        controlled[part]={origCC=origCC,origAnch=origAnch,bp=bp,bg=bg,origColor=part.Color,origMaterial=part.Material}
        partCount=partCount+1
    end

    local function releasePart(part,data)
        pcall(function()
            if data.bp and data.bp.Parent then data.bp:Destroy()end
            if data.bg and data.bg.Parent then data.bg:Destroy()end
        end)
        if part and part.Parent then
            pcall(function()
                part.CanCollide=data.origCC; part.Anchored=data.origAnch or false
                if data.origColor then part.Color=data.origColor end
                if data.origMaterial then part.Material=data.origMaterial end
            end)
        end
    end

    local function stripMotors(part)
        if not(part and part.Parent)then return end
        for _,child in ipairs(part:GetChildren())do
            if child:IsA("BodyPosition") or child:IsA("BodyGyro")then pcall(function()child:Destroy()end)end
        end
        if controlled[part]then controlled[part].bp=nil; controlled[part].bg=nil end
    end

    local function releaseAll()
        for part,data in pairs(controlled)do releasePart(part,data)end
        controlled={}; partCount=0; snakeT=0; snakeHistory={}
        if tankActive then pcall(destroyTank);pcall(destroyTankGui)end
        if carActive  then pcall(destroyCar); pcall(destroyCarGui) end
        if shrineActive then pcall(destroyShrine);pcall(destroyShrineGui)end
        if gojoActive  then pcall(destroyGojo); pcall(destroyGojoGui) end
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
    end

    sweepMap=function()
        for _,obj in ipairs(workspace:GetDescendants())do
            if isValid(obj) and not controlled[obj]then grabPart(obj)end
        end
    end

    -- fullSweep: no distance filter, grabs EVERY unanchored part in workspace.
    -- Also re-asserts network ownership so nobody else can move our blocks.
    fullSweep=function()
        for _,obj in ipairs(workspace:GetDescendants())do
            if isValid(obj) and not controlled[obj]then
                local origCC=obj.CanCollide; local origAnch=obj.Anchored
                pcall(function()obj.CanCollide=false end)
                pcall(function()obj:SetNetworkOwner(player)end)  -- claim ownership
                local p=math.max(1,pullStrength); local d=math.max(50,p*0.05)
                local bp=Instance.new("BodyPosition"); bp.MaxForce=Vector3.new(1e12,1e12,1e12); bp.P=p; bp.D=d; bp.Position=obj.Position; bp.Parent=obj
                local bg=Instance.new("BodyGyro"); bg.MaxTorque=Vector3.new(1e12,1e12,1e12); bp.P=p; bg.D=d; bg.CFrame=obj.CFrame; bg.Parent=obj
                controlled[obj]={origCC=origCC,origAnch=origAnch,bp=bp,bg=bg,origColor=obj.Color,origMaterial=obj.Material}
                partCount=partCount+1
            elseif controlled[obj] then
                -- Re-assert ownership on already-controlled parts (in case someone grabbed)
                pcall(function()obj:SetNetworkOwner(player)end)
            end
        end
    end

    -- lockAllNow: maximum-force lock on all controlled parts.
    -- Called every frame when lockedBlocks=true.
    local function lockAllNow()
        for part, data in pairs(controlled) do
            if part and part.Parent then
                pcall(function()
                    part:SetNetworkOwner(player)
                    part.CanCollide = false
                    if data.bp and data.bp.Parent then
                        data.bp.MaxForce = Vector3.new(1e14,1e14,1e14)
                        data.bp.P = 200000
                        data.bp.D = 8000
                    end
                    if data.bg and data.bg.Parent then
                        data.bg.MaxTorque = Vector3.new(1e14,1e14,1e14)
                        data.bg.P = 200000
                        data.bg.D = 8000
                    end
                end)
            end
        end
    end

    -- ── Helpers ───────────────────────────────────────────────
    -- Aim direction = character HRP look vector (not camera)
    -- dist = how far in front of the character the target point is
    local function getAimPoint(dist)
        local char=player.Character
        local root=char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if not root then
            local cam=workspace.CurrentCamera
            return cam.CFrame.Position+cam.CFrame.LookVector*(dist or 30), cam.CFrame.LookVector
        end
        local lookDir=root.CFrame.LookVector
        return root.Position + lookDir*(dist or 30), lookDir
    end

    local function getSnakeTarget(i)
        local idx=math.clamp(i*SNAKE_GAP,1,math.max(1,#snakeHistory))
        return snakeHistory[idx] or snakeHistory[#snakeHistory] or Vector3.zero
    end

    local function getWingCF(ptIdx,side,cf,t)
        local wp=WING_POINTS[ptIdx]; if not wp then return CFrame.new(0,-5000,0)end
        local fa=WING_CA+(((math.sin(t*WING_FS*math.pi)+1)/2))*(WING_OA-WING_CA); local cosA,sinA=math.cos(fa),math.sin(fa)
        local rotX=(wp.outX*cosA-wp.backZ*sinA)*side; local sh=(side==1)and WING_SR or WING_SL
        return CFrame.new(cf:PointToWorldSpace(Vector3.new(sh.X+rotX,sh.Y+wp.upY,sh.Z+wp.outX*sinA+wp.backZ*cosA+0.5)))
    end

    local SPHERE_SHELL_SPACING=0.8
    local function getSphereShellPos(index,total)
        local phi=(1+math.sqrt(5))/2; local i=index-1; local s=math.max(total,1)
        local theta=math.acos(math.clamp(1-2*(i+0.5)/s,-1,1)); local ang=2*math.pi*i/phi
        local r=SPHERE_SHELL_SPACING*(1+math.floor(i/12)*0.5)
        return Vector3.new(r*math.sin(theta)*math.cos(ang),r*math.sin(theta)*math.sin(ang),r*math.cos(theta))
    end

    local function updateSphereTarget(dt,rootPos)
        if sphereMode=="orbit" then
            sphereOrbitAngle=sphereOrbitAngle+dt*SPHERE_SPEED
            local tgt=rootPos+Vector3.new(math.cos(sphereOrbitAngle)*SPHERE_RADIUS,1.5,math.sin(sphereOrbitAngle)*SPHERE_RADIUS)
            sphereVel=sphereVel+(tgt-spherePos)*(SPHERE_SPRING*dt); sphereVel=sphereVel*(1-SPHERE_DAMP*dt); spherePos=spherePos+sphereVel*dt
        elseif sphereMode=="follow" then
            local b=rootPos+Vector3.new(0,1.5,4); local d=b-spherePos; local dist=d.Magnitude
            if dist>3 then sphereVel=sphereVel+d.Unit*(dist-3)*SPHERE_SPRING*dt end
            sphereVel=sphereVel*(1-SPHERE_DAMP*dt); spherePos=spherePos+sphereVel*dt
        else sphereVel=sphereVel*(1-SPHERE_DAMP*2*dt); spherePos=spherePos+sphereVel*dt end
    end

    local function updateSphereBenderTargets(dt,rootPos)
        for _,sp in ipairs(sbSpheres)do
            if sp.stopped then sp.vel=Vector3.zero
            elseif sp.mode=="orbit" then
                sp.orbitAngle=sp.orbitAngle+dt*SPHERE_SPEED
                local tgt=rootPos+Vector3.new(math.cos(sp.orbitAngle)*SPHERE_RADIUS,1.5,math.sin(sp.orbitAngle)*SPHERE_RADIUS)
                sp.vel=sp.vel+(tgt-sp.pos)*(SPHERE_SPRING*dt); sp.vel=sp.vel*(1-SPHERE_DAMP*dt); sp.pos=sp.pos+sp.vel*dt
            elseif sp.mode=="follow" then
                local b=rootPos+Vector3.new(0,1.5,4); local d=b-sp.pos; local dist=d.Magnitude
                if dist>3 then sp.vel=sp.vel+d.Unit*(dist-3)*SPHERE_SPRING*dt end
                sp.vel=sp.vel*(1-SPHERE_DAMP*dt); sp.pos=sp.pos+sp.vel*dt
            else sp.vel=sp.vel*(1-SPHERE_DAMP*2*dt); sp.pos=sp.pos+sp.vel*dt end
        end
    end

    local function getFormationCF(mode,i,n,origin,cf,t)
        if mode=="heart" then
            local a=((i-1)/math.max(n,1))*math.pi*2; local hx=16*math.sin(a)^3; local hz=-(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))
            return CFrame.new(origin+cf:VectorToWorldSpace(Vector3.new(hx*(radius/16),0,hz*(radius/16))))
        elseif mode=="rings" then local a=((i-1)/math.max(n,1))*math.pi*2+t*1.4; return CFrame.new(origin+Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius))
        elseif mode=="wall" then
            local cols=math.max(1,math.ceil(math.sqrt(n))); return CFrame.new(origin+cf.LookVector*radius+cf.RightVector*(((i-1)%cols-math.floor(cols/2))*1.8)+cf.UpVector*((math.floor((i-1)/cols)-1)*1.8+1))
        elseif mode=="box" then
            local fV={cf.LookVector,-cf.LookVector,cf.RightVector,-cf.RightVector,cf.UpVector,-cf.UpVector}
            local fA={cf.RightVector,cf.RightVector,cf.LookVector,cf.LookVector,cf.RightVector,cf.RightVector}
            local fB={cf.UpVector,cf.UpVector,cf.UpVector,cf.UpVector,cf.LookVector,cf.LookVector}
            local fi=((i-1)%6)+1; local si=math.floor((i-1)/6); local sp=radius*0.45
            return CFrame.new(origin+fV[fi]*radius+fA[fi]*((si%2-0.5)*sp)+fB[fi]*(math.floor(si/2)-0.5)*sp)
        elseif mode=="wings" then
            local half=math.ceil(n/2); local side,ptIdx=1,i
            if i>half then side=-1;ptIdx=i-half end
            return getWingCF(((ptIdx-1)%WING_POINT_COUNT)+1,side,cf,t)
        end
        return CFrame.new(origin)
    end

    local function getGasterCF(slotIdx,side,cf,gt)
        local slot=ALL_HAND_SLOTS[slotIdx]; if not slot then return CFrame.new(0,-5000,0)end
        local sx=slot.x*HAND_SCALE; local sy=slot.y*HAND_SCALE; local floatY=math.sin(gt*2+side*1.2)*1
        if not slot.isPalm then
            if gasterAnim=="pointing" then sy=sy+(POINTING_BIAS[slotIdx] or 0)*HAND_SCALE
            elseif gasterAnim=="punching" then sy=sy+(PUNCH_BIAS[slotIdx] or 0)*HAND_SCALE end
        end
        local waveAng=(gasterAnim=="waving") and math.sin(gt*2.2)*0.5 or 0
        local punchZ=(gasterAnim=="punching" and not slot.isPalm) and (math.sin(gt*10)*0.5+0.5)*8 or 0
        local base=(side==1)and HAND_RIGHT or HAND_LEFT; local palmOff=slot.isPalm and 1.5 or 0
        return CFrame.new(cf:PointToWorldSpace(Vector3.new(base.X+sx*math.cos(waveAng)*side,base.Y+sy+floatY,base.Z+sx*math.sin(waveAng)-punchZ+palmOff)))
    end

    -- ── Helper: set block color/material ──────────────────────
    local function colorParts(parts, col, mat)
        for _,part in ipairs(parts)do pcall(function()if part and part.Parent then part.Color=col;part.Material=mat or Enum.Material.Neon end end)end
    end
    local function colorAllControlled(col, mat)
        for part,_ in pairs(controlled)do pcall(function()if part and part.Parent then part.Color=col;part.Material=mat or Enum.Material.Neon end end)end
    end
    local function restoreAllColors()
        for part,data in pairs(controlled)do
            pcall(function()
                if part and part.Parent and data.origColor then part.Color=data.origColor end
                if part and part.Parent and data.origMaterial then part.Material=data.origMaterial end
            end)
        end
    end

    -- ── Set BodyPosition on controlled part (used by techniques) ──
    local function setBP(part, targetPos)
        local data=controlled[part]; if not data then return end
        if data.bp and data.bp.Parent then data.bp.Position=targetPos end
    end

    -- ── Remove BodyPosition/Gyro from a part and give it velocity ──
    local function firePartVelocity(part, velocity)
        local data=controlled[part]; if not data then return end
        pcall(function()
            if data.bp and data.bp.Parent then data.bp:Destroy();data.bp=nil end
            if data.bg and data.bg.Parent then data.bg:Destroy();data.bg=nil end
        end)
        -- Add BodyVelocity for the fire direction
        pcall(function()
            -- Remove any existing BV
            for _,child in ipairs(part:GetChildren())do
                if child:IsA("BodyVelocity")then child:Destroy()end
            end
            local bv=Instance.new("BodyVelocity")
            bv.MaxForce=Vector3.new(1e12,1e12,1e12)
            bv.Velocity=velocity; bv.Parent=part
            -- Remove BV after 6 seconds so physics takes over
            Debris:AddItem(bv, 6)
        end)
    end

    -- ════════════════════════════════════════════════════════════
    -- TANK (identical to v8)
    -- ════════════════════════════════════════════════════════════
    local function buildTankFromParts(position,cf)
        local pl={}
        for part,_ in pairs(controlled)do if part and part.Parent then table.insert(pl,part)end end
        if #pl<25 then sweepMap();task.wait(0.3);pl={}
            for part,_ in pairs(controlled)do if part and part.Parent then table.insert(pl,part)end end
            if #pl<25 then print("[ManipKii] Tank needs 25+ parts (found "..#pl..")");return false end
        end
        table.sort(pl,function(a,b)return a.Size.Magnitude>b.Size.Magnitude end)
        tks.tankParts={};tks.partOffsets={};tks.turretPartIdx=nil;tks.barrelPartIdx=nil
        local idx=1
        local hull=pl[idx]; hull.CFrame=cf*CFrame.new(0,TANK_H/2,0)
        tks.tankBase=hull;tks.tankParts[idx]=hull;tks.partOffsets[idx]=CFrame.new(0,TANK_H/2,0);idx=idx+1
        for i=1,4 do if pl[idx]then local off=CFrame.new(-TANK_W/2-0.5,-0.5,-TANK_L/3+i*3.5);pl[idx].CFrame=hull.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end end
        for i=1,4 do if pl[idx]then local off=CFrame.new(TANK_W/2+0.5,-0.5,-TANK_L/3+i*3.5);pl[idx].CFrame=hull.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end end
        if pl[idx]then local off=CFrame.new(0,-0.5,TANK_L/2+1);pl[idx].CFrame=hull.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end
        if pl[idx]then local off=CFrame.new(0,-0.5,-TANK_L/2-1);pl[idx].CFrame=hull.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end
        for i=1,3 do if pl[idx]then local off=CFrame.new(-TANK_W/2,0.5,-TANK_L/3+i*4);pl[idx].CFrame=hull.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end end
        for i=1,3 do if pl[idx]then local off=CFrame.new(TANK_W/2,0.5,-TANK_L/3+i*4);pl[idx].CFrame=hull.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end end
        for i=1,5 do if pl[idx]then local off=CFrame.new(-TANK_W/2-1,-1,-TANK_L/2+i*3.2);pl[idx].CFrame=hull.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end end
        for i=1,5 do if pl[idx]then local off=CFrame.new(TANK_W/2+1,-1,-TANK_L/2+i*3.2);pl[idx].CFrame=hull.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end end
        local tBase=nil
        if pl[idx]then tBase=pl[idx];local off=CFrame.new(0,TANK_H/2+0.5,0);tBase.CFrame=hull.CFrame*off;tks.tankParts[idx]=tBase;tks.partOffsets[idx]=off;idx=idx+1 end
        if pl[idx] and tBase then
            local tb=pl[idx];local off=CFrame.new(0,TANK_H/2+2,0);tb.CFrame=hull.CFrame*off
            tks.turretPart=tb;tks.turretPartIdx=idx;tks.tankParts[idx]=tb;tks.partOffsets[idx]=off;idx=idx+1
        end
        if pl[idx] and tks.turretPart then local off=CFrame.new(-2.5,0,0);pl[idx].CFrame=tks.turretPart.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end
        if pl[idx] and tks.turretPart then local off=CFrame.new(2.5,0,0);pl[idx].CFrame=tks.turretPart.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end
        if pl[idx] and tks.turretPart then local off=CFrame.new(0,1.5,-0.5);pl[idx].CFrame=tks.turretPart.CFrame*off;tks.tankHatch=pl[idx];tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end
        for i=idx,math.min(idx+6,#pl)do
            if pl[i] and tks.turretPart and pl[i].Size.Z>pl[i].Size.X and pl[i].Size.Z>pl[i].Size.Y then
                local off=CFrame.new(0,0.3,5.5);pl[i].CFrame=tks.turretPart.CFrame*off
                tks.barrelPart=pl[i];tks.barrelPartIdx=i;tks.tankParts[i]=pl[i];tks.partOffsets[i]=off;break
            end
        end
        local filterList={}
        for _,part in ipairs(tks.tankParts)do if part and part.Parent then stripMotors(part);table.insert(filterList,part)end end
        tankRayParams.FilterDescendantsInstances=filterList
        frozenTankCF=nil; return true
    end

    destroyTank=function()
        if tks.tankBase then pcall(function()local e=Instance.new("Explosion");e.Position=tks.tankBase.Position;e.BlastRadius=15;e.BlastPressure=300000;e.Parent=workspace end)end
        for _,part in ipairs(tks.tankParts)do if part and part.Parent and controlled[part]then releasePart(part,controlled[part]);controlled[part]=nil;partCount=math.max(0,partCount-1)end end
        tks={forward=0,turn=0,hatchOpen=false,insideTank=false,tankBase=nil,turretPart=nil,barrelPart=nil,turretPartIdx=nil,barrelPartIdx=nil,tankParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0,tankHatch=nil}
        frozenTankCF=nil;tankActive=false;cameraOrbitAngle=0;cameraPitchAngle=math.rad(25)
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end); thawPlayer()
    end

    local function shootProjectile()
        if not tankActive or not tks.barrelPart or not tks.insideTank then return end
        local now=tick(); if now-lastShot<SHOOT_CD then return end; lastShot=now
        local shell=Instance.new("Part"); shell.Name="TankShell"; shell.Size=Vector3.new(0.35,0.35,2)
        shell.BrickColor=BrickColor.new("Dark grey metallic"); shell.Material=Enum.Material.Metal; shell.CanCollide=true; shell.CastShadow=false
        local barrelCF=tks.barrelPart.CFrame; shell.CFrame=barrelCF*CFrame.new(0,0,tks.barrelPart.Size.Z/2+1.2); shell.Parent=workspace
        local pitchBias=math.sin(cameraPitchAngle*0.15)*PROJ_SPEED*0.2
        local arcDir=(barrelCF.LookVector+Vector3.new(0,pitchBias/PROJ_SPEED,0)).Unit
        pcall(function()shell.AssemblyLinearVelocity=arcDir*PROJ_SPEED end)
        pcall(function()local fl=Instance.new("PointLight");fl.Brightness=10;fl.Range=20;fl.Color=Color3.fromRGB(255,220,100);fl.Parent=shell;Debris:AddItem(fl,0.08)end)
        local hitConn; hitConn=shell.Touched:Connect(function(hit)
            if hit==tks.barrelPart or hit==tks.turretPart then return end
            local c2=player.Character; if c2 and hit:IsDescendantOf(c2)then return end
            pcall(function()local ex=Instance.new("Explosion");ex.Position=shell.Position;ex.BlastRadius=10;ex.BlastPressure=150000;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace end)
            hitConn:Disconnect(); pcall(function()shell:Destroy()end)
        end); Debris:AddItem(shell,12)
        if tks.tankBase then pcall(function()tks.tankBase.AssemblyLinearVelocity=tks.tankBase.AssemblyLinearVelocity-barrelCF.LookVector*4 end)end
    end

    local function toggleHatch()
        if not tks.tankBase then return end
        if not tks.hatchOpen then
            tks.hatchOpen=true;tks.insideTank=false;frozenTankCF=tks.tankBase.CFrame
            if tks.tankHatch then pcall(function()tks.tankHatch.CFrame=tks.tankHatch.CFrame*CFrame.new(0,2.5,0)*CFrame.Angles(math.rad(65),0,0)end)end
            thawPlayer(tks.tankBase.CFrame*CFrame.new(0,TANK_H+4,0))
            pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        else
            tks.hatchOpen=false;tks.insideTank=true;frozenTankCF=nil
            if tks.tankHatch then pcall(function()tks.tankHatch.CFrame=tks.tankHatch.CFrame*CFrame.Angles(math.rad(-65),0,0)*CFrame.new(0,-2.5,0)end)end
            freezePlayer(tks.tankBase.CFrame*CFrame.new(0,TANK_INTERIOR_Y,0))
        end
    end

    local function updateTank(dt)
        if not tankActive or not tks.tankBase then return end
        if not tks.insideTank then
            if frozenTankCF then
                pcall(function()tks.tankBase.CFrame=frozenTankCF;tks.tankBase.AssemblyLinearVelocity=Vector3.zero;tks.tankBase.AssemblyAngularVelocity=Vector3.zero end)
                for i,part in ipairs(tks.tankParts)do if part and part.Parent and tks.partOffsets[i]then pcall(function()part.CFrame=frozenTankCF*tks.partOffsets[i];part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end)end end
            end
            return
        end
        if tks.forward~=0 then tks.currentSpeed=math.clamp(tks.currentSpeed+tks.forward*TANK_ACCEL*dt,-TANK_SPEED,TANK_SPEED) else tks.currentSpeed=tks.currentSpeed*TANK_FRIC end
        tks.currentTurnSpeed=tks.turn~=0 and tks.turn*TANK_TURN or 0
        local newCF=tks.tankBase.CFrame*CFrame.new(tks.tankBase.CFrame.LookVector*tks.currentSpeed*dt)*CFrame.Angles(0,tks.currentTurnSpeed*dt,0)
        local ray=workspace:Raycast(newCF.Position+Vector3.new(0,6,0),Vector3.new(0,-20,0),tankRayParams)
        if ray then newCF=CFrame.new(Vector3.new(newCF.Position.X,ray.Position.Y+TANK_H/2,newCF.Position.Z))*newCF.Rotation end
        pcall(function()tks.tankBase.CFrame=newCF;tks.tankBase.AssemblyLinearVelocity=Vector3.zero;tks.tankBase.AssemblyAngularVelocity=Vector3.zero end)
        for i,part in ipairs(tks.tankParts)do
            if part and part.Parent and tks.partOffsets[i] and part~=tks.turretPart and part~=tks.barrelPart then
                local off=tks.partOffsets[i]; local isTD=math.abs(off.Position.X)>2 and math.abs(off.Position.X)<3 and math.abs(off.Position.Y)<0.2
                if not isTD then pcall(function()part.CFrame=newCF*off;part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end)end
            end
        end
        if tks.turretPart and tks.turretPartIdx then
            pcall(function()
                local hullOff=tks.partOffsets[tks.turretPartIdx]; local anchor=newCF*hullOff
                local _,tankYaw=select(2,newCF:ToEulerAnglesYXZ()); tankYaw=select(2,newCF:ToEulerAnglesYXZ())
                tks.turretPart.CFrame=CFrame.new(anchor.Position)*CFrame.Angles(0,tankYaw+cameraOrbitAngle,0)
                tks.turretPart.AssemblyLinearVelocity=Vector3.zero;tks.turretPart.AssemblyAngularVelocity=Vector3.zero
            end)
        end
        if tks.turretPart then
            for i,part in ipairs(tks.tankParts)do
                local off=tks.partOffsets[i]
                if off and part and part.Parent and part~=tks.turretPart and part~=tks.barrelPart then
                    if math.abs(off.Position.X)>2 and math.abs(off.Position.X)<3 and math.abs(off.Position.Y)<0.2 then
                        pcall(function()part.CFrame=tks.turretPart.CFrame*off;part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end)
                    end
                end
            end
        end
        if tks.barrelPart and tks.turretPart and tks.barrelPartIdx then
            pcall(function()
                local bp2=math.clamp(-math.rad(10)+cameraPitchAngle*0.35,math.rad(-5),math.rad(25))
                local off=tks.partOffsets[tks.barrelPartIdx]
                if off then tks.barrelPart.CFrame=tks.turretPart.CFrame*CFrame.Angles(bp2,0,0)*CFrame.new(off.Position);tks.barrelPart.AssemblyLinearVelocity=Vector3.zero;tks.barrelPart.AssemblyAngularVelocity=Vector3.zero end
            end)
        end
        local char=player.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.Anchored then pcall(function()hrp.CFrame=newCF*CFrame.new(0,TANK_INTERIOR_Y,0)end)end
            for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=false end)end end
        end
        pcall(function()
            workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
            local tankPos=newCF.Position; local _,tankYaw=select(2,newCF:ToEulerAnglesYXZ()); tankYaw=select(2,newCF:ToEulerAnglesYXZ())
            local pitch=math.clamp(cameraPitchAngle,CAM_PITCH_MIN,CAM_PITCH_MAX); local worldAngle=tankYaw+math.pi+cameraOrbitAngle
            local camX=tankPos.X+math.sin(worldAngle)*math.cos(pitch)*CAMERA_DIST; local camY=tankPos.Y+math.sin(pitch)*CAMERA_DIST+1; local camZ=tankPos.Z+math.cos(worldAngle)*math.cos(pitch)*CAMERA_DIST
            local oa=worldAngle+math.pi; local lookAt=Vector3.new(tankPos.X+math.sin(oa)*14,tankPos.Y+2,tankPos.Z+math.cos(oa)*14)
            workspace.CurrentCamera.CFrame=CFrame.new(Vector3.new(camX,camY,camZ),lookAt)
        end)
    end

    -- ════════════════════════════════════════════════════════════
    -- CAR (identical to v8 logic, joystick fixed)
    -- ════════════════════════════════════════════════════════════
    local CAR_OFFSETS={CFrame.new(0,0,0),CFrame.new(-5,-1.2,-6.5),CFrame.new(5,-1.2,-6.5),CFrame.new(-5,-1.2,6.5),CFrame.new(5,-1.2,6.5),CFrame.new(-4.8,0.5,-2),CFrame.new(4.8,0.5,-2),CFrame.new(-4.8,0.5,3),CFrame.new(4.8,0.5,3),CFrame.new(0,-0.5,-8.5),CFrame.new(0,-0.5,8.5),CFrame.new(0,1.4,-5),CFrame.new(0,1.4,5),CFrame.new(0,2.8,0),CFrame.new(0,2.4,-3.5),CFrame.new(0,2.4,3.5),CFrame.new(-4,2.4,-2.5),CFrame.new(4,2.4,-2.5),CFrame.new(-4,2.4,2.5),CFrame.new(4,2.4,2.5),CFrame.new(0,0.4,-8),CFrame.new(-2,-1.2,8),CFrame.new(2,-1.2,8),CFrame.new(0,3.2,6),CFrame.new(0,1,-1.5),CFrame.new(-5,1.4,-2.5)}

    local function buildCarFromParts(position,cf)
        local pl={}
        for part,_ in pairs(controlled)do if part and part.Parent then table.insert(pl,part)end end
        local needed=#CAR_OFFSETS
        if #pl<needed then sweepMap();task.wait(0.3);pl={}
            for part,_ in pairs(controlled)do if part and part.Parent then table.insert(pl,part)end end
            if #pl<needed then print("[ManipKii] Car needs "..needed.."+ parts (found "..#pl..")");return false end
        end
        table.sort(pl,function(a,b)return a.Size.Magnitude>b.Size.Magnitude end)
        cs.carParts={};cs.partOffsets={};cs.carBase=nil;cs.carDoor=nil
        cs.carBase=pl[1];pl[1].CFrame=cf*CFrame.new(0,CAR_H/2,0);cs.carParts[1]=pl[1];cs.partOffsets[1]=CFrame.new(0,CAR_H/2,0)
        for i=2,math.min(needed,#pl)do local off=CAR_OFFSETS[i];pl[i].CFrame=pl[1].CFrame*off;cs.carParts[i]=pl[i];cs.partOffsets[i]=off;if i==26 then cs.carDoor=pl[i]end end
        local filterList={}
        for _,part in ipairs(cs.carParts)do if part and part.Parent then stripMotors(part);table.insert(filterList,part)end end
        carRayParams.FilterDescendantsInstances=filterList; frozenCarCF=nil; return true
    end

    destroyCar=function()
        for _,part in ipairs(cs.carParts)do if part and part.Parent and controlled[part]then releasePart(part,controlled[part]);controlled[part]=nil;partCount=math.max(0,partCount-1)end end
        cs={doorOpen=false,carBase=nil,carDoor=nil,carParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0}
        frozenCarCF=nil;carActive=false;carJoy.active=false;carJoy.forward=0;carJoy.turn=0
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end); thawPlayer()
    end

    local function toggleCarDoor()
        if not cs.carBase then return end
        if not cs.doorOpen then
            cs.doorOpen=true;frozenCarCF=nil
            if cs.carDoor then pcall(function()cs.carDoor.CFrame=cs.carDoor.CFrame*CFrame.Angles(0,math.rad(70),0)end)end
            freezePlayer(cs.carBase.CFrame*CFrame.new(-2,CAR_INTERIOR_Y,-1.5))
            pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        else
            cs.doorOpen=false;frozenCarCF=cs.carBase.CFrame
            if cs.carDoor then pcall(function()cs.carDoor.CFrame=cs.carDoor.CFrame*CFrame.Angles(0,math.rad(-70),0)end)end
            thawPlayer(cs.carBase.CFrame*CFrame.new(-5.5,CAR_H+2,-1.5))
        end
    end

    local function updateCar(dt)
        if not carActive or not cs.carBase then return end
        if not cs.doorOpen then
            if frozenCarCF then
                pcall(function()cs.carBase.CFrame=frozenCarCF;cs.carBase.AssemblyLinearVelocity=Vector3.zero;cs.carBase.AssemblyAngularVelocity=Vector3.zero end)
                for i,part in ipairs(cs.carParts)do if part and part.Parent and cs.partOffsets[i]then pcall(function()part.CFrame=frozenCarCF*cs.partOffsets[i];part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end)end end
            end
            return
        end
        local fwd=carJoy.forward;local trn=carJoy.turn
        if fwd~=0 then cs.currentSpeed=math.clamp(cs.currentSpeed+fwd*CAR_ACCEL*dt,-CAR_SPEED,CAR_SPEED) else cs.currentSpeed=cs.currentSpeed*CAR_FRIC end
        cs.currentTurnSpeed=trn~=0 and trn*CAR_TURN or 0
        local moveVec=cs.carBase.CFrame.LookVector*cs.currentSpeed*dt
        local newCF=cs.carBase.CFrame*CFrame.new(moveVec)*CFrame.Angles(0,cs.currentTurnSpeed*dt,0)
        local ray=workspace:Raycast(newCF.Position+Vector3.new(0,5,0),Vector3.new(0,-15,0),carRayParams)
        if ray then newCF=CFrame.new(Vector3.new(newCF.Position.X,ray.Position.Y+CAR_H/2,newCF.Position.Z))*newCF.Rotation end
        pcall(function()cs.carBase.CFrame=newCF;cs.carBase.AssemblyLinearVelocity=Vector3.zero;cs.carBase.AssemblyAngularVelocity=Vector3.zero end)
        for i,part in ipairs(cs.carParts)do if part and part.Parent and cs.partOffsets[i]then pcall(function()part.CFrame=newCF*cs.partOffsets[i];part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end)end end
        local char=player.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.Anchored then pcall(function()hrp.CFrame=newCF*CFrame.new(-2,CAR_INTERIOR_Y,-1.5)end)end
            for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=false end)end end
        end
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
    end

    -- ════════════════════════════════════════════════════════════
    -- DE SHRINE (completely reworked)
    -- Phases: inactive → underground → closing (anim) → closed → opening (anim) → underground
    -- All blocks from grabbed world parts.  Shrine structure = biggest 20 parts.
    -- Slashes = next 6 parts.  Sphere wall = remaining parts.
    -- ════════════════════════════════════════════════════════════

    -- Initialize shrine: sweep ALL blocks, send underground immediately
    local function initDeShrine(pos)
        shrineCenter = pos
        shrinePhase  = "underground"
        -- Full sweep (no range limit)
        fullSweep()
        -- Assign roles
        assignShrineParts()
        -- Color assignment
        colorParts(shrineStructParts, Color3.fromRGB(35,28,28), Enum.Material.SmoothPlastic)
        colorParts(shrineSlashParts,  Color3.fromRGB(240,240,200), Enum.Material.Neon)
        -- Send ALL blocks underground
        for i, part in ipairs(shrinePartList) do setUnderground(part, i) end
    end

    -- Trigger the closing animation (blocks rise from underground into formation)
    local function closeDomain()
        if shrinePhase~="underground" then return end
        shrinePhase="closing"; shrineTimer=0
    end

    -- Trigger the opening animation (blocks descend back underground)
    local function openDomain()
        if shrinePhase~="closed" then return end
        shrinePhase="opening"; shrineTimer=0
        -- Disable collision on all sphere parts
        for _,part in ipairs(shrinePartList) do pcall(function()part.CanCollide=false end)end
        -- Stop slash velocities
        for _,part in ipairs(shrineSlashParts) do
            pcall(function()
                for _,child in ipairs(part:GetChildren())do if child:IsA("BodyVelocity")then child:Destroy()end end
            end)
        end
    end

    -- Give slash parts BodyVelocity with random direction
    local function activateSlashes()
        slashVelocities={}
        for i,part in ipairs(shrineSlashParts) do
            if part and part.Parent then
                -- Remove any existing BV
                for _,child in ipairs(part:GetChildren())do if child:IsA("BodyVelocity")then child:Destroy()end end
                local dir=Vector3.new(math.random()-0.5, (math.random()-0.5)*0.5, math.random()-0.5).Unit
                local bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(1e9,1e9,1e9); bv.Velocity=dir*SLASH_SPEED; bv.Parent=part
                slashVelocities[i]=dir*SLASH_SPEED
                -- Color as slash
                pcall(function()part.Color=Color3.fromRGB(255,255,240);part.Material=Enum.Material.Neon end)
            end
        end
    end

    local function updateDeShrine(dt)
        if not shrineActive then return end
        local t=tick()

        if shrinePhase=="underground" then
            -- Just hold everything underground
            for i,part in ipairs(shrinePartList) do
                local data=controlled[part]
                if data and data.bp and data.bp.Parent then
                    data.bp.Position=Vector3.new(shrineCenter.X+(i%20)*3, UNDERGROUND_Y, shrineCenter.Z+math.floor(i/20)*3)
                end
            end

        elseif shrinePhase=="closing" then
            shrineTimer=shrineTimer+dt
            local progress=math.clamp(shrineTimer/SHRINE_CLOSE_TIME, 0, 1)
            -- Ease out cubic
            local ease=1-(1-progress)^3

            -- Move sphere wall blocks from underground to sphere surface
            local wallTotal=#shrineWallIndices
            for wi, partIdx in ipairs(shrineWallIndices) do
                local part=shrinePartList[partIdx]
                if part then
                    local data=controlled[part]
                    if data and data.bp and data.bp.Parent then
                        local underground=Vector3.new(shrineCenter.X+(partIdx%20)*3, UNDERGROUND_Y, shrineCenter.Z+math.floor(partIdx/20)*3)
                        local target=getSphereWallCF(wi, wallTotal)
                        data.bp.Position=underground:Lerp(target, ease)
                        if data.bg and data.bg.Parent then
                            data.bg.CFrame=CFrame.new(data.bp.Position, shrineCenter)*CFrame.Angles(0,math.pi,0)
                        end
                    end
                end
            end

            -- Move shrine structure blocks from underground to shrine offsets
            for i, part in ipairs(shrineStructParts) do
                if part then
                    local data=controlled[part]
                    if data and data.bp and data.bp.Parent then
                        local underground=Vector3.new(shrineCenter.X+(i%20)*3, UNDERGROUND_Y, shrineCenter.Z+math.floor(i/20)*3)
                        local offset=shrineStructOffsets[i]
                        local target=offset and (shrineCenter+offset.Position) or shrineCenter
                        data.bp.Position=underground:Lerp(target, ease)
                        if data.bg and data.bg.Parent then
                            local rot=offset and CFrame.new(target)*CFrame.Angles(offset:ToEulerAnglesXYZ()) or CFrame.new(target)
                            data.bg.CFrame=rot
                        end
                    end
                end
            end

            -- Move slash blocks to their starting positions underground until almost done
            for i, part in ipairs(shrineSlashParts) do
                if part then
                    local data=controlled[part]
                    if data and data.bp and data.bp.Parent then
                        local underground=Vector3.new(shrineCenter.X+(i%5)*3, UNDERGROUND_Y, shrineCenter.Z+math.floor(i/5)*3)
                        -- Slash parts rise last (after 80% progress) - sprint in from sphere wall positions
                        local slashEase=math.clamp((ease-0.8)/0.2, 0, 1)
                        local startInSphere=shrineCenter+Vector3.new(math.cos(i*math.pi/3)*DOMAIN_RADIUS, 0, math.sin(i*math.pi/3)*DOMAIN_RADIUS)
                        data.bp.Position=underground:Lerp(startInSphere, slashEase)
                    end
                end
            end

            -- Closing complete
            if progress>=1 then
                shrinePhase="closed"
                -- CanCollide = true on sphere wall parts (trap players)
                for _, partIdx in ipairs(shrineWallIndices) do
                    local part=shrinePartList[partIdx]
                    if part then pcall(function()part.CanCollide=true end)end
                end
                -- Activate slashes with BodyVelocity
                activateSlashes()
            end

        elseif shrinePhase=="closed" then
            -- Hold shrine structure in place
            for i, part in ipairs(shrineStructParts) do
                if part then
                    local data=controlled[part]; local offset=shrineStructOffsets[i]
                    if data and data.bp and data.bp.Parent and offset then
                        data.bp.Position=shrineCenter+offset.Position
                        if data.bg and data.bg.Parent then
                            local rot=CFrame.new(data.bp.Position)*CFrame.Angles(offset:ToEulerAnglesXYZ())
                            data.bg.CFrame=rot
                        end
                    end
                end
            end

            -- Hold sphere wall in place (with slight breathing pulse)
            local pulse=1+math.sin(t*1.2)*0.03
            local wallTotal=#shrineWallIndices
            for wi, partIdx in ipairs(shrineWallIndices) do
                local part=shrinePartList[partIdx]
                if part then
                local data=controlled[part]
                if data and data.bp and data.bp.Parent then
                    local phi=(1+math.sqrt(5))/2; local i2=wi-1; local s=math.max(wallTotal,1)
                    local theta=math.acos(math.clamp(1-2*(i2+0.5)/s,-1,1)); local ang=2*math.pi*i2/phi
                    local r=DOMAIN_RADIUS*pulse
                    data.bp.Position=Vector3.new(shrineCenter.X+r*math.sin(theta)*math.cos(ang),shrineCenter.Y+r*math.sin(theta)*math.sin(ang),shrineCenter.Z+r*math.cos(theta))
                    if data.bg and data.bg.Parent then data.bg.CFrame=CFrame.new(data.bp.Position,shrineCenter)*CFrame.Angles(0,math.pi,0)end
                end
                end  -- end if part
            end

            -- Update slash bouncing
            for i, part in ipairs(shrineSlashParts) do
                if part and part.Parent then
                    local slashPos=part.Position; local dist=(slashPos-shrineCenter).Magnitude
                    if dist>DOMAIN_RADIUS*0.82 then
                        local normal=(shrineCenter-slashPos).Unit; local vel=slashVelocities[i]
                        if vel then
                            local reflected=vel-2*(vel:Dot(normal))*normal
                            reflected=(reflected.Unit+Vector3.new((math.random()-0.5)*0.35,(math.random()-0.5)*0.2,(math.random()-0.5)*0.35)).Unit*SLASH_SPEED
                            slashVelocities[i]=reflected
                            pcall(function()
                                local bv=part:FindFirstChildOfClass("BodyVelocity")
                                if bv then bv.Velocity=reflected else
                                    local nbv=Instance.new("BodyVelocity");nbv.MaxForce=Vector3.new(1e9,1e9,1e9);nbv.Velocity=reflected;nbv.Parent=part
                                end
                            end)
                        end
                    end
                    -- Orient slash to face travel direction
                    if slashVelocities[i] and slashVelocities[i].Magnitude>0 then
                        pcall(function()
                            local dir=slashVelocities[i].Unit
                            part.CFrame=CFrame.new(slashPos,slashPos+dir)*CFrame.Angles(0,0,math.pi/2)
                        end)
                    end
                end
            end

        elseif shrinePhase=="opening" then
            shrineTimer=shrineTimer+dt
            local progress=math.clamp(shrineTimer/SHRINE_OPEN_TIME, 0, 1)
            local ease=progress^3  -- ease in cubic (fast at start, slow end)

            -- All blocks descend back underground
            for i, part in ipairs(shrinePartList) do
                local data=controlled[part]
                if data and data.bp and data.bp.Parent then
                    local current=data.bp.Position
                    local underground=Vector3.new(shrineCenter.X+(i%20)*3, UNDERGROUND_Y, shrineCenter.Z+math.floor(i/20)*3)
                    data.bp.Position=current:Lerp(underground, ease)
                end
            end

            if progress>=1 then shrinePhase="underground" end
        end
    end

    destroyShrine=function()
        for part,_ in pairs(controlled) do pcall(function()part.CanCollide=true end)end
        for _,part in ipairs(shrineSlashParts) do
            pcall(function()
                if part and part.Parent then
                    for _,child in ipairs(part:GetChildren())do if child:IsA("BodyVelocity")then child:Destroy()end end
                end
            end)
        end
        restoreAllColors()
        shrinePhase="inactive"; shrineCenter=Vector3.zero; shrineTimer=0
        shrinePartList={}; shrineStructParts={}; shrineSlashParts={}; shrineWallIndices={}; slashVelocities={}
        shrineActive=false
    end

    -- ════════════════════════════════════════════════════════════
    -- GOJO MODE
    -- Max Blue / Reversal Red / Hollow Purple / DE Infinity
    -- All use grabbed unanchored blocks with color changes.
    -- ════════════════════════════════════════════════════════════

    -- ── Fling helper ──────────────────────────────────────────
    -- Uses an Explosion on touch — explosions run server-side in Roblox
    -- and apply BlastPressure to ALL physics objects including player HRPs,
    -- making this the most reliable way to fling players in FE games.
    local function addFlingOnTouch(part, _flingVelocity)
        if not (part and part.Parent) then return end
        local conn; local fired = false
        conn = part.Touched:Connect(function(hit)
            if fired then return end
            if not hit or not hit.Parent then return end
            -- Only fling when touching a character part
            local hitChar = hit.Parent
            local hitHum  = hitChar and hitChar:FindFirstChildOfClass("Humanoid")
            if not hitHum or hitHum.Health <= 0 then return end
            -- Don't fling ourselves
            local myChar = player.Character
            if myChar and (hit:IsDescendantOf(myChar) or hitChar == myChar) then return end
            fired = true
            pcall(function() conn:Disconnect() end)
            -- Explosion at impact — BlastPressure flings all nearby physics objects
            -- including the player's HumanoidRootPart
            pcall(function()
                local ex = Instance.new("Explosion")
                ex.Position        = part.Position
                ex.BlastRadius     = 8
                ex.BlastPressure   = 800000   -- strong enough to send players flying
                ex.DestroyJointRadiusPercent = 0  -- don't destroy welds
                ex.Parent = workspace
            end)
        end)
        task.delay(10, function() pcall(function() conn:Disconnect() end) end)
    end

    -- ── Cooldown tracker ─────────────────────────────────────
    local gojoLastFire = { blue=0, red=0, purple=0 }
    local BLUE_CD   = 12   -- seconds (10s duration + 2s buffer)
    local RED_CD    = 4
    local PURPLE_CD = 6

    -- ── Max Blue ─────────────────────────────────────────────
    -- Blocks scatter outward then get pulled back to aim point cyclically.
    -- Runs for 10 seconds then auto-stops.
    local blueThread = nil
    local function fireMaxBlue()
        local now = tick()
        if now - gojoLastFire.blue < BLUE_CD and gojoState == "blue_hold" then
            -- already running, stop it
            gojoState = "idle"; restoreAllColors(); blueThread = nil; return
        end
        if gojoState ~= "idle" then return end
        gojoLastFire.blue = now
        gojoState = "blue_hold"
        colorAllControlled(Color3.fromRGB(20,100,255), Enum.Material.Neon)

        local th = {}; blueThread = th
        task.spawn(function()
            local elapsed   = 0
            local DURATION  = 10
            local CYCLE     = 1.4  -- scatter/pull cycle length in seconds
            while gojoState == "blue_hold" and elapsed < DURATION do
                local dt = task.wait()
                if blueThread ~= th then return end  -- superseded
                elapsed = elapsed + dt

                local char = player.Character
                local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
                if not root then break end

                local _, aimDir = getAimPoint(1)
                local aimPt = root.Position + aimDir * 20

                local cycleT = (elapsed % CYCLE) / CYCLE  -- 0→1 per cycle
                -- First half: scatter outward in a sphere around aim point
                -- Second half: pull tight to aim point
                local pullFactor = cycleT < 0.5 and (cycleT * 2) or (1 - (cycleT-0.5)*2)
                -- pullFactor: 0=tight cluster at aim, 1=scattered sphere

                local allParts = {}
                for part,_ in pairs(controlled) do if part and part.Parent then table.insert(allParts,part) end end
                local n = #allParts
                for i, part in ipairs(allParts) do
                    local data = controlled[part]
                    if data and data.bp and data.bp.Parent then
                        -- Scattered position on sphere surface
                        local phi = (1+math.sqrt(5))/2
                        local i2  = i-1; local s = math.max(n,1)
                        local theta2 = math.acos(math.clamp(1-2*(i2+0.5)/s,-1,1))
                        local ang2   = 2*math.pi*i2/phi
                        local scatterR = 12 + math.sin(elapsed*2+i*0.3)*3
                        local scatterPos = aimPt + Vector3.new(
                            scatterR*math.sin(theta2)*math.cos(ang2),
                            scatterR*math.sin(theta2)*math.sin(ang2),
                            scatterR*math.cos(theta2))
                        -- Cluster at aim point
                        local clusterPos = aimPt + Vector3.new(
                            (math.random()-0.5)*2, (math.random()-0.5)*2, (math.random()-0.5)*2)
                        -- Lerp between cluster and scattered based on cycle
                        local targetPos = clusterPos:Lerp(scatterPos, pullFactor)
                        data.bp.P = 60000; data.bp.D = 1800
                        data.bp.Position = targetPos
                        -- Pulse color between cyan and white-blue
                        pcall(function()
                            local p = (math.sin(elapsed*4+i*0.4)+1)/2
                            part.Color = Color3.new(p*0.05, 0.4+p*0.4, 1)
                        end)
                    end
                end
            end
            -- Auto-stop after duration or if state changed
            if gojoState == "blue_hold" then
                safeResetGojo()
            end
            blueThread = nil
        end)
    end

    local function stopMaxBlue()
        if gojoState == "blue_hold" then
            safeResetGojo()
        end
    end

    -- ── Reversal Red ─────────────────────────────────────────
    -- Blocks are sucked from wherever they are to a point directly in front
    -- of the player. On fire they launch forward and fling anyone they hit.
    local function fireReversalRed()
        local now = tick()
        if now - gojoLastFire.red < RED_CD then return end
        if gojoState ~= "idle" then return end
        gojoLastFire.red  = now
        gojoState         = "red_charge"

        local char = player.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local playerPos = root and root.Position or Vector3.new(0,5,0)
        local _, aimDir = getAimPoint(1)
        local suckPt    = playerPos + aimDir * 4  -- right in front of player

        -- Pick parts for this technique (up to RED_PART_COUNT)
        local redParts = {}
        for part,_ in pairs(controlled) do
            if part and part.Parent then
                table.insert(redParts, part)
                if #redParts >= RED_PART_COUNT then break end
            end
        end

        colorParts(redParts, Color3.fromRGB(255,50,0), Enum.Material.Neon)

        -- Suck animation: parts spiral in from their current positions toward suckPt
        task.spawn(function()
            local elapsed = 0
            local CHARGE  = 1.2  -- seconds to charge
            while elapsed < CHARGE and gojoState == "red_charge" do
                local dt = task.wait()
                elapsed  = elapsed + dt
                local progress = elapsed / CHARGE  -- 0→1

                local char2 = player.Character
                local root2 = char2 and (char2:FindFirstChild("HumanoidRootPart") or char2:FindFirstChild("Torso"))
                if not root2 then break end
                local _, ad = getAimPoint(1)
                suckPt = root2.Position + ad * 4  -- track player movement

                for i, part in ipairs(redParts) do
                    local data = controlled[part]
                    if data and data.bp and data.bp.Parent then
                        -- Spiral: orbiting radius shrinks toward zero as progress→1
                        local spiralR = (1-progress)*8
                        local spiralAng = progress*math.pi*6 + i*(math.pi*2/#redParts)
                        local offset = Vector3.new(
                            math.cos(spiralAng)*spiralR,
                            math.sin(spiralAng + i)*spiralR*0.5,
                            math.sin(spiralAng)*spiralR)
                        data.bp.P = 70000 + progress*30000
                        data.bp.D = 1500
                        data.bp.Position = suckPt + offset
                        -- Glow brighter as we charge
                        pcall(function()
                            local p = progress
                            part.Color = Color3.new(1, 0.2-p*0.15, 0)
                        end)
                    end
                end
            end

            if gojoState ~= "red_charge" then return end
            gojoState = "red_fire"

            -- FIRE: strip BP/BG and blast everything forward
            local char2 = player.Character
            local root2 = char2 and (char2:FindFirstChild("HumanoidRootPart") or char2:FindFirstChild("Torso"))
            local _, fireDir = getAimPoint(1)
            if root2 then fireDir = root2.CFrame.LookVector end

            for _, part in ipairs(redParts) do
                if part and part.Parent then
                    addFlingOnTouch(part, fireDir * 220)
                    firePartVelocity(part, fireDir * 920)
                end
            end

            task.wait(0.4)
            if gojoActive then safeResetGojo() end
        end)
    end

    -- ── Hollow Purple ────────────────────────────────────────
    -- Phase 1 (1s): blue group left, red group right.
    -- Phase 2 (0.8s): both converge to aim point (purple).
    -- Phase 3: LAUNCH with massive velocity.
    -- While flying, creates a black-hole-style pull on nearby loose blocks.
    local function fireHollowPurple()
        local now = tick()
        if now - gojoLastFire.purple < PURPLE_CD then return end
        if gojoState ~= "idle" then return end
        gojoLastFire.purple = now
        gojoState           = "purple_split"

        local char = player.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if not root then gojoState="idle"; return end

        local _, aimDir  = getAimPoint(1)
        local aimDir2    = root.CFrame.LookVector  -- lock at cast time
        local aimPt      = root.Position + aimDir2 * 30
        local perpR      = root.CFrame.RightVector

        local allParts = {}
        for part,_ in pairs(controlled) do if part and part.Parent then table.insert(allParts,part) end end
        local half     = math.ceil(#allParts/2)

        local blueGroup={}; local redGroup={}
        for i,part in ipairs(allParts) do
            if i<=half then table.insert(blueGroup,part) else table.insert(redGroup,part) end
        end

        colorParts(blueGroup, Color3.fromRGB(20,80,255),  Enum.Material.Neon)
        colorParts(redGroup,  Color3.fromRGB(255,40,0),   Enum.Material.Neon)

        -- Phase 1: spread 14 studs apart
        local leftPt  = root.Position + aimDir2*18 - perpR*14
        local rightPt = root.Position + aimDir2*18 + perpR*14

        local function setGroupPositions(group, center)
            for i,part in ipairs(group) do
                local data = controlled[part]
                if data and data.bp and data.bp.Parent then
                    local off = Vector3.new((i%3-1)*2, (math.floor(i/3)%3-1)*2, (i%2)*1.5)
                    data.bp.P = 60000; data.bp.D = 2000
                    data.bp.Position = center + off
                end
            end
        end

        setGroupPositions(blueGroup, leftPt)
        setGroupPositions(redGroup,  rightPt)

        task.spawn(function()
            -- Phase 1: hold split position for 1 second
            local elapsed = 0
            while elapsed < 1.0 and gojoState == "purple_split" do
                local dt = task.wait(); elapsed = elapsed + dt
                -- Animate slight orbit during split
                local t2 = elapsed * 3
                for i, part in ipairs(blueGroup) do
                    local data = controlled[part]
                    if data and data.bp and data.bp.Parent then
                        local off = Vector3.new(math.cos(t2+i)*1.5, math.sin(t2+i)*1.5, 0)
                        data.bp.Position = leftPt + off
                    end
                end
                for i, part in ipairs(redGroup) do
                    local data = controlled[part]
                    if data and data.bp and data.bp.Parent then
                        local off = Vector3.new(math.cos(t2+i)*1.5, math.sin(t2+i)*1.5, 0)
                        data.bp.Position = rightPt + off
                    end
                end
            end
            if gojoState ~= "purple_split" then return end
            gojoState = "purple_fire"

            -- Phase 2: converge to aim point with growing purple glow
            colorParts(allParts, Color3.fromRGB(160,0,255), Enum.Material.Neon)
            elapsed = 0
            while elapsed < 0.8 and gojoState == "purple_fire" do
                local dt = task.wait(); elapsed = elapsed + dt
                local progress = elapsed / 0.8
                for i, part in ipairs(allParts) do
                    local data = controlled[part]
                    if data and data.bp and data.bp.Parent then
                        local off = Vector3.new(
                            (math.random()-0.5)*(1-progress)*4,
                            (math.random()-0.5)*(1-progress)*4,
                            (math.random()-0.5)*(1-progress)*4)
                        data.bp.P = 80000 + progress*40000
                        data.bp.D = 1000
                        data.bp.Position = aimPt + off*(1-progress)
                        pcall(function()
                            local p = progress
                            part.Color = Color3.new(0.3+p*0.4, 0, 0.8+p*0.2)
                        end)
                    end
                end
            end
            if gojoState ~= "purple_fire" then return end

            -- Phase 3: FIRE + black hole pull
            for _, part in ipairs(allParts) do
                if part and part.Parent then
                    addFlingOnTouch(part, aimDir2 * 300)
                    firePartVelocity(part, aimDir2 * 1600)
                end
            end

            -- Black hole effect: for 3 seconds, any remaining controlled blocks
            -- get sucked toward the projectile cluster's leading point
            task.spawn(function()
                local bhElapsed = 0
                while bhElapsed < 3.0 and gojoActive do
                    local dt2 = task.wait(); bhElapsed = bhElapsed + dt2
                    -- Estimate projectile position along aim dir
                    local bhCenter = aimPt + aimDir2 * (bhElapsed * 1600 * 0.25)  -- rough tracking
                    for part, data in pairs(controlled) do
                        if part and part.Parent and data.bp and data.bp.Parent then
                            -- Pull all loose blocks toward the black hole
                            local toCenter = bhCenter - part.Position
                            local dist2    = math.max(toCenter.Magnitude, 1)
                            local pull     = math.clamp(300/dist2, 0, 80)
                            data.bp.P = 90000; data.bp.D = 500
                            data.bp.Position = part.Position + toCenter.Unit * pull * dt2 * 20
                            pcall(function() part.Color = Color3.fromRGB(80,0,140) end)
                        end
                    end
                end
                if gojoActive then
                    gojoState = "idle"
                    restoreAllColors()
                end
            end)

            -- Main task ends here; black hole runs in its own thread
            task.wait(3.2)
            if gojoActive then safeResetGojo() end
        end)
    end

    -- ── DE Infinity ───────────────────────────────────────────
    local function activateDeInfinity(rootPos)
        gojoState = "de_infinity"
        gojoInfinityAngle = 0
        colorAllControlled(Color3.fromRGB(240,240,255), Enum.Material.Neon)
        for part,_ in pairs(controlled) do pcall(function() part.CanCollide=false end) end
    end

    local function deactivateDeInfinity()
        safeResetGojo()
        for part,_ in pairs(controlled) do pcall(function() part.CanCollide=false end) end
    end

    local function detectAllPartsForGojo()
        fullSweep()
    end

    local function updateGojo(dt, rootPos)
        if not gojoActive then return end
        gojoOrbitAngle=gojoOrbitAngle+dt

        if gojoState=="blue_hold" then
            -- Animation handled inside fireMaxBlue task.spawn loop.
            -- updateGojo just needs to keep the state alive; nothing to do here.

        elseif gojoState=="de_infinity" then
            -- Large sphere of blocks orbiting the player slowly.
            local allParts={}
            for part,_ in pairs(controlled) do if part and part.Parent then table.insert(allParts,part) end end
            local n=#allParts; local t2=tick()
            for i,part in ipairs(allParts) do
                local data=controlled[part]
                if data and data.bp and data.bp.Parent then
                    local phi=(1+math.sqrt(5))/2
                    local idx=i-1; local s=math.max(n,1)
                    local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1))
                    local ang=2*math.pi*idx/phi + t2*0.25  -- slow rotation
                    local r=gojoInfinityRadius*(0.95+math.sin(t2*0.7+i*0.2)*0.05)
                    data.bp.P=60000; data.bp.D=3000
                    data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=Vector3.new(
                        rootPos.X + r*math.sin(theta)*math.cos(ang),
                        rootPos.Y + r*math.sin(theta)*math.sin(ang),
                        rootPos.Z + r*math.cos(theta))
                    if data.bg and data.bg.Parent then
                        data.bg.CFrame=CFrame.new(data.bp.Position,rootPos)*CFrame.Angles(0,math.pi,0)
                    end
                    -- Gentle white-blue pulse
                    pcall(function()
                        local pulse=(math.sin(t2*1.5+i*0.3)+1)/2
                        part.Color=Color3.new(0.88+pulse*0.12, 0.88+pulse*0.10, 1)
                        part.Material=Enum.Material.Neon
                    end)
                end
            end
        end
    end

    -- ── Safe state reset: always callable, clears stuck states ──
    local function safeResetGojo()
        gojoState  = "idle"
        blueThread = nil
        restoreAllColors()
        for part,_ in pairs(controlled) do pcall(function()part.CanCollide=false end) end
    end

    destroyGojo=function()
        safeResetGojo()
        gojoActive=false
    end

    -- ════════════════════════════════════════════════════════════
    -- SUB-GUIS
    -- ════════════════════════════════════════════════════════════

    local function destroyGasterGui() if gasterSubGui and gasterSubGui.Parent then gasterSubGui:Destroy()end;gasterSubGui=nil end
    local function createGasterGui()
        destroyGasterGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="GasterSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;sg.Parent=pg;gasterSubGui=sg
        local W,H=195,180;local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(W,H);panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-100);panel.BackgroundColor3=Color3.fromRGB(6,6,18);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,7);local ps=Instance.new("UIStroke",panel);ps.Color=Color3.fromRGB(180,60,255);ps.Thickness=1.2
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(20,8,45);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,7)
        Instance.new("TextLabel",tBar).Text="GASTER FORM" -- simplified
        local tLbl=tBar:FindFirstChildOfClass("TextLabel");tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(6,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(200,120,255);tLbl.TextSize=11;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local animLbl=Instance.new("TextLabel",panel);animLbl.Text="FORM: "..gasterAnim:upper();animLbl.Size=UDim2.new(1,-10,0,14);animLbl.Position=UDim2.fromOffset(6,31);animLbl.BackgroundTransparency=1;animLbl.TextColor3=Color3.fromRGB(130,130,255);animLbl.TextSize=9;animLbl.Font=Enum.Font.GothamBold;animLbl.TextXAlignment=Enum.TextXAlignment.Left
        for idx,anim in ipairs({{txt="POINTING",key="pointing",col=Color3.fromRGB(100,200,255)},{txt="WAVING",key="waving",col=Color3.fromRGB(100,255,160)},{txt="PUNCHING",key="punching",col=Color3.fromRGB(255,120,120)}})do
            local btn=Instance.new("TextButton",panel);btn.Text=anim.txt;btn.Size=UDim2.new(1,-12,0,30);btn.Position=UDim2.fromOffset(6,48+(idx-1)*36);btn.BackgroundColor3=Color3.fromRGB(22,10,48);btn.TextColor3=anim.col;btn.TextSize=11;btn.Font=Enum.Font.GothamBold;btn.BorderSizePixel=0;Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()gasterAnim=anim.key;gasterT=0;animLbl.Text="FORM: "..anim.key:upper()end)
        end
        makeDraggable(tBar,panel,false)
    end

    local function destroySphereGui() if sphereSubGui and sphereSubGui.Parent then sphereSubGui:Destroy()end;sphereSubGui=nil end
    local function createSphereGui()
        destroySphereGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="SphereSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;sg.Parent=pg;sphereSubGui=sg
        local W,H=195,172;local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(W,H);panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-100);panel.BackgroundColor3=Color3.fromRGB(4,12,20);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,7);local ps=Instance.new("UIStroke",panel);ps.Color=Color3.fromRGB(60,180,255);ps.Thickness=1.2
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(8,20,45);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,7)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="SPHERE CONTROL";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(6,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(80,200,255);tLbl.TextSize=11;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local mLbl=Instance.new("TextLabel",panel);mLbl.Text="STATE: "..sphereMode:upper();mLbl.Size=UDim2.new(1,-10,0,14);mLbl.Position=UDim2.fromOffset(6,31);mLbl.BackgroundTransparency=1;mLbl.TextColor3=Color3.fromRGB(80,180,255);mLbl.TextSize=9;mLbl.Font=Enum.Font.GothamBold;mLbl.TextXAlignment=Enum.TextXAlignment.Left
        for idx,sb in ipairs({{txt="ORBIT",key="orbit",col=Color3.fromRGB(80,220,255)},{txt="FOLLOW",key="follow",col=Color3.fromRGB(120,255,160)},{txt="STAY",key="stay",col=Color3.fromRGB(255,200,80)}})do
            local btn=Instance.new("TextButton",panel);btn.Text=sb.txt;btn.Size=UDim2.new(1,-12,0,30);btn.Position=UDim2.fromOffset(6,48+(idx-1)*36);btn.BackgroundColor3=Color3.fromRGB(8,22,44);btn.TextColor3=sb.col;btn.TextSize=11;btn.Font=Enum.Font.GothamBold;btn.BorderSizePixel=0;Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()sphereMode=sb.key;sphereVel=Vector3.zero;mLbl.Text="STATE: "..sb.key:upper()end)
        end
        makeDraggable(tBar,panel,false)
    end

    local function destroySphereBenderGui() if sbSubGui and sbSubGui.Parent then sbSubGui:Destroy()end;sbSubGui=nil end
    rebuildSBGui=function()
        destroySphereBenderGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="SphereBenderGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1001;sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;sg.Parent=pg;sbSubGui=sg
        local W=205;local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(W,300);panel.Position=UDim2.new(0.5,-W-10,0.5,-150);panel.BackgroundColor3=Color3.fromRGB(5,8,20);panel.BorderSizePixel=0;panel.ClipsDescendants=false;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local stk=Instance.new("UIStroke",panel);stk.Color=Color3.fromRGB(0,200,255);stk.Thickness=1.4
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(4,18,40);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="SPHERE BENDER";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(0,220,255);tLbl.TextSize=12;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local yOff=32
        local function getSelMode()for _,sp in ipairs(sbSpheres)do if sp.selected then return sp.mode end end;return "orbit"end
        local mLbl=Instance.new("TextLabel",panel);mLbl.Text="STATE: "..getSelMode():upper();mLbl.Size=UDim2.new(1,-10,0,16);mLbl.Position=UDim2.fromOffset(6,yOff);mLbl.BackgroundTransparency=1;mLbl.TextColor3=Color3.fromRGB(0,180,255);mLbl.TextSize=9;mLbl.Font=Enum.Font.GothamBold;mLbl.TextXAlignment=Enum.TextXAlignment.Left;yOff=yOff+18
        for _,mb in ipairs({{txt="ORBIT",key="orbit",col=Color3.fromRGB(80,220,255)},{txt="FOLLOW",key="follow",col=Color3.fromRGB(120,255,160)},{txt="STAY",key="stay",col=Color3.fromRGB(255,200,80)}})do
            local btn=Instance.new("TextButton",panel);btn.Text=mb.txt;btn.Size=UDim2.new(1,-12,0,28);btn.Position=UDim2.fromOffset(6,yOff);btn.BackgroundColor3=Color3.fromRGB(6,18,36);btn.TextColor3=mb.col;btn.TextSize=11;btn.Font=Enum.Font.GothamBold;btn.BorderSizePixel=0;Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()for _,sp in ipairs(sbSpheres)do if sp.selected then sp.mode=mb.key;sp.stopped=false;sp.vel=Vector3.zero end end;mLbl.Text="STATE: "..mb.key:upper()end);yOff=yOff+32
        end
        local div=Instance.new("Frame",panel);div.Size=UDim2.new(1,-12,0,1);div.Position=UDim2.fromOffset(6,yOff+2);div.BackgroundColor3=Color3.fromRGB(0,100,160);div.BorderSizePixel=0;yOff=yOff+10
        local function sBtn2(t2,x,w,yp,bg,fg)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.fromOffset(w,26);b.Position=UDim2.fromOffset(x,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=11;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b);return b end
        local stopBtn=sBtn2("STOP",6,(W-18)/2,yOff,Color3.fromRGB(60,8,8),Color3.fromRGB(255,60,60));local goBtn=sBtn2("GO",10+(W-18)/2,(W-18)/2,yOff,Color3.fromRGB(8,50,8),Color3.fromRGB(60,255,100));yOff=yOff+30
        stopBtn.MouseButton1Click:Connect(function()for _,sp in ipairs(sbSpheres)do if sp.selected then sp.stopped=true;sp.vel=Vector3.zero end end;mLbl.Text="STATE: STOPPED"end)
        goBtn.MouseButton1Click:Connect(function()for _,sp in ipairs(sbSpheres)do if sp.selected then sp.stopped=false;sp.vel=Vector3.zero end end;mLbl.Text="STATE: "..getSelMode():upper()end)
        local splitBtn=sBtn2("SPLIT SPHERE",6,W-12,yOff,Color3.fromRGB(10,30,55),Color3.fromRGB(0,200,255));yOff=yOff+30
        splitBtn.MouseButton1Click:Connect(function()
            local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local s=newSBSphere((root and root.Position or Vector3.new(0,5,0))+Vector3.new(math.random(-4,4),2,math.random(-4,4)));table.insert(sbSpheres,s);rebuildSBGui()
        end)
        local hdr=Instance.new("TextLabel",panel);hdr.Text="SPHERES";hdr.Size=UDim2.new(1,-10,0,16);hdr.Position=UDim2.fromOffset(6,yOff);hdr.BackgroundTransparency=1;hdr.TextColor3=Color3.fromRGB(0,160,220);hdr.TextSize=9;hdr.Font=Enum.Font.GothamBold;hdr.TextXAlignment=Enum.TextXAlignment.Left;yOff=yOff+18
        for idx,sp in ipairs(sbSpheres)do
            local sBtn=Instance.new("TextButton",panel);sBtn.Text="SPHERE "..idx..(sp.stopped and"  [STOP]"or"  ["..sp.mode:upper().."]");sBtn.Size=UDim2.new(1,-12,0,26);sBtn.Position=UDim2.fromOffset(6,yOff);sBtn.BackgroundColor3=sp.selected and Color3.fromRGB(0,60,120) or Color3.fromRGB(6,18,36);sBtn.TextColor3=sp.selected and Color3.fromRGB(80,200,255) or Color3.fromRGB(140,140,180);sBtn.TextSize=9;sBtn.Font=Enum.Font.GothamBold;sBtn.BorderSizePixel=0;Instance.new("UICorner",sBtn)
            local sBtkS=Instance.new("UIStroke",sBtn);sBtkS.Color=sp.selected and Color3.fromRGB(0,180,255) or Color3.fromRGB(30,60,100);sBtkS.Thickness=sp.selected and 1.5 or 0.8
            local cSp,cBtn,cStk=sp,sBtn,sBtkS
            sBtn.MouseButton1Click:Connect(function()cSp.selected=not cSp.selected;cBtn.BackgroundColor3=cSp.selected and Color3.fromRGB(0,60,120) or Color3.fromRGB(6,18,36);cBtn.TextColor3=cSp.selected and Color3.fromRGB(80,200,255) or Color3.fromRGB(140,140,180);cStk.Color=cSp.selected and Color3.fromRGB(0,180,255) or Color3.fromRGB(30,60,100);cStk.Thickness=cSp.selected and 1.5 or 0.8;mLbl.Text="STATE: "..getSelMode():upper()end)
            yOff=yOff+30
        end
        panel.Size=UDim2.fromOffset(W,yOff+8);makeDraggable(tBar,panel,false)
    end

    -- ── Tank GUI ──────────────────────────────────────────────
    destroyTankGui=function() if tankSubGui and tankSubGui.Parent then tankSubGui:Destroy()end;tankSubGui=nil end
    local function createTankGui()
        destroyTankGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="TankSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;sg.Parent=pg;tankSubGui=sg
        local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(185,280);panel.Position=UDim2.new(0,10,0.5,-140);panel.BackgroundColor3=Color3.fromRGB(18,18,18);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local stk=Instance.new("UIStroke",panel);stk.Color=Color3.fromRGB(90,90,90);stk.Thickness=1.5
        local titleBar=Instance.new("Frame");titleBar.Size=UDim2.new(1,0,0,28);titleBar.BackgroundColor3=Color3.fromRGB(30,30,30);titleBar.BorderSizePixel=0;titleBar.ZIndex=10;titleBar.Parent=panel;Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",titleBar);tLbl.Text="🪖 TANK";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(210,210,210);tLbl.TextSize=12;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local sLbl=Instance.new("TextLabel",panel);sLbl.Text="INSIDE  |  READY";sLbl.Size=UDim2.new(1,-10,0,16);sLbl.Position=UDim2.fromOffset(6,30);sLbl.BackgroundTransparency=1;sLbl.TextColor3=Color3.fromRGB(130,200,130);sLbl.TextSize=9;sLbl.Font=Enum.Font.GothamBold;sLbl.TextXAlignment=Enum.TextXAlignment.Left
        local dLbl=Instance.new("TextLabel",panel);dLbl.Text="MOVEMENT";dLbl.Size=UDim2.new(1,-10,0,12);dLbl.Position=UDim2.fromOffset(6,49);dLbl.BackgroundTransparency=1;dLbl.TextColor3=Color3.fromRGB(100,100,150);dLbl.TextSize=8;dLbl.Font=Enum.Font.GothamBold;dLbl.TextXAlignment=Enum.TextXAlignment.Left
        local cx=(185-36)/2;local dy0=63;local bs=36;local gap=2
        local function dpBtn(t2,xp,yp)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.fromOffset(bs,bs);b.Position=UDim2.fromOffset(xp,yp);b.BackgroundColor3=Color3.fromRGB(40,40,55);b.TextColor3=Color3.fromRGB(200,200,255);b.TextSize=16;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b).CornerRadius=UDim.new(0,6);Instance.new("UIStroke",b).Color=Color3.fromRGB(80,80,130);return b end
        local upBtn=dpBtn("▲",cx,dy0);local leftBtn=dpBtn("◀",cx-bs-gap,dy0+bs+gap);local rightBtn=dpBtn("▶",cx+bs+gap,dy0+bs+gap);local downBtn=dpBtn("▼",cx,dy0+bs*2+gap*2)
        local function setP(btn,on)btn.BackgroundColor3=on and Color3.fromRGB(60,60,100) or Color3.fromRGB(40,40,55)end
        upBtn.MouseButton1Down:Connect(function()tks.forward=1;setP(upBtn,true)end);upBtn.MouseButton1Up:Connect(function()tks.forward=0;setP(upBtn,false)end)
        downBtn.MouseButton1Down:Connect(function()tks.forward=-1;setP(downBtn,true)end);downBtn.MouseButton1Up:Connect(function()tks.forward=0;setP(downBtn,false)end)
        leftBtn.MouseButton1Down:Connect(function()tks.turn=-1;setP(leftBtn,true)end);leftBtn.MouseButton1Up:Connect(function()tks.turn=0;setP(leftBtn,false)end)
        rightBtn.MouseButton1Down:Connect(function()tks.turn=1;setP(rightBtn,true)end);rightBtn.MouseButton1Up:Connect(function()tks.turn=0;setP(rightBtn,false)end)
        local ay=dy0+bs*3+gap*2+10
        local function aBtn(t2,yp,bg,fg)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.new(1,-12,0,28);b.Position=UDim2.fromOffset(6,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=11;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b);return b end
        local fireBtn=aBtn("🔥 FIRE",ay,Color3.fromRGB(65,35,12),Color3.fromRGB(255,200,80))
        local hatchBtn=aBtn("🚪 OPEN HATCH",ay+32,Color3.fromRGB(30,45,60),Color3.fromRGB(120,200,255))
        local destructBtn=aBtn("💥 DESTRUCT",ay+64,Color3.fromRGB(75,12,12),Color3.fromRGB(255,80,80))
        fireBtn.MouseButton1Click:Connect(function()shootProjectile();sLbl.Text="FIRING!";sLbl.TextColor3=Color3.fromRGB(255,200,80);task.wait(0.4);if sLbl.Parent then sLbl.Text="INSIDE  |  READY";sLbl.TextColor3=Color3.fromRGB(130,200,130)end end)
        hatchBtn.MouseButton1Click:Connect(function()toggleHatch();if tks.hatchOpen then hatchBtn.Text="🚪 CLOSE HATCH";sLbl.Text="OUTSIDE  |  FREE";sLbl.TextColor3=Color3.fromRGB(200,200,100) else hatchBtn.Text="🚪 OPEN HATCH";sLbl.Text="INSIDE  |  READY";sLbl.TextColor3=Color3.fromRGB(130,200,130)end end)
        destructBtn.MouseButton1Click:Connect(function()task.spawn(function()destroyTank();destroyTankGui()end)end)
        local jR=rightJoy.radius
        local jBase=Instance.new("Frame",sg);jBase.Size=UDim2.fromOffset(jR*2,jR*2);jBase.Position=UDim2.new(1,-(jR*2+18),0.36,-jR);jBase.BackgroundColor3=Color3.fromRGB(50,50,80);jBase.BackgroundTransparency=0.35;jBase.BorderSizePixel=0;Instance.new("UICorner",jBase).CornerRadius=UDim.new(1,0);local jStk=Instance.new("UIStroke",jBase);jStk.Color=Color3.fromRGB(100,120,200);jStk.Thickness=1.5
        local jAimLbl=Instance.new("TextLabel",jBase);jAimLbl.Text="AIM";jAimLbl.Size=UDim2.new(1,0,0,14);jAimLbl.Position=UDim2.new(0,0,0,4);jAimLbl.BackgroundTransparency=1;jAimLbl.TextColor3=Color3.fromRGB(180,180,255);jAimLbl.TextSize=8;jAimLbl.Font=Enum.Font.GothamBold;jAimLbl.ZIndex=5
        local jThumb=Instance.new("Frame",jBase);jThumb.Size=UDim2.fromOffset(28,28);jThumb.Position=UDim2.new(0.5,-14,0.5,-14);jThumb.BackgroundColor3=Color3.fromRGB(140,150,230);jThumb.BackgroundTransparency=0.2;jThumb.BorderSizePixel=0;Instance.new("UICorner",jThumb).CornerRadius=UDim.new(1,0)
        local function updAimThumb()if rightJoy.active then local off=rightJoy.current-rightJoy.origin;local dist=math.min(off.Magnitude,jR);local dir=off.Magnitude>0 and off.Unit or Vector2.zero;jThumb.Position=UDim2.new(0.5,dir.X*dist-14,0.5,dir.Y*dist-14)else jThumb.Position=UDim2.new(0.5,-14,0.5,-14)end end
        local conKBB=UserInputService.InputBegan:Connect(function(inp,proc)if proc then return end;if inp.KeyCode==Enum.KeyCode.W then tks.forward=1 elseif inp.KeyCode==Enum.KeyCode.S then tks.forward=-1 elseif inp.KeyCode==Enum.KeyCode.A then tks.turn=-1 elseif inp.KeyCode==Enum.KeyCode.D then tks.turn=1 elseif inp.KeyCode==Enum.KeyCode.F then if tks.insideTank then shootProjectile()end elseif inp.KeyCode==Enum.KeyCode.H then toggleHatch()end end)
        local conKBE=UserInputService.InputEnded:Connect(function(inp,_)if inp.KeyCode==Enum.KeyCode.W or inp.KeyCode==Enum.KeyCode.S then tks.forward=0 elseif inp.KeyCode==Enum.KeyCode.A or inp.KeyCode==Enum.KeyCode.D then tks.turn=0 end end)
        local conTS=UserInputService.TouchStarted:Connect(function(touch,proc)if proc then return end;local pos=Vector2.new(touch.Position.X,touch.Position.Y);local center=Vector2.new(jBase.AbsolutePosition.X+jBase.AbsoluteSize.X/2,jBase.AbsolutePosition.Y+jBase.AbsoluteSize.Y/2);if(pos-center).Magnitude<jR*1.6 then rightJoy.active=true;rightJoy.origin=pos;rightJoy.current=pos;rightJoy.touchId=touch end end)
        local conTM=UserInputService.TouchMoved:Connect(function(touch,_)if not rightJoy.active or rightJoy.touchId~=touch then return end;local pos=Vector2.new(touch.Position.X,touch.Position.Y);rightJoy.current=pos;local off=pos-rightJoy.origin;local dist=math.min(off.Magnitude,jR);if dist>rightJoy.deadzone then local dir=off.Unit;cameraOrbitAngle=cameraOrbitAngle+dir.X*CAM_ORBIT_SENS*0.018;cameraPitchAngle=math.clamp(cameraPitchAngle+dir.Y*CAM_PITCH_SENS*0.014,CAM_PITCH_MIN,CAM_PITCH_MAX)end;updAimThumb()end)
        local conTE=UserInputService.TouchEnded:Connect(function(touch,_)if rightJoy.touchId==touch then rightJoy.active=false;rightJoy.touchId=nil;updAimThumb()end end)
        sg.AncestryChanged:Connect(function(_,par)if not par then pcall(function()conKBB:Disconnect()end);pcall(function()conKBE:Disconnect()end);pcall(function()conTS:Disconnect()end);pcall(function()conTM:Disconnect()end);pcall(function()conTE:Disconnect()end);tks.forward=0;tks.turn=0;rightJoy.active=false end end)
        makeDraggable(titleBar,panel,false)
    end

    -- ── Car GUI (FIXED JOYSTICK: frame InputBegan, not UserInputService) ──
    destroyCarGui=function() if carSubGui and carSubGui.Parent then carSubGui:Destroy()end;carSubGui=nil end
    local function createCarGui()
        destroyCarGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="CarSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;sg.Parent=pg;carSubGui=sg
        local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(165,130);panel.Position=UDim2.new(0,10,0.5,-65);panel.BackgroundColor3=Color3.fromRGB(14,18,14);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local stk=Instance.new("UIStroke",panel);stk.Color=Color3.fromRGB(60,160,60);stk.Thickness=1.5
        local titleBar=Instance.new("Frame");titleBar.Size=UDim2.new(1,0,0,28);titleBar.BackgroundColor3=Color3.fromRGB(20,35,20);titleBar.BorderSizePixel=0;titleBar.ZIndex=10;titleBar.Parent=panel;Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",titleBar);tLbl.Text="🚗 CAR";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(120,220,120);tLbl.TextSize=12;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local sLbl=Instance.new("TextLabel",panel);sLbl.Text="PARKED  |  OPEN DOOR";sLbl.Size=UDim2.new(1,-10,0,16);sLbl.Position=UDim2.fromOffset(6,30);sLbl.BackgroundTransparency=1;sLbl.TextColor3=Color3.fromRGB(180,180,100);sLbl.TextSize=9;sLbl.Font=Enum.Font.GothamBold;sLbl.TextXAlignment=Enum.TextXAlignment.Left
        local function aBtn2(t2,yp,bg,fg)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.new(1,-12,0,30);b.Position=UDim2.fromOffset(6,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=11;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b);return b end
        local doorBtn=aBtn2("🚪 OPEN DOOR",50,Color3.fromRGB(25,45,25),Color3.fromRGB(80,240,80))
        local destBtn=aBtn2("🔧 DESTROY",86,Color3.fromRGB(70,10,10),Color3.fromRGB(255,70,70))
        doorBtn.MouseButton1Click:Connect(function()toggleCarDoor();if cs.doorOpen then doorBtn.Text="🚪 CLOSE DOOR";sLbl.Text="DRIVING  |  INSIDE";sLbl.TextColor3=Color3.fromRGB(100,230,100) else doorBtn.Text="🚪 OPEN DOOR";sLbl.Text="PARKED  |  OPEN DOOR";sLbl.TextColor3=Color3.fromRGB(180,180,100)end end)
        destBtn.MouseButton1Click:Connect(function()task.spawn(function()destroyCar();destroyCarGui()end)end)

        -- Drive joystick (left side, large)
        local jR2=carJoy.radius
        local jBase2=Instance.new("Frame",sg)
        jBase2.Name="CarJoyBase"
        jBase2.Size=UDim2.fromOffset(jR2*2,jR2*2)
        jBase2.Position=UDim2.new(0,18,0.62,-jR2)
        jBase2.BackgroundColor3=Color3.fromRGB(30,60,30)
        jBase2.BackgroundTransparency=0.3
        jBase2.BorderSizePixel=0
        -- IMPORTANT: Active=false so GuiObject does NOT consume touch events
        -- This prevents the touch from being flagged as "processed=true" in
        -- UserInputService.TouchStarted, which was silently blocking the joystick.
        jBase2.Active=false
        Instance.new("UICorner",jBase2).CornerRadius=UDim.new(1,0)
        local jStk2=Instance.new("UIStroke",jBase2);jStk2.Color=Color3.fromRGB(60,180,60);jStk2.Thickness=2
        local jDLbl=Instance.new("TextLabel",jBase2);jDLbl.Text="DRIVE";jDLbl.Size=UDim2.new(1,0,0,16);jDLbl.Position=UDim2.new(0,0,0,4);jDLbl.BackgroundTransparency=1;jDLbl.TextColor3=Color3.fromRGB(100,220,100);jDLbl.TextSize=9;jDLbl.Font=Enum.Font.GothamBold;jDLbl.ZIndex=5
        local jThumb2=Instance.new("Frame",jBase2);jThumb2.Size=UDim2.fromOffset(36,36);jThumb2.Position=UDim2.new(0.5,-18,0.5,-18);jThumb2.BackgroundColor3=Color3.fromRGB(80,200,80);jThumb2.BackgroundTransparency=0.2;jThumb2.BorderSizePixel=0;Instance.new("UICorner",jThumb2).CornerRadius=UDim.new(1,0)

        local function updCarJoy()
            if carJoy.active then
                local off=carJoy.current-carJoy.origin;local dist=math.min(off.Magnitude,jR2);local dir=off.Magnitude>0 and off.Unit or Vector2.zero
                jThumb2.Position=UDim2.new(0.5,dir.X*dist-18,0.5,dir.Y*dist-18)
            else jThumb2.Position=UDim2.new(0.5,-18,0.5,-18) end
        end

        -- ▶ KEY FIX: Use jBase2.InputBegan (frame's OWN input event) instead of
        --   UserInputService.TouchStarted. Frame InputBegan fires regardless of
        --   the "processed" flag, so the touch ALWAYS registers.
        jBase2.InputBegan:Connect(function(inp)
            if inp.UserInputType~=Enum.UserInputType.Touch then return end
            if not cs.doorOpen then return end
            local pos=Vector2.new(inp.Position.X,inp.Position.Y)
            carJoy.active=true; carJoy.origin=pos; carJoy.current=pos; carJoy.touchId=inp
        end)

        -- TouchMoved/Ended still use UserInputService (they fire on the touch ID regardless)
        local conCTM=UserInputService.TouchMoved:Connect(function(touch,_)
            if not carJoy.active or carJoy.touchId~=touch then return end
            local pos=Vector2.new(touch.Position.X,touch.Position.Y); carJoy.current=pos
            local off=pos-carJoy.origin; local dist=math.min(off.Magnitude,jR2)
            if dist>carJoy.deadzone then local dir=off.Unit;carJoy.forward=-dir.Y;carJoy.turn=dir.X else carJoy.forward=0;carJoy.turn=0 end
            updCarJoy()
        end)
        local conCTE=UserInputService.TouchEnded:Connect(function(touch,_)
            if carJoy.touchId==touch then carJoy.active=false;carJoy.touchId=nil;carJoy.forward=0;carJoy.turn=0;updCarJoy() end
        end)
        -- KB
        local conCKBB=UserInputService.InputBegan:Connect(function(inp,proc)if proc or not cs.doorOpen then return end;if inp.KeyCode==Enum.KeyCode.W then carJoy.forward=1 elseif inp.KeyCode==Enum.KeyCode.S then carJoy.forward=-1 elseif inp.KeyCode==Enum.KeyCode.A then carJoy.turn=-1 elseif inp.KeyCode==Enum.KeyCode.D then carJoy.turn=1 end end)
        local conCKBE=UserInputService.InputEnded:Connect(function(inp,_)if inp.KeyCode==Enum.KeyCode.W or inp.KeyCode==Enum.KeyCode.S then carJoy.forward=0 elseif inp.KeyCode==Enum.KeyCode.A or inp.KeyCode==Enum.KeyCode.D then carJoy.turn=0 end end)
        sg.AncestryChanged:Connect(function(_,par)if not par then pcall(function()conCTM:Disconnect()end);pcall(function()conCTE:Disconnect()end);pcall(function()conCKBB:Disconnect()end);pcall(function()conCKBE:Disconnect()end);carJoy.forward=0;carJoy.turn=0;carJoy.active=false end end)
        makeDraggable(titleBar,panel,false)
    end

    -- ── DE Shrine GUI ─────────────────────────────────────────
    destroyShrineGui=function() if shrineSubGui and shrineSubGui.Parent then shrineSubGui:Destroy()end;shrineSubGui=nil end
    local function createShrineGui()
        destroyShrineGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="ShrineSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;sg.Parent=pg;shrineSubGui=sg
        local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(175,150);panel.Position=UDim2.new(0,10,0.5,-75);panel.BackgroundColor3=Color3.fromRGB(12,4,4);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local stk=Instance.new("UIStroke",panel);stk.Color=Color3.fromRGB(180,20,20);stk.Thickness=1.5
        local titleBar=Instance.new("Frame");titleBar.Size=UDim2.new(1,0,0,28);titleBar.BackgroundColor3=Color3.fromRGB(40,8,8);titleBar.BorderSizePixel=0;titleBar.ZIndex=10;titleBar.Parent=panel;Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",titleBar);tLbl.Text="⛩ DE SHRINE";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(255,80,50);tLbl.TextSize=12;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local sLbl=Instance.new("TextLabel",panel);sLbl.Text="BLOCKS UNDERGROUND";sLbl.Size=UDim2.new(1,-10,0,16);sLbl.Position=UDim2.fromOffset(6,31);sLbl.BackgroundTransparency=1;sLbl.TextColor3=Color3.fromRGB(130,130,130);sLbl.TextSize=9;sLbl.Font=Enum.Font.GothamBold;sLbl.TextXAlignment=Enum.TextXAlignment.Left
        local pLbl=Instance.new("TextLabel",panel);pLbl.Text="PARTS: "..partCount;pLbl.Size=UDim2.new(1,-10,0,14);pLbl.Position=UDim2.fromOffset(6,49);pLbl.BackgroundTransparency=1;pLbl.TextColor3=Color3.fromRGB(100,100,160);pLbl.TextSize=9;pLbl.Font=Enum.Font.Gotham;pLbl.TextXAlignment=Enum.TextXAlignment.Left
        task.spawn(function()
            while sg.Parent and shrineActive do
                if shrinePhase=="underground" then sLbl.Text="UNDERGROUND  |  READY"; sLbl.TextColor3=Color3.fromRGB(130,130,130)
                elseif shrinePhase=="closing" then sLbl.Text="SUMMONING..."; sLbl.TextColor3=Color3.fromRGB(255,80,50)
                elseif shrinePhase=="closed"  then sLbl.Text="DOMAIN CLOSED"; sLbl.TextColor3=Color3.fromRGB(255,50,50)
                elseif shrinePhase=="opening" then sLbl.Text="DISPERSING..."; sLbl.TextColor3=Color3.fromRGB(200,100,50) end
                pLbl.Text="PARTS: "..partCount
                task.wait(0.3)
            end
        end)
        local function aBtn3(t2,yp,bg,fg)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.new(1,-12,0,32);b.Position=UDim2.fromOffset(6,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=11;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b);return b end
        local closeBtn2=aBtn3("🔒 CLOSE DOMAIN",68,Color3.fromRGB(60,15,8),Color3.fromRGB(255,100,60))
        local cancelBtn=aBtn3("💀 CANCEL",104,Color3.fromRGB(60,10,10),Color3.fromRGB(255,60,60))
        closeBtn2.MouseButton1Click:Connect(function()
            if shrinePhase=="underground" then closeDomain(); closeBtn2.Text="🔓 OPEN DOMAIN"
            elseif shrinePhase=="closed"  then openDomain();  closeBtn2.Text="🔒 CLOSE DOMAIN" end
        end)
        cancelBtn.MouseButton1Click:Connect(function()
            destroyShrine(); destroyShrineGui(); activeMode="none"; isActivated=false
        end)
        makeDraggable(titleBar,panel,false)
    end

    -- ════════════════════════════════════════════════════════════
    -- PET MODE
    -- Chat commands: !pet <name>  then  !follow/!stay/!dance etc.
    -- ════════════════════════════════════════════════════════════

    -- Get all parts assigned to an owner (for split mode)
    local function getPetPartsForOwner(ownerName)
        if petSplitOwners[ownerName] then return petSplitOwners[ownerName] end
        -- If no split, all controlled parts
        local arr={}
        for part,_ in pairs(controlled) do if part and part.Parent then table.insert(arr,part) end end
        return arr
    end

    -- Get character root for a player name
    local function getPlayerRoot(name)
        for _,p in ipairs(Players:GetPlayers()) do
            if p.Name:lower()==name:lower() or p.DisplayName:lower()==name:lower() then
                local char=p.Character
                return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            end
        end
    end

    local function updatePet(dt, rootPos)
        if not petActive then return end
        local t=tick()
        petDanceT=petDanceT+dt

        -- For each owner, get their assigned parts
        local function getParts(ownerName)
            if petSplitOwners[ownerName] then return petSplitOwners[ownerName]
            else
                local arr={}
                for part,_ in pairs(controlled) do if part and part.Parent then table.insert(arr,part) end end
                return arr
            end
        end

        local function moveParts(parts, targetPos, orbitDist, orbitT, mode2)
            local n=math.max(#parts,1)
            for i,part in ipairs(parts) do
                local data=controlled[part]; if not(data and data.bp and data.bp.Parent) then return end
                local tgt

                if mode2=="follow" or mode2=="stay" then
                    -- Hover in a small sphere cluster around target
                    local phi=(1+math.sqrt(5))/2; local i2=i-1; local s=math.max(n,1)
                    local theta=math.acos(math.clamp(1-2*(i2+0.5)/s,-1,1)); local ang=2*math.pi*i2/phi
                    local r=1.5+math.floor(i/10)*1.2
                    tgt=targetPos+Vector3.new(r*math.sin(theta)*math.cos(ang),r*math.sin(theta)*math.sin(ang)+2,r*math.cos(theta))

                elseif mode2=="orbit" then
                    local ang2=orbitT*1.5+i*(math.pi*2/n)
                    tgt=targetPos+Vector3.new(math.cos(ang2)*orbitDist,2,math.sin(ang2)*orbitDist)

                elseif mode2=="ring" then
                    local ang2=orbitT*2+i*(math.pi*2/n)
                    tgt=targetPos+Vector3.new(math.cos(ang2)*orbitDist,0.5,math.sin(ang2)*orbitDist)

                elseif mode2=="wall" then
                    -- Flat grid in front of target facing
                    local root2=getPlayerRoot(petOwnerList[1] or "")
                    local fwd=root2 and root2.CFrame.LookVector or Vector3.new(0,0,-1)
                    local right=root2 and root2.CFrame.RightVector or Vector3.new(1,0,0)
                    local cols=math.max(1,math.ceil(math.sqrt(n))); local col=(i-1)%cols-math.floor(cols/2); local row=math.floor((i-1)/cols)
                    tgt=targetPos+fwd*5+right*(col*1.8)+Vector3.new(0,row*1.8,0)

                elseif mode2=="dance" then
                    -- Random swirling pattern that cycles through phases
                    local phase=math.floor(petDanceT/2)%4
                    if phase==0 then -- spin ring
                        local ang2=petDanceT*3+i*(math.pi*2/n); tgt=targetPos+Vector3.new(math.cos(ang2)*4,1+math.sin(petDanceT*2)*2,math.sin(ang2)*4)
                    elseif phase==1 then -- vertical helix
                        local ang2=petDanceT*4+i*(math.pi*2/n); tgt=targetPos+Vector3.new(math.cos(ang2)*3,(i/n)*8-4+math.sin(petDanceT)*1,math.sin(ang2)*3)
                    elseif phase==2 then -- sphere pulse
                        local phi=(1+math.sqrt(5))/2; local i2=i-1; local s=math.max(n,1)
                        local theta=math.acos(math.clamp(1-2*(i2+0.5)/s,-1,1)); local ang3=2*math.pi*i2/phi
                        local r=5+math.sin(petDanceT*3)*2
                        tgt=targetPos+Vector3.new(r*math.sin(theta)*math.cos(ang3),r*math.sin(theta)*math.sin(ang3)+2,r*math.cos(theta))
                    else -- chaos swarm
                        local ang2=petDanceT*2+i*1.3; local r=3+math.sin(i+petDanceT*1.5)*2
                        tgt=targetPos+Vector3.new(math.cos(ang2+i)*r, math.sin(i*0.7+petDanceT)*3+2, math.sin(ang2)*r)
                    end

                elseif mode2=="stop" then
                    -- Stay exactly where they are
                    tgt=part.Position

                else -- default hover above
                    tgt=targetPos+Vector3.new(0,4,0)
                end

                if tgt then
                    data.bp.P=70000; data.bp.D=2500; data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=tgt
                end
            end
        end

        if #petOwnerList==0 then
            -- No owner, hover above local player
            local arr={}
            for part,_ in pairs(controlled) do if part and part.Parent then table.insert(arr,part) end end
            moveParts(arr, rootPos, petOrbitDist, t, petState)
        elseif #petOwnerList==1 then
            local root=getPlayerRoot(petOwnerList[1])
            local tpos=root and root.Position or rootPos
            local arr=getParts(petOwnerList[1])
            moveParts(arr, tpos, petOrbitDist, t, petState)
        else
            -- Split between owners
            for _,ownerName in ipairs(petOwnerList) do
                local root=getPlayerRoot(ownerName)
                local tpos=root and root.Position or rootPos
                local arr=getParts(ownerName)
                moveParts(arr, tpos, petOrbitDist, t, petState)
            end
        end
    end

    destroyPet=function()
        petActive=false; petOwners={}; petOwnerList={}; petState="idle"
        petSplitOwners={}
        if petGuiUpdateFn then pcall(petGuiUpdateFn) end
    end

    destroyPetGui=function()
        if petSubGui and petSubGui.Parent then petSubGui:Destroy() end
        petSubGui=nil; petGuiUpdateFn=nil
    end

    local function rebuildPetOwnerList(listFrame)
        -- Clear existing labels
        for _,child in ipairs(listFrame:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        if #petOwnerList==0 then
            local l=Instance.new("TextLabel",listFrame); l.Text="No owners yet.  Use !pet <name>"
            l.Size=UDim2.new(1,0,0,18); l.BackgroundTransparency=1; l.TextColor3=Color3.fromRGB(100,100,130)
            l.TextSize=9; l.Font=Enum.Font.Gotham; l.TextXAlignment=Enum.TextXAlignment.Left
        else
            for idx,name in ipairs(petOwnerList) do
                local l=Instance.new("TextLabel",listFrame); l.Text="• "..name
                l.Size=UDim2.new(1,0,0,18); l.BackgroundTransparency=1; l.TextColor3=Color3.fromRGB(140,220,140)
                l.TextSize=9; l.Font=Enum.Font.GothamBold; l.TextXAlignment=Enum.TextXAlignment.Left
                l.LayoutOrder=idx
            end
        end
        local lay=listFrame:FindFirstChildOfClass("UIListLayout")
        if lay then listFrame.CanvasSize=UDim2.fromOffset(0, lay.AbsoluteContentSize.Y+4) end
    end

    local function createPetGui()
        destroyPetGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="PetSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; petSubGui=sg

        local W=210; local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(W,380); panel.Position=UDim2.new(0.5,15,0.5,-190); panel.BackgroundColor3=Color3.fromRGB(8,14,8); panel.BorderSizePixel=0; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8)
        local stk=Instance.new("UIStroke",panel); stk.Color=Color3.fromRGB(60,180,60); stk.Thickness=1.5

        -- Title bar
        local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=Color3.fromRGB(16,30,16); titleBar.BorderSizePixel=0; titleBar.ZIndex=10; titleBar.Parent=panel; Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",titleBar); tLbl.Text="🐾 PET MODE"; tLbl.Size=UDim2.new(1,-40,1,0); tLbl.Position=UDim2.fromOffset(8,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(100,240,100); tLbl.TextSize=12; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10
        local closeX=Instance.new("TextButton",titleBar); closeX.Text="✕"; closeX.Size=UDim2.fromOffset(24,22); closeX.Position=UDim2.new(1,-28,0,3); closeX.BackgroundColor3=Color3.fromRGB(120,20,20); closeX.TextColor3=Color3.fromRGB(255,255,255); closeX.TextSize=10; closeX.Font=Enum.Font.GothamBold; closeX.BorderSizePixel=0; closeX.ZIndex=11; Instance.new("UICorner",closeX)
        closeX.MouseButton1Click:Connect(function() destroyPet(); destroyPetGui(); activeMode="none"; isActivated=false end)

        local yOff=32

        -- Current state label
        local stateLbl=Instance.new("TextLabel",panel); stateLbl.Text="STATE: IDLE"; stateLbl.Size=UDim2.new(1,-10,0,14); stateLbl.Position=UDim2.fromOffset(6,yOff); stateLbl.BackgroundTransparency=1; stateLbl.TextColor3=Color3.fromRGB(100,200,100); stateLbl.TextSize=9; stateLbl.Font=Enum.Font.GothamBold; stateLbl.TextXAlignment=Enum.TextXAlignment.Left
        yOff=yOff+16
        task.spawn(function()
            while sg.Parent and petActive do stateLbl.Text="STATE: "..petState:upper().."  |  OWNERS: "..#petOwnerList; task.wait(0.3) end
        end)

        -- Commands reference
        local cmdBox=Instance.new("Frame",panel); cmdBox.Size=UDim2.new(1,-12,0,148); cmdBox.Position=UDim2.fromOffset(6,yOff); cmdBox.BackgroundColor3=Color3.fromRGB(5,10,5); cmdBox.BorderSizePixel=0; Instance.new("UICorner",cmdBox).CornerRadius=UDim.new(0,5); Instance.new("UIStroke",cmdBox).Color=Color3.fromRGB(40,100,40)
        local cmdScroll=Instance.new("ScrollingFrame",cmdBox); cmdScroll.Size=UDim2.new(1,0,1,0); cmdScroll.BackgroundTransparency=1; cmdScroll.BorderSizePixel=0; cmdScroll.ScrollBarThickness=2; cmdScroll.ScrollBarImageColor3=Color3.fromRGB(60,180,60); cmdScroll.CanvasSize=UDim2.fromOffset(0,0); cmdScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
        local cmdLay=Instance.new("UIListLayout",cmdScroll); cmdLay.Padding=UDim.new(0,1); Instance.new("UIPadding",cmdScroll).PaddingLeft=UDim.new(0,4)
        local cmds={
            "!pet <name> — give pet to player",
            "!follow — follow owner",
            "!stay — stay in place",
            "!dance — random dance",
            "!orbit — orbit owner",
            "!orbit <dist> — orbit at distance",
            "!wall — wall in front",
            "!split — split between owners",
            "!ring — ring around owner",
            "!stop — freeze completely",
        }
        for _,cmd in ipairs(cmds) do
            local l=Instance.new("TextLabel",cmdScroll); l.Text=cmd; l.Size=UDim2.new(1,0,0,14); l.BackgroundTransparency=1
            l.TextColor3=Color3.fromRGB(100,180,100); l.TextSize=8; l.Font=Enum.Font.Gotham; l.TextXAlignment=Enum.TextXAlignment.Left
        end
        yOff=yOff+152

        -- Active owners list
        local ownerHeader=Instance.new("TextLabel",panel); ownerHeader.Text="OWNERS"; ownerHeader.Size=UDim2.new(1,-10,0,14); ownerHeader.Position=UDim2.fromOffset(6,yOff); ownerHeader.BackgroundTransparency=1; ownerHeader.TextColor3=Color3.fromRGB(80,200,80); ownerHeader.TextSize=9; ownerHeader.Font=Enum.Font.GothamBold; ownerHeader.TextXAlignment=Enum.TextXAlignment.Left
        yOff=yOff+16
        local listFrame=Instance.new("ScrollingFrame",panel); listFrame.Size=UDim2.new(1,-12,0,70); listFrame.Position=UDim2.fromOffset(6,yOff); listFrame.BackgroundColor3=Color3.fromRGB(5,10,5); listFrame.BorderSizePixel=0; listFrame.ScrollBarThickness=2; listFrame.ScrollBarImageColor3=Color3.fromRGB(60,180,60); listFrame.CanvasSize=UDim2.fromOffset(0,0); listFrame.AutomaticCanvasSize=Enum.AutomaticSize.Y; Instance.new("UICorner",listFrame).CornerRadius=UDim.new(0,4); Instance.new("UIStroke",listFrame).Color=Color3.fromRGB(40,100,40)
        Instance.new("UIListLayout",listFrame).Padding=UDim.new(0,1); Instance.new("UIPadding",listFrame).PaddingLeft=UDim.new(0,4)
        yOff=yOff+74

        -- Remove owner button
        local remBtn=Instance.new("TextButton",panel); remBtn.Text="REMOVE ALL OWNERS"; remBtn.Size=UDim2.new(1,-12,0,26); remBtn.Position=UDim2.fromOffset(6,yOff); remBtn.BackgroundColor3=Color3.fromRGB(50,12,12); remBtn.TextColor3=Color3.fromRGB(255,80,80); remBtn.TextSize=9; remBtn.Font=Enum.Font.GothamBold; remBtn.BorderSizePixel=0; Instance.new("UICorner",remBtn)
        remBtn.MouseButton1Click:Connect(function()
            petOwners={}; petOwnerList={}; petSplitOwners={}
            petState="idle"; rebuildPetOwnerList(listFrame)
        end)

        panel.Size=UDim2.fromOffset(W, yOff+32)
        petGuiUpdateFn=function() rebuildPetOwnerList(listFrame) end
        rebuildPetOwnerList(listFrame)
        makeDraggable(titleBar,panel,false)

        -- ── Chat listener ─────────────────────────────────────
        -- Listen to ALL players' chat so owners can use commands too
        local function handleCommand(speakerName, msg)
            local lower=msg:lower():gsub("^%s+","")
            local isSelf=speakerName==player.Name
            local isOwner=petOwners[speakerName]

            -- !pet <name>: only the script owner can assign
            if isSelf then
                local assignName=lower:match("^!pet%s+(.+)$")
                if assignName then
                    assignName=assignName:gsub("%s+$","")
                    -- Find the player
                    local found=false
                    for _,p2 in ipairs(Players:GetPlayers()) do
                        if p2.Name:lower()==assignName or p2.DisplayName:lower()==assignName then
                            found=true
                            if not petOwners[p2.Name] then
                                petOwners[p2.Name]=true; table.insert(petOwnerList,p2.Name)
                                -- If 2+ owners, split parts equally
                                if #petOwnerList>=2 then
                                    local allParts={}
                                    for part,_ in pairs(controlled) do if part and part.Parent then table.insert(allParts,part) end end
                                    petSplitOwners={}
                                    local perOwner=math.max(1,math.floor(#allParts/#petOwnerList))
                                    local startIdx=1
                                    for i,ownerN in ipairs(petOwnerList) do
                                        local endIdx= (i==#petOwnerList) and #allParts or (startIdx+perOwner-1)
                                        petSplitOwners[ownerN]={}
                                        for j=startIdx,endIdx do table.insert(petSplitOwners[ownerN], allParts[j]) end
                                        startIdx=endIdx+1
                                    end
                                else
                                    petSplitOwners={}
                                end
                                rebuildPetOwnerList(listFrame)
                            end
                            break
                        end
                    end
                    return
                end
            end

            -- Commands usable by owner or self
            if not (isSelf or isOwner) then return end

            if lower=="!follow"   then petState="follow"
            elseif lower=="!stay" then petState="stay"
            elseif lower=="!dance"then petState="dance"; petDanceT=0; petDancePhase=0
            elseif lower=="!orbit"then petState="orbit"; petOrbitDist=8
            elseif lower:match("^!orbit%s+(%d+)$") then
                local d=tonumber(lower:match("^!orbit%s+(%d+)$")); if d then petOrbitDist=d; petState="orbit" end
            elseif lower=="!wall" then petState="wall"
            elseif lower=="!ring" then petState="ring"; petOrbitDist=8
            elseif lower=="!stop" then petState="stop"
            elseif lower=="!split"then
                -- Redistribute parts equally among current owners
                if #petOwnerList>=2 then
                    local allParts={}
                    for part,_ in pairs(controlled) do if part and part.Parent then table.insert(allParts,part) end end
                    petSplitOwners={}
                    local perOwner=math.max(1,math.floor(#allParts/#petOwnerList))
                    local si=1
                    for i2,ownerN in ipairs(petOwnerList) do
                        local ei=(i2==#petOwnerList) and #allParts or (si+perOwner-1)
                        petSplitOwners[ownerN]={}
                        for j=si,ei do table.insert(petSplitOwners[ownerN],allParts[j]) end
                        si=ei+1
                    end
                end
            end
        end

        -- Connect to our own chat
        player.Chatted:Connect(function(msg) if petActive then handleCommand(player.Name,msg) end end)

        -- Connect to all current + future players
        local function connectPlayer(p2)
            p2.Chatted:Connect(function(msg) if petActive then handleCommand(p2.Name,msg) end end)
        end
        for _,p2 in ipairs(Players:GetPlayers()) do if p2~=player then connectPlayer(p2) end end
        Players.PlayerAdded:Connect(function(p2) if petActive then connectPlayer(p2) end end)
    end
    destroyGojoGui=function() if gojoSubGui and gojoSubGui.Parent then gojoSubGui:Destroy()end;gojoSubGui=nil end
    local function createGojoGui()
        destroyGojoGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="GojoSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;sg.Parent=pg;gojoSubGui=sg

        -- Crosshair in center of screen
        local crosshair=Instance.new("Frame",sg);crosshair.Size=UDim2.fromOffset(20,20);crosshair.Position=UDim2.new(0.5,-10,0.5,-10);crosshair.BackgroundTransparency=1;crosshair.BorderSizePixel=0
        local ch1=Instance.new("Frame",crosshair);ch1.Size=UDim2.fromOffset(16,2);ch1.Position=UDim2.new(0.5,-8,0.5,-1);ch1.BackgroundColor3=Color3.fromRGB(255,255,255);ch1.BorderSizePixel=0;ch1.BackgroundTransparency=0.3
        local ch2=Instance.new("Frame",crosshair);ch2.Size=UDim2.fromOffset(2,16);ch2.Position=UDim2.new(0.5,-1,0.5,-8);ch2.BackgroundColor3=Color3.fromRGB(255,255,255);ch2.BorderSizePixel=0;ch2.BackgroundTransparency=0.3

        local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(170,210);panel.Position=UDim2.new(1,-185,0.5,-105);panel.BackgroundColor3=Color3.fromRGB(5,5,18);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local stk=Instance.new("UIStroke",panel);stk.Color=Color3.fromRGB(80,80,180);stk.Thickness=1.5
        local titleBar=Instance.new("Frame");titleBar.Size=UDim2.new(1,0,0,28);titleBar.BackgroundColor3=Color3.fromRGB(15,15,40);titleBar.BorderSizePixel=0;titleBar.ZIndex=10;titleBar.Parent=panel;Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",titleBar);tLbl.Text="👁 GOJO LIMITLESS";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(180,180,255);tLbl.TextSize=11;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local stateLbl=Instance.new("TextLabel",panel);stateLbl.Text="STATE: IDLE";stateLbl.Size=UDim2.new(1,-10,0,14);stateLbl.Position=UDim2.fromOffset(6,31);stateLbl.BackgroundTransparency=1;stateLbl.TextColor3=Color3.fromRGB(120,120,200);stateLbl.TextSize=9;stateLbl.Font=Enum.Font.GothamBold;stateLbl.TextXAlignment=Enum.TextXAlignment.Left

        task.spawn(function()
            while sg.Parent and gojoActive do
                stateLbl.Text="STATE: "..(gojoState:upper():gsub("_"," "))
                task.wait(0.2)
            end
        end)

        local function gBtn(t2,yp,bg,fg)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.new(1,-12,0,32);b.Position=UDim2.fromOffset(6,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=10;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b);return b end

        local detectBtn =gBtn("🔍 DETECT PARTS",   50,  Color3.fromRGB(20,40,20),   Color3.fromRGB(80,255,80))
        local blueBtn   =gBtn("◈ MAX BLUE",         86,  Color3.fromRGB(5,15,55),    Color3.fromRGB(60,140,255))
        local redBtn    =gBtn("◈ REVERSAL RED",     122, Color3.fromRGB(45,8,5),     Color3.fromRGB(255,70,40))
        local purpleBtn =gBtn("◈ HOLLOW PURPLE",    158, Color3.fromRGB(30,5,45),    Color3.fromRGB(200,80,255))
        local deBtn     =gBtn("◈ DE: INFINITY",     194, Color3.fromRGB(10,10,35),   Color3.fromRGB(200,200,255))

        -- Resize panel to fit 5 buttons
        panel.Size = UDim2.fromOffset(170, 240)

        -- Visual flash when button activates
        local function btnFlash(btn, col)
            local orig = btn.BackgroundColor3
            btn.BackgroundColor3 = col
            task.wait(0.15)
            if btn.Parent then btn.BackgroundColor3 = orig end
        end

        detectBtn.MouseButton1Click:Connect(function()
            task.spawn(function()
                btnFlash(detectBtn, Color3.fromRGB(40,120,40))
                detectAllPartsForGojo()
                stateLbl.Text = "DETECTED: "..partCount.." parts"
            end)
        end)

        -- Max Blue: click to start, click again to stop
        blueBtn.MouseButton1Click:Connect(function()
            if gojoState == "blue_hold" then
                stopMaxBlue()
                blueBtn.Text = "◈ MAX BLUE"
            elseif gojoState == "idle" then
                fireMaxBlue()
                blueBtn.Text = "◈ MAX BLUE  [STOP]"
                task.spawn(function()
                    -- Auto-revert button label after 10s
                    task.wait(11)
                    if blueBtn.Parent then blueBtn.Text = "◈ MAX BLUE" end
                end)
            end
        end)

        redBtn.MouseButton1Click:Connect(function()
            local now = tick()
            if gojoState ~= "idle" then return end
            if now - gojoLastFire.red < RED_CD then
                stateLbl.Text = "RED: cooldown "..(math.ceil(RED_CD-(now-gojoLastFire.red)).."s")
                return
            end
            task.spawn(function() btnFlash(redBtn, Color3.fromRGB(200,50,20)) end)
            fireReversalRed()
        end)

        purpleBtn.MouseButton1Click:Connect(function()
            local now = tick()
            if gojoState ~= "idle" then return end
            if now - gojoLastFire.purple < PURPLE_CD then
                stateLbl.Text = "PURPLE: cooldown "..(math.ceil(PURPLE_CD-(now-gojoLastFire.purple)).."s")
                return
            end
            task.spawn(function() btnFlash(purpleBtn, Color3.fromRGB(120,0,200)) end)
            fireHollowPurple()
        end)

        local deActive=false
        deBtn.MouseButton1Click:Connect(function()
            if not deActive and gojoState=="idle" then
                deActive=true; deBtn.Text="◈ DEACTIVATE ∞"
                local char=player.Character
                local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
                activateDeInfinity(root and root.Position or Vector3.new(0,5,0))
            elseif deActive then
                deActive=false; deBtn.Text="◈ DE: INFINITY"
                deactivateDeInfinity()
            end
        end)

        makeDraggable(titleBar,panel,false)
    end

    -- ════════════════════════════════════════════════════════════
    -- MAIN LOOP (Stepped = before physics, minimum lag)
    -- ════════════════════════════════════════════════════════════
    local function mainLoop()
        RunService.Stepped:Connect(function(_,dt)
            if not scriptAlive then return end
            snakeT=snakeT+dt; gasterT=gasterT+dt
            petDanceT=petDanceT+dt

            -- Lock blocks every frame when enabled
            if lockedBlocks then lockAllNow() end

            -- Clean continuous spin
            if spinSpeed~=0 then
                spinAngle=spinAngle+spinSpeed*dt
                if spinAngle>math.pi*200 then spinAngle=spinAngle-math.pi*400 end
            end

            local char=player.Character
            local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            if not root then return end
            local pos=root.Position; local cf=root.CFrame; local t=tick()

            if activeMode=="sphere"       then updateSphereTarget(dt,pos) end
            if activeMode=="spherebender" then updateSphereBenderTargets(dt,pos) end
            if activeMode=="tank"         then updateTank(dt) end
            if activeMode=="car"          then updateCar(dt) end
            if activeMode=="de_shrine"    then updateDeShrine(dt) end
            if activeMode=="gojo"         then updateGojo(dt,pos) end
            if activeMode=="pet"           then updatePet(dt,pos) end

            table.insert(snakeHistory,1,pos)
            if #snakeHistory>SNAKE_HIST_MAX then table.remove(snakeHistory,SNAKE_HIST_MAX+1) end

            -- Mode transitions
            if activeMode~=lastMode then
                if GASTER_MODES[activeMode]        then createGasterGui()     else destroyGasterGui() end
                if SPHERE_MODES[activeMode] then spherePos=pos+Vector3.new(0,1.5,4);sphereVel=Vector3.zero;createSphereGui() else destroySphereGui() end
                if SPHERE_BENDER_MODES[activeMode] then
                    if #sbSpheres==0 then local s=newSBSphere(pos+Vector3.new(0,1.5,4));s.selected=true;table.insert(sbSpheres,s)end; rebuildSBGui()
                else destroySphereBenderGui();sbSpheres={} end
                if TANK_MODES[activeMode] then
                    tankActive=true;cameraOrbitAngle=0;cameraPitchAngle=math.rad(25);createTankGui()
                    local ok=buildTankFromParts(pos,cf)
                    if ok then tks.insideTank=true;tks.hatchOpen=false;freezePlayer(tks.tankBase.CFrame*CFrame.new(0,TANK_INTERIOR_Y,0))end
                else if tankActive then destroyTank();destroyTankGui()end end
                if CAR_MODES[activeMode] then
                    carActive=true;createCarGui()
                    local ok=buildCarFromParts(pos,cf)
                    if ok then frozenCarCF=cs.carBase.CFrame end
                else if carActive then destroyCar();destroyCarGui()end end
                if SHRINE_MODES[activeMode] then
                    shrineActive=true
                    task.spawn(function() initDeShrine(pos) end)
                    createShrineGui()
                else if shrineActive then destroyShrine();destroyShrineGui()end end
                if GOJO_MODES[activeMode] then
                    gojoActive=true; gojoState="idle"; sweepMap(); createGojoGui()
                else if gojoActive then destroyGojo();destroyGojoGui()end end
                if PET_MODES[activeMode] then
                    petActive=true; petState="idle"; petOwners={}; petOwnerList={}; petSplitOwners={}
                    fullSweep(); createPetGui()
                else if petActive then destroyPet();destroyPetGui()end end
                lastMode=activeMode
            end

            -- Skip standard loop for special modes with own update
            if not isActivated or activeMode=="none" or partCount==0 then return end
            if activeMode=="tank" or activeMode=="car" or activeMode=="de_shrine" or activeMode=="gojo" or activeMode=="pet" then return end

            -- Standard formation loop
            local arr={}
            for part,data in pairs(controlled) do
                if part and part.Parent then table.insert(arr,{p=part,d=data})
                else controlled[part]=nil;partCount=math.max(0,partCount-1) end
            end
            local n=#arr

            for i,item in ipairs(arr) do
                local part=item.p; local targetCF=nil
                if activeMode=="snake" then targetCF=CFrame.new(getSnakeTarget(i))
                elseif activeMode=="gasterhand" then targetCF=(i<=HAND_SLOTS_COUNT) and getGasterCF(i,1,cf,gasterT) or CFrame.new(pos+Vector3.new(0,-5000,0))
                elseif activeMode=="gaster2hands" then
                    if i<=HAND_SLOTS_COUNT then targetCF=getGasterCF(i,1,cf,gasterT)
                    elseif i<=HAND_SLOTS_COUNT*2 then targetCF=getGasterCF(i-HAND_SLOTS_COUNT,-1,cf,gasterT)
                    else targetCF=CFrame.new(pos+Vector3.new(0,-5000,0))end
                elseif activeMode=="sphere" then
                    local off=getSphereShellPos(i,n);local st=t*3
                    targetCF=CFrame.new(spherePos)*CFrame.Angles(st,st*1.3,st*0.7)*CFrame.new(off)
                elseif activeMode=="spherebender" then
                    local ns=math.max(1,#sbSpheres);local pps=math.max(1,math.ceil(n/ns))
                    local si=math.min(math.ceil(i/pps),ns);local sp=sbSpheres[si]
                    local li=((i-1)%pps)+1;local lt=math.max(math.min(pps,n-(si-1)*pps),1)
                    local off=getSphereShellPos(li,lt);local st=t*3
                    targetCF=CFrame.new(sp.pos)*CFrame.Angles(st,st*1.3,st*0.7)*CFrame.new(off)
                elseif CFRAME_MODES[activeMode] then targetCF=getFormationCF(activeMode,i,n,pos,cf,t) end

                if targetCF then
                    -- Clean single-axis spin
                    local finalCF=targetCF
                    if spinSpeed~=0 then
                        local phase=i*(math.pi*2/math.max(n,1))
                        local spinAxis=Vector3.new(math.sin(phase)*0.15,1,math.cos(phase)*0.15).Unit
                        finalCF=CFrame.new(targetCF.Position)*CFrame.fromAxisAngle(spinAxis,spinAngle+phase)
                    end
                    local data=item.d
                    pcall(function()
                        if data.bp and data.bp.Parent then data.bp.Position=finalCF.Position;data.bg.CFrame=finalCF
                        else part.CFrame=finalCF;part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end
                    end)
                end
            end
        end)
    end

    local function scanLoop()
        while scriptAlive do
            if isActivated and activeMode~="none" and activeMode~="tank" and activeMode~="car"
            and activeMode~="de_shrine" and activeMode~="gojo" then sweepMap() end
            task.wait(1.5)
        end
    end

    -- ════════════════════════════════════════════════════════════
    -- MAIN GUI
    -- ════════════════════════════════════════════════════════════
    local function createGUI()
        local pg=player:WaitForChild("PlayerGui")
        local old=pg:FindFirstChild("ManipGUI"); if old then old:Destroy()end
        local gui=Instance.new("ScreenGui");gui.Name="ManipGUI";gui.ResetOnSpawn=false;gui.DisplayOrder=999;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Parent=pg
        local W,H=195,370
        local panel=Instance.new("Frame");panel.Name="Panel";panel.Size=UDim2.fromOffset(W,H);panel.Position=UDim2.new(0.5,-W/2,0.5,-H/2);panel.BackgroundColor3=Color3.fromRGB(10,10,25);panel.BorderSizePixel=0;panel.ClipsDescendants=true;panel.Parent=gui;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local pS=Instance.new("UIStroke",panel);pS.Color=Color3.fromRGB(90,40,180);pS.Thickness=1.5
        local titleBar=Instance.new("Frame");titleBar.Size=UDim2.new(1,0,0,30);titleBar.BackgroundColor3=Color3.fromRGB(20,10,48);titleBar.BorderSizePixel=0;titleBar.ZIndex=10;titleBar.Parent=panel;Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tTxt=Instance.new("TextLabel",titleBar);tTxt.Text="MANIPULATOR KII";tTxt.Size=UDim2.new(1,-60,1,0);tTxt.Position=UDim2.fromOffset(8,0);tTxt.BackgroundTransparency=1;tTxt.TextColor3=Color3.fromRGB(195,140,255);tTxt.TextSize=11;tTxt.Font=Enum.Font.GothamBold;tTxt.TextXAlignment=Enum.TextXAlignment.Left;tTxt.ZIndex=10
        local closeBtn=Instance.new("TextButton",titleBar);closeBtn.Text="✕";closeBtn.Size=UDim2.fromOffset(24,22);closeBtn.Position=UDim2.new(1,-28,0,4);closeBtn.BackgroundColor3=Color3.fromRGB(150,25,25);closeBtn.TextColor3=Color3.fromRGB(255,255,255);closeBtn.TextSize=10;closeBtn.Font=Enum.Font.GothamBold;closeBtn.BorderSizePixel=0;closeBtn.ZIndex=11;Instance.new("UICorner",closeBtn)
        makeDraggable(titleBar,panel,false); makeDraggable(panel,panel,true)
        local scroll=Instance.new("ScrollingFrame");scroll.Size=UDim2.new(1,0,1,-30);scroll.Position=UDim2.fromOffset(0,30);scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0;scroll.ScrollBarThickness=3;scroll.ScrollBarImageColor3=Color3.fromRGB(90,40,180);scroll.CanvasSize=UDim2.fromOffset(0,0);scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.Parent=panel
        local lay=Instance.new("UIListLayout",scroll);lay.Padding=UDim.new(0,3);lay.HorizontalAlignment=Enum.HorizontalAlignment.Center;lay.SortOrder=Enum.SortOrder.LayoutOrder
        local pad=Instance.new("UIPadding",scroll);pad.PaddingTop=UDim.new(0,4);pad.PaddingBottom=UDim.new(0,6);pad.PaddingLeft=UDim.new(0,5);pad.PaddingRight=UDim.new(0,5)
        local function sLbl2(t2,ord)local l=Instance.new("TextLabel",scroll);l.Text=t2;l.Size=UDim2.new(1,0,0,16);l.BackgroundTransparency=1;l.TextColor3=Color3.fromRGB(160,110,255);l.TextSize=9;l.Font=Enum.Font.GothamBold;l.TextXAlignment=Enum.TextXAlignment.Left;l.LayoutOrder=ord end
        local function sBtn3(t2,bg,fg,ord)local b=Instance.new("TextButton",scroll);b.Text=t2;b.Size=UDim2.new(1,0,0,28);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=9;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;b.LayoutOrder=ord;Instance.new("UICorner",b);return b end

        -- Settings
        sLbl2("⚙ SETTINGS",0)
        local function makeSettingRow(labelTxt,defaultVal,accentCol,order,onApply)
            local row=Instance.new("Frame",scroll);row.Size=UDim2.new(1,0,0,38);row.BackgroundColor3=Color3.fromRGB(14,12,32);row.BorderSizePixel=0;row.LayoutOrder=order;Instance.new("UICorner",row).CornerRadius=UDim.new(0,6);local rowStk=Instance.new("UIStroke",row);rowStk.Color=Color3.fromRGB(50,35,90);rowStk.Thickness=1
            local lbl=Instance.new("TextLabel",row);lbl.Text=labelTxt;lbl.Size=UDim2.new(0.48,0,0,16);lbl.Position=UDim2.fromOffset(6,3);lbl.BackgroundTransparency=1;lbl.TextColor3=accentCol;lbl.TextSize=8;lbl.Font=Enum.Font.GothamBold;lbl.TextXAlignment=Enum.TextXAlignment.Left
            local tb=Instance.new("TextBox",row);tb.Text=tostring(defaultVal);tb.Size=UDim2.new(0.52,-36,0,22);tb.Position=UDim2.new(0.46,0,0,8);tb.BackgroundColor3=Color3.fromRGB(22,18,50);tb.TextColor3=Color3.fromRGB(255,255,255);tb.TextSize=10;tb.Font=Enum.Font.GothamBold;tb.ClearTextOnFocus=false;tb.BorderSizePixel=0;Instance.new("UICorner",tb).CornerRadius=UDim.new(0,4)
            local applyBtn=Instance.new("TextButton",row);applyBtn.Text="✓";applyBtn.Size=UDim2.fromOffset(28,22);applyBtn.Position=UDim2.new(1,-32,0,8);applyBtn.BackgroundColor3=accentCol;applyBtn.TextColor3=Color3.fromRGB(0,0,0);applyBtn.TextSize=11;applyBtn.Font=Enum.Font.GothamBold;applyBtn.BorderSizePixel=0;Instance.new("UICorner",applyBtn).CornerRadius=UDim.new(0,4)
            local function flash(ok)applyBtn.BackgroundColor3=ok and Color3.fromRGB(80,255,120) or Color3.fromRGB(255,80,80);task.wait(0.25);if applyBtn.Parent then applyBtn.BackgroundColor3=accentCol end end
            applyBtn.MouseButton1Click:Connect(function()local num=tonumber(tb.Text);if num then onApply(num);task.spawn(function()flash(true)end)else task.spawn(function()flash(false)end)end end)
            tb.FocusLost:Connect(function(enter)if enter then local num=tonumber(tb.Text);if num then onApply(num)end end end)
            local hint=Instance.new("TextLabel",row);hint.Size=UDim2.new(1,-6,0,10);hint.Position=UDim2.fromOffset(6,26);hint.BackgroundTransparency=1;hint.TextColor3=Color3.fromRGB(80,75,120);hint.TextSize=7;hint.Font=Enum.Font.Gotham;hint.TextXAlignment=Enum.TextXAlignment.Left
            return tb,hint
        end
        local _,psHint=makeSettingRow("PULL STRENGTH",pullStrength,Color3.fromRGB(255,180,60),1,function(v)pullStrength=math.clamp(v,1,1e8);applyStrengthToAll();sweepMap();psHint.Text="current: "..tostring(pullStrength)end)
        psHint.Text="current: "..tostring(pullStrength).." (higher=faster)"
        local _,radHint=makeSettingRow("RADIUS",radius,Color3.fromRGB(80,200,255),2,function(v)radius=math.clamp(v,0.5,500);radHint.Text="current: "..tostring(radius).." studs"end)
        radHint.Text="current: "..tostring(radius).." studs"
        local _,spinHint=makeSettingRow("SPIN SPEED",spinSpeed,Color3.fromRGB(180,100,255),3,function(v)spinSpeed=v;if v==0 then spinAngle=0 end;spinHint.Text="current: "..tostring(v).." (0=off)"end)
        spinHint.Text="current: 0  (0=off)"

        sLbl2("STATUS",4)
        local stLbl=Instance.new("TextLabel",scroll);stLbl.Text="IDLE  |  PARTS: 0";stLbl.Size=UDim2.new(1,0,0,16);stLbl.BackgroundTransparency=1;stLbl.TextColor3=Color3.fromRGB(80,255,140);stLbl.TextSize=9;stLbl.Font=Enum.Font.GothamBold;stLbl.TextXAlignment=Enum.TextXAlignment.Left;stLbl.LayoutOrder=5
        local modLbl=Instance.new("TextLabel",scroll);modLbl.Text="MODE: NONE";modLbl.Size=UDim2.new(1,0,0,14);modLbl.BackgroundTransparency=1;modLbl.TextColor3=Color3.fromRGB(130,130,255);modLbl.TextSize=9;modLbl.Font=Enum.Font.GothamBold;modLbl.TextXAlignment=Enum.TextXAlignment.Left;modLbl.LayoutOrder=6
        task.spawn(function()while gui.Parent and scriptAlive do stLbl.Text=isActivated and("ACTIVE  |  PARTS: "..partCount) or "IDLE  |  PARTS: 0";task.wait(0.5)end end)

        sLbl2("STANDARD MODES",7)
        local stdModes={{txt="SNAKE",mode="snake",col=Color3.fromRGB(160,110,255)},{txt="HEART",mode="heart",col=Color3.fromRGB(255,100,150)},{txt="RINGS",mode="rings",col=Color3.fromRGB(80,210,255)},{txt="WALL",mode="wall",col=Color3.fromRGB(255,200,90)},{txt="BOX",mode="box",col=Color3.fromRGB(160,255,100)},{txt="WINGS",mode="wings",col=Color3.fromRGB(100,220,255)}}
        local sRows=math.ceil(#stdModes/2);local sFrame=Instance.new("Frame",scroll);sFrame.Size=UDim2.new(1,0,0,sRows*28+(sRows-1)*3);sFrame.BackgroundTransparency=1;sFrame.LayoutOrder=8
        local sGL=Instance.new("UIGridLayout",sFrame);sGL.CellSize=UDim2.new(0.5,-3,0,28);sGL.CellPadding=UDim2.fromOffset(3,3);sGL.HorizontalAlignment=Enum.HorizontalAlignment.Left;sGL.SortOrder=Enum.SortOrder.LayoutOrder
        for idx,m in ipairs(stdModes)do
            local btn=Instance.new("TextButton",sFrame);btn.Text=m.txt;btn.BackgroundColor3=Color3.fromRGB(26,14,55);btn.TextColor3=m.col;btn.TextSize=9;btn.Font=Enum.Font.GothamBold;btn.BorderSizePixel=0;btn.LayoutOrder=idx;Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()
                destroyGasterGui();destroySphereGui();destroySphereBenderGui()
                if tankActive then destroyTank();destroyTankGui()end;if carActive then destroyCar();destroyCarGui()end
                if shrineActive then destroyShrine();destroyShrineGui()end;if gojoActive then destroyGojo();destroyGojoGui()end
                activeMode=m.mode;isActivated=true;modLbl.Text="MODE: "..m.mode:upper();sweepMap()
            end)
        end

        sLbl2("SPECIAL MODES",9)
        local spModes={
            {txt="GASTER",     mode="gasterhand",  col=Color3.fromRGB(180,80,255)},
            {txt="2x GASTER",  mode="gaster2hands",col=Color3.fromRGB(220,110,255)},
            {txt="SPHERE",     mode="sphere",       col=Color3.fromRGB(60,210,255)},
            {txt="SPH.BENDER", mode="spherebender", col=Color3.fromRGB(0,230,255)},
            {txt="TANK",       mode="tank",         col=Color3.fromRGB(190,190,190)},
            {txt="CAR",        mode="car",          col=Color3.fromRGB(80,220,80)},
            {txt="DE SHRINE",  mode="de_shrine",    col=Color3.fromRGB(255,70,50)},
            {txt="GOJO",       mode="gojo",         col=Color3.fromRGB(160,160,255)},
            {txt="PET MODE",   mode="pet",           col=Color3.fromRGB(80,255,140)},
        }
        local spRows=math.ceil(#spModes/2);local spFrame=Instance.new("Frame",scroll);spFrame.Size=UDim2.new(1,0,0,spRows*28+(spRows-1)*3);spFrame.BackgroundTransparency=1;spFrame.LayoutOrder=10
        local spGL=Instance.new("UIGridLayout",spFrame);spGL.CellSize=UDim2.new(0.5,-3,0,28);spGL.CellPadding=UDim2.fromOffset(3,3);spGL.HorizontalAlignment=Enum.HorizontalAlignment.Left;spGL.SortOrder=Enum.SortOrder.LayoutOrder
        for idx,m in ipairs(spModes)do
            local btn=Instance.new("TextButton",spFrame);btn.Text=m.txt;btn.BackgroundColor3=Color3.fromRGB(30,8,58);btn.TextColor3=m.col;btn.TextSize=9;btn.Font=Enum.Font.GothamBold;btn.BorderSizePixel=0;btn.LayoutOrder=idx;Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()
                destroyGasterGui();destroySphereGui();destroySphereBenderGui()
                if tankActive then destroyTank();destroyTankGui()end;if carActive then destroyCar();destroyCarGui()end
                if shrineActive then destroyShrine();destroyShrineGui()end;if gojoActive then destroyGojo();destroyGojoGui()end
                activeMode=m.mode;isActivated=true;modLbl.Text="MODE: "..m.mode:upper()
                if GASTER_MODES[m.mode] then createGasterGui()
                elseif SPHERE_MODES[m.mode] then
                    local r2=player.Character and(player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"))
                    spherePos=(r2 and r2.Position or Vector3.new(0,5,0))+Vector3.new(0,1.5,4);sphereVel=Vector3.zero;createSphereGui()
                elseif SPHERE_BENDER_MODES[m.mode] then
                    sbSpheres={};local r2=player.Character and(player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"))
                    local s=newSBSphere((r2 and r2.Position or Vector3.new(0,5,0))+Vector3.new(0,2,4));s.selected=true;table.insert(sbSpheres,s);rebuildSBGui()
                end
                sweepMap()
            end)
        end

        sLbl2("ACTIONS",11)
        -- Lock Blocks toggle
        local lockBtn=Instance.new("TextButton",scroll)
        lockBtn.Text="🔒 LOCK BLOCKS: OFF"
        lockBtn.Size=UDim2.new(1,0,0,28)
        lockBtn.BackgroundColor3=Color3.fromRGB(30,30,50)
        lockBtn.TextColor3=Color3.fromRGB(140,140,200)
        lockBtn.TextSize=9; lockBtn.Font=Enum.Font.GothamBold
        lockBtn.BorderSizePixel=0; lockBtn.LayoutOrder=11
        Instance.new("UICorner",lockBtn)
        lockBtn.MouseButton1Click:Connect(function()
            lockedBlocks=not lockedBlocks
            if lockedBlocks then
                lockBtn.Text="🔒 LOCK BLOCKS: ON"
                lockBtn.BackgroundColor3=Color3.fromRGB(15,55,15)
                lockBtn.TextColor3=Color3.fromRGB(80,255,100)
                -- Immediate full enforcement on all current parts
                lockAllNow()
            else
                lockBtn.Text="🔒 LOCK BLOCKS: OFF"
                lockBtn.BackgroundColor3=Color3.fromRGB(30,30,50)
                lockBtn.TextColor3=Color3.fromRGB(140,140,200)
                -- Restore normal BP strength
                applyStrengthToAll()
            end
        end)
        local scanBtn=sBtn3("SCAN PARTS", Color3.fromRGB(18,55,20),Color3.fromRGB(80,255,120),12)
        local relBtn =sBtn3("RELEASE ALL",Color3.fromRGB(55,30,8), Color3.fromRGB(255,155,55),13)
        local deaBtn =sBtn3("DEACTIVATE", Color3.fromRGB(70,8,8),  Color3.fromRGB(255,55,55), 14)
        scanBtn.MouseButton1Click:Connect(function()sweepMap()end)
        relBtn.MouseButton1Click:Connect(function()releaseAll();activeMode="none";isActivated=false;modLbl.Text="MODE: NONE"end)
        deaBtn.MouseButton1Click:Connect(function()releaseAll();scriptAlive=false;gui:Destroy();local icon=pg:FindFirstChild("ManipIcon");if icon then icon:Destroy()end end)
        closeBtn.MouseButton1Click:Connect(function()
            gui:Destroy();local mini=Instance.new("ScreenGui");mini.Name="ManipIcon";mini.ResetOnSpawn=false;mini.DisplayOrder=999;mini.Parent=pg
            local ib=Instance.new("TextButton",mini);ib.Text="M";ib.Size=UDim2.fromOffset(34,34);ib.Position=UDim2.new(1,-42,0,8);ib.BackgroundColor3=Color3.fromRGB(22,10,50);ib.TextColor3=Color3.fromRGB(195,140,255);ib.TextSize=13;ib.Font=Enum.Font.GothamBold;ib.BorderSizePixel=0;Instance.new("UICorner",ib)
            ib.MouseButton1Click:Connect(function()mini:Destroy();createGUI()end)
        end)
    end

    createGUI(); task.spawn(mainLoop); task.spawn(scanLoop)
end

main()
