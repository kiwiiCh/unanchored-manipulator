-- ============================================================
-- UNANCHORED MANIPULATOR KII v17 -- DELTA EXECUTOR
-- v17 CHANGES:
--   SNAKE: SNAKE_GAP 8→3 (faster, tighter)
--   DETECT BUTTON: fullSweep + pulls ALL unanchored to owner
-- PET NEW COMMANDS: !hollow purple, !trail, !slap, !throne,
--   !judgement sword, !rain, !titanic (+?forward/?stop/?right/
--   ?left/?anchor/?unanchor/?sink), !wings, !tornado, !blackhole
-- PET BUG FIXES: !spin, !bring, !gotto, !attack, !say
-- UI: Pet panel water/ocean animated theme
-- ============================================================
local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local TweenService=game:GetService("TweenService")
local player=Players.LocalPlayer

local EDGE_MARGIN=36
local function makeDraggable(handle,panel,edgeOnly)
    local dragging=false;local dragStartM=Vector2.zero;local dragStartPos=UDim2.new();local conC,conE
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType~=Enum.UserInputType.MouseButton1 and inp.UserInputType~=Enum.UserInputType.Touch then return end
        if edgeOnly then
            local p=Vector2.new(inp.Position.X,inp.Position.Y);local ap=panel.AbsolutePosition;local as=panel.AbsoluteSize
            if not(p.X-ap.X<EDGE_MARGIN or ap.X+as.X-p.X<EDGE_MARGIN or p.Y-ap.Y<EDGE_MARGIN or ap.Y+as.Y-p.Y<EDGE_MARGIN)then return end
        end
        dragging=true;dragStartM=Vector2.new(inp.Position.X,inp.Position.Y);dragStartPos=panel.Position
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
        if not par then pcall(function()conC:Disconnect()end);pcall(function()conE:Disconnect()end)end
    end)
end

local function main()
    print("[ManipKii v17] "..player.Name)
    local isActivated=false;local activeMode="none";local scriptAlive=true
    local radius=7;local detectionRange=math.huge;local pullStrength=50000
    local spinSpeed=0;local spinAngle=0

    -- Snake history: GAP=3 for faster, tighter snake
    local snakeT=0;local snakeHistory={};local SNAKE_HIST_MAX=600;local SNAKE_GAP=3
    local gasterAnim="pointing";local gasterT=0;local gasterSubGui=nil
    local sphereSubGui=nil;local sphereMode="orbit"
    local spherePos=Vector3.new(0,0,0);local sphereVel=Vector3.new(0,0,0);local sphereOrbitAngle=0
    local SPHERE_RADIUS=6;local SPHERE_SPEED=1.2;local SPHERE_SPRING=8;local SPHERE_DAMP=4
    local sbSubGui=nil;local sbSpheres={}
    local function newSBSphere(p)return{pos=p or Vector3.zero,vel=Vector3.zero,orbitAngle=0,mode="orbit",stopped=false,selected=false}end

    local savedWS=16;local savedJP=50;local savedAR=true
    local function freezePlayer(anchorCF)
        local char=player.Character;if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid");local hrp=char:FindFirstChild("HumanoidRootPart")
        if hum then savedWS=hum.WalkSpeed;savedJP=hum.JumpPower;savedAR=hum.AutoRotate;hum.WalkSpeed=0;hum.JumpPower=0;hum.AutoRotate=false;pcall(function()hum:ChangeState(Enum.HumanoidStateType.PlatformStanding)end)end
        if hrp then hrp.Anchored=true;if anchorCF then hrp.CFrame=anchorCF end end
        for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=false end)end end
    end
    local function thawPlayer(exitCF)
        local char=player.Character;if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid");local hrp=char:FindFirstChild("HumanoidRootPart")
        if hum then hum.WalkSpeed=savedWS;hum.JumpPower=savedJP;hum.AutoRotate=savedAR;pcall(function()hum:ChangeState(Enum.HumanoidStateType.GettingUp)end)end
        if hrp then hrp.Anchored=false;if exitCF then hrp.CFrame=exitCF end end
        for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=true end)end end
    end

    -- Tank state
    local tankSubGui=nil;local tankActive=false
    local cameraOrbitAngle=0;local cameraPitchAngle=math.rad(25)
    local CAM_PITCH_MIN=math.rad(8);local CAM_PITCH_MAX=math.rad(70);local CAMERA_DIST=24;local frozenTankCF=nil
    local CAM_ORBIT_SENS=3.0;local CAM_PITCH_SENS=2.0
    local tks={forward=0,turn=0,hatchOpen=false,insideTank=false,tankBase=nil,turretPart=nil,barrelPart=nil,turretPartIdx=nil,barrelPartIdx=nil,tankParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0,tankHatch=nil}
    local TANK_H=5;local TANK_W=12;local TANK_L=16;local TANK_INTERIOR_Y=TANK_H/2+2.5
    local TANK_SPEED=35;local TANK_TURN=2.2;local TANK_ACCEL=12;local TANK_FRIC=0.88
    local SHOOT_CD=1.5;local lastShot=0;local PROJ_SPEED=650
    local rightJoy={active=false,origin=Vector2.zero,current=Vector2.zero,radius=55,deadzone=10,touchId=nil}
    local tankRayParams=RaycastParams.new();tankRayParams.FilterType=Enum.RaycastFilterType.Exclude

    -- Car state
    local carSubGui=nil;local carActive=false;local frozenCarCF=nil
    local cs={doorOpen=false,carBase=nil,carDoor=nil,carParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0}
    local CAR_H=2.8;local CAR_INTERIOR_Y=CAR_H/2+1.8
    local CAR_SPEED=48;local CAR_TURN=2.8;local CAR_ACCEL=20;local CAR_FRIC=0.88
    local carJoy={active=false,origin=Vector2.zero,current=Vector2.zero,radius=70,deadzone=8,touchId=nil,forward=0,turn=0}
    local carRayParams=RaycastParams.new();carRayParams.FilterType=Enum.RaycastFilterType.Exclude

    -- DE Shrine state
    local shrineSubGui=nil;local shrineActive=false;local shrinePhase="inactive"
    local shrineCenter=Vector3.zero;local shrineTimer=0
    local SHRINE_CLOSE_TIME=3.5;local SHRINE_OPEN_TIME=2.5;local DOMAIN_RADIUS=30;local SLASH_SPEED=290
    local shrineStructOffsets={
        CFrame.new(0,0.25,0),CFrame.new(0,0.75,0),CFrame.new(0,1.25,0),CFrame.new(0,1.75,0),
        CFrame.new(0,4,0),CFrame.new(0,6.25,0),CFrame.new(0,6.6,0),CFrame.new(0,7,0),
        CFrame.new(-3,2.5,6.5),CFrame.new(3,2.5,6.5),CFrame.new(0,5,6.5),CFrame.new(0,4.2,6.5),
        CFrame.new(0,9,0)*CFrame.Angles(0,0,math.rad(30)),
        CFrame.new(-1.8,2.75,0),CFrame.new(1.8,2.75,0),CFrame.new(0,2.75,-1.8),CFrame.new(0,2.75,1.8),
        CFrame.new(0,0.02,4),CFrame.new(0,0.02,4)*CFrame.Angles(0,math.rad(60),0),
        CFrame.new(0,0.02,4)*CFrame.Angles(0,math.rad(120),0),
    }
    local STRUCT_COUNT=#shrineStructOffsets;local SLASH_COUNT=6;local UNDERGROUND_Y=-600
    local shrineWallIndices={};local shrineStructParts={};local shrineSlashParts={};local slashVelocities={};local shrinePartList={}

    -- Gojo state
    local gojoSubGui=nil;local gojoActive=false;local gojoState="idle"
    local gojoOrbitAngle=0;local gojoInfinityRadius=28;local gojoInfinityAngle=0;local RED_PART_COUNT=10
    local gojoLastFire={blue=0,red=0,purple=0}
    local BLUE_CD=12;local RED_CD=4;local PURPLE_CD=6;local gojoGen=0;local blueThread=nil

    -- Mode tables
    local CFRAME_MODES={heart=true,rings=true,wall=true,box=true,gasterhand=true,gaster2hands=true,wings=true,sphere=true,spherebender=true,tank=true,car=true,de_shrine=true,gojo=true,pet=true}
    local GASTER_MODES={gasterhand=true,gaster2hands=true};local SPHERE_MODES={sphere=true}
    local SPHERE_BENDER_MODES={spherebender=true};local TANK_MODES={tank=true}
    local CAR_MODES={car=true};local SHRINE_MODES={de_shrine=true};local GOJO_MODES={gojo=true};local PET_MODES={pet=true}
    local lockedBlocks=false

    -- Pet state
    local petSubGui=nil;local petActive=false
    local petOwners={};local petOwnerList={};local petState="idle";local petOrbitDist=8
    local petDanceT=0;local petDancePhase=0;local petSplitOwners={};local petGuiUpdateFn=nil
    local petCarpetOwners={};local petAttackTarget=nil;local petAttackFired=false
    local petGuardActive=false;local petSpinSpeed=0;local petSayText=nil
    local petSphereMode=false;local petOwnerStates_global={}
    -- New pet state vars
    local petThronePos=nil;local petTornadoAngle=0
    local petRainDrops={};local petSwordSwinging=false;local petSwordSwingT=0
    -- Titanic state
    local titanicActive=false;local titanicAnchored=false
    local titanicCF=CFrame.new(0,5,0);local titanicSpd=0;local titanicTrn=0
    local titanicSinking=false;local titanicSinkT=0
    local TITAN_SPD=16;local TITAN_TRN=1.1;local TITAN_ACCEL=7;local TITAN_FRIC=0.91
    local titanicFwd=0;local titanicTurn=0

    -- Titanic part layout (local offsets, bow = -Z, stern = +Z)
    local TITANIC_OFFSETS={
        -- Bottom keel
        {v=Vector3.new(0,-5,-50)},{v=Vector3.new(0,-5,-38)},{v=Vector3.new(0,-5,-25)},
        {v=Vector3.new(0,-5,-12)},{v=Vector3.new(0,-5,0)},{v=Vector3.new(0,-5,12)},
        {v=Vector3.new(0,-5,25)},{v=Vector3.new(0,-5,38)},{v=Vector3.new(0,-5,50)},
        -- Port hull
        {v=Vector3.new(-8,0,-38)},{v=Vector3.new(-9,0,-22)},{v=Vector3.new(-9,0,-6)},
        {v=Vector3.new(-9,0,8)},{v=Vector3.new(-9,0,22)},{v=Vector3.new(-8,0,36)},
        -- Starboard hull
        {v=Vector3.new(8,0,-38)},{v=Vector3.new(9,0,-22)},{v=Vector3.new(9,0,-6)},
        {v=Vector3.new(9,0,8)},{v=Vector3.new(9,0,22)},{v=Vector3.new(8,0,36)},
        -- Red waterline
        {v=Vector3.new(-9,3,-18)},{v=Vector3.new(-9,3,0)},{v=Vector3.new(-9,3,18)},
        {v=Vector3.new(9,3,-18)},{v=Vector3.new(9,3,0)},{v=Vector3.new(9,3,18)},
        -- Bow
        {v=Vector3.new(0,0,-54)},{v=Vector3.new(-4,-2,-50)},{v=Vector3.new(4,-2,-50)},
        {v=Vector3.new(0,-7,-52)},
        -- Forecastle
        {v=Vector3.new(0,7,-42)},{v=Vector3.new(-5,7,-36)},{v=Vector3.new(5,7,-36)},
        -- Main deck
        {v=Vector3.new(0,6,-22)},{v=Vector3.new(0,6,-10)},{v=Vector3.new(0,6,2)},
        {v=Vector3.new(0,6,15)},{v=Vector3.new(0,6,28)},
        -- Superstructure
        {v=Vector3.new(0,10,-22)},{v=Vector3.new(0,10,-10)},{v=Vector3.new(0,10,2)},{v=Vector3.new(0,10,14)},
        -- Bridge
        {v=Vector3.new(0,14,-30)},{v=Vector3.new(0,18,-30)},
        -- Funnel 1
        {v=Vector3.new(0,18,-18)},{v=Vector3.new(0,26,-18)},
        -- Funnel 2
        {v=Vector3.new(0,18,-8)},{v=Vector3.new(0,26,-8)},
        -- Funnel 3
        {v=Vector3.new(0,18,2)},{v=Vector3.new(0,26,2)},
        -- Funnel 4 (shorter, dummy)
        {v=Vector3.new(0,16,12)},{v=Vector3.new(0,23,12)},
        -- Masts
        {v=Vector3.new(0,24,-44)},{v=Vector3.new(0,24,32)},
        -- Stern
        {v=Vector3.new(0,8,42)},{v=Vector3.new(0,4,50)},{v=Vector3.new(0,-2,54)},
        -- Propeller shafts
        {v=Vector3.new(-5,-5,52)},{v=Vector3.new(5,-5,52)},
        -- Port lifeboats
        {v=Vector3.new(-12,10,-24)},{v=Vector3.new(-12,10,-14)},
        {v=Vector3.new(-12,10,-4)},{v=Vector3.new(-12,10,6)},
        -- Starboard lifeboats
        {v=Vector3.new(12,10,-24)},{v=Vector3.new(12,10,-14)},
        {v=Vector3.new(12,10,-4)},{v=Vector3.new(12,10,6)},
        -- Hawse pipes
        {v=Vector3.new(-5,-1,-47)},{v=Vector3.new(5,-1,-47)},
    }
    local function getTitanicColor(idx)
        local n=idx
        if n<=9 then return Color3.fromRGB(20,20,26),Enum.Material.SmoothPlastic     -- keel: near-black
        elseif n<=21 then return Color3.fromRGB(22,22,28),Enum.Material.SmoothPlastic -- hull: black
        elseif n<=27 then return Color3.fromRGB(130,18,18),Enum.Material.SmoothPlastic -- waterline: red
        elseif n<=31 then return Color3.fromRGB(22,22,28),Enum.Material.SmoothPlastic  -- bow
        elseif n<=34 then return Color3.fromRGB(200,195,185),Enum.Material.SmoothPlastic -- forecastle
        elseif n<=39 then return Color3.fromRGB(175,158,130),Enum.Material.SmoothPlastic -- deck
        elseif n<=43 then return Color3.fromRGB(238,235,228),Enum.Material.SmoothPlastic -- superstructure
        elseif n<=45 then return Color3.fromRGB(228,225,218),Enum.Material.SmoothPlastic -- bridge
        elseif n<=50 then return n%2==0 and Color3.fromRGB(18,16,16) or Color3.fromRGB(200,150,80),Enum.Material.SmoothPlastic -- funnels
        elseif n<=52 then return Color3.fromRGB(200,200,200),Enum.Material.SmoothPlastic -- masts
        elseif n<=55 then return Color3.fromRGB(175,158,130),Enum.Material.SmoothPlastic -- stern
        elseif n<=57 then return Color3.fromRGB(50,40,35),Enum.Material.SmoothPlastic   -- props
        elseif n<=65 then return Color3.fromRGB(238,228,178),Enum.Material.SmoothPlastic -- lifeboats
        else return Color3.fromRGB(22,22,28),Enum.Material.SmoothPlastic end
    end

    -- Pixel font 5x7
    local PF={
        A={"01110","10001","10001","11111","10001","10001","10001"},B={"11110","10001","10001","11110","10001","10001","11110"},
        C={"01110","10001","10000","10000","10000","10001","01110"},D={"11100","10010","10001","10001","10001","10010","11100"},
        E={"11111","10000","10000","11110","10000","10000","11111"},F={"11111","10000","10000","11110","10000","10000","10000"},
        G={"01110","10001","10000","10111","10001","10001","01110"},H={"10001","10001","10001","11111","10001","10001","10001"},
        I={"01110","00100","00100","00100","00100","00100","01110"},J={"00111","00010","00010","00010","00010","10010","01100"},
        K={"10001","10010","10100","11000","10100","10010","10001"},L={"10000","10000","10000","10000","10000","10000","11111"},
        M={"10001","11011","10101","10001","10001","10001","10001"},N={"10001","11001","10101","10011","10001","10001","10001"},
        O={"01110","10001","10001","10001","10001","10001","01110"},P={"11110","10001","10001","11110","10000","10000","10000"},
        Q={"01110","10001","10001","10001","10101","10010","01101"},R={"11110","10001","10001","11110","10100","10010","10001"},
        S={"01111","10000","10000","01110","00001","00001","11110"},T={"11111","00100","00100","00100","00100","00100","00100"},
        U={"10001","10001","10001","10001","10001","10001","01110"},V={"10001","10001","10001","10001","10001","01010","00100"},
        W={"10001","10001","10001","10101","10101","11011","10001"},X={"10001","10001","01010","00100","01010","10001","10001"},
        Y={"10001","10001","01010","00100","00100","00100","00100"},Z={"11111","00001","00010","00100","01000","10000","11111"},
        ["0"]={"01110","10001","10011","10101","11001","10001","01110"},["1"]={"00100","01100","00100","00100","00100","00100","01110"},
        ["2"]={"01110","10001","00001","00010","00100","01000","11111"},["3"]={"11111","00001","00010","00110","00001","10001","01110"},
        ["4"]={"00010","00110","01010","10010","11111","00010","00010"},["5"]={"11111","10000","11110","00001","00001","10001","01110"},
        ["6"]={"00110","01000","10000","11110","10001","10001","01110"},["7"]={"11111","00001","00010","00100","01000","01000","01000"},
        ["8"]={"01110","10001","10001","01110","10001","10001","01110"},["9"]={"01110","10001","10001","01111","00001","00010","01100"},
        ["!"]={"00100","00100","00100","00100","00000","00000","00100"},["?"]={"01110","10001","00001","00110","00100","00000","00100"},
    }
    local function getTextPositions(text,origin,cf)
        local positions={};local xOff=0
        for i=1,#text do
            local ch=text:sub(i,i):upper();local pat=PF[ch]
            if pat then
                for row,line in ipairs(pat) do
                    for col=1,#line do
                        if line:sub(col,col)=="1" then
                            table.insert(positions,origin+cf.RightVector*(xOff+col)*1.3+cf.UpVector*(8-row)*1.3)
                        end
                    end
                end
                xOff=xOff+6
            else xOff=xOff+4 end
        end
        return positions
    end

    local function findPlayer(query)
        if not query or #query<1 then return nil end
        local q=query:lower()
        for _,p in ipairs(Players:GetPlayers())do if p.Name:lower()==q or p.DisplayName:lower()==q then return p end end
        local matches={}
        for _,p in ipairs(Players:GetPlayers())do if p.Name:lower():sub(1,#q)==q or p.DisplayName:lower():sub(1,#q)==q then table.insert(matches,p)end end
        if #matches==1 then return matches[1] end
        for _,p in ipairs(Players:GetPlayers())do if p.Name:lower():find(q,1,true) or p.DisplayName:lower():find(q,1,true) then return p end end
        return nil
    end

    -- Hand/Wing definitions
    local HAND_SCALE=2.8
    local HAND_SLOTS={{x=-4,y=5},{x=-4,y=4},{x=-4,y=3},{x=-4,y=2},{x=-2,y=6},{x=-2,y=5},{x=-2,y=4},{x=-2,y=3},{x=0,y=7},{x=0,y=6},{x=0,y=5},{x=0,y=4},{x=0,y=3},{x=2,y=6},{x=2,y=5},{x=2,y=4},{x=2,y=3},{x=5,y=2},{x=5,y=1},{x=5,y=0},{x=-4,y=1},{x=-2,y=1},{x=0,y=1},{x=2,y=1},{x=-4,y=0},{x=-2,y=0},{x=0,y=0},{x=2,y=0},{x=4,y=0},{x=-2,y=-1},{x=0,y=-1},{x=2,y=-1}}
    local PALM_SLOTS={{x=-3,y=2},{x=-1,y=2},{x=1,y=2},{x=3,y=2},{x=-3,y=1},{x=-1,y=1},{x=1,y=1},{x=3,y=1},{x=-3,y=0},{x=-1,y=0},{x=1,y=0},{x=3,y=0},{x=-2,y=-1},{x=0,y=-1},{x=2,y=-1},{x=-2,y=-2},{x=0,y=-2},{x=2,y=-2}}
    local ALL_HAND_SLOTS={}
    for _,s in ipairs(HAND_SLOTS)do table.insert(ALL_HAND_SLOTS,{x=s.x,y=s.y,isPalm=false})end
    for _,s in ipairs(PALM_SLOTS)do table.insert(ALL_HAND_SLOTS,{x=s.x,y=s.y,isPalm=true})end
    local HAND_SLOTS_COUNT=#ALL_HAND_SLOTS
    local POINTING_BIAS={[1]=-5,[2]=-5,[3]=-5,[4]=-5,[5]=-4.5,[6]=-4.5,[7]=-4.5,[8]=-4.5,[9]=-5.5,[10]=-5,[11]=-4,[12]=-2.5,[13]=-1.2,[18]=-0.6,[19]=-1.2,[20]=-1.2}
    local PUNCH_BIAS={[1]=-3,[2]=-2.5,[3]=-1.5,[4]=-0.5,[5]=-3,[6]=-2.5,[7]=-1.5,[8]=-0.5,[9]=-3.5,[10]=-3,[11]=-2,[12]=-1,[13]=-0.3,[14]=-3,[15]=-2.5,[16]=-1.5,[17]=-0.5,[18]=-0.8,[19]=-1.4,[20]=-1.4}
    local HAND_RIGHT=Vector3.new(9,2,1);local HAND_LEFT=Vector3.new(-9,2,1)
    local WING_POINTS={};local WING_SR=Vector3.new(1,1.8,0.6);local WING_SL=Vector3.new(-1,1.8,0.6)
    local WING_OA=math.rad(82);local WING_CA=math.rad(22);local WING_FS=1.8;local WING_SPAN=14
    for _,f in ipairs({{0.15,2.2,0.4},{0.28,2.8,0.5},{0.4,3,0.6},{0.52,2.8,0.6},{0.63,2.2,0.5},{0.73,1.2,0.4},{0.82,-0.2,0.3},{0.9,-1.8,0.2},{0.97,-3.5,0.1}})do for seg=1,4 do local t2=(seg-1)/3;table.insert(WING_POINTS,{outX=f[1]*WING_SPAN+t2*0.6,upY=f[2]-t2*2,backZ=f[3]+t2*0.2,layer=1})end end
    for _,f in ipairs({{0.12,3.5,0.6},{0.22,4.4,0.7},{0.33,5,0.8},{0.44,5,0.8},{0.54,4.4,0.7},{0.62,3.4,0.6}})do for seg=1,3 do local t2=(seg-1)/2;table.insert(WING_POINTS,{outX=f[1]*WING_SPAN+t2*0.4,upY=f[2]-t2*1.2,backZ=f[3],layer=2})end end
    for _,f in ipairs({{0.04,1.5,0.5},{0.08,2.2,0.6},{0.12,2.8,0.7},{0.18,3,0.7},{0.04,0.6,0.5},{0.08,1,0.6},{0.14,1.2,0.6},{0.2,1,0.5}})do table.insert(WING_POINTS,{outX=f[1]*WING_SPAN,upY=f[2],backZ=f[3],layer=3})end
    local WING_POINT_COUNT=#WING_POINTS

    local controlled={};local partCount=0
    local sweepMap,fullSweep,rebuildSBGui
    local destroyTank,destroyTankGui,destroyCar,destroyCarGui
    local destroyShrine,destroyShrineGui,destroyGojo,destroyGojoGui
    local destroyPet,destroyPetGui

    local function isValid(obj)
        if not obj then return false end
        local ok=pcall(function()if not obj.Parent then error()end end)
        if not ok or not obj.Parent then return false end
        if not obj:IsA("BasePart")then return false end
        if obj.Anchored then return false end
        if obj.Size.Magnitude<0.2 then return false end
        if obj.Transparency>=1 then return false end
        local p=obj.Parent
        while p and p~=workspace do if p:FindFirstChildOfClass("Humanoid")then return false end;p=p.Parent end
        return true
    end

    local function applyStrengthToAll()
        local p=math.max(1,pullStrength);local d=math.max(50,p*0.05)
        for _,data in pairs(controlled)do
            pcall(function()
                if data.bp and data.bp.Parent then data.bp.P=p;data.bp.D=d;data.bp.MaxForce=Vector3.new(1e9,1e9,1e9)end
                if data.bg and data.bg.Parent then data.bg.P=p;data.bg.D=d;data.bg.MaxTorque=Vector3.new(1e9,1e9,1e9)end
            end)
        end
    end

    local function grabPart(part)
        if controlled[part]then return end
        if not isValid(part)then return end
        local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local effectiveRange=(pullStrength>=5000) and math.huge or detectionRange
        if root and(part.Position-root.Position).Magnitude>effectiveRange then return end
        local origCC=part.CanCollide;local origAnch=part.Anchored
        local origMassless=part.Massless;local origPhysProps=part.CustomPhysicalProperties
        pcall(function()part.CanCollide=false end)
        pcall(function()part:SetNetworkOwner(player)end)
        pcall(function()part.CustomPhysicalProperties=PhysicalProperties.new(0.01,0.3,0.5,1,1);part.Massless=true end)
        local bp=Instance.new("BodyPosition");bp.MaxForce=Vector3.new(1e9,1e9,1e9);bp.P=300000;bp.D=8000;bp.Position=part.Position;bp.Parent=part
        local bg=Instance.new("BodyGyro");bg.MaxTorque=Vector3.new(1e9,1e9,1e9);bg.P=300000;bg.D=8000;bg.CFrame=part.CFrame;bg.Parent=part
        controlled[part]={origCC=origCC,origAnch=origAnch,bp=bp,bg=bg,origColor=part.Color,origMaterial=part.Material,origMassless=origMassless,origPhysProps=origPhysProps}
        partCount=partCount+1
    end

    local function releasePart(part,data)
        pcall(function()
            if data.bp and data.bp.Parent then data.bp:Destroy()end
            if data.bg and data.bg.Parent then data.bg:Destroy()end
        end)
        if part and part.Parent then
            pcall(function()
                part.CanCollide=data.origCC;part.Anchored=data.origAnch or false
                if data.origColor then part.Color=data.origColor end
                if data.origMaterial then part.Material=data.origMaterial end
                part.Massless=data.origMassless or false
                if data.origPhysProps then part.CustomPhysicalProperties=data.origPhysProps end
            end)
        end
    end

    local function stripMotors(part)
        if not(part and part.Parent)then return end
        for _,child in ipairs(part:GetChildren())do
            if child:IsA("BodyPosition") or child:IsA("BodyGyro")then pcall(function()child:Destroy()end)end
        end
        if controlled[part]then controlled[part].bp=nil;controlled[part].bg=nil end
    end

    local function releaseAll()
        for part,data in pairs(controlled)do releasePart(part,data)end
        controlled={};partCount=0;snakeT=0;snakeHistory={}
        if tankActive then pcall(destroyTank);pcall(destroyTankGui)end
        if carActive then pcall(destroyCar);pcall(destroyCarGui)end
        if shrineActive then pcall(destroyShrine);pcall(destroyShrineGui)end
        if gojoActive then pcall(destroyGojo);pcall(destroyGojoGui)end
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
    end

    sweepMap=function()
        for _,obj in ipairs(workspace:GetDescendants())do
            if isValid(obj) and not controlled[obj]then grabPart(obj)end
        end
    end

    fullSweep=function()
        for _,obj in ipairs(workspace:GetDescendants())do
            if isValid(obj) and not controlled[obj]then
                local origCC=obj.CanCollide;local origAnch=obj.Anchored
                local origMassless=obj.Massless;local origPhysProps=obj.CustomPhysicalProperties
                pcall(function()obj.CanCollide=false end)
                pcall(function()obj:SetNetworkOwner(player)end)
                pcall(function()obj.CustomPhysicalProperties=PhysicalProperties.new(0.01,0.3,0.5,1,1);obj.Massless=true end)
                local bp=Instance.new("BodyPosition");bp.MaxForce=Vector3.new(1e9,1e9,1e9);bp.P=300000;bp.D=8000;bp.Position=obj.Position;bp.Parent=obj
                local bg=Instance.new("BodyGyro");bg.MaxTorque=Vector3.new(1e9,1e9,1e9);bg.P=300000;bg.D=8000;bg.CFrame=obj.CFrame;bg.Parent=obj
                controlled[obj]={origCC=origCC,origAnch=origAnch,bp=bp,bg=bg,origColor=obj.Color,origMaterial=obj.Material,origMassless=origMassless,origPhysProps=origPhysProps}
                partCount=partCount+1
            elseif controlled[obj]then
                pcall(function()obj:SetNetworkOwner(player)end)
            end
        end
    end

    -- v17: Detect & pull - grabs EVERY unanchored block then pulls toward any owner
    local function detectAndPull()
        local char=player.Character
        local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local rootPos=root and root.Position or Vector3.new(0,5,0)
        fullSweep()
        isActivated=true
        local ownerRoots={}
        if #petOwnerList>0 then
            for _,oname in ipairs(petOwnerList)do
                local p2=findPlayer(oname);local char2=p2 and p2.Character
                local r2=char2 and(char2:FindFirstChild("HumanoidRootPart") or char2:FindFirstChild("Torso"))
                if r2 then table.insert(ownerRoots,r2.Position) end
            end
        end
        if #ownerRoots==0 then table.insert(ownerRoots,rootPos) end
        local i=0
        for part,data in pairs(controlled)do
            if part and part.Parent and data.bp and data.bp.Parent then
                local ownerPos=ownerRoots[(i%#ownerRoots)+1]
                local phi=(1+math.sqrt(5))/2
                local theta=math.acos(math.clamp(1-2*(i+0.5)/math.max(partCount,1),-1,1))
                local ang=2*math.pi*i/phi
                local r=math.max(radius,5)
                data.bp.P=900000;data.bp.D=35000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                data.bp.Position=ownerPos+Vector3.new(r*math.sin(theta)*math.cos(ang),r*math.sin(theta)*math.sin(ang)+1,r*math.cos(theta))
                i=i+1
            end
        end
    end

    local function lockAllNow()
        for part,data in pairs(controlled)do
            if part and part.Parent then
            pcall(function()
                part.CanCollide=false
                part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero
                if not(data.bp and data.bp.Parent)then
                    local bp=Instance.new("BodyPosition");bp.MaxForce=Vector3.new(1e15,1e15,1e15);bp.P=3000000;bp.D=50000;bp.Position=part.Position;bp.Parent=part;data.bp=bp
                else data.bp.MaxForce=Vector3.new(1e15,1e15,1e15);data.bp.P=3000000;data.bp.D=50000 end
                if not(data.bg and data.bg.Parent)then
                    local bg=Instance.new("BodyGyro");bg.MaxTorque=Vector3.new(1e15,1e15,1e15);bg.P=500000;bg.D=50000;bg.CFrame=part.CFrame;bg.Parent=part;data.bg=bg
                else data.bg.MaxTorque=Vector3.new(1e15,1e15,1e15);data.bg.P=500000;data.bg.D=50000 end
            end)
            end
        end
    end

    -- Helpers
    local function getAimPoint(dist)
        local char=player.Character
        local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if not root then local cam=workspace.CurrentCamera;return cam.CFrame.Position+cam.CFrame.LookVector*(dist or 30),cam.CFrame.LookVector end
        return root.Position+root.CFrame.LookVector*(dist or 30),root.CFrame.LookVector
    end
    local function getSnakeTarget(i)
        local idx=math.clamp(i*SNAKE_GAP,1,math.max(1,#snakeHistory))
        return snakeHistory[idx] or snakeHistory[#snakeHistory] or Vector3.zero
    end
    local function getWingCF(ptIdx,side,cf,t)
        local wp=WING_POINTS[ptIdx];if not wp then return CFrame.new(0,-5000,0)end
        local fa=WING_CA+(((math.sin(t*WING_FS*math.pi)+1)/2))*(WING_OA-WING_CA);local cosA,sinA=math.cos(fa),math.sin(fa)
        local rotX=(wp.outX*cosA-wp.backZ*sinA)*side;local sh=(side==1)and WING_SR or WING_SL
        return CFrame.new(cf:PointToWorldSpace(Vector3.new(sh.X+rotX,sh.Y+wp.upY,sh.Z+wp.outX*sinA+wp.backZ*cosA+0.5)))
    end
    local function getSphereShellPos(index,total)
        local phi=(1+math.sqrt(5))/2;local i=index-1;local s=math.max(total,1)
        local theta=math.acos(math.clamp(1-2*(i+0.5)/s,-1,1));local ang=2*math.pi*i/phi
        local r=0.8*(1+math.floor(i/12)*0.5)
        return Vector3.new(r*math.sin(theta)*math.cos(ang),r*math.sin(theta)*math.sin(ang),r*math.cos(theta))
    end
    local function updateSphereTarget(dt,rootPos)
        if sphereMode=="orbit" then
            sphereOrbitAngle=sphereOrbitAngle+dt*SPHERE_SPEED
            local tgt=rootPos+Vector3.new(math.cos(sphereOrbitAngle)*SPHERE_RADIUS,1.5,math.sin(sphereOrbitAngle)*SPHERE_RADIUS)
            sphereVel=sphereVel+(tgt-spherePos)*(SPHERE_SPRING*dt);sphereVel=sphereVel*(1-SPHERE_DAMP*dt);spherePos=spherePos+sphereVel*dt
        elseif sphereMode=="follow" then
            local b=rootPos+Vector3.new(0,1.5,4);local d=b-spherePos;local dist=d.Magnitude
            if dist>3 then sphereVel=sphereVel+d.Unit*(dist-3)*SPHERE_SPRING*dt end
            sphereVel=sphereVel*(1-SPHERE_DAMP*dt);spherePos=spherePos+sphereVel*dt
        else sphereVel=sphereVel*(1-SPHERE_DAMP*2*dt);spherePos=spherePos+sphereVel*dt end
    end
    local function updateSphereBenderTargets(dt,rootPos)
        for _,sp in ipairs(sbSpheres)do
            if sp.stopped then sp.vel=Vector3.zero
            elseif sp.mode=="orbit" then
                sp.orbitAngle=sp.orbitAngle+dt*SPHERE_SPEED
                local tgt=rootPos+Vector3.new(math.cos(sp.orbitAngle)*SPHERE_RADIUS,1.5,math.sin(sp.orbitAngle)*SPHERE_RADIUS)
                sp.vel=sp.vel+(tgt-sp.pos)*(SPHERE_SPRING*dt);sp.vel=sp.vel*(1-SPHERE_DAMP*dt);sp.pos=sp.pos+sp.vel*dt
            elseif sp.mode=="follow" then
                local b=rootPos+Vector3.new(0,1.5,4);local d=b-sp.pos;local dist=d.Magnitude
                if dist>3 then sp.vel=sp.vel+d.Unit*(dist-3)*SPHERE_SPRING*dt end
                sp.vel=sp.vel*(1-SPHERE_DAMP*dt);sp.pos=sp.pos+sp.vel*dt
            else sp.vel=sp.vel*(1-SPHERE_DAMP*2*dt);sp.pos=sp.pos+sp.vel*dt end
        end
    end
    local function getFormationCF(mode,i,n,origin,cf,t)
        if mode=="heart" then
            local a=((i-1)/math.max(n,1))*math.pi*2;local hx=16*math.sin(a)^3;local hz=-(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))
            return CFrame.new(origin+cf:VectorToWorldSpace(Vector3.new(hx*(radius/16),0,hz*(radius/16))))
        elseif mode=="rings" then
            local a=((i-1)/math.max(n,1))*math.pi*2+t*1.4;return CFrame.new(origin+Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius))
        elseif mode=="wall" then
            local cols=math.max(1,math.ceil(math.sqrt(n)));return CFrame.new(origin+cf.LookVector*radius+cf.RightVector*(((i-1)%cols-math.floor(cols/2))*1.8)+cf.UpVector*((math.floor((i-1)/cols)-1)*1.8+1))
        elseif mode=="box" then
            local fV={cf.LookVector,-cf.LookVector,cf.RightVector,-cf.RightVector,cf.UpVector,-cf.UpVector}
            local fA={cf.RightVector,cf.RightVector,cf.LookVector,cf.LookVector,cf.RightVector,cf.RightVector}
            local fB={cf.UpVector,cf.UpVector,cf.UpVector,cf.UpVector,cf.LookVector,cf.LookVector}
            local fi=((i-1)%6)+1;local si=math.floor((i-1)/6);local sp=radius*0.45
            return CFrame.new(origin+fV[fi]*radius+fA[fi]*((si%2-0.5)*sp)+fB[fi]*(math.floor(si/2)-0.5)*sp)
        elseif mode=="wings" then
            local half=math.ceil(n/2);local side,ptIdx=1,i
            if i>half then side=-1;ptIdx=i-half end
            return getWingCF(((ptIdx-1)%WING_POINT_COUNT)+1,side,cf,t)
        end
        return CFrame.new(origin)
    end
    local function getGasterCF(slotIdx,side,cf,gt)
        local slot=ALL_HAND_SLOTS[slotIdx];if not slot then return CFrame.new(0,-5000,0)end
        local sx=slot.x*HAND_SCALE;local sy=slot.y*HAND_SCALE;local floatY=math.sin(gt*2+side*1.2)*1
        if not slot.isPalm then
            if gasterAnim=="pointing" then sy=sy+(POINTING_BIAS[slotIdx] or 0)*HAND_SCALE
            elseif gasterAnim=="punching" then sy=sy+(PUNCH_BIAS[slotIdx] or 0)*HAND_SCALE end
        end
        local waveAng=(gasterAnim=="waving") and math.sin(gt*2.2)*0.5 or 0
        local punchZ=(gasterAnim=="punching" and not slot.isPalm) and(math.sin(gt*10)*0.5+0.5)*8 or 0
        local base=(side==1)and HAND_RIGHT or HAND_LEFT;local palmOff=slot.isPalm and 1.5 or 0
        return CFrame.new(cf:PointToWorldSpace(Vector3.new(base.X+sx*math.cos(waveAng)*side,base.Y+sy+floatY,base.Z+sx*math.sin(waveAng)-punchZ+palmOff)))
    end
    local function colorParts(parts,col,mat)
        for _,part in ipairs(parts)do pcall(function()if part and part.Parent then part.Color=col;part.Material=mat or Enum.Material.Neon end end)end
    end
    local function colorAllControlled(col,mat)
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
    local function firePartVelocity(part,velocity)
        local data=controlled[part];if not data then return end
        pcall(function()
            if data.bp and data.bp.Parent then data.bp:Destroy();data.bp=nil end
            if data.bg and data.bg.Parent then data.bg:Destroy();data.bg=nil end
        end)
        pcall(function()
            for _,ch in ipairs(part:GetChildren())do if ch:IsA("BodyVelocity")then ch:Destroy()end end
            local bv=Instance.new("BodyVelocity");bv.MaxForce=Vector3.new(1e12,1e12,1e12);bv.Velocity=velocity;bv.Parent=part;Debris:AddItem(bv,6)
        end)
    end
    local function addFlingOnTouch(part)
        if not(part and part.Parent)then return end
        local conn;local fired=false
        conn=part.Touched:Connect(function(hit)
            if fired or not hit or not hit.Parent then return end
            local hitHum=hit.Parent:FindFirstChildOfClass("Humanoid")
            if not hitHum or hitHum.Health<=0 then return end
            local myChar=player.Character
            if myChar and hit:IsDescendantOf(myChar)then return end
            fired=true;pcall(function()conn:Disconnect()end)
            pcall(function()local ex=Instance.new("Explosion");ex.Position=part.Position;ex.BlastRadius=8;ex.BlastPressure=800000;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace end)
        end)
        task.delay(10,function()pcall(function()conn:Disconnect()end)end)
    end

    -- ════ TANK ════
    local function buildTankFromParts(position,cf)
        local pl={}
        for part,_ in pairs(controlled)do if part and part.Parent then table.insert(pl,part)end end
        if #pl<25 then sweepMap();task.wait(0.3);pl={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(pl,part)end end;if #pl<25 then return false end end
        table.sort(pl,function(a,b)return a.Size.Magnitude>b.Size.Magnitude end)
        tks.tankParts={};tks.partOffsets={};tks.turretPartIdx=nil;tks.barrelPartIdx=nil
        local idx=1
        local hull=pl[idx];hull.CFrame=cf*CFrame.new(0,TANK_H/2,0)
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
        if pl[idx] and tBase then local tb=pl[idx];local off=CFrame.new(0,TANK_H/2+2,0);tb.CFrame=hull.CFrame*off;tks.turretPart=tb;tks.turretPartIdx=idx;tks.tankParts[idx]=tb;tks.partOffsets[idx]=off;idx=idx+1 end
        if pl[idx] and tks.turretPart then local off=CFrame.new(-2.5,0,0);pl[idx].CFrame=tks.turretPart.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end
        if pl[idx] and tks.turretPart then local off=CFrame.new(2.5,0,0);pl[idx].CFrame=tks.turretPart.CFrame*off;tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end
        if pl[idx] and tks.turretPart then local off=CFrame.new(0,1.5,-0.5);pl[idx].CFrame=tks.turretPart.CFrame*off;tks.tankHatch=pl[idx];tks.tankParts[idx]=pl[idx];tks.partOffsets[idx]=off;idx=idx+1 end
        for i=idx,math.min(idx+6,#pl)do
            if pl[i] and tks.turretPart and pl[i].Size.Z>pl[i].Size.X and pl[i].Size.Z>pl[i].Size.Y then
                local off=CFrame.new(0,0.3,5.5);pl[i].CFrame=tks.turretPart.CFrame*off;tks.barrelPart=pl[i];tks.barrelPartIdx=i;tks.tankParts[i]=pl[i];tks.partOffsets[i]=off;break
            end
        end
        local filterList={}
        for _,part in ipairs(tks.tankParts)do if part and part.Parent then stripMotors(part);table.insert(filterList,part)end end
        tankRayParams.FilterDescendantsInstances=filterList;frozenTankCF=nil;return true
    end
    destroyTank=function()
        if tks.tankBase then pcall(function()local e=Instance.new("Explosion");e.Position=tks.tankBase.Position;e.BlastRadius=15;e.BlastPressure=300000;e.Parent=workspace end)end
        for _,part in ipairs(tks.tankParts)do if part and part.Parent and controlled[part]then releasePart(part,controlled[part]);controlled[part]=nil;partCount=math.max(0,partCount-1)end end
        tks={forward=0,turn=0,hatchOpen=false,insideTank=false,tankBase=nil,turretPart=nil,barrelPart=nil,turretPartIdx=nil,barrelPartIdx=nil,tankParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0,tankHatch=nil}
        frozenTankCF=nil;tankActive=false;cameraOrbitAngle=0;cameraPitchAngle=math.rad(25)
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        local char=player.Character;if char then
            local hrp=char:FindFirstChild("HumanoidRootPart");local hum=char:FindFirstChildOfClass("Humanoid")
            if hrp then hrp.Anchored=false end
            if hum then hum.WalkSpeed=savedWS;hum.JumpPower=savedJP;hum.AutoRotate=savedAR end
            for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=true end)end end
        end
    end
    local function shootProjectile()
        if not tankActive or not tks.barrelPart or not tks.insideTank then return end
        local now=tick();if now-lastShot<SHOOT_CD then return end;lastShot=now
        local shell=Instance.new("Part");shell.Name="TankShell";shell.Size=Vector3.new(0.35,0.35,2);shell.BrickColor=BrickColor.new("Dark grey metallic");shell.Material=Enum.Material.Metal;shell.CanCollide=true;shell.CastShadow=false
        local barrelCF=tks.barrelPart.CFrame;shell.CFrame=barrelCF*CFrame.new(0,0,tks.barrelPart.Size.Z/2+1.2);shell.Parent=workspace
        local arcDir=barrelCF.LookVector;pcall(function()shell.AssemblyLinearVelocity=arcDir*PROJ_SPEED end)
        local hitConn;hitConn=shell.Touched:Connect(function(hit)
            if hit==tks.barrelPart or hit==tks.turretPart then return end
            local c2=player.Character;if c2 and hit:IsDescendantOf(c2)then return end
            pcall(function()local ex=Instance.new("Explosion");ex.Position=shell.Position;ex.BlastRadius=10;ex.BlastPressure=150000;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace end)
            hitConn:Disconnect();pcall(function()shell:Destroy()end)
        end);Debris:AddItem(shell,12)
    end
    local function toggleHatch()
        if not tks.tankBase then return end
        if not tks.hatchOpen then
            tks.hatchOpen=true;tks.insideTank=false;frozenTankCF=tks.tankBase.CFrame
            if tks.tankHatch then pcall(function()tks.tankHatch.CFrame=tks.tankHatch.CFrame*CFrame.new(0,2.5,0)*CFrame.Angles(math.rad(65),0,0)end)end
            local char=player.Character;if char then
                local hrp=char:FindFirstChild("HumanoidRootPart");local hum=char:FindFirstChildOfClass("Humanoid")
                if hrp then hrp.Anchored=false;hrp.CFrame=tks.tankBase.CFrame*CFrame.new(0,TANK_H+4,0)end
                if hum then hum.WalkSpeed=savedWS;hum.JumpPower=savedJP;hum.AutoRotate=savedAR end
                for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=true end)end end
            end
            pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        else
            tks.hatchOpen=false;tks.insideTank=true;frozenTankCF=nil
            if tks.tankHatch then pcall(function()tks.tankHatch.CFrame=tks.tankHatch.CFrame*CFrame.Angles(math.rad(-65),0,0)*CFrame.new(0,-2.5,0)end)end
            local char=player.Character;if char then
                local hrp=char:FindFirstChild("HumanoidRootPart");local hum=char:FindFirstChildOfClass("Humanoid")
                if hrp then hrp.Anchored=true;hrp.CFrame=tks.tankBase.CFrame*CFrame.new(0,TANK_INTERIOR_Y,0)end
                if hum then hum.WalkSpeed=0;hum.JumpPower=0 end
                for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=false end)end end
            end
        end
    end

    -- ════ CAR ════
    local function buildCarFromParts(position,cf)
        local pl={}
        for part,_ in pairs(controlled)do if part and part.Parent then table.insert(pl,part)end end
        if #pl<8 then sweepMap();task.wait(0.3);pl={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(pl,part)end end;if #pl<8 then return false end end
        table.sort(pl,function(a,b)return a.Size.Magnitude>b.Size.Magnitude end)
        cs.carParts={};cs.partOffsets={};cs.carBase=nil;cs.carDoor=nil
        local idx=1
        local hull=pl[idx];hull.CFrame=cf*CFrame.new(0,CAR_H/2,0);cs.carBase=hull;cs.carParts[idx]=hull;cs.partOffsets[idx]=CFrame.new(0,CAR_H/2,0);idx=idx+1
        local wheelOffsets={CFrame.new(-3,-CAR_H/2,-3.5),CFrame.new(3,-CAR_H/2,-3.5),CFrame.new(-3,-CAR_H/2,3.5),CFrame.new(3,-CAR_H/2,3.5)}
        for _,off in ipairs(wheelOffsets)do if pl[idx]then pl[idx].CFrame=hull.CFrame*off;cs.carParts[idx]=pl[idx];cs.partOffsets[idx]=off;idx=idx+1 end end
        if pl[idx]then local off=CFrame.new(0,CAR_H/2+0.5,0);pl[idx].CFrame=hull.CFrame*off;cs.carParts[idx]=pl[idx];cs.partOffsets[idx]=off;idx=idx+1 end
        if pl[idx]then local off=CFrame.new(-3.5,0.3,0);pl[idx].CFrame=hull.CFrame*off;cs.carDoor=pl[idx];cs.carParts[idx]=pl[idx];cs.partOffsets[idx]=off;idx=idx+1 end
        local filterList={}
        for _,part in ipairs(cs.carParts)do if part and part.Parent then stripMotors(part);table.insert(filterList,part)end end
        carRayParams.FilterDescendantsInstances=filterList;frozenCarCF=nil;return true
    end
    destroyCar=function()
        for _,part in ipairs(cs.carParts)do if part and part.Parent and controlled[part]then releasePart(part,controlled[part]);controlled[part]=nil;partCount=math.max(0,partCount-1)end end
        cs={doorOpen=false,carBase=nil,carDoor=nil,carParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0}
        frozenCarCF=nil;carActive=false
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        local char=player.Character;if char then
            local hrp=char:FindFirstChild("HumanoidRootPart");local hum=char:FindFirstChildOfClass("Humanoid")
            if hrp then hrp.Anchored=false end
            if hum then hum.WalkSpeed=savedWS;hum.JumpPower=savedJP;hum.AutoRotate=savedAR end
            for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=true end)end end
        end
    end
    local function toggleCarDoor()
        if not cs.carBase then return end
        if not cs.doorOpen then
            cs.doorOpen=true;frozenCarCF=cs.carBase.CFrame
            if cs.carDoor then pcall(function()cs.carDoor.CFrame=cs.carDoor.CFrame*CFrame.Angles(0,math.rad(-80),0)end)end
            local char=player.Character;if char then
                local hrp=char:FindFirstChild("HumanoidRootPart");local hum=char:FindFirstChildOfClass("Humanoid")
                if hrp then hrp.Anchored=false;hrp.CFrame=cs.carBase.CFrame*CFrame.new(-5,CAR_INTERIOR_Y,0)end
                if hum then hum.WalkSpeed=savedWS;hum.JumpPower=savedJP;hum.AutoRotate=savedAR end
                for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=true end)end end
            end
            pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        else
            cs.doorOpen=false;frozenCarCF=nil
            if cs.carDoor then pcall(function()cs.carDoor.CFrame=cs.carDoor.CFrame*CFrame.Angles(0,math.rad(80),0)end)end
            local char=player.Character;if char then
                local hrp=char:FindFirstChild("HumanoidRootPart");local hum=char:FindFirstChildOfClass("Humanoid")
                if hrp then hrp.Anchored=true;hrp.CFrame=cs.carBase.CFrame*CFrame.new(0,CAR_INTERIOR_Y,0)end
                if hum then hum.WalkSpeed=0;hum.JumpPower=0 end
                for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then pcall(function()p.CanCollide=false end)end end
            end
        end
    end

    -- ════ DE SHRINE ════
    local function assignShrineParts()
        shrinePartList={}
        for part,_ in pairs(controlled)do if part and part.Parent then table.insert(shrinePartList,part)end end
        table.sort(shrinePartList,function(a,b)return a.Size.Magnitude>b.Size.Magnitude end)
        shrineStructParts={};shrineSlashParts={};shrineWallIndices={}
        for i,part in ipairs(shrinePartList)do
            if i<=STRUCT_COUNT then table.insert(shrineStructParts,part)
            elseif i<=STRUCT_COUNT+SLASH_COUNT then table.insert(shrineSlashParts,part)
            else table.insert(shrineWallIndices,i)end
        end
    end
    local function setUnderground(part,idx)
        local data=controlled[part];if not data then return end
        if data.bp and data.bp.Parent then data.bp.P=500000;data.bp.D=30000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12);data.bp.Position=Vector3.new(shrineCenter.X+(idx%20)*3,UNDERGROUND_Y,shrineCenter.Z+math.floor(idx/20)*3)end
        if data.bg and data.bg.Parent then data.bg.P=80000;data.bg.D=4000;data.bg.CFrame=CFrame.new(shrineCenter.X+(idx%20)*3,UNDERGROUND_Y,shrineCenter.Z+math.floor(idx/20)*3)end
    end
    local function getSphereWallCF(idx,total)
        local phi=(1+math.sqrt(5))/2;local i=idx-1;local s=math.max(total,1)
        local theta=math.acos(math.clamp(1-2*(i+0.5)/s,-1,1));local ang=2*math.pi*i/phi;local r=DOMAIN_RADIUS
        return Vector3.new(shrineCenter.X+r*math.sin(theta)*math.cos(ang),shrineCenter.Y+r*math.sin(theta)*math.sin(ang),shrineCenter.Z+r*math.cos(theta))
    end
    local function activateSlashes()
        for i,part in ipairs(shrineSlashParts)do
            if part and part.Parent then
                pcall(function()
                    part.CanCollide=true;part.Color=Color3.fromRGB(255,200,50);part.Material=Enum.Material.Neon
                    for _,ch in ipairs(part:GetChildren())do if ch:IsA("BodyVelocity") or ch:IsA("BodyPosition")then ch:Destroy()end end
                    local startAng=((i-1)/math.max(#shrineSlashParts,1))*math.pi*2
                    local dir=Vector3.new(math.cos(startAng),0,math.sin(startAng))
                    local bv=Instance.new("BodyVelocity");bv.MaxForce=Vector3.new(1e9,1e9,1e9);bv.Velocity=dir*SLASH_SPEED;bv.Parent=part
                    slashVelocities[i]=dir*SLASH_SPEED
                end)
            end
        end
    end
    local function updateShrine(dt,t)
        if shrinePhase=="inactive" then return end
        if shrinePhase=="underground" then
            shrineTimer=shrineTimer+dt;local progress=math.clamp(shrineTimer/SHRINE_CLOSE_TIME,0,1);local ease=1-(1-progress)^3
            for i,part in ipairs(shrineStructParts)do
                local data=controlled[part]
                if data and data.bp and data.bp.Parent then
                    local underground=Vector3.new(shrineCenter.X+(i%20)*3,UNDERGROUND_Y,shrineCenter.Z+math.floor(i/20)*3)
                    local offset=shrineStructOffsets[i];local target=offset and(shrineCenter+offset.Position) or shrineCenter
                    data.bp.Position=underground:Lerp(target,ease)
                    if data.bg and data.bg.Parent then
                        local rot=offset and CFrame.new(target)*CFrame.Angles(offset:ToEulerAnglesXYZ()) or CFrame.new(target);data.bg.CFrame=rot
                    end
                end
            end
            local wallTotal=#shrineWallIndices
            for wi,partIdx in ipairs(shrineWallIndices)do
                local part=shrinePartList[partIdx];if not part then continue end
                local data=controlled[part]
                if data and data.bp and data.bp.Parent then
                    local underground=Vector3.new(shrineCenter.X+(wi%20)*3,UNDERGROUND_Y,shrineCenter.Z+math.floor(wi/20)*3)
                    data.bp.Position=underground:Lerp(getSphereWallCF(wi,wallTotal),ease)
                end
            end
            for i,part in ipairs(shrineSlashParts)do
                local data=controlled[part]
                if data and data.bp and data.bp.Parent then
                    local underground=Vector3.new(shrineCenter.X+(i%5)*3,UNDERGROUND_Y,shrineCenter.Z+math.floor(i/5)*3)
                    local slashEase=math.clamp((ease-0.8)/0.2,0,1)
                    local startInSphere=shrineCenter+Vector3.new(math.cos(i*math.pi/3)*DOMAIN_RADIUS,0,math.sin(i*math.pi/3)*DOMAIN_RADIUS)
                    data.bp.Position=underground:Lerp(startInSphere,slashEase)
                end
            end
            if progress>=1 then
                shrinePhase="closed"
                for _,partIdx in ipairs(shrineWallIndices)do local part=shrinePartList[partIdx];if part then pcall(function()part.CanCollide=true end)end end
                activateSlashes()
            end
        elseif shrinePhase=="closed" then
            for i,part in ipairs(shrineStructParts)do
                if part then local data=controlled[part];local offset=shrineStructOffsets[i]
                    if data and data.bp and data.bp.Parent and offset then
                        data.bp.Position=shrineCenter+offset.Position
                        if data.bg and data.bg.Parent then data.bg.CFrame=CFrame.new(data.bp.Position)*CFrame.Angles(offset:ToEulerAnglesXYZ())end
                    end
                end
            end
            local pulse=1+math.sin(t*1.2)*0.03;local wallTotal=#shrineWallIndices
            for wi,partIdx in ipairs(shrineWallIndices)do
                local part=shrinePartList[partIdx];if not part then continue end
                local data=controlled[part]
                if data and data.bp and data.bp.Parent then
                    local phi=(1+math.sqrt(5))/2;local i2=wi-1;local s=math.max(wallTotal,1)
                    local theta=math.acos(math.clamp(1-2*(i2+0.5)/s,-1,1));local ang=2*math.pi*i2/phi;local r=DOMAIN_RADIUS*pulse
                    data.bp.Position=Vector3.new(shrineCenter.X+r*math.sin(theta)*math.cos(ang),shrineCenter.Y+r*math.sin(theta)*math.sin(ang),shrineCenter.Z+r*math.cos(theta))
                    if data.bg and data.bg.Parent then data.bg.CFrame=CFrame.new(data.bp.Position,shrineCenter)*CFrame.Angles(0,math.pi,0)end
                end
            end
            for i,part in ipairs(shrineSlashParts)do
                if part and part.Parent then
                    local slashPos=part.Position;local dist=(slashPos-shrineCenter).Magnitude
                    if dist>DOMAIN_RADIUS*0.82 then
                        local normal=(shrineCenter-slashPos).Unit;local vel=slashVelocities[i]
                        if vel then
                            local reflected=vel-2*(vel:Dot(normal))*normal
                            reflected=(reflected.Unit+Vector3.new((math.random()-0.5)*0.35,(math.random()-0.5)*0.2,(math.random()-0.5)*0.35)).Unit*SLASH_SPEED
                            slashVelocities[i]=reflected
                            pcall(function()local bv=part:FindFirstChildOfClass("BodyVelocity");if bv then bv.Velocity=reflected else local nbv=Instance.new("BodyVelocity");nbv.MaxForce=Vector3.new(1e9,1e9,1e9);nbv.Velocity=reflected;nbv.Parent=part end end)
                        end
                    end
                    if slashVelocities[i] and slashVelocities[i].Magnitude>0 then
                        pcall(function()local dir=slashVelocities[i].Unit;part.CFrame=CFrame.new(slashPos,slashPos+dir)*CFrame.Angles(0,0,math.pi/2)end)
                    end
                end
            end
        elseif shrinePhase=="opening" then
            shrineTimer=shrineTimer+dt;local progress=math.clamp(shrineTimer/SHRINE_OPEN_TIME,0,1);local ease=progress^3
            for i,part in ipairs(shrinePartList)do
                local data=controlled[part]
                if data and data.bp and data.bp.Parent then
                    data.bp.Position=data.bp.Position:Lerp(Vector3.new(shrineCenter.X+(i%20)*3,UNDERGROUND_Y,shrineCenter.Z+math.floor(i/20)*3),ease)
                end
            end
            if progress>=1 then shrinePhase="underground" end
        end
    end
    destroyShrine=function()
        for part,_ in pairs(controlled)do pcall(function()part.CanCollide=true end)end
        for _,part in ipairs(shrineSlashParts)do
            pcall(function()if part and part.Parent then for _,child in ipairs(part:GetChildren())do if child:IsA("BodyVelocity")then child:Destroy()end end end end)
        end
        restoreAllColors();shrinePhase="inactive";shrineCenter=Vector3.zero;shrineTimer=0
        shrinePartList={};shrineStructParts={};shrineSlashParts={};shrineWallIndices={};slashVelocities={};shrineActive=false
    end

    -- ════ GOJO ════
    local function safeResetGojo()
        gojoGen=gojoGen+1;gojoState="idle";blueThread=nil
        restoreAllColors();for part,_ in pairs(controlled)do pcall(function()part.CanCollide=false end)end
    end
    local function fireMaxBlue()
        if gojoState~="idle" then return end
        gojoLastFire.blue=tick();gojoState="blue_hold";colorAllControlled(Color3.fromRGB(20,100,255),Enum.Material.Neon)
        local th={};blueThread=th;local myGen=gojoGen
        task.spawn(function()
            local elapsed=0;local DURATION=10;local CYCLE=1.4
            while gojoState=="blue_hold" and elapsed<DURATION and gojoGen==myGen do
                local dt=task.wait();if blueThread~=th or gojoGen~=myGen then return end
                elapsed=elapsed+dt
                local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
                if not root then break end
                local _,aimDir=getAimPoint(1);local aimPt=root.Position+aimDir*20
                local cycleT=(elapsed%CYCLE)/CYCLE;local pullFactor=cycleT<0.5 and(cycleT*2) or(1-(cycleT-0.5)*2)
                local allParts={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(allParts,part)end end;local n=#allParts
                for i,part in ipairs(allParts)do
                    local data=controlled[part]
                    if data and data.bp and data.bp.Parent then
                        local phi=(1+math.sqrt(5))/2;local idx=i-1;local s=math.max(n,1)
                        local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+elapsed*0.8
                        local r=2+pullFactor*12
                        data.bp.P=600000;data.bp.D=25000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                        data.bp.Position=aimPt+Vector3.new(r*math.sin(theta)*math.cos(ang),r*math.sin(theta)*math.sin(ang),r*math.cos(theta))
                    end
                end
            end
            if gojoGen==myGen then safeResetGojo()end
        end)
    end
    local function fireReversalRed()
        if gojoState~="idle" then return end
        gojoState="red_charge";local myGen=gojoGen
        local redParts={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(redParts,part);if #redParts>=RED_PART_COUNT then break end end end
        colorParts(redParts,Color3.fromRGB(255,40,40),Enum.Material.Neon)
        task.spawn(function()
            local elapsed=0;local chargeTime=1.5
            while elapsed<chargeTime and gojoGen==myGen do
                local dt=task.wait();elapsed=elapsed+dt
                local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
                if not root then break end
                local aimPt=root.Position+root.CFrame.LookVector*5
                for i,part in ipairs(redParts)do
                    local data=controlled[part]
                    if data and data.bp and data.bp.Parent then
                        local phi=(1+math.sqrt(5))/2;local idx=i-1;local s=math.max(#redParts,1)
                        local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+elapsed*3;local r=2*(1-elapsed/chargeTime)+0.3
                        data.bp.P=800000;data.bp.D=30000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                        data.bp.Position=aimPt+Vector3.new(r*math.sin(theta)*math.cos(ang),r*math.sin(theta)*math.sin(ang),r*math.cos(theta))
                    end
                end
            end
            if gojoGen~=myGen then return end
            gojoState="red_fire"
            local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            if root then
                local aimDir=root.CFrame.LookVector
                for _,part in ipairs(redParts)do
                    local data=controlled[part]
                    if data then
                        pcall(function()if data.bp and data.bp.Parent then data.bp:Destroy();data.bp=nil end;if data.bg and data.bg.Parent then data.bg:Destroy();data.bg=nil end end)
                        local bv=Instance.new("BodyVelocity");bv.MaxForce=Vector3.new(1e12,1e12,1e12);bv.Velocity=aimDir*280;bv.Parent=part;Debris:AddItem(bv,3)
                        addFlingOnTouch(part)
                    end
                end
            end
            task.wait(3);if gojoGen==myGen then safeResetGojo()end
        end)
    end
    local function fireHollowPurple()
        if gojoState~="idle" then return end
        gojoState="purple_split";local myGen=gojoGen
        local allParts={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(allParts,part)end end
        local half=math.ceil(#allParts/2);local blueParts={};local redParts={}
        for i,part in ipairs(allParts)do if i<=half then table.insert(blueParts,part)else table.insert(redParts,part)end end
        colorParts(blueParts,Color3.fromRGB(20,80,255),Enum.Material.Neon);colorParts(redParts,Color3.fromRGB(255,40,40),Enum.Material.Neon)
        task.spawn(function()
            local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            if not root then safeResetGojo();return end
            local elapsed=0
            while elapsed<2 and gojoGen==myGen do
                local dt=task.wait();elapsed=elapsed+dt
                local char2=player.Character;local root2=char2 and(char2:FindFirstChild("HumanoidRootPart") or char2:FindFirstChild("Torso"))
                if not root2 then break end
                local right2=root2.CFrame.RightVector;local fwd2=root2.CFrame.LookVector
                local blueOrb=root2.Position+fwd2*8-right2*5;local redOrb=root2.Position+fwd2*8+right2*5
                for i2,part in ipairs(blueParts)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local phi=(1+math.sqrt(5))/2;local idx=i2-1;local s=math.max(#blueParts,1)
                    local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+elapsed*4
                    data.bp.P=900000;data.bp.D=35000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=blueOrb+Vector3.new(1.5*math.sin(theta)*math.cos(ang),1.5*math.sin(theta)*math.sin(ang),1.5*math.cos(theta))
                end
                for i2,part in ipairs(redParts)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local phi=(1+math.sqrt(5))/2;local idx=i2-1;local s=math.max(#redParts,1)
                    local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+elapsed*4
                    data.bp.P=900000;data.bp.D=35000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=redOrb+Vector3.new(1.5*math.sin(theta)*math.cos(ang),1.5*math.sin(theta)*math.sin(ang),1.5*math.cos(theta))
                end
            end
            if gojoGen~=myGen then return end
            gojoState="purple_fire";colorAllControlled(Color3.fromRGB(160,40,255),Enum.Material.Neon)
            local char4=player.Character;local root4=char4 and(char4:FindFirstChild("HumanoidRootPart") or char4:FindFirstChild("Torso"))
            if not root4 then safeResetGojo();return end
            local aimDir=root4.CFrame.LookVector
            for i2,part in ipairs(allParts)do
                local data=controlled[part]
                if data then
                    pcall(function()if data.bp and data.bp.Parent then data.bp:Destroy();data.bp=nil end;if data.bg and data.bg.Parent then data.bg:Destroy();data.bg=nil end end)
                    local bv=Instance.new("BodyVelocity");bv.MaxForce=Vector3.new(1e12,1e12,1e12)
                    bv.Velocity=(aimDir+Vector3.new((i2%3-1)*0.04,(math.floor(i2/3)%3-1)*0.04,0)).Unit*450;bv.Parent=part;Debris:AddItem(bv,4)
                    addFlingOnTouch(part)
                end
            end
            task.wait(0.8);pcall(function()local ex=Instance.new("Explosion");ex.Position=root4.Position+aimDir*60;ex.BlastRadius=25;ex.BlastPressure=1500000;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace end)
            task.wait(2);if gojoGen==myGen then safeResetGojo()end
        end)
    end
    local function fireDEInfinity()
        if gojoState~="idle" then return end
        gojoState="de_infinity";colorAllControlled(Color3.new(0.9,0.9,1),Enum.Material.Neon)
        local myGen=gojoGen
        task.spawn(function()task.wait(20);if gojoGen==myGen then safeResetGojo()end end)
    end
    destroyGojo=function() safeResetGojo();gojoActive=false end

    -- ════ PET COMMAND ACTIONS ════
    local function getPlayerRoot(name)
        local p2=findPlayer(name);if not p2 then return nil end
        local char=p2.Character;if not char then return nil end
        return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    end
    local function getParts(ownerName)
        if #petOwnerList<=1 then
            local arr={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(arr,part)end end;return arr
        end
        if not petSplitOwners[ownerName] then
            local allArr={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(allArr,part)end end
            local n=#allArr;local k=#petOwnerList
            for oi,oname in ipairs(petOwnerList)do
                petSplitOwners[oname]={parts={}}
                local st=math.floor((oi-1)*n/k)+1;local en=math.floor(oi*n/k)
                for pi=st,en do if allArr[pi]then table.insert(petSplitOwners[oname].parts,allArr[pi])end end
            end
        end
        local sd=petSplitOwners[ownerName];if not sd then return{} end
        local arr={};for _,part in ipairs(sd.parts)do if part and part.Parent then table.insert(arr,part)end end;return arr
    end

    -- Carpet helpers
    local carpetOrigWS={}
    local function applyCarpetBoost(ownerName)
        if petCarpetOwners[ownerName]then return end
        local p2=findPlayer(ownerName);if not p2 then return end
        local char=p2.Character;local hum=char and char:FindFirstChildOfClass("Humanoid")
        if hum then carpetOrigWS[ownerName]=hum.WalkSpeed;pcall(function()hum.WalkSpeed=60;hum.JumpPower=80 end);petCarpetOwners[ownerName]=true end
    end
    local function removeCarpetBoost(ownerName)
        if not petCarpetOwners[ownerName]then return end
        local p2=findPlayer(ownerName);if p2 then local char=p2.Character;local hum=char and char:FindFirstChildOfClass("Humanoid")
            if hum then pcall(function()hum.WalkSpeed=carpetOrigWS[ownerName] or 16;hum.JumpPower=50 end)end end
        petCarpetOwners[ownerName]=nil
    end

    -- Guard
    local function doPetGuard(pos)
        for _,p2 in ipairs(Players:GetPlayers())do
            if p2==player or petOwners[p2.Name]then continue end
            local char2=p2.Character;local hrp2=char2 and char2:FindFirstChild("HumanoidRootPart")
            if hrp2 and(hrp2.Position-pos).Magnitude<15 then
                pcall(function()local ex=Instance.new("Explosion");ex.Position=hrp2.Position;ex.BlastRadius=8;ex.BlastPressure=600000;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace end)
            end
        end
    end

    -- Attack (FIX: actually works, gathers then explodes on target)
    local function doPetAttackFling()
        petAttackFired=true
        local target=petAttackTarget;if not target then return end
        local allArr={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(allArr,part)end end
        local count=math.min(#allArr,20)
        colorAllControlled(Color3.fromRGB(255,60,60),Enum.Material.Neon)
        task.spawn(function()
            local t0=tick()
            while tick()-t0<0.8 do
                task.wait()
                local tr=getPlayerRoot(target);if not tr then break end
                local tp=tr.Position
                for i=1,count do
                    local part=allArr[i];if not part then continue end
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local phi=(1+math.sqrt(5))/2;local idx=i-1;local s=math.max(count,1)
                    local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+(tick()-t0)*4
                    data.bp.P=1000000;data.bp.D=35000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=tp+Vector3.new(2*math.sin(theta)*math.cos(ang),2*math.sin(theta)*math.sin(ang),2*math.cos(theta))
                end
            end
            local tr3=getPlayerRoot(target)
            if tr3 then pcall(function()local ex=Instance.new("Explosion");ex.Position=tr3.Position;ex.BlastRadius=14;ex.BlastPressure=1200000;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace end)end
            task.wait(0.5);petAttackTarget=nil;petAttackFired=false;restoreAllColors()
        end)
    end

    -- Bring (FIX: block wall push - FE server visible)
    local function doPetBring(targetName)
        local targetRoot=getPlayerRoot(targetName);if not targetRoot then return end
        local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if not root then return end
        local ownerPos=root.Position
        local allArr={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(allArr,part)end end
        local count=math.min(#allArr,8)
        task.spawn(function()
            local t0=tick()
            while tick()-t0<2.5 do
                task.wait()
                local tr=getPlayerRoot(targetName);if not tr then break end
                local dir=(ownerPos-tr.Position);local dist=dir.Magnitude
                if dist<4 then break end
                dir=dir.Unit
                -- Move blocks behind target, pushing toward owner
                for i=1,count do
                    local part=allArr[i];if not part then continue end
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local ang=((i-1)/count)*math.pi*2
                    local pushPos=tr.Position-dir*3+Vector3.new(math.cos(ang)*1.5,i*0.4,math.sin(ang)*1.5)
                    data.bp.P=900000;data.bp.D=30000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=pushPos
                end
                -- Wall of force behind the target
                pcall(function()
                    local ex=Instance.new("Explosion");ex.Position=tr.Position-dir*2;ex.BlastRadius=5
                    ex.BlastPressure=200000;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace
                end)
                task.wait(0.18)
            end
        end)
    end

    -- GoTo (FIX: actually teleport blocks under owner's feet to carry owner to target)
    local function doPetGoTo(targetName)
        local targetRoot=getPlayerRoot(targetName);if not targetRoot then return end
        local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if not root then return end
        local allArr={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(allArr,part)end end
        if #allArr==0 then return end
        local destPos=targetRoot.Position+Vector3.new(0,4,3)
        -- Stage 1: form platform under player (~0.8s)
        local t0=tick()
        task.spawn(function()
            while tick()-t0<0.5 do
                task.wait()
                local root2=player.Character and(player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"))
                if not root2 then break end
                local base=root2.Position+Vector3.new(0,-1.5,0)
                for i,part in ipairs(allArr)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local ang=((i-1)/math.max(#allArr,1))*math.pi*2
                    data.bp.P=800000;data.bp.D=28000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=base+Vector3.new(math.cos(ang)*2.5,0,math.sin(ang)*2.5)
                end
            end
            -- Stage 2: charge to destination carrying player (parts + player rush to target)
            local t1=tick();local startPos=root.Position
            while tick()-t1<1.5 do
                task.wait()
                local frac=math.clamp((tick()-t1)/1.2,0,1)
                local curPos=startPos:Lerp(destPos,frac)
                for i,part in ipairs(allArr)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local ang=((i-1)/math.max(#allArr,1))*math.pi*2
                    data.bp.P=1200000;data.bp.D=40000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=curPos+Vector3.new(math.cos(ang)*2.5,-1.5,math.sin(ang)*2.5)
                end
                -- Teleport/push player alongside
                local root3=player.Character and(player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"))
                if root3 then
                    pcall(function()root3.CFrame=CFrame.new(curPos)end)
                end
            end
        end)
    end

    -- Slap
    local function doPetSlap(targetName)
        local targetRoot=getPlayerRoot(targetName);if not targetRoot then return end
        local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if not root then return end
        local allArr={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(allArr,part)end end
        local n=#allArr;if n==0 then return end
        colorAllControlled(Color3.fromRGB(255,220,160),Enum.Material.SmoothPlastic)
        -- Palm offsets for hand shape
        local palmGrid={};local gridW=5;local gridH=5
        for row=0,gridH-1 do for col=0,gridW-1 do table.insert(palmGrid,Vector3.new((col-gridW/2)*1.6,(row-gridH/2)*1.6,0))end end
        -- Fingers
        for f=0,4 do for seg=1,4 do table.insert(palmGrid,Vector3.new((f-2)*1.6,gridH/2*1.6+seg*1.5,0))end end
        task.spawn(function()
            local t0=tick()
            -- Form hand facing target for 1s
            while tick()-t0<1 do
                task.wait()
                local tr=getPlayerRoot(targetName);if not tr then break end
                local dir=Vector3.new(tr.Position.X-root.Position.X,0,tr.Position.Z-root.Position.Z)
                if dir.Magnitude>0 then dir=dir.Unit end
                local rot=CFrame.new(Vector3.zero,dir)
                local handBase=root.Position+dir*4+Vector3.new(0,4,0)
                for i,part in ipairs(allArr)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local off=palmGrid[((i-1)%#palmGrid)+1]
                    data.bp.P=700000;data.bp.D=22000;data.bp.MaxForce=Vector3.new(1e11,1e11,1e11)
                    data.bp.Position=handBase+rot:VectorToWorldSpace(off)
                end
            end
            -- Swing: rush at target
            local tr4=getPlayerRoot(targetName)
            if tr4 then
                local targetPos=tr4.Position
                for i,part in ipairs(allArr)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local off=palmGrid[((i-1)%#palmGrid)+1]*0.5
                    data.bp.P=1800000;data.bp.D=60000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=targetPos+Vector3.new(off.X*0.3,off.Y*0.3,0)
                end
                task.wait(0.25)
                pcall(function()local ex=Instance.new("Explosion");ex.Position=targetPos;ex.BlastRadius=16;ex.BlastPressure=1400000;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace end)
            end
            task.wait(0.6);restoreAllColors()
        end)
    end

    -- Hollow Purple (pet chat command version)
    local function doPetHollowPurple(ownerName)
        local ownerRoot=getPlayerRoot(ownerName) or (player.Character and(player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso")))
        if not ownerRoot then return end
        local allArr={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(allArr,part)end end
        if #allArr==0 then return end
        local half=math.ceil(#allArr/2);local blueParts={};local redParts={}
        for i,p2 in ipairs(allArr)do if i<=half then table.insert(blueParts,p2)else table.insert(redParts,p2)end end
        colorParts(blueParts,Color3.fromRGB(20,80,255),Enum.Material.Neon);colorParts(redParts,Color3.fromRGB(255,40,40),Enum.Material.Neon)
        local fwd=ownerRoot.CFrame.LookVector;local right=ownerRoot.CFrame.RightVector
        task.spawn(function()
            local t0=tick()
            while tick()-t0<1.5 do
                task.wait();local elapsed=tick()-t0
                local blueOrb=ownerRoot.Position+fwd*8-right*4;local redOrb=ownerRoot.Position+fwd*8+right*4
                for i2,part in ipairs(blueParts)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local phi=(1+math.sqrt(5))/2;local idx=i2-1;local s=math.max(#blueParts,1)
                    local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+elapsed*4
                    data.bp.P=800000;data.bp.D=28000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=blueOrb+Vector3.new(1.5*math.sin(theta)*math.cos(ang),1.5*math.sin(theta)*math.sin(ang),1.5*math.cos(theta))
                end
                for i2,part in ipairs(redParts)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local phi=(1+math.sqrt(5))/2;local idx=i2-1;local s=math.max(#redParts,1)
                    local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+elapsed*4
                    data.bp.P=800000;data.bp.D=28000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    data.bp.Position=redOrb+Vector3.new(1.5*math.sin(theta)*math.cos(ang),1.5*math.sin(theta)*math.sin(ang),1.5*math.cos(theta))
                end
            end
            colorAllControlled(Color3.fromRGB(160,40,255),Enum.Material.Neon)
            local me=tick()
            while tick()-me<0.4 do
                task.wait()
                local mergePos=ownerRoot.Position+fwd*10
                for i2,part in ipairs(allArr)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local phi=(1+math.sqrt(5))/2;local idx=i2-1;local s=math.max(#allArr,1)
                    local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi
                    data.bp.Position=ownerRoot.Position+fwd*10+Vector3.new(math.sin(theta)*math.cos(ang),math.sin(theta)*math.sin(ang),math.cos(theta))
                end
            end
            -- Fire
            local shootDir=fwd
            for i2,part in ipairs(allArr)do
                local data=controlled[part]
                if data then
                    pcall(function()if data.bp and data.bp.Parent then data.bp:Destroy();data.bp=nil end;if data.bg and data.bg.Parent then data.bg:Destroy();data.bg=nil end end)
                    local bv=Instance.new("BodyVelocity");bv.MaxForce=Vector3.new(1e12,1e12,1e12)
                    bv.Velocity=(shootDir+Vector3.new((i2%3-1)*0.04,(math.floor(i2/3)%3-1)*0.04,0)).Unit*380;bv.Parent=part;Debris:AddItem(bv,3)
                    addFlingOnTouch(part)
                end
            end
            task.wait(0.7);pcall(function()local ex=Instance.new("Explosion");ex.Position=ownerRoot.Position+fwd*60;ex.BlastRadius=22;ex.BlastPressure=1200000;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace end)
            task.wait(2);restoreAllColors();sweepMap()
        end)
    end

    -- ════ PET MOVE PARTS (main per-frame positioning) ════
    local petTornadoAngle=0
    local function moveParts(arr,tpos,dist,t,state)
        local n=#arr;if n==0 then return end
        local spinOff=petSpinSpeed~=0 and(t*petSpinSpeed) or 0

        if state=="follow" or state=="idle" then
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local phi=(1+math.sqrt(5))/2;local idx=i-1;local s=math.max(n,1)
                local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+spinOff
                data.bp.P=400000;data.bp.D=15000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+Vector3.new(dist*math.sin(theta)*math.cos(ang),dist*math.sin(theta)*math.sin(ang)+1,dist*math.cos(theta))
            end
        elseif state=="orbit" then
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local ang=((i-1)/math.max(n,1))*math.pi*2+t*1.8+spinOff
                data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+Vector3.new(math.cos(ang)*dist,math.sin(t*0.8+i*0.4)*1.5+1.5,math.sin(ang)*dist)
            end
        elseif state=="dance" then
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local ang=((i-1)/math.max(n,1))*math.pi*2+t*3+spinOff
                local bounceY=math.abs(math.sin(t*4+i*0.5))*3
                data.bp.P=500000;data.bp.D=15000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+Vector3.new(math.cos(ang)*(dist+math.sin(t*2)*2),bounceY+1,math.sin(ang)*(dist+math.sin(t*2)*2))
            end
        elseif state=="ring" then
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local ang=((i-1)/math.max(n,1))*math.pi*2+t*1.2+spinOff
                data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+Vector3.new(math.cos(ang)*dist,2,math.sin(ang)*dist)
            end
        elseif state=="wall" then
            local cols=math.max(1,math.ceil(math.sqrt(n)))
            local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local wcf=root and root.CFrame or CFrame.new(tpos)
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local col=(i-1)%cols;local row=math.floor((i-1)/cols)
                data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+wcf.LookVector*dist+wcf.RightVector*(col-cols/2)*2+wcf.UpVector*(row-1)*2
            end
        elseif state=="heart" then
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local a=((i-1)/math.max(n,1))*math.pi*2+spinOff
                local hx=16*math.sin(a)^3;local hz=-(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))
                data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+Vector3.new(hx*(dist/16),1.5,hz*(dist/16))
            end
        elseif state=="sphere" then
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local phi=(1+math.sqrt(5))/2;local idx=i-1;local s=math.max(n,1)
                local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+spinOff
                data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+Vector3.new(dist*math.sin(theta)*math.cos(ang),dist*math.sin(theta)*math.sin(ang),dist*math.cos(theta))
            end
        elseif state=="carpet" then
            local cols=math.max(1,math.ceil(math.sqrt(n)))
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local col=(i-1)%cols;local row=math.floor((i-1)/cols)
                data.bp.P=600000;data.bp.D=20000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+Vector3.new((col-cols/2)*1.4,-1.5,(row-math.floor(cols/2))*1.4)
            end
        elseif state=="trail" then
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local histIdx=math.clamp(i*SNAKE_GAP,1,math.max(1,#snakeHistory))
                local target=snakeHistory[histIdx] or tpos
                data.bp.P=500000;data.bp.D=15000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=target
            end
        elseif state=="wings" then
            local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local wcf=root and root.CFrame or CFrame.new(tpos);local half=math.ceil(n/2)
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local side=1;local ptIdx=i
                if i>half then side=-1;ptIdx=i-half end
                local wpos=getWingCF(((ptIdx-1)%WING_POINT_COUNT)+1,side,wcf,t)
                data.bp.P=500000;data.bp.D=16000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=wpos.Position
            end
        elseif state=="tornado" then
            petTornadoAngle=petTornadoAngle+0.06
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local frac=(i-1)/math.max(n,1)
                local ang=frac*math.pi*8+petTornadoAngle+spinOff
                local r=dist*(1-frac*0.65)
                data.bp.P=700000;data.bp.D=22000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                data.bp.Position=tpos+Vector3.new(math.cos(ang)*r,frac*22,math.sin(ang)*r)
                pcall(function()part.Color=Color3.fromHSV((t*0.3+frac)%1,0.8,1);part.Material=Enum.Material.Neon end)
            end
            -- Pull all unanchored blocks in range toward tornado
            for _,obj in ipairs(workspace:GetDescendants())do
                if not controlled[obj] and isValid(obj)then
                    local d=(obj.Position-tpos).Magnitude
                    if d<55 then
                        pcall(function()
                            obj:SetNetworkOwner(player)
                            for _,ch in ipairs(obj:GetChildren())do if ch:IsA("BodyVelocity")then ch:Destroy()end end
                            local pullDir=(tpos-obj.Position).Unit
                            local bv=Instance.new("BodyVelocity");bv.MaxForce=Vector3.new(1e9,1e9,1e9)
                            bv.Velocity=pullDir*((55-d)/55)*90+Vector3.new(0,5,0);bv.Parent=obj;Debris:AddItem(bv,0.25)
                        end)
                    end
                end
            end
        elseif state=="blackhole" then
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local phi=(1+math.sqrt(5))/2;local idx=i-1;local s=math.max(n,1)
                local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+t*3+spinOff
                local r=math.max(0.8,dist*0.12)
                data.bp.P=900000;data.bp.D=35000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                data.bp.Position=tpos+Vector3.new(r*math.sin(theta)*math.cos(ang),r*math.sin(theta)*math.sin(ang),r*math.cos(theta))
                pcall(function()local pulse=(math.sin(t*6+i*0.3)+1)/2;part.Color=Color3.new(pulse*0.12,0,pulse*0.28);part.Material=Enum.Material.Neon end)
            end
            -- Pull all unanchored blocks in range
            for _,obj in ipairs(workspace:GetDescendants())do
                if not controlled[obj] and isValid(obj)then
                    local d=(obj.Position-tpos).Magnitude
                    if d<90 then
                        pcall(function()
                            obj:SetNetworkOwner(player)
                            for _,ch in ipairs(obj:GetChildren())do if ch:IsA("BodyVelocity")then ch:Destroy()end end
                            local strength=math.clamp(1-(d/90),0,1)^2*130
                            local bv=Instance.new("BodyVelocity");bv.MaxForce=Vector3.new(1e9,1e9,1e9)
                            bv.Velocity=(tpos-obj.Position).Unit*strength;bv.Parent=obj;Debris:AddItem(bv,0.2)
                        end)
                    end
                end
            end
        elseif state=="rain" then
            local cloudCount=math.max(1,math.floor(n*0.35));local dropCount=n-cloudCount
            for i=1,cloudCount do
                local part=arr[i];if not part then continue end
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local ang=((i-1)/cloudCount)*math.pi*2+spinOff;local fuzz=math.sin(t*1.5+i)*0.8
                data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+Vector3.new(math.cos(ang)*(3+fuzz),11+fuzz,math.sin(ang)*(3+fuzz))
                pcall(function()part.Color=Color3.fromRGB(160,170,190);part.Material=Enum.Material.SmoothPlastic end)
            end
            for i=1,dropCount do
                local part=arr[cloudCount+i];if not part then continue end
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                if not petRainDrops[i]then petRainDrops[i]=(i-1)/math.max(dropCount,1)end
                petRainDrops[i]=(petRainDrops[i]+0.008)%1
                local phase=petRainDrops[i];local ang=((i-1)/dropCount)*math.pi*2
                local xOff=math.cos(ang)*3;local zOff=math.sin(ang)*3
                local dropY=11-phase*16
                data.bp.P=600000;data.bp.D=20000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=tpos+Vector3.new(xOff,dropY,zOff)
                pcall(function()part.Color=Color3.fromRGB(100,160,255);part.Material=Enum.Material.Neon end)
            end
        elseif state=="throne" then
            if not petThronePos then petThronePos=tpos end
            local tp=petThronePos
            local throneOff={
                Vector3.new(0,0,0),Vector3.new(0,0,1),Vector3.new(0,0,-1),Vector3.new(-1,0,0),Vector3.new(1,0,0),
                Vector3.new(-1,2,-1.8),Vector3.new(0,2,-1.8),Vector3.new(1,2,-1.8),
                Vector3.new(-1,4,-1.8),Vector3.new(0,4,-1.8),Vector3.new(1,4,-1.8),Vector3.new(0,6,-1.8),
                Vector3.new(-1.8,1.2,0),Vector3.new(-1.8,1.2,-0.6),Vector3.new(-1.8,1.2,-1.2),
                Vector3.new(1.8,1.2,0),Vector3.new(1.8,1.2,-0.6),Vector3.new(1.8,1.2,-1.2),
                Vector3.new(-1,-1.5,-1.8),Vector3.new(1,-1.5,-1.8),Vector3.new(-1,-1.5,0.8),Vector3.new(1,-1.5,0.8),
                Vector3.new(-1.8,7,-1.8),Vector3.new(0,7.5,-1.8),Vector3.new(1.8,7,-1.8),
            }
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local off=throneOff[((i-1)%#throneOff)+1]
                data.bp.P=700000;data.bp.D=22000;data.bp.MaxForce=Vector3.new(1e11,1e11,1e11)
                data.bp.Position=tp+off*1.6
                pcall(function()part.Color=Color3.fromRGB(220,180,60);part.Material=Enum.Material.Neon end)
            end
        elseif state=="judgement_sword" then
            -- Sword shape: blade up, guard, handle, pommel
            local swordOff={}
            for j=1,14 do table.insert(swordOff,Vector3.new(0,j*1.5+2,0))end -- blade
            for c=-3,3 do table.insert(swordOff,Vector3.new(c*1.2,2,0))end    -- guard
            table.insert(swordOff,Vector3.new(0,1,0));table.insert(swordOff,Vector3.new(0,0,0));table.insert(swordOff,Vector3.new(0,-1,0)) -- handle
            table.insert(swordOff,Vector3.new(-0.7,-2.2,0));table.insert(swordOff,Vector3.new(0.7,-2.2,0)) -- pommel
            if petSwordSwinging then
                petSwordSwingT=petSwordSwingT+0.016667
                if petSwordSwingT>1.8 then petSwordSwinging=false;petSwordSwingT=0 end
            end
            local swingAng=petSwordSwinging and math.sin(math.clamp(petSwordSwingT/1.2,0,1)*math.pi)*math.rad(120) or 0
            local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local swordBase=tpos+Vector3.new(2,0,0)
            for i,part in ipairs(arr)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local off=swordOff[((i-1)%#swordOff)+1]
                local rotOff=CFrame.Angles(swingAng,0,0)*CFrame.new(off)
                data.bp.P=700000;data.bp.D=22000;data.bp.MaxForce=Vector3.new(1e11,1e11,1e11)
                data.bp.Position=swordBase+rotOff.Position
                pcall(function()part.Color=Color3.fromRGB(200,220,255);part.Material=Enum.Material.Neon end)
            end
        elseif state=="titanic" then
            -- Handled in titanic update section below
            if titanicActive then
                for i,part in ipairs(arr)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local entry=TITANIC_OFFSETS[((i-1)%#TITANIC_OFFSETS)+1]
                    local localV=entry.v
                    local sinkOff=Vector3.new(0,0,0)
                    if titanicSinking then
                        -- Stern stays, bow submerges
                        local sinkFrac=math.clamp(titanicSinkT/25,0,1)
                        local bowFactor=math.clamp(-localV.Z/60,0,1) -- more negative Z = more bow = more submerged
                        sinkOff=Vector3.new(0,-sinkFrac*bowFactor*40,0)
                    end
                    local worldPos=titanicCF:PointToWorldSpace(localV+sinkOff)
                    if titanicAnchored and not titanicSinking then
                        data.bp.P=1500000;data.bp.D=50000;data.bp.MaxForce=Vector3.new(1e14,1e14,1e14)
                    else
                        data.bp.P=800000;data.bp.D=28000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                    end
                    data.bp.Position=worldPos
                    if data.bg and data.bg.Parent then
                        local sinkTilt=titanicSinking and CFrame.Angles(math.clamp(titanicSinkT/25,0,1)*math.rad(-18),0,0) or CFrame.identity
                        data.bg.CFrame=titanicCF*sinkTilt
                    end
                    -- Color by role
                    local col,mat=getTitanicColor(((i-1)%#TITANIC_OFFSETS)+1)
                    pcall(function()part.Color=col;part.Material=mat end)
                end
            end
        elseif state=="say" then
            if petSayText and #petSayText>0 then
                local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
                local origin=tpos+Vector3.new(-#petSayText*2,6,0)
                local positions=getTextPositions(petSayText,origin,root and root.CFrame or CFrame.new(origin))
                for i,part in ipairs(arr)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local pos=positions[i] or(tpos+Vector3.new(0,4,0))
                    data.bp.P=600000;data.bp.D=20000;data.bp.MaxForce=Vector3.new(1e11,1e11,1e11)
                    data.bp.Position=pos
                    pcall(function()part.Color=Color3.fromRGB(255,255,255);part.Material=Enum.Material.Neon end)
                end
            else moveParts(arr,tpos,dist,t,"follow")end
        elseif state=="guard" then moveParts(arr,tpos,dist,t,"orbit")
        elseif state=="stop" then -- hold
        else moveParts(arr,tpos,dist,t,"follow")end
    end

    destroyPet=function()
        for ownerName,_ in pairs(petCarpetOwners)do removeCarpetBoost(ownerName)end
        petCarpetOwners={};petAttackTarget=nil;petAttackFired=false
        petGuardActive=false;petSpinSpeed=0;petSayText=nil
        petActive=false;petOwners={};petOwnerList={};petState="idle"
        petSplitOwners={};petOwnerStates_global={};titanicActive=false;titanicAnchored=false
        petThronePos=nil;petRainDrops={}
        if petGuiUpdateFn then pcall(petGuiUpdateFn)end
    end
    destroyPetGui=function()
        if petSubGui and petSubGui.Parent then petSubGui:Destroy()end
        petSubGui=nil;petGuiUpdateFn=nil
    end

    -- ════ PET GUI (Water/Ocean Theme with Animated Waves) ════
    local function createPetGui()
        destroyPetGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="PetSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1002;sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;sg.Parent=pg;petSubGui=sg

        local W,H=230,420
        local panel=Instance.new("Frame");panel.Name="PetPanel";panel.Size=UDim2.fromOffset(W,H)
        panel.Position=UDim2.new(1,-W-10,0.5,-H/2);panel.BackgroundColor3=Color3.fromRGB(6,18,38)
        panel.BorderSizePixel=0;panel.ClipsDescendants=true;panel.Parent=sg
        Instance.new("UICorner",panel).CornerRadius=UDim.new(0,10)
        local stroke=Instance.new("UIStroke",panel);stroke.Color=Color3.fromRGB(40,140,220);stroke.Thickness=1.6

        -- Animated wave canvas
        local waveCanvas=Instance.new("Frame");waveCanvas.Size=UDim2.new(1,0,1,0);waveCanvas.Position=UDim2.new(0,0,0,0)
        waveCanvas.BackgroundTransparency=1;waveCanvas.ZIndex=0;waveCanvas.Parent=panel
        -- Wave gradient bars (4 horizontal strips)
        local waveFrames={}
        local waveCols={Color3.fromRGB(8,40,90),Color3.fromRGB(10,55,115),Color3.fromRGB(12,70,140),Color3.fromRGB(14,85,160)}
        for i=1,4 do
            local wf=Instance.new("Frame");wf.Size=UDim2.new(1,0,0.25,0)
            wf.Position=UDim2.new(0,0,(i-1)*0.25,0);wf.BackgroundColor3=waveCols[i];wf.BorderSizePixel=0;wf.ZIndex=1;wf.Parent=waveCanvas
            table.insert(waveFrames,wf)
        end
        -- Wave animation loop
        task.spawn(function()
            local wt=0
            while petSubGui and petSubGui.Parent and scriptAlive do
                local dt=task.wait(0.03);wt=wt+dt
                for i,wf in ipairs(waveFrames)do
                    if wf and wf.Parent then
                        local yOff=math.sin(wt*1.4+i*0.9)*4
                        wf.Position=UDim2.new(0,0,(i-1)*0.25,yOff)
                        local alpha=0.75+math.sin(wt*2+i)*0.08
                        wf.BackgroundTransparency=alpha
                    end
                end
            end
        end)

        -- Title bar
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,32);tBar.BackgroundColor3=Color3.fromRGB(5,25,60)
        tBar.BorderSizePixel=0;tBar.ZIndex=5;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,10)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="PET MODE";tLbl.Size=UDim2.new(1,-10,1,0)
        tLbl.Position=UDim2.fromOffset(10,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(80,200,255)
        tLbl.TextSize=13;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        -- Bubbles label decoration
        local bubbleLbl=Instance.new("TextLabel",tBar);bubbleLbl.Text="~ ~ ~";bubbleLbl.Size=UDim2.new(0,60,1,0)
        bubbleLbl.Position=UDim2.new(1,-62,0,0);bubbleLbl.BackgroundTransparency=1;bubbleLbl.TextColor3=Color3.fromRGB(120,220,255)
        bubbleLbl.TextSize=11;bubbleLbl.Font=Enum.Font.GothamBold;bubbleLbl.ZIndex=10

        -- Scrolling owner/state readout
        local stateLbl=Instance.new("TextLabel",panel);stateLbl.Size=UDim2.new(1,-10,0,14)
        stateLbl.Position=UDim2.fromOffset(6,34);stateLbl.BackgroundTransparency=1
        stateLbl.TextColor3=Color3.fromRGB(80,180,255);stateLbl.TextSize=9;stateLbl.Font=Enum.Font.GothamBold
        stateLbl.TextXAlignment=Enum.TextXAlignment.Left;stateLbl.ZIndex=10;stateLbl.Text="State: idle"
        local ownerLbl=Instance.new("TextLabel",panel);ownerLbl.Size=UDim2.new(1,-10,0,12)
        ownerLbl.Position=UDim2.fromOffset(6,48);ownerLbl.BackgroundTransparency=1
        ownerLbl.TextColor3=Color3.fromRGB(60,160,220);ownerLbl.TextSize=8;ownerLbl.Font=Enum.Font.GothamBold
        ownerLbl.TextXAlignment=Enum.TextXAlignment.Left;ownerLbl.ZIndex=10;ownerLbl.Text="Owners: none"
        task.spawn(function()
            while petSubGui and petSubGui.Parent and scriptAlive do
                stateLbl.Text="State: "..petState:upper().." | Spin: "..petSpinSpeed
                local ol=#petOwnerList>0 and table.concat(petOwnerList,", ") or "none"
                ownerLbl.Text="Owners: "..ol
                task.wait(0.4)
            end
        end)

        -- Helper for water-styled buttons
        local function wBtn(parent,txt,yp,bg,fg,ht)
            local b=Instance.new("TextButton",parent);b.Text=txt
            b.Size=UDim2.new(1,-12,0,ht or 26);b.Position=UDim2.fromOffset(6,yp)
            b.BackgroundColor3=bg or Color3.fromRGB(8,50,100);b.TextColor3=fg or Color3.fromRGB(130,220,255)
            b.TextSize=10;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;b.ZIndex=10
            Instance.new("UICorner",b).CornerRadius=UDim.new(0,5)
            local bs2=Instance.new("UIStroke",b);bs2.Color=Color3.fromRGB(40,120,200);bs2.Thickness=1
            return b
        end

        -- Section label helper
        local function sectionLbl(parent,txt,yp)
            local l=Instance.new("TextLabel",parent);l.Text=txt;l.Size=UDim2.new(1,-12,0,14)
            l.Position=UDim2.fromOffset(6,yp);l.BackgroundTransparency=1;l.TextColor3=Color3.fromRGB(40,140,200)
            l.TextSize=8;l.Font=Enum.Font.GothamBold;l.TextXAlignment=Enum.TextXAlignment.Left;l.ZIndex=10;return l
        end

        local yOff=64

        -- Owner input
        sectionLbl(panel,"ADD/REMOVE OWNER",yOff);yOff=yOff+16
        local ownerInput=Instance.new("TextBox",panel);ownerInput.PlaceholderText="player name..."
        ownerInput.Text="";ownerInput.Size=UDim2.new(1,-12,0,24);ownerInput.Position=UDim2.fromOffset(6,yOff)
        ownerInput.BackgroundColor3=Color3.fromRGB(5,30,70);ownerInput.TextColor3=Color3.fromRGB(160,230,255)
        ownerInput.PlaceholderColor3=Color3.fromRGB(60,100,150);ownerInput.TextSize=10;ownerInput.Font=Enum.Font.Gotham
        ownerInput.BorderSizePixel=0;ownerInput.ZIndex=10;ownerInput.ClearTextOnFocus=false
        Instance.new("UICorner",ownerInput).CornerRadius=UDim.new(0,5)
        Instance.new("UIStroke",ownerInput).Color=Color3.fromRGB(40,100,180)
        yOff=yOff+26
        local addBtn=wBtn(panel,"+ Add Owner",yOff,Color3.fromRGB(5,60,30),Color3.fromRGB(80,255,160));yOff=yOff+28
        local remBtn=wBtn(panel,"- Remove Owner",yOff,Color3.fromRGB(60,10,10),Color3.fromRGB(255,100,100));yOff=yOff+28
        addBtn.MouseButton1Click:Connect(function()
            local name=ownerInput.Text:match("^%s*(.-)%s*$")
            if #name<1 then return end
            petOwners[name]=true;petSplitOwners={}
            if not table.find(petOwnerList,name)then table.insert(petOwnerList,name)end
        end)
        remBtn.MouseButton1Click:Connect(function()
            local name=ownerInput.Text:match("^%s*(.-)%s*$")
            petOwners[name]=nil;petSplitOwners={}
            for i,n in ipairs(petOwnerList)do if n==name then table.remove(petOwnerList,i);break end end
        end)

        sectionLbl(panel,"MOVEMENT STATE",yOff);yOff=yOff+16
        local stateBtns={
            {"Follow","follow"},{"Orbit","orbit"},{"Trail","trail"},
            {"Dance","dance"},{"Ring","ring"},{"Wall","wall"},
            {"Heart","heart"},{"Sphere","sphere"},{"Wings","wings"},
            {"Stay","stop"},{"Carpet","carpet"},
        }
        local col=0
        for _,sb in ipairs(stateBtns)do
            local xp=6+col*(W/2-8);local b=Instance.new("TextButton",panel)
            b.Text=sb[1];b.Size=UDim2.fromOffset(W/2-10,22);b.Position=UDim2.fromOffset(xp,yOff)
            b.BackgroundColor3=Color3.fromRGB(6,40,85);b.TextColor3=Color3.fromRGB(120,210,255)
            b.TextSize=9;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;b.ZIndex=10
            Instance.new("UICorner",b).CornerRadius=UDim.new(0,4)
            local stateName=sb[2]
            b.MouseButton1Click:Connect(function()
                petState=stateName
                if stateName~="carpet" then for _,oname in ipairs(petOwnerList)do removeCarpetBoost(oname)end end
                if stateName~="throne" then petThronePos=nil end
            end)
            col=col+1;if col>=2 then col=0;yOff=yOff+24 end
        end
        if col~=0 then yOff=yOff+24 end

        sectionLbl(panel,"COMBAT / SPECIAL",yOff);yOff=yOff+16
        local combatInput=Instance.new("TextBox",panel);combatInput.PlaceholderText="target name..."
        combatInput.Text="";combatInput.Size=UDim2.new(1,-12,0,24);combatInput.Position=UDim2.fromOffset(6,yOff)
        combatInput.BackgroundColor3=Color3.fromRGB(5,30,70);combatInput.TextColor3=Color3.fromRGB(160,230,255)
        combatInput.PlaceholderColor3=Color3.fromRGB(60,100,150);combatInput.TextSize=10;combatInput.Font=Enum.Font.Gotham
        combatInput.BorderSizePixel=0;combatInput.ZIndex=10;combatInput.ClearTextOnFocus=false
        Instance.new("UICorner",combatInput).CornerRadius=UDim.new(0,5)
        Instance.new("UIStroke",combatInput).Color=Color3.fromRGB(40,100,180)
        yOff=yOff+26
        local atkBtn=wBtn(panel,"Attack Target",yOff,Color3.fromRGB(70,10,10),Color3.fromRGB(255,90,90));yOff=yOff+28
        local slapBtn=wBtn(panel,"Slap Target",yOff,Color3.fromRGB(60,30,10),Color3.fromRGB(255,180,80));yOff=yOff+28
        local bringBtn=wBtn(panel,"Bring Target",yOff,Color3.fromRGB(10,40,70),Color3.fromRGB(80,200,255));yOff=yOff+28
        local gotoBtn=wBtn(panel,"GoTo Target",yOff,Color3.fromRGB(10,50,30),Color3.fromRGB(80,255,150));yOff=yOff+28
        atkBtn.MouseButton1Click:Connect(function()
            if petAttackFired then return end
            local name=combatInput.Text:match("^%s*(.-)%s*$");if #name<1 then return end
            petAttackTarget=name;task.spawn(doPetAttackFling)
        end)
        slapBtn.MouseButton1Click:Connect(function()
            local name=combatInput.Text:match("^%s*(.-)%s*$");if #name<1 then return end
            task.spawn(function()doPetSlap(name)end)
        end)
        bringBtn.MouseButton1Click:Connect(function()
            local name=combatInput.Text:match("^%s*(.-)%s*$");if #name<1 then return end
            task.spawn(function()doPetBring(name)end)
        end)
        gotoBtn.MouseButton1Click:Connect(function()
            local name=combatInput.Text:match("^%s*(.-)%s*$");if #name<1 then return end
            task.spawn(function()doPetGoTo(name)end)
        end)

        -- Guard toggle
        local guardBtn=wBtn(panel,"Guard OFF",yOff,Color3.fromRGB(10,50,80),Color3.fromRGB(80,200,255));yOff=yOff+28
        guardBtn.MouseButton1Click:Connect(function()
            petGuardActive=not petGuardActive
            guardBtn.Text=petGuardActive and "Guard ON" or "Guard OFF"
            guardBtn.BackgroundColor3=petGuardActive and Color3.fromRGB(10,80,30) or Color3.fromRGB(10,50,80)
        end)

        -- Titanic anchor button (visible only when titanic mode)
        sectionLbl(panel,"TITANIC (use ?commands in chat)",yOff);yOff=yOff+14
        local titanicBtn=wBtn(panel,"Titanic Mode ON",yOff,Color3.fromRGB(8,30,60),Color3.fromRGB(80,180,255));yOff=yOff+28
        titanicBtn.MouseButton1Click:Connect(function()
            if petState=="titanic" then
                petState="follow";titanicActive=false;titanicAnchored=false;titanicSinking=false
                titanicBtn.Text="Titanic Mode ON";titanicBtn.BackgroundColor3=Color3.fromRGB(8,30,60)
                restoreAllColors()
            else
                local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
                if root then
                    titanicCF=CFrame.new(root.Position+Vector3.new(0,5,0))
                    titanicSpd=0;titanicFwd=0;titanicTurn=0
                    titanicActive=true;titanicAnchored=false;titanicSinking=false
                    petState="titanic";titanicBtn.Text="Exit Titanic";titanicBtn.BackgroundColor3=Color3.fromRGB(60,10,10)
                end
            end
        end)

        -- Resize panel
        panel.Size=UDim2.fromOffset(W,yOff+10)
        makeDraggable(tBar,panel,false)
        petGuiUpdateFn=function()
            if panel and panel.Parent then panel.Size=UDim2.fromOffset(W,yOff+10)end
        end
    end

    -- ════ SUB-GUIS (Gaster, Sphere, SphereBender, Shrine, Gojo, Tank, Car) ════
    local function destroyGasterGui() if gasterSubGui and gasterSubGui.Parent then gasterSubGui:Destroy()end;gasterSubGui=nil end
    local function createGasterGui()
        destroyGasterGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="GasterSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.Parent=pg;gasterSubGui=sg
        local W,H=190,178;local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(W,H);panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-100);panel.BackgroundColor3=Color3.fromRGB(6,6,18);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,7);local ps=Instance.new("UIStroke",panel);ps.Color=Color3.fromRGB(180,60,255);ps.Thickness=1.2
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(20,8,45);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,7)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="GASTER FORM";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(6,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(200,120,255);tLbl.TextSize=11;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local animLbl=Instance.new("TextLabel",panel);animLbl.Text="FORM: POINTING";animLbl.Size=UDim2.new(1,-10,0,14);animLbl.Position=UDim2.fromOffset(6,31);animLbl.BackgroundTransparency=1;animLbl.TextColor3=Color3.fromRGB(130,130,255);animLbl.TextSize=9;animLbl.Font=Enum.Font.GothamBold;animLbl.TextXAlignment=Enum.TextXAlignment.Left
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
        local sg=Instance.new("ScreenGui");sg.Name="SphereSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.Parent=pg;sphereSubGui=sg
        local W,H=190,172;local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(W,H);panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-100);panel.BackgroundColor3=Color3.fromRGB(4,12,20);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,7);local ps=Instance.new("UIStroke",panel);ps.Color=Color3.fromRGB(60,180,255);ps.Thickness=1.2
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(8,20,45);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,7)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="SPHERE CONTROL";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(6,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(80,200,255);tLbl.TextSize=11;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local mLbl=Instance.new("TextLabel",panel);mLbl.Text="STATE: ORBIT";mLbl.Size=UDim2.new(1,-10,0,14);mLbl.Position=UDim2.fromOffset(6,31);mLbl.BackgroundTransparency=1;mLbl.TextColor3=Color3.fromRGB(80,180,255);mLbl.TextSize=9;mLbl.Font=Enum.Font.GothamBold;mLbl.TextXAlignment=Enum.TextXAlignment.Left
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
        local sg=Instance.new("ScreenGui");sg.Name="SphereBenderGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1001;sg.Parent=pg;sbSubGui=sg
        local W=205;local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(W,300);panel.Position=UDim2.new(0.5,-W-10,0.5,-150);panel.BackgroundColor3=Color3.fromRGB(5,8,20);panel.BorderSizePixel=0;panel.ClipsDescendants=false;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local stk=Instance.new("UIStroke",panel);stk.Color=Color3.fromRGB(0,200,255);stk.Thickness=1.4
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(4,18,40);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="SPHERE BENDER";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(0,220,255);tLbl.TextSize=12;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local yOff=32
        local function getSelMode()for _,sp in ipairs(sbSpheres)do if sp.selected then return sp.mode end end;return"orbit"end
        local mLbl=Instance.new("TextLabel",panel);mLbl.Text="STATE: "..getSelMode():upper();mLbl.Size=UDim2.new(1,-10,0,16);mLbl.Position=UDim2.fromOffset(6,yOff);mLbl.BackgroundTransparency=1;mLbl.TextColor3=Color3.fromRGB(0,180,255);mLbl.TextSize=9;mLbl.Font=Enum.Font.GothamBold;mLbl.TextXAlignment=Enum.TextXAlignment.Left;yOff=yOff+18
        for _,mb in ipairs({{txt="ORBIT",key="orbit",col=Color3.fromRGB(80,220,255)},{txt="FOLLOW",key="follow",col=Color3.fromRGB(120,255,160)},{txt="STAY",key="stay",col=Color3.fromRGB(255,200,80)}})do
            local btn=Instance.new("TextButton",panel);btn.Text=mb.txt;btn.Size=UDim2.new(1,-12,0,28);btn.Position=UDim2.fromOffset(6,yOff);btn.BackgroundColor3=Color3.fromRGB(6,18,36);btn.TextColor3=mb.col;btn.TextSize=11;btn.Font=Enum.Font.GothamBold;btn.BorderSizePixel=0;Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()for _,sp in ipairs(sbSpheres)do if sp.selected then sp.mode=mb.key;sp.stopped=false;sp.vel=Vector3.zero end end;mLbl.Text="STATE: "..mb.key:upper()end);yOff=yOff+32
        end
        local splitBtn=Instance.new("TextButton",panel);splitBtn.Text="SPLIT SPHERE";splitBtn.Size=UDim2.new(1,-12,0,26);splitBtn.Position=UDim2.fromOffset(6,yOff);splitBtn.BackgroundColor3=Color3.fromRGB(10,30,55);splitBtn.TextColor3=Color3.fromRGB(0,200,255);splitBtn.TextSize=11;splitBtn.Font=Enum.Font.GothamBold;splitBtn.BorderSizePixel=0;Instance.new("UICorner",splitBtn);yOff=yOff+30
        splitBtn.MouseButton1Click:Connect(function()
            local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local s=newSBSphere((root and root.Position or Vector3.new(0,5,0))+Vector3.new(math.random(-4,4),2,math.random(-4,4)));table.insert(sbSpheres,s);rebuildSBGui()
        end)
        for idx,sp in ipairs(sbSpheres)do
            local sBtn=Instance.new("TextButton",panel);sBtn.Text="SPHERE "..idx..(sp.stopped and"  [STOP]"or"  ["..sp.mode:upper().."]");sBtn.Size=UDim2.new(1,-12,0,26);sBtn.Position=UDim2.fromOffset(6,yOff);sBtn.BackgroundColor3=sp.selected and Color3.fromRGB(0,60,120) or Color3.fromRGB(6,18,36);sBtn.TextColor3=sp.selected and Color3.fromRGB(80,200,255) or Color3.fromRGB(140,140,180);sBtn.TextSize=9;sBtn.Font=Enum.Font.GothamBold;sBtn.BorderSizePixel=0;Instance.new("UICorner",sBtn)
            local cSp=sp;sBtn.MouseButton1Click:Connect(function()cSp.selected=not cSp.selected;sBtn.BackgroundColor3=cSp.selected and Color3.fromRGB(0,60,120) or Color3.fromRGB(6,18,36);sBtn.TextColor3=cSp.selected and Color3.fromRGB(80,200,255) or Color3.fromRGB(140,140,180)end);yOff=yOff+30
        end
        panel.Size=UDim2.fromOffset(W,yOff+8);makeDraggable(tBar,panel,false)
    end
    destroyGojoGui=function() if gojoSubGui and gojoSubGui.Parent then gojoSubGui:Destroy()end;gojoSubGui=nil end
    local function createGojoGui()
        destroyGojoGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="GojoSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.Parent=pg;gojoSubGui=sg
        local W,H=200,240;local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(W,H);panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-60);panel.BackgroundColor3=Color3.fromRGB(4,6,20);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local ps=Instance.new("UIStroke",panel);ps.Color=Color3.fromRGB(140,120,255);ps.Thickness=1.5
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(14,10,45);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="GOJO TECHNIQUES";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(180,160,255);tLbl.TextSize=11;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local stateLbl=Instance.new("TextLabel",panel);stateLbl.Text="STATE: IDLE";stateLbl.Size=UDim2.new(1,-10,0,14);stateLbl.Position=UDim2.fromOffset(6,30);stateLbl.BackgroundTransparency=1;stateLbl.TextColor3=Color3.fromRGB(100,100,200);stateLbl.TextSize=9;stateLbl.Font=Enum.Font.GothamBold;stateLbl.TextXAlignment=Enum.TextXAlignment.Left
        task.spawn(function()while gojoSubGui and gojoSubGui.Parent and scriptAlive do stateLbl.Text="STATE: "..gojoState:upper();task.wait(0.2)end end)
        local function gBtn(txt,yp,bg,fg)local b=Instance.new("TextButton",panel);b.Text=txt;b.Size=UDim2.new(1,-12,0,32);b.Position=UDim2.fromOffset(6,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=11;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b);return b end
        gBtn("MAX BLUE",48,Color3.fromRGB(8,25,65),Color3.fromRGB(60,140,255)).MouseButton1Click:Connect(function()task.spawn(fireMaxBlue)end)
        gBtn("REVERSAL RED",84,Color3.fromRGB(55,10,10),Color3.fromRGB(255,80,60)).MouseButton1Click:Connect(function()task.spawn(fireReversalRed)end)
        gBtn("HOLLOW PURPLE",120,Color3.fromRGB(35,5,55),Color3.fromRGB(180,80,255)).MouseButton1Click:Connect(function()task.spawn(fireHollowPurple)end)
        gBtn("DOMAIN: INFINITY",156,Color3.fromRGB(12,12,30),Color3.fromRGB(200,200,255)).MouseButton1Click:Connect(function()task.spawn(fireDEInfinity)end)
        gBtn("STOP / RESET",196,Color3.fromRGB(40,8,8),Color3.fromRGB(255,80,80)).MouseButton1Click:Connect(function()safeResetGojo()end)
        makeDraggable(tBar,panel,false)
    end
    destroyShrineGui=function() if shrineSubGui and shrineSubGui.Parent then shrineSubGui:Destroy()end;shrineSubGui=nil end
    local function createShrineGui()
        destroyShrineGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="ShrineSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.Parent=pg;shrineSubGui=sg
        local W,H=180,170;local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(W,H);panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-60);panel.BackgroundColor3=Color3.fromRGB(15,6,4);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local ps=Instance.new("UIStroke",panel);ps.Color=Color3.fromRGB(255,80,50);ps.Thickness=1.5
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(30,10,8);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="DE SHRINE";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(255,100,80);tLbl.TextSize=11;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local phaseLbl=Instance.new("TextLabel",panel);phaseLbl.Text="PHASE: INACTIVE";phaseLbl.Size=UDim2.new(1,-10,0,14);phaseLbl.Position=UDim2.fromOffset(6,30);phaseLbl.BackgroundTransparency=1;phaseLbl.TextColor3=Color3.fromRGB(200,120,100);phaseLbl.TextSize=9;phaseLbl.Font=Enum.Font.GothamBold;phaseLbl.TextXAlignment=Enum.TextXAlignment.Left
        task.spawn(function()while shrineSubGui and shrineSubGui.Parent and scriptAlive do phaseLbl.Text="PHASE: "..shrinePhase:upper();task.wait(0.3)end end)
        local function sBtn(txt,yp,bg,fg)local b=Instance.new("TextButton",panel);b.Text=txt;b.Size=UDim2.new(1,-12,0,30);b.Position=UDim2.fromOffset(6,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=11;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b);return b end
        sBtn("OPEN DOMAIN",50,Color3.fromRGB(45,12,8),Color3.fromRGB(255,100,80)).MouseButton1Click:Connect(function()
            if shrinePhase=="inactive" then
                local char=player.Character;local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
                if not root then return end
                shrineCenter=root.Position;assignShrineParts()
                for i,part in ipairs(shrinePartList)do setUnderground(part,i)end
                task.wait(0.05);shrinePhase="underground";shrineTimer=0
            end
        end)
        sBtn("CLOSE DOMAIN",85,Color3.fromRGB(8,8,8),Color3.fromRGB(150,150,180)).MouseButton1Click:Connect(function()
            if shrinePhase=="closed" then shrinePhase="opening";shrineTimer=0
            elseif shrinePhase~="inactive" then destroyShrine()end
        end)
        makeDraggable(tBar,panel,false)
    end
    destroyTankGui=function() if tankSubGui and tankSubGui.Parent then tankSubGui:Destroy()end;tankSubGui=nil end
    local function createTankGui()
        destroyTankGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="TankSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.Parent=pg;tankSubGui=sg
        local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(185,260);panel.Position=UDim2.new(0,10,0.5,-130);panel.BackgroundColor3=Color3.fromRGB(18,18,18);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local stk=Instance.new("UIStroke",panel);stk.Color=Color3.fromRGB(90,90,90);stk.Thickness=1.5
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(30,30,30);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="TANK";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(210,210,210);tLbl.TextSize=12;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local cx=(185-36)/2;local dy0=50;local bs=36;local gap=2
        local function dpBtn(t2,xp,yp)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.fromOffset(bs,bs);b.Position=UDim2.fromOffset(xp,yp);b.BackgroundColor3=Color3.fromRGB(40,40,55);b.TextColor3=Color3.fromRGB(200,200,255);b.TextSize=16;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b).CornerRadius=UDim.new(0,6);return b end
        local upBtn=dpBtn("^",cx,dy0);local leftBtn=dpBtn("<",cx-bs-gap,dy0+bs+gap);local rightBtn=dpBtn(">",cx+bs+gap,dy0+bs+gap);local downBtn=dpBtn("v",cx,dy0+bs*2+gap*2)
        upBtn.MouseButton1Down:Connect(function()tks.forward=1 end);upBtn.MouseButton1Up:Connect(function()tks.forward=0 end)
        downBtn.MouseButton1Down:Connect(function()tks.forward=-1 end);downBtn.MouseButton1Up:Connect(function()tks.forward=0 end)
        leftBtn.MouseButton1Down:Connect(function()tks.turn=-1 end);leftBtn.MouseButton1Up:Connect(function()tks.turn=0 end)
        rightBtn.MouseButton1Down:Connect(function()tks.turn=1 end);rightBtn.MouseButton1Up:Connect(function()tks.turn=0 end)
        local ay=dy0+bs*3+gap*2+8
        local function aBtn(t2,yp,bg,fg)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.new(1,-12,0,28);b.Position=UDim2.fromOffset(6,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=11;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b);return b end
        aBtn("FIRE",ay,Color3.fromRGB(65,35,12),Color3.fromRGB(255,200,80)).MouseButton1Click:Connect(function()shootProjectile()end)
        local hatchBtn=aBtn("OPEN HATCH",ay+32,Color3.fromRGB(30,45,60),Color3.fromRGB(120,200,255))
        hatchBtn.MouseButton1Click:Connect(function()toggleHatch();hatchBtn.Text=tks.hatchOpen and"CLOSE HATCH"or"OPEN HATCH"end)
        aBtn("DESTRUCT",ay+64,Color3.fromRGB(75,12,12),Color3.fromRGB(255,80,80)).MouseButton1Click:Connect(function()task.spawn(function()destroyTank();destroyTankGui()end)end)
        local conKBB=UserInputService.InputBegan:Connect(function(inp,proc)if proc then return end;if inp.KeyCode==Enum.KeyCode.W then tks.forward=1 elseif inp.KeyCode==Enum.KeyCode.S then tks.forward=-1 elseif inp.KeyCode==Enum.KeyCode.A then tks.turn=-1 elseif inp.KeyCode==Enum.KeyCode.D then tks.turn=1 elseif inp.KeyCode==Enum.KeyCode.F then if tks.insideTank then shootProjectile()end end end)
        local conKBE=UserInputService.InputEnded:Connect(function(inp,_)if inp.KeyCode==Enum.KeyCode.W or inp.KeyCode==Enum.KeyCode.S then tks.forward=0 elseif inp.KeyCode==Enum.KeyCode.A or inp.KeyCode==Enum.KeyCode.D then tks.turn=0 end end)
        sg.AncestryChanged:Connect(function(_,par)if not par then pcall(function()conKBB:Disconnect()end);pcall(function()conKBE:Disconnect()end);tks.forward=0;tks.turn=0 end end)
        makeDraggable(tBar,panel,false)
    end
    destroyCarGui=function() if carSubGui and carSubGui.Parent then carSubGui:Destroy()end;carSubGui=nil end
    local function createCarGui()
        destroyCarGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui");sg.Name="CarSubGUI";sg.ResetOnSpawn=false;sg.DisplayOrder=1000;sg.Parent=pg;carSubGui=sg
        local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(165,180);panel.Position=UDim2.new(0,10,0.5,-90);panel.BackgroundColor3=Color3.fromRGB(14,18,14);panel.BorderSizePixel=0;panel.Parent=sg;Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8);local stk=Instance.new("UIStroke",panel);stk.Color=Color3.fromRGB(60,160,60);stk.Thickness=1.5
        local tBar=Instance.new("Frame");tBar.Size=UDim2.new(1,0,0,28);tBar.BackgroundColor3=Color3.fromRGB(20,35,20);tBar.BorderSizePixel=0;tBar.ZIndex=10;tBar.Parent=panel;Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel",tBar);tLbl.Text="CAR";tLbl.Size=UDim2.new(1,-8,1,0);tLbl.Position=UDim2.fromOffset(8,0);tLbl.BackgroundTransparency=1;tLbl.TextColor3=Color3.fromRGB(120,220,120);tLbl.TextSize=12;tLbl.Font=Enum.Font.GothamBold;tLbl.TextXAlignment=Enum.TextXAlignment.Left;tLbl.ZIndex=10
        local cx2=(165-36)/2;local dy02=50;local bs2=36;local gap2=2
        local function dpBtn2(t2,xp,yp)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.fromOffset(bs2,bs2);b.Position=UDim2.fromOffset(xp,yp);b.BackgroundColor3=Color3.fromRGB(30,50,30);b.TextColor3=Color3.fromRGB(180,255,180);b.TextSize=16;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b).CornerRadius=UDim.new(0,6);return b end
        local upB=dpBtn2("^",cx2,dy02);local lB=dpBtn2("<",cx2-bs2-gap2,dy02+bs2+gap2);local rB=dpBtn2(">",cx2+bs2+gap2,dy02+bs2+gap2);local dnB=dpBtn2("v",cx2,dy02+bs2*2+gap2*2)
        upB.MouseButton1Down:Connect(function()carJoy.forward=1 end);upB.MouseButton1Up:Connect(function()carJoy.forward=0 end)
        dnB.MouseButton1Down:Connect(function()carJoy.forward=-1 end);dnB.MouseButton1Up:Connect(function()carJoy.forward=0 end)
        lB.MouseButton1Down:Connect(function()carJoy.turn=-1 end);lB.MouseButton1Up:Connect(function()carJoy.turn=0 end)
        rB.MouseButton1Down:Connect(function()carJoy.turn=1 end);rB.MouseButton1Up:Connect(function()carJoy.turn=0 end)
        local ay2=dy02+bs2*3+gap2*2+8
        local function aBtn2(t2,yp,bg,fg)local b=Instance.new("TextButton",panel);b.Text=t2;b.Size=UDim2.new(1,-12,0,28);b.Position=UDim2.fromOffset(6,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=11;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;Instance.new("UICorner",b);return b end
        local doorBtn2=aBtn2("OPEN DOOR",ay2,Color3.fromRGB(25,45,25),Color3.fromRGB(80,240,80))
        doorBtn2.MouseButton1Click:Connect(function()toggleCarDoor();doorBtn2.Text=cs.doorOpen and"CLOSE DOOR"or"OPEN DOOR"end)
        aBtn2("DESTROY",ay2+32,Color3.fromRGB(70,10,10),Color3.fromRGB(255,70,70)).MouseButton1Click:Connect(function()task.spawn(function()destroyCar();destroyCarGui()end)end)
        local conK1=UserInputService.InputBegan:Connect(function(inp,proc)if proc then return end;if inp.KeyCode==Enum.KeyCode.W then carJoy.forward=1 elseif inp.KeyCode==Enum.KeyCode.S then carJoy.forward=-1 elseif inp.KeyCode==Enum.KeyCode.A then carJoy.turn=-1 elseif inp.KeyCode==Enum.KeyCode.D then carJoy.turn=1 end end)
        local conK2=UserInputService.InputEnded:Connect(function(inp,_)if inp.KeyCode==Enum.KeyCode.W or inp.KeyCode==Enum.KeyCode.S then carJoy.forward=0 elseif inp.KeyCode==Enum.KeyCode.A or inp.KeyCode==Enum.KeyCode.D then carJoy.turn=0 end end)
        sg.AncestryChanged:Connect(function(_,par)if not par then pcall(function()conK1:Disconnect()end);pcall(function()conK2:Disconnect()end);carJoy.forward=0;carJoy.turn=0 end end)
        makeDraggable(tBar,panel,false)
    end

    -- ════ PET CHAT COMMAND HANDLER ════
    local function handlePetChat(playerSent, message)
        local msg=message:lower():match("^%s*(.-)%s*$")
        -- Only owner(s) or self can command
        local isOwner=(playerSent.Name==player.Name) or petOwners[playerSent.Name]
        if not isOwner then return end

        -- Titanic sub-commands (? prefix)
        if titanicActive then
            if msg=="?forward" then titanicFwd=1;return
            elseif msg=="?stop" then titanicFwd=0;titanicTurn=0;titanicSpd=0;return
            elseif msg=="?right" then titanicTurn=1;return
            elseif msg=="?left" then titanicTurn=-1;return
            elseif msg=="?anchor" then
                if not titanicAnchored then
                    titanicAnchored=true
                    -- Anchor chain drop animation: a few parts briefly drop then snap
                    local arr={};for part,_ in pairs(controlled)do if part and part.Parent then table.insert(arr,part)end end
                    local chainCount=math.min(6,#arr)
                    task.spawn(function()
                        for i=1,chainCount do
                            local part=arr[i];if not part then continue end
                            local data=controlled[part];if not(data and data.bp) then continue end
                            local origPos=data.bp.Position
                            data.bp.Position=origPos+Vector3.new(0,-8,0)
                            task.wait(0.05)
                            data.bp.Position=origPos
                        end
                    end)
                end
                return
            elseif msg=="?unanchor" then titanicAnchored=false;return
            elseif msg=="?sink" then titanicSinking=true;titanicSinkT=0;return
            end
        end

        -- Main ! commands
        if msg:sub(1,1)~="!" then return end
        local cmd=msg:sub(2):match("^%s*(.-)%s*$")

        -- State commands
        if cmd=="follow" then petState="follow";petThronePos=nil
        elseif cmd=="orbit" then petState="orbit";petThronePos=nil
        elseif cmd=="trail" then petState="trail";petThronePos=nil
        elseif cmd=="dance" then petState="dance";petThronePos=nil
        elseif cmd=="ring" then petState="ring";petThronePos=nil
        elseif cmd=="wall" then petState="wall";petThronePos=nil
        elseif cmd=="heart" then petState="heart";petThronePos=nil
        elseif cmd=="sphere" then petState="sphere";petThronePos=nil
        elseif cmd=="wings" then petState="wings";petThronePos=nil
        elseif cmd=="tornado" then petState="tornado";petTornadoAngle=0;petThronePos=nil
        elseif cmd=="blackhole" then petState="blackhole";petThronePos=nil
        elseif cmd=="rain" then petState="rain";petRainDrops={};petThronePos=nil
        elseif cmd=="throne" then
            petThronePos=nil -- will be set on first frame using owner position
            local ownerRoot=getPlayerRoot(playerSent.Name) or (player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
            if ownerRoot then petThronePos=ownerRoot.Position end
            petState="throne"
        elseif cmd=="judgement sword" then
            petState="judgement_sword";petSwordSwinging=true;petSwordSwingT=0
        elseif cmd=="stop" then petState="stop"
        elseif cmd=="carpet" then petState="carpet";for _,oname in ipairs(petOwnerList)do applyCarpetBoost(oname)end
        elseif cmd=="guard" then petGuardActive=not petGuardActive;petState=petGuardActive and"guard"or"follow"
        elseif cmd=="hollow purple" then
            task.spawn(function()doPetHollowPurple(playerSent.Name)end)

        -- Spin FIX: now properly sets petSpinSpeed which is used in moveParts
        elseif cmd:sub(1,4)=="spin" then
            local spd=tonumber(cmd:match("spin%s+(%S+)"))
            petSpinSpeed=spd or 0

        -- Say FIX: stores text so pixel-font rendering runs in moveParts
        elseif cmd:sub(1,3)=="say" then
            local txt=cmd:match("say%s+(.*)")
            if txt and #txt>0 then
                petSayText=txt:upper()
                petState="say"
            end

        -- Attack FIX
        elseif cmd:sub(1,6)=="attack" then
            local tname=cmd:match("attack%s+(.+)")
            if tname and not petAttackFired then
                petAttackTarget=tname:match("^%s*(.-)%s*$")
                task.spawn(doPetAttackFling)
            end

        -- Bring FIX
        elseif cmd:sub(1,5)=="bring" then
            local tname=cmd:match("bring%s+(.+)")
            if tname then task.spawn(function()doPetBring(tname:match("^%s*(.-)%s*$"))end)end

        -- GoTo FIX
        elseif cmd:sub(1,5)=="gotto" then
            local tname=cmd:match("gotto%s+(.+)")
            if tname then task.spawn(function()doPetGoTo(tname:match("^%s*(.-)%s*$"))end)end

        -- Slap
        elseif cmd:sub(1,4)=="slap" then
            local tname=cmd:match("slap%s+(.+)")
            if tname then task.spawn(function()doPetSlap(tname:match("^%s*(.-)%s*$"))end)end

        -- Titanic mode toggle
        elseif cmd=="titanic" then
            if petState~="titanic" then
                local ownerRoot=getPlayerRoot(playerSent.Name) or (player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
                if ownerRoot then
                    titanicCF=CFrame.new(ownerRoot.Position+Vector3.new(0,5,0))
                    titanicSpd=0;titanicFwd=0;titanicTurn=0
                    titanicActive=true;titanicAnchored=false;titanicSinking=false;titanicSinkT=0
                    petState="titanic"
                end
            else
                petState="follow";titanicActive=false;titanicAnchored=false
                titanicSinking=false;restoreAllColors()
            end

        -- Dist / Radius
        elseif cmd:sub(1,4)=="dist" then
            local v=tonumber(cmd:match("dist%s+(%S+)"));if v then petOrbitDist=v end
        elseif cmd:sub(1,2)=="r+" then
            petOrbitDist=petOrbitDist+2
        elseif cmd:sub(1,2)=="r-" then
            petOrbitDist=math.max(1,petOrbitDist-2)

        -- Color
        elseif cmd:sub(1,5)=="color" then
            local r,g,b=cmd:match("color%s+(%d+)%s+(%d+)%s+(%d+)")
            if r then colorAllControlled(Color3.fromRGB(tonumber(r),tonumber(g),tonumber(b)),Enum.Material.Neon)end

        -- Add/remove owner
        elseif cmd:sub(1,8)=="addowner" then
            local oname=cmd:match("addowner%s+(.+)");if oname then
                oname=oname:match("^%s*(.-)%s*$");petOwners[oname]=true;petSplitOwners={}
                if not table.find(petOwnerList,oname)then table.insert(petOwnerList,oname)end
            end
        elseif cmd:sub(1,11)=="removeowner" then
            local oname=cmd:match("removeowner%s+(.+)");if oname then
                oname=oname:match("^%s*(.-)%s*$");petOwners[oname]=nil;petSplitOwners={}
                for i,n in ipairs(petOwnerList)do if n==oname then table.remove(petOwnerList,i);break end end
            end
        end
    end

    -- Chat listener
    local chatConn
    local function connectChat()
        if chatConn then pcall(function()chatConn:Disconnect()end)end
        chatConn=Players.PlayerAdded:Connect(function()end) -- placeholder, real below
        -- Listen to all players' chat
        local function hookPlayer(p2)
            p2.Chatted:Connect(function(msg)
                if petActive and PET_MODES[activeMode] then
                    handlePetChat(p2,msg)
                end
            end)
        end
        for _,p2 in ipairs(Players:GetPlayers())do hookPlayer(p2)end
        Players.PlayerAdded:Connect(hookPlayer)
    end
    connectChat()

    -- ════ MAIN HEARTBEAT LOOP ════
    local t=0
    RunService.Heartbeat:Connect(function(dt)
        if not scriptAlive then return end
        t=t+dt

        local char=player.Character
        local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local rootPos=root and root.Position or Vector3.new(0,5,0)
        local rootCF=root and root.CFrame or CFrame.new(rootPos)

        -- Snake history (used by snake mode + !trail)
        if root then
            table.insert(snakeHistory,1,rootPos)
            if #snakeHistory>SNAKE_HIST_MAX then snakeHistory[SNAKE_HIST_MAX+1]=nil end
        end

        -- Titanic steering update
        if titanicActive and petState=="titanic" and not titanicAnchored then
            if titanicSinking then
                titanicSinkT=titanicSinkT+dt
                -- Slowly tip bow down while drifting
                local sinkFrac=math.clamp(titanicSinkT/28,0,1)
                titanicCF=CFrame.new(titanicCF.Position+Vector3.new(0,-sinkFrac*0.04,0))*CFrame.Angles(-sinkFrac*math.rad(18),titanicCF:ToEulerAnglesXYZ() and select(2,titanicCF:ToEulerAnglesXYZ()) or 0,0)
            else
                -- Accelerate / decelerate
                titanicSpd=titanicSpd+titanicFwd*TITAN_ACCEL*dt
                titanicSpd=titanicSpd*TITAN_FRIC
                titanicSpd=math.clamp(titanicSpd,-TITAN_SPD*0.5,TITAN_SPD)
                local turnSpd=titanicTurn*TITAN_TRN*dt*(math.abs(titanicSpd)/TITAN_SPD)
                local fwd=titanicCF.LookVector
                local newPos=titanicCF.Position+fwd*titanicSpd*dt
                titanicCF=CFrame.new(newPos)*CFrame.Angles(0,math.atan2(-titanicCF.LookVector.X,titanicCF.LookVector.Z)+turnSpd,0)
            end
        end

        -- Lock mode
        if lockedBlocks then lockAllNow();return end

        if not isActivated then return end

        -- Collect parts list
        local partList={}
        for part,_ in pairs(controlled)do if part and part.Parent then table.insert(partList,part)end end
        local n=#partList

        -- Spin angle update
        if spinSpeed~=0 then spinAngle=spinAngle+spinSpeed*dt end

        -- ── SNAKE MODE ──
        if activeMode=="snake" then
            for i,part in ipairs(partList)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local target=getSnakeTarget(i)
                data.bp.P=900000;data.bp.D=30000;data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                data.bp.Position=target
                if data.bg and data.bg.Parent then
                    if i<#partList then
                        local nextT=getSnakeTarget(i+1)
                        local dir=(target-nextT)
                        if dir.Magnitude>0.01 then data.bg.CFrame=CFrame.new(target,target+dir)end
                    end
                end
            end

        -- ── CFRAME MODES ──
        elseif CFRAME_MODES[activeMode] then
            if GASTER_MODES[activeMode] then
                gasterT=gasterT+dt
                local handSlots=activeMode=="gasterhand" and HAND_SLOTS_COUNT or HAND_SLOTS_COUNT*2
                for i,part in ipairs(partList)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local targetCF
                    if activeMode=="gasterhand" then
                        local slotIdx=((i-1)%HAND_SLOTS_COUNT)+1
                        targetCF=getGasterCF(slotIdx,1,rootCF,gasterT)
                    else
                        local half=math.ceil(n/2);local side,slotIdx
                        if i<=half then side=1;slotIdx=((i-1)%HAND_SLOTS_COUNT)+1
                        else side=-1;slotIdx=((i-half-1)%HAND_SLOTS_COUNT)+1 end
                        targetCF=getGasterCF(slotIdx,side,rootCF,gasterT)
                    end
                    data.bp.P=600000;data.bp.D=20000;data.bp.MaxForce=Vector3.new(1e11,1e11,1e11)
                    data.bp.Position=targetCF.Position
                end
            elseif SPHERE_MODES[activeMode] then
                updateSphereTarget(dt,rootPos)
                for i,part in ipairs(partList)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local shellOffset=getSphereShellPos(i,n)
                    data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                    data.bp.Position=spherePos+shellOffset
                end
            elseif SPHERE_BENDER_MODES[activeMode] then
                updateSphereBenderTargets(dt,rootPos)
                local perSphere=math.max(1,math.ceil(n/math.max(1,#sbSpheres)))
                for i,part in ipairs(partList)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local spIdx=math.floor((i-1)/perSphere)+1;local sp=sbSpheres[spIdx] or sbSpheres[#sbSpheres]
                    if not sp then continue end
                    local localIdx=(i-1)%perSphere+1
                    local shellOff=getSphereShellPos(localIdx,perSphere)
                    data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                    data.bp.Position=sp.pos+shellOff
                end
            elseif TANK_MODES[activeMode] then
                if tankActive and tks.tankBase then
                    local rayList={};for _,p2 in ipairs(tks.tankParts)do if p2 then table.insert(rayList,p2)end end
                    local char2=player.Character;if char2 then for _,p2 in ipairs(char2:GetDescendants())do if p2:IsA("BasePart")then table.insert(rayList,p2)end end end
                    tankRayParams.FilterDescendantsInstances=rayList
                    -- Ground ray
                    local rayResult=workspace:Raycast(tks.tankBase.Position,Vector3.new(0,-TANK_H-4,0),tankRayParams)
                    local groundY=rayResult and rayResult.Position.Y or(tks.tankBase.Position.Y-TANK_H/2)
                    local targetY=groundY+TANK_H/2+0.3
                    local targetPos=tks.tankBase.Position;targetPos=Vector3.new(targetPos.X,targetY,targetPos.Z)
                    -- Drive
                    tks.currentSpeed=tks.currentSpeed+tks.forward*TANK_ACCEL*dt
                    tks.currentSpeed=tks.currentSpeed*TANK_FRIC
                    tks.currentSpeed=math.clamp(tks.currentSpeed,-TANK_SPEED*0.5,TANK_SPEED)
                    tks.currentTurnSpeed=tks.currentTurnSpeed+tks.turn*4*dt
                    tks.currentTurnSpeed=tks.currentTurnSpeed*0.82
                    local tankFwd=tks.tankBase.CFrame.LookVector
                    local newPos=targetPos+tankFwd*tks.currentSpeed*dt
                    local newAngle=math.atan2(-tankFwd.X,tankFwd.Z)+tks.currentTurnSpeed*dt*TANK_TURN
                    local newCF=CFrame.new(newPos)*CFrame.Angles(0,newAngle,0)
                    -- Update all tank parts
                    local tankData=controlled[tks.tankBase]
                    if tankData and tankData.bp and tankData.bp.Parent then
                        tankData.bp.P=1500000;tankData.bp.D=50000;tankData.bp.MaxForce=Vector3.new(1e13,1e13,1e13)
                        tankData.bp.Position=newCF.Position
                        if tankData.bg and tankData.bg.Parent then tankData.bg.P=800000;tankData.bg.D=40000;tankData.bg.CFrame=newCF end
                    end
                    for idx,part in ipairs(tks.tankParts)do
                        if part==tks.tankBase then continue end
                        local off=tks.partOffsets[idx];if not off then continue end
                        local pdata=controlled[part];if not(pdata and pdata.bp and pdata.bp.Parent)then continue end
                        local target2=newCF*off
                        pdata.bp.P=1200000;pdata.bp.D=40000;pdata.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                        pdata.bp.Position=target2.Position
                        if pdata.bg and pdata.bg.Parent then pdata.bg.P=600000;pdata.bg.D=30000;pdata.bg.CFrame=newCF*CFrame.Angles(off:ToEulerAnglesXYZ()) end
                    end
                    -- Freeze player inside tank
                    if tks.insideTank then
                        local chr3=player.Character;local hrp3=chr3 and chr3:FindFirstChild("HumanoidRootPart")
                        if hrp3 then hrp3.CFrame=newCF*CFrame.new(0,TANK_INTERIOR_Y,0) end
                    end
                    -- Orbit camera when inside
                    if tks.insideTank and not tks.hatchOpen then
                        local cam=workspace.CurrentCamera;cam.CameraType=Enum.CameraType.Scriptable
                        local camPos=newCF.Position+Vector3.new(math.cos(cameraOrbitAngle)*math.cos(cameraPitchAngle)*CAMERA_DIST,math.sin(cameraPitchAngle)*CAMERA_DIST,math.sin(cameraOrbitAngle)*math.cos(cameraPitchAngle)*CAMERA_DIST)
                        cam.CFrame=CFrame.new(camPos,newCF.Position)
                    end
                end
            elseif CAR_MODES[activeMode] then
                if carActive and cs.carBase then
                    local rayList2={};for _,p2 in ipairs(cs.carParts)do if p2 then table.insert(rayList2,p2)end end
                    carRayParams.FilterDescendantsInstances=rayList2
                    local rayResult2=workspace:Raycast(cs.carBase.Position,Vector3.new(0,-CAR_H-3,0),carRayParams)
                    local groundY2=rayResult2 and rayResult2.Position.Y or(cs.carBase.Position.Y-CAR_H/2)
                    local targetY2=groundY2+CAR_H/2+0.2
                    local carPos=cs.carBase.Position;carPos=Vector3.new(carPos.X,targetY2,carPos.Z)
                    cs.currentSpeed=cs.currentSpeed+carJoy.forward*CAR_ACCEL*dt
                    cs.currentSpeed=cs.currentSpeed*CAR_FRIC
                    cs.currentSpeed=math.clamp(cs.currentSpeed,-CAR_SPEED*0.4,CAR_SPEED)
                    cs.currentTurnSpeed=cs.currentTurnSpeed+carJoy.turn*5*dt
                    cs.currentTurnSpeed=cs.currentTurnSpeed*0.80
                    local carFwd=cs.carBase.CFrame.LookVector
                    local newCarPos=carPos+carFwd*cs.currentSpeed*dt
                    local newCarAngle=math.atan2(-carFwd.X,carFwd.Z)+cs.currentTurnSpeed*dt*CAR_TURN
                    local newCarCF=CFrame.new(newCarPos)*CFrame.Angles(0,newCarAngle,0)
                    local carData=controlled[cs.carBase]
                    if carData and carData.bp and carData.bp.Parent then
                        carData.bp.P=1200000;carData.bp.D=40000;carData.bp.MaxForce=Vector3.new(1e12,1e12,1e12);carData.bp.Position=newCarCF.Position
                        if carData.bg and carData.bg.Parent then carData.bg.P=600000;carData.bg.D=30000;carData.bg.CFrame=newCarCF end
                    end
                    for idx,part in ipairs(cs.carParts)do
                        if part==cs.carBase then continue end
                        local off=cs.partOffsets[idx];if not off then continue end
                        local pdata=controlled[part];if not(pdata and pdata.bp and pdata.bp.Parent)then continue end
                        pdata.bp.P=900000;pdata.bp.D=30000;pdata.bp.MaxForce=Vector3.new(1e11,1e11,1e11)
                        pdata.bp.Position=(newCarCF*off).Position
                        if pdata.bg and pdata.bg.Parent then pdata.bg.P=400000;pdata.bg.D=20000;pdata.bg.CFrame=newCarCF end
                    end
                    if not cs.doorOpen then
                        local chr4=player.Character;local hrp4=chr4 and chr4:FindFirstChild("HumanoidRootPart")
                        if hrp4 then hrp4.CFrame=newCarCF*CFrame.new(0,CAR_INTERIOR_Y,0) end
                    end
                end
            elseif SHRINE_MODES[activeMode] then
                updateShrine(dt,t)
            elseif GOJO_MODES[activeMode] then
                -- DE Infinity spinning wall
                if gojoState=="de_infinity" then
                    gojoInfinityAngle=gojoInfinityAngle+dt*0.6
                    for i,part in ipairs(partList)do
                        local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                        local phi=(1+math.sqrt(5))/2;local idx=i-1;local s=math.max(n,1)
                        local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+gojoInfinityAngle
                        data.bp.P=600000;data.bp.D=22000;data.bp.MaxForce=Vector3.new(1e11,1e11,1e11)
                        data.bp.Position=rootPos+Vector3.new(gojoInfinityRadius*math.sin(theta)*math.cos(ang),gojoInfinityRadius*math.sin(theta)*math.sin(ang),gojoInfinityRadius*math.cos(theta))
                    end
                elseif gojoState=="idle" then
                    gojoOrbitAngle=gojoOrbitAngle+dt*0.4
                    for i,part in ipairs(partList)do
                        local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                        local ang=((i-1)/math.max(n,1))*math.pi*2+gojoOrbitAngle
                        data.bp.P=400000;data.bp.D=14000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                        data.bp.Position=rootPos+Vector3.new(math.cos(ang)*8,math.sin(t*0.8+i*0.5)*1.5+1.5,math.sin(ang)*8)
                    end
                end
            elseif PET_MODES[activeMode] then
                -- Pet mode: per-owner movement
                if #petOwnerList==0 then
                    moveParts(partList,rootPos,petOrbitDist,t,petState)
                    if petGuardActive then doPetGuard(rootPos)end
                else
                    for _,oname in ipairs(petOwnerList)do
                        local ownerRoot=getPlayerRoot(oname)
                        local oPos=ownerRoot and ownerRoot.Position or rootPos
                        local ownerParts=getParts(oname)
                        if #ownerParts>0 then
                            moveParts(ownerParts,oPos,petOrbitDist,t,petState)
                        end
                        if petGuardActive then doPetGuard(oPos)end
                    end
                end
            else
                -- Standard CFrame modes: heart, rings, wall, box, wings
                for i,part in ipairs(partList)do
                    local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                    local targetCF=getFormationCF(activeMode,i,n,rootPos,rootCF,t+spinAngle)
                    data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                    data.bp.Position=targetCF.Position
                    if data.bg and data.bg.Parent then data.bg.CFrame=targetCF end
                end
            end

        -- ── PULL MODE ──
        elseif activeMode=="pull" then
            for i,part in ipairs(partList)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local aimPt,_=getAimPoint(30)
                data.bp.P=pullStrength;data.bp.D=math.max(50,pullStrength*0.05);data.bp.MaxForce=Vector3.new(1e12,1e12,1e12)
                data.bp.Position=aimPt+Vector3.new((i%3-1)*0.5,(math.floor(i/3)%3-1)*0.5,0)
            end

        -- ── FLY MODE ──
        elseif activeMode=="fly" then
            for i,part in ipairs(partList)do
                local data=controlled[part];if not(data and data.bp and data.bp.Parent)then continue end
                local phi=(1+math.sqrt(5))/2;local idx=i-1;local s=math.max(n,1)
                local theta=math.acos(math.clamp(1-2*(idx+0.5)/s,-1,1));local ang=2*math.pi*idx/phi+spinAngle
                data.bp.P=500000;data.bp.D=18000;data.bp.MaxForce=Vector3.new(1e10,1e10,1e10)
                data.bp.Position=rootPos+Vector3.new(radius*math.sin(theta)*math.cos(ang),radius*math.sin(theta)*math.sin(ang),radius*math.cos(theta))
            end
        end
    end)

    -- ════ MAIN GUI ════
    local pg=player:WaitForChild("PlayerGui")
    local mainGui=Instance.new("ScreenGui");mainGui.Name="ManipKiiV17";mainGui.ResetOnSpawn=false;mainGui.DisplayOrder=999;mainGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;mainGui.Parent=pg

    local W,H=260,580
    local panel=Instance.new("Frame");panel.Name="MainPanel";panel.Size=UDim2.fromOffset(W,H)
    panel.Position=UDim2.new(0,10,0.5,-H/2);panel.BackgroundColor3=Color3.fromRGB(7,7,14)
    panel.BorderSizePixel=0;panel.ClipsDescendants=true;panel.Parent=mainGui
    Instance.new("UICorner",panel).CornerRadius=UDim.new(0,10)
    local mainStroke=Instance.new("UIStroke",panel);mainStroke.Color=Color3.fromRGB(60,60,120);mainStroke.Thickness=1.5

    -- Title bar
    local titleBar=Instance.new("Frame");titleBar.Size=UDim2.new(1,0,0,34);titleBar.BackgroundColor3=Color3.fromRGB(10,10,28)
    titleBar.BorderSizePixel=0;titleBar.ZIndex=10;titleBar.Parent=panel;Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,10)
    local titleLbl=Instance.new("TextLabel",titleBar);titleLbl.Text="MANIPULATOR KII v17"
    titleLbl.Size=UDim2.new(1,-10,1,0);titleLbl.Position=UDim2.fromOffset(10,0);titleLbl.BackgroundTransparency=1
    titleLbl.TextColor3=Color3.fromRGB(140,140,255);titleLbl.TextSize=13;titleLbl.Font=Enum.Font.GothamBold
    titleLbl.TextXAlignment=Enum.TextXAlignment.Left;titleLbl.ZIndex=10

    -- Status bar
    local statusLbl=Instance.new("TextLabel",panel);statusLbl.Size=UDim2.new(1,-10,0,14)
    statusLbl.Position=UDim2.fromOffset(6,36);statusLbl.BackgroundTransparency=1
    statusLbl.TextColor3=Color3.fromRGB(80,80,160);statusLbl.TextSize=9;statusLbl.Font=Enum.Font.GothamBold
    statusLbl.TextXAlignment=Enum.TextXAlignment.Left;statusLbl.ZIndex=10;statusLbl.Text="Inactive | Parts: 0"
    task.spawn(function()
        while mainGui and mainGui.Parent and scriptAlive do
            local modeStr=isActivated and activeMode:upper() or "OFF"
            statusLbl.Text=modeStr.." | Parts: "..partCount.." | R: "..radius
            task.wait(0.3)
        end
    end)

    local yOff=52

    -- Helpers for main GUI buttons
    local function mBtn(txt,yp,bg,fg,ht)
        local b=Instance.new("TextButton",panel);b.Text=txt
        b.Size=UDim2.new(1,-12,0,ht or 26);b.Position=UDim2.fromOffset(6,yp)
        b.BackgroundColor3=bg or Color3.fromRGB(18,18,35);b.TextColor3=fg or Color3.fromRGB(180,180,255)
        b.TextSize=10;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;b.ZIndex=10
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,5)
        return b
    end
    local function mLabel(txt,yp)
        local l=Instance.new("TextLabel",panel);l.Text=txt;l.Size=UDim2.new(1,-12,0,13)
        l.Position=UDim2.fromOffset(6,yp);l.BackgroundTransparency=1;l.TextColor3=Color3.fromRGB(60,60,110)
        l.TextSize=8;l.Font=Enum.Font.GothamBold;l.TextXAlignment=Enum.TextXAlignment.Left;l.ZIndex=10;return l
    end

    -- Scan & Detect (v17 FIX)
    local scanBtn=mBtn("SCAN (Grab All)",yOff,Color3.fromRGB(12,30,60),Color3.fromRGB(80,180,255));yOff=yOff+28
    scanBtn.MouseButton1Click:Connect(function()sweepMap()end)

    local detectBtn=mBtn("DETECT + PULL ALL",yOff,Color3.fromRGB(5,50,20),Color3.fromRGB(60,255,140));yOff=yOff+28
    detectBtn.MouseButton1Click:Connect(function()task.spawn(detectAndPull)end)

    local releaseBtn=mBtn("RELEASE ALL",yOff,Color3.fromRGB(50,10,10),Color3.fromRGB(255,80,80));yOff=yOff+28
    releaseBtn.MouseButton1Click:Connect(function()isActivated=false;releaseAll()end)

    -- Lock toggle
    local lockBtn=mBtn("LOCK: OFF",yOff,Color3.fromRGB(18,18,18),Color3.fromRGB(160,160,160));yOff=yOff+28
    lockBtn.MouseButton1Click:Connect(function()
        lockedBlocks=not lockedBlocks
        lockBtn.Text="LOCK: "..(lockedBlocks and"ON"or"OFF")
        lockBtn.BackgroundColor3=lockedBlocks and Color3.fromRGB(50,40,8) or Color3.fromRGB(18,18,18)
        lockBtn.TextColor3=lockedBlocks and Color3.fromRGB(255,220,60) or Color3.fromRGB(160,160,160)
    end)

    yOff=yOff+4;mLabel("FORMATION MODES",yOff);yOff=yOff+14

    local formationModes={
        {"Heart","heart",Color3.fromRGB(255,60,120)},
        {"Rings","rings",Color3.fromRGB(80,180,255)},
        {"Wall","wall",Color3.fromRGB(180,180,60)},
        {"Box","box",Color3.fromRGB(120,200,120)},
        {"Wings","wings",Color3.fromRGB(200,140,255)},
        {"Snake","snake",Color3.fromRGB(255,160,60)},
        {"Pull","pull",Color3.fromRGB(255,100,60)},
        {"Fly","fly",Color3.fromRGB(60,220,255)},
    }
    local col=0
    for _,fm in ipairs(formationModes)do
        local xp=6+col*(W/2-8)
        local b=Instance.new("TextButton",panel);b.Text=fm[1]
        b.Size=UDim2.fromOffset(W/2-10,24);b.Position=UDim2.fromOffset(xp,yOff)
        b.BackgroundColor3=Color3.fromRGB(12,12,24);b.TextColor3=fm[3]
        b.TextSize=10;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;b.ZIndex=10
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,4)
        local modeName=fm[2]
        b.MouseButton1Click:Connect(function()
            activeMode=modeName;isActivated=true
            -- Sub-guis
            if modeName=="gasterhand" then createGasterGui()
            elseif modeName=="gaster2hands" then createGasterGui()
            else destroyGasterGui()end
            if SPHERE_MODES[modeName] then createSphereGui()else destroySphereGui()end
            if SPHERE_BENDER_MODES[modeName] then rebuildSBGui()else destroySphereBenderGui()end
            if not PET_MODES[modeName] then petActive=false;destroyPetGui()end
            if not SHRINE_MODES[modeName] then shrineActive=false end
            if not GOJO_MODES[modeName] then gojoActive=false end
            if not TANK_MODES[modeName] then tankActive=false end
            if not CAR_MODES[modeName] then carActive=false end
            statusLbl.Text=modeName:upper().." | Parts: "..partCount
        end)
        col=col+1;if col>=2 then col=0;yOff=yOff+26 end
    end
    if col~=0 then yOff=yOff+26 end

    yOff=yOff+4;mLabel("SPECIAL MODES",yOff);yOff=yOff+14

    local specialModes={
        {"Gaster Hand","gasterhand",Color3.fromRGB(180,80,255)},
        {"Gaster 2 Hands","gaster2hands",Color3.fromRGB(200,100,255)},
        {"Sphere","sphere",Color3.fromRGB(60,200,255)},
        {"Sphere Bender","spherebender",Color3.fromRGB(0,200,255)},
        {"DE Shrine","de_shrine",Color3.fromRGB(255,80,50)},
        {"Gojo Mode","gojo",Color3.fromRGB(160,120,255)},
        {"Tank","tank",Color3.fromRGB(160,160,100)},
        {"Car","car",Color3.fromRGB(80,200,80)},
        {"Pet Mode","pet",Color3.fromRGB(80,200,255)},
    }
    for _,sm in ipairs(specialModes)do
        local b=mBtn(sm[1],yOff,Color3.fromRGB(12,12,24),sm[3]);yOff=yOff+28
        local modeName=sm[2]
        b.MouseButton1Click:Connect(function()
            activeMode=modeName;isActivated=true
            -- Cleanup old modes
            if not GASTER_MODES[modeName] then destroyGasterGui()end
            if not SPHERE_MODES[modeName] then destroySphereGui()end
            if not SPHERE_BENDER_MODES[modeName] then destroySphereBenderGui()end
            if GASTER_MODES[modeName] then createGasterGui()end
            if SPHERE_MODES[modeName] then spherePos=rootPos or Vector3.new(0,5,0);createSphereGui()end
            if SPHERE_BENDER_MODES[modeName] then if #sbSpheres==0 then local r2=player.Character and(player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"));table.insert(sbSpheres,newSBSphere(r2 and r2.Position or Vector3.new(0,5,0)))end;rebuildSBGui()end
            if SHRINE_MODES[modeName] then if not shrineActive then shrineActive=true;createShrineGui()end
            else destroyShrineGui();if shrineActive then destroyShrine()end end
            if GOJO_MODES[modeName] then if not gojoActive then gojoActive=true;createGojoGui()end
            else destroyGojoGui();if gojoActive then destroyGojo()end end
            if TANK_MODES[modeName] then
                if not tankActive then
                    local chr5=player.Character;local r5=chr5 and(chr5:FindFirstChild("HumanoidRootPart") or chr5:FindFirstChild("Torso"))
                    if r5 and buildTankFromParts(r5.Position,r5.CFrame)then
                        tankActive=true;freezePlayer(r5.CFrame*CFrame.new(0,TANK_INTERIOR_Y,0))
                        tks.insideTank=true;createTankGui()
                    end
                end
            else destroyTankGui();if tankActive then destroyTank()end end
            if CAR_MODES[modeName] then
                if not carActive then
                    local chr6=player.Character;local r6=chr6 and(chr6:FindFirstChild("HumanoidRootPart") or chr6:FindFirstChild("Torso"))
                    if r6 and buildCarFromParts(r6.Position,r6.CFrame)then carActive=true;createCarGui()end
                end
            else destroyCarGui();if carActive then destroyCar()end end
            if PET_MODES[modeName] then
                if not petActive then petActive=true;createPetGui()end
            else petActive=false;destroyPetGui()end
        end)
    end

    yOff=yOff+4;mLabel("RADIUS / STRENGTH / SPIN",yOff);yOff=yOff+14

    -- Radius slider row
    local function numRow(labelTxt,getVal,setVal,stepUp,stepDown,yp)
        local lbl=Instance.new("TextLabel",panel);lbl.Size=UDim2.fromOffset(80,22);lbl.Position=UDim2.fromOffset(6,yp)
        lbl.BackgroundTransparency=1;lbl.TextColor3=Color3.fromRGB(120,120,200);lbl.TextSize=9;lbl.Font=Enum.Font.GothamBold
        lbl.TextXAlignment=Enum.TextXAlignment.Left;lbl.ZIndex=10
        task.spawn(function()while mainGui and mainGui.Parent and scriptAlive do lbl.Text=labelTxt..tostring(getVal());task.wait(0.2)end end)
        local minBtn=Instance.new("TextButton",panel);minBtn.Text="-";minBtn.Size=UDim2.fromOffset(26,22);minBtn.Position=UDim2.fromOffset(W-68,yp)
        minBtn.BackgroundColor3=Color3.fromRGB(30,10,10);minBtn.TextColor3=Color3.fromRGB(255,80,80);minBtn.TextSize=14;minBtn.Font=Enum.Font.GothamBold;minBtn.BorderSizePixel=0;minBtn.ZIndex=10;Instance.new("UICorner",minBtn).CornerRadius=UDim.new(0,4)
        local plusBtn=Instance.new("TextButton",panel);plusBtn.Text="+";plusBtn.Size=UDim2.fromOffset(26,22);plusBtn.Position=UDim2.fromOffset(W-38,yp)
        plusBtn.BackgroundColor3=Color3.fromRGB(10,30,10);plusBtn.TextColor3=Color3.fromRGB(80,255,80);plusBtn.TextSize=14;plusBtn.Font=Enum.Font.GothamBold;plusBtn.BorderSizePixel=0;plusBtn.ZIndex=10;Instance.new("UICorner",plusBtn).CornerRadius=UDim.new(0,4)
        minBtn.MouseButton1Click:Connect(function()setVal(stepDown(getVal()))end)
        plusBtn.MouseButton1Click:Connect(function()setVal(stepUp(getVal()))end)
    end
    numRow("Radius: ",function()return radius end,function(v)radius=v end,function(v)return v+1 end,function(v)return math.max(1,v-1)end,yOff);yOff=yOff+26
    numRow("Strength: ",function()return pullStrength end,function(v)pullStrength=v;applyStrengthToAll()end,function(v)return v+5000 end,function(v)return math.max(1000,v-5000)end,yOff);yOff=yOff+26
    numRow("Spin: ",function()return spinSpeed end,function(v)spinSpeed=v;petSpinSpeed=v end,function(v)return v+0.5 end,function(v)return v-0.5 end,yOff);yOff=yOff+26

    -- Color picker row
    yOff=yOff+2;mLabel("QUICK COLOR",yOff);yOff=yOff+14
    local colors={
        {"Red",Color3.fromRGB(255,50,50)},{"Orange",Color3.fromRGB(255,140,30)},
        {"Yellow",Color3.fromRGB(255,230,30)},{"Green",Color3.fromRGB(40,220,80)},
        {"Cyan",Color3.fromRGB(40,200,255)},{"Blue",Color3.fromRGB(40,80,255)},
        {"Purple",Color3.fromRGB(180,50,255)},{"White",Color3.fromRGB(255,255,255)},
    }
    local ccol=0
    for _,c in ipairs(colors)do
        local xp=6+ccol*(W/4-3)
        local b=Instance.new("TextButton",panel);b.Text=""
        b.Size=UDim2.fromOffset(W/4-5,14);b.Position=UDim2.fromOffset(xp,yOff)
        b.BackgroundColor3=c[2];b.BorderSizePixel=0;b.ZIndex=10
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,3)
        local col2=c[2];b.MouseButton1Click:Connect(function()colorAllControlled(col2,Enum.Material.Neon)end)
        ccol=ccol+1;if ccol>=4 then ccol=0;yOff=yOff+16 end
    end
    if ccol~=0 then yOff=yOff+16 end
    mBtn("Restore Colors",yOff,Color3.fromRGB(14,14,28),Color3.fromRGB(160,160,200)).MouseButton1Click:Connect(function()restoreAllColors()end);yOff=yOff+28

    -- Resize panel to fit
    panel.Size=UDim2.fromOffset(W,yOff+8)
    makeDraggable(titleBar,panel,true)

    print("[ManipKii v17] Ready - "..partCount.." parts")
end -- end main()

main()
