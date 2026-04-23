-- ============================================================
-- UNANCHORED MANIPULATOR KII v8 -- DELTA EXECUTOR
-- v8 fixes: clean 360° axis spin, tank/car BP movers removed
--   from vehicle parts so no flying, working ground-snap,
--   PlatformStanding state so Humanoid can't fight the tank.
-- New: DE SHRINE (Domain Expansion: Malevolent Shrine)
-- ============================================================
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Debris           = game:GetService("Debris")

local player = Players.LocalPlayer

-- ── Edge/corner drag helper ──────────────────────────────────
local EDGE_MARGIN = 36
local function makeDraggable(handle, panel, edgeOnly)
    local dragging=false; local dragStartM=Vector2.zero; local dragStartPos=UDim2.new()
    local conC, conE
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType~=Enum.UserInputType.MouseButton1 and inp.UserInputType~=Enum.UserInputType.Touch then return end
        if edgeOnly then
            local p=Vector2.new(inp.Position.X,inp.Position.Y); local ap=panel.AbsolutePosition; local as=panel.AbsoluteSize
            if not (p.X-ap.X<EDGE_MARGIN or ap.X+as.X-p.X<EDGE_MARGIN or p.Y-ap.Y<EDGE_MARGIN or ap.Y+as.Y-p.Y<EDGE_MARGIN) then return end
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
        if not par then pcall(function()conC:Disconnect()end); pcall(function()conE:Disconnect()end) end
    end)
end

local function main()
    print("[ManipKii v8] "..player.Name)

    -- ── Core state ────────────────────────────────────────────
    local isActivated=false; local activeMode="none"; local lastMode="none"
    local scriptAlive=true;  local radius=7;          local detectionRange=math.huge

    local pullStrength = 50000  -- BodyPosition.P
    local spinSpeed    = 0      -- rad/s around Y axis (0=off)
    local spinAngle    = 0      -- accumulated clean spin angle

    local function applyStrengthToAll()
        local p=math.max(1,pullStrength); local d=math.max(50,p*0.05)
        for _,data in pairs(controlled) do
            pcall(function()
                if data.bp and data.bp.Parent then data.bp.P=p; data.bp.D=d; data.bp.MaxForce=Vector3.new(1e12,1e12,1e12) end
                if data.bg and data.bg.Parent then data.bg.P=p; data.bg.D=d; data.bg.MaxTorque=Vector3.new(1e12,1e12,1e12) end
            end)
        end
    end

    -- ── Snake ─────────────────────────────────────────────────
    local snakeT=0; local snakeHistory={}; local SNAKE_HIST_MAX=600; local SNAKE_GAP=8

    -- ── Gaster ───────────────────────────────────────────────
    local gasterAnim="pointing"; local gasterT=0; local gasterSubGui=nil

    -- ── Sphere ───────────────────────────────────────────────
    local sphereSubGui=nil; local sphereMode="orbit"
    local spherePos=Vector3.new(0,0,0); local sphereVel=Vector3.new(0,0,0)
    local sphereOrbitAngle=0
    local SPHERE_RADIUS=6; local SPHERE_SPEED=1.2; local SPHERE_SPRING=8; local SPHERE_DAMP=4

    -- ── SphereBender ─────────────────────────────────────────
    local sbSubGui=nil; local sbSpheres={}
    local function newSBSphere(p) return{pos=p or Vector3.zero,vel=Vector3.zero,orbitAngle=0,mode="orbit",stopped=false,selected=false}end

    -- ── Humanoid freeze/thaw ─────────────────────────────────
    local savedWS=16; local savedJP=50; local savedAR=true
    local function freezePlayer(anchorCF)
        local char=player.Character; if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid"); local hrp=char:FindFirstChild("HumanoidRootPart")
        if hum then
            savedWS=hum.WalkSpeed; savedJP=hum.JumpPower; savedAR=hum.AutoRotate
            hum.WalkSpeed=0; hum.JumpPower=0; hum.AutoRotate=false
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.PlatformStanding) end)
        end
        if hrp then hrp.Anchored=true; if anchorCF then hrp.CFrame=anchorCF end end
        for _,p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then pcall(function()p.CanCollide=false end) end
        end
    end
    local function thawPlayer(exitCF)
        local char=player.Character; if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid"); local hrp=char:FindFirstChild("HumanoidRootPart")
        if hum then
            hum.WalkSpeed=savedWS; hum.JumpPower=savedJP; hum.AutoRotate=savedAR
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
        if hrp then hrp.Anchored=false; if exitCF then hrp.CFrame=exitCF end end
        for _,p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then pcall(function()p.CanCollide=true end) end
        end
    end

    -- ── Tank state ────────────────────────────────────────────
    local tankSubGui=nil; local tankActive=false
    local cameraOrbitAngle=0; local cameraPitchAngle=math.rad(25)
    local CAM_PITCH_MIN=math.rad(8); local CAM_PITCH_MAX=math.rad(70)
    local CAMERA_DIST=24; local frozenTankCF=nil
    local CAM_ORBIT_SENS=3.0; local CAM_PITCH_SENS=2.0
    local tks={forward=0,turn=0,hatchOpen=false,insideTank=false,
               tankBase=nil,turretPart=nil,barrelPart=nil,turretPartIdx=nil,barrelPartIdx=nil,
               tankParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0,tankHatch=nil}
    local TANK_H=5; local TANK_W=12; local TANK_L=16
    local TANK_INTERIOR_Y=TANK_H/2+2.5
    local TANK_SPEED=35; local TANK_TURN=2.2; local TANK_ACCEL=12; local TANK_FRIC=0.88
    local SHOOT_CD=1.5; local lastShot=0; local PROJ_SPEED=650
    local rightJoy={active=false,origin=Vector2.zero,current=Vector2.zero,radius=55,deadzone=10,touchId=nil}

    -- ── Car state ─────────────────────────────────────────────
    local carSubGui=nil; local carActive=false; local frozenCarCF=nil
    local cs={doorOpen=false,carBase=nil,carDoor=nil,carParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0}
    local CAR_H=2.8; local CAR_INTERIOR_Y=CAR_H/2+1.8
    local CAR_SPEED=48; local CAR_TURN=2.8; local CAR_ACCEL=20; local CAR_FRIC=0.88
    local carJoy={active=false,origin=Vector2.zero,current=Vector2.zero,radius=70,deadzone=8,touchId=nil,forward=0,turn=0}

    -- ── DE Shrine state ───────────────────────────────────────
    local shrineSubGui=nil; local shrineActive=false
    local shrineNewParts={}   -- Parts created by us (shrine + slashes), cleanup on exit
    local shrineSlashes={}    -- 6 slash BodyVelocity parts
    local slashVelocities={}  -- current direction vec for each slash
    local domainOpen=false    -- sphere formed but CanCollide still off (opening phase)
    local domainClosed=false  -- sphere CanCollide on, trapping players
    local domainTimer=0
    local DOMAIN_OPEN_TIME=3.5   -- seconds before it "slams shut"
    local DOMAIN_RADIUS=30
    local SLASH_SPEED=280
    local shrineCenter=Vector3.zero

    -- ── Mode tables ───────────────────────────────────────────
    local CFRAME_MODES={heart=true,rings=true,wall=true,box=true,gasterhand=true,gaster2hands=true,wings=true,sphere=true,spherebender=true,tank=true,car=true,de_shrine=true}
    local GASTER_MODES={gasterhand=true,gaster2hands=true}
    local SPHERE_MODES={sphere=true}
    local SPHERE_BENDER_MODES={spherebender=true}
    local TANK_MODES={tank=true}
    local CAR_MODES={car=true}
    local SHRINE_MODES={de_shrine=true}

    -- ── Gaster/Wing data ─────────────────────────────────────
    local HAND_SCALE=2.8
    local HAND_SLOTS={{x=-4,y=5},{x=-4,y=4},{x=-4,y=3},{x=-4,y=2},{x=-2,y=6},{x=-2,y=5},{x=-2,y=4},{x=-2,y=3},{x=0,y=7},{x=0,y=6},{x=0,y=5},{x=0,y=4},{x=0,y=3},{x=2,y=6},{x=2,y=5},{x=2,y=4},{x=2,y=3},{x=5,y=2},{x=5,y=1},{x=5,y=0},{x=-4,y=1},{x=-2,y=1},{x=0,y=1},{x=2,y=1},{x=-4,y=0},{x=-2,y=0},{x=0,y=0},{x=2,y=0},{x=4,y=0},{x=-2,y=-1},{x=0,y=-1},{x=2,y=-1}}
    local PALM_SLOTS={{x=-3,y=2},{x=-1,y=2},{x=1,y=2},{x=3,y=2},{x=-3,y=1},{x=-1,y=1},{x=1,y=1},{x=3,y=1},{x=-3,y=0},{x=-1,y=0},{x=1,y=0},{x=3,y=0},{x=-2,y=-1},{x=0,y=-1},{x=2,y=-1},{x=-2,y=-2},{x=0,y=-2},{x=2,y=-2}}
    local ALL_HAND_SLOTS={}
    for _,s in ipairs(HAND_SLOTS) do table.insert(ALL_HAND_SLOTS,{x=s.x,y=s.y,isPalm=false}) end
    for _,s in ipairs(PALM_SLOTS) do table.insert(ALL_HAND_SLOTS,{x=s.x,y=s.y,isPalm=true}) end
    local HAND_SLOTS_COUNT=#ALL_HAND_SLOTS
    local POINTING_BIAS={[1]=-5.0,[2]=-5.0,[3]=-5.0,[4]=-5.0,[5]=-4.5,[6]=-4.5,[7]=-4.5,[8]=-4.5,[9]=-5.5,[10]=-5.0,[11]=-4.0,[12]=-2.5,[13]=-1.2,[18]=-0.6,[19]=-1.2,[20]=-1.2}
    local PUNCH_BIAS={[1]=-3.0,[2]=-2.5,[3]=-1.5,[4]=-0.5,[5]=-3.0,[6]=-2.5,[7]=-1.5,[8]=-0.5,[9]=-3.5,[10]=-3.0,[11]=-2.0,[12]=-1.0,[13]=-0.3,[14]=-3.0,[15]=-2.5,[16]=-1.5,[17]=-0.5,[18]=-0.8,[19]=-1.4,[20]=-1.4}
    local HAND_RIGHT=Vector3.new(9,2,1); local HAND_LEFT=Vector3.new(-9,2,1)
    local WING_POINTS={}
    local WING_SR=Vector3.new(1.0,1.8,0.6); local WING_SL=Vector3.new(-1.0,1.8,0.6)
    local WING_OA=math.rad(82); local WING_CA=math.rad(22); local WING_FS=1.8; local WING_SPAN=14
    for _,f in ipairs({{0.15,2.2,0.4},{0.28,2.8,0.5},{0.40,3.0,0.6},{0.52,2.8,0.6},{0.63,2.2,0.5},{0.73,1.2,0.4},{0.82,-0.2,0.3},{0.90,-1.8,0.2},{0.97,-3.5,0.1}}) do
        for seg=1,4 do local t2=(seg-1)/3; table.insert(WING_POINTS,{outX=f[1]*WING_SPAN+t2*0.6,upY=f[2]-t2*2.0,backZ=f[3]+t2*0.2,layer=1}) end
    end
    for _,f in ipairs({{0.12,3.5,0.6},{0.22,4.4,0.7},{0.33,5.0,0.8},{0.44,5.0,0.8},{0.54,4.4,0.7},{0.62,3.4,0.6}}) do
        for seg=1,3 do local t2=(seg-1)/2; table.insert(WING_POINTS,{outX=f[1]*WING_SPAN+t2*0.4,upY=f[2]-t2*1.2,backZ=f[3],layer=2}) end
    end
    for _,f in ipairs({{0.04,1.5,0.5},{0.08,2.2,0.6},{0.12,2.8,0.7},{0.18,3.0,0.7},{0.04,0.6,0.5},{0.08,1.0,0.6},{0.14,1.2,0.6},{0.20,1.0,0.5}}) do
        table.insert(WING_POINTS,{outX=f[1]*WING_SPAN,upY=f[2],backZ=f[3],layer=3})
    end
    local WING_POINT_COUNT=#WING_POINTS

    -- ── Part tracking ─────────────────────────────────────────
    local controlled={}; local partCount=0

    -- ── Forward declarations ──────────────────────────────────
    local sweepMap,rebuildSBGui,destroyTank,destroyTankGui,destroyCar,destroyCarGui,destroyShrine,destroyShrineGui

    -- ── Validation ────────────────────────────────────────────
    local function isValid(obj)
        if not obj then return false end
        local ok=pcall(function() if not obj.Parent then error() end end)
        if not ok or not obj.Parent then return false end
        if not obj:IsA("BasePart") then return false end
        if obj.Anchored then return false end
        if obj.Size.Magnitude<0.2 then return false end
        if obj.Transparency>=1 then return false end
        local p=obj.Parent
        while p and p~=workspace do
            if p:FindFirstChildOfClass("Humanoid") then return false end
            p=p.Parent
        end
        return true
    end

    -- ── Grab / release (BodyPosition+BodyGyro, server-replicated physics) ──
    local function grabPart(part)
        if controlled[part] then return end
        if not isValid(part) then return end
        local char=player.Character
        local root=char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local effectiveRange=(pullStrength>=5000) and math.huge or detectionRange
        if root and (part.Position-root.Position).Magnitude>effectiveRange then return end
        local origCC=part.CanCollide; local origAnch=part.Anchored
        pcall(function()part.CanCollide=false end)
        local p=math.max(1,pullStrength); local d=math.max(50,p*0.05)
        local bp=Instance.new("BodyPosition")
        bp.MaxForce=Vector3.new(1e12,1e12,1e12); bp.P=p; bp.D=d; bp.Position=part.Position; bp.Parent=part
        local bg=Instance.new("BodyGyro")
        bg.MaxTorque=Vector3.new(1e12,1e12,1e12); bg.P=p; bg.D=d; bg.CFrame=part.CFrame; bg.Parent=part
        controlled[part]={origCC=origCC,origAnch=origAnch,bp=bp,bg=bg}
        partCount=partCount+1
    end

    local function releasePart(part,data)
        pcall(function()
            if data.bp and data.bp.Parent then data.bp:Destroy() end
            if data.bg and data.bg.Parent then data.bg:Destroy() end
        end)
        if part and part.Parent then
            pcall(function() part.CanCollide=data.origCC; part.Anchored=data.origAnch or false end)
        end
    end

    -- ── Strip BP/BG from a part so direct CFrame can drive it ─
    -- Used for vehicle parts: BP+BG would fight updateTank/updateCar's CFrame sets.
    local function stripMotors(part)
        if not (part and part.Parent) then return end
        for _,child in ipairs(part:GetChildren()) do
            if child:IsA("BodyPosition") or child:IsA("BodyGyro") then
                pcall(function()child:Destroy()end)
            end
        end
        if controlled[part] then
            controlled[part].bp=nil; controlled[part].bg=nil
        end
    end

    local function releaseAll()
        for part,data in pairs(controlled) do releasePart(part,data) end
        controlled={}; partCount=0; snakeT=0; snakeHistory={}
        if tankActive   then pcall(destroyTank);  pcall(destroyTankGui)  end
        if carActive    then pcall(destroyCar);   pcall(destroyCarGui)   end
        if shrineActive then pcall(destroyShrine);pcall(destroyShrineGui)end
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
    end

    sweepMap=function()
        for _,obj in ipairs(workspace:GetDescendants()) do
            if isValid(obj) and not controlled[obj] then grabPart(obj) end
        end
    end

    -- ── Helpers ───────────────────────────────────────────────
    local function getSnakeTarget(i)
        local idx=math.clamp(i*SNAKE_GAP,1,math.max(1,#snakeHistory))
        return snakeHistory[idx] or snakeHistory[#snakeHistory] or Vector3.zero
    end

    local function getWingCF(ptIdx,side,cf,t)
        local wp=WING_POINTS[ptIdx]; if not wp then return CFrame.new(0,-5000,0) end
        local rawSin=math.sin(t*WING_FS*math.pi); local flapT=(rawSin+1)/2
        local fa=WING_CA+flapT*(WING_OA-WING_CA); local cosA,sinA=math.cos(fa),math.sin(fa)
        local rotX=(wp.outX*cosA-wp.backZ*sinA)*side; local rotZ=wp.outX*sinA+wp.backZ*cosA+0.5
        local sh=(side==1) and WING_SR or WING_SL
        return CFrame.new(cf:PointToWorldSpace(Vector3.new(sh.X+rotX,sh.Y+wp.upY,sh.Z+rotZ)))
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
        elseif sphereMode=="stay" then
            sphereVel=sphereVel*(1-SPHERE_DAMP*2*dt); spherePos=spherePos+sphereVel*dt
        end
    end

    local function updateSphereBenderTargets(dt,rootPos)
        for _,sp in ipairs(sbSpheres) do
            if sp.stopped then sp.vel=Vector3.zero
            elseif sp.mode=="orbit" then
                sp.orbitAngle=sp.orbitAngle+dt*SPHERE_SPEED
                local tgt=rootPos+Vector3.new(math.cos(sp.orbitAngle)*SPHERE_RADIUS,1.5,math.sin(sp.orbitAngle)*SPHERE_RADIUS)
                sp.vel=sp.vel+(tgt-sp.pos)*(SPHERE_SPRING*dt); sp.vel=sp.vel*(1-SPHERE_DAMP*dt); sp.pos=sp.pos+sp.vel*dt
            elseif sp.mode=="follow" then
                local b=rootPos+Vector3.new(0,1.5,4); local d=b-sp.pos; local dist=d.Magnitude
                if dist>3 then sp.vel=sp.vel+d.Unit*(dist-3)*SPHERE_SPRING*dt end
                sp.vel=sp.vel*(1-SPHERE_DAMP*dt); sp.pos=sp.pos+sp.vel*dt
            elseif sp.mode=="stay" then sp.vel=sp.vel*(1-SPHERE_DAMP*2*dt); sp.pos=sp.pos+sp.vel*dt end
        end
    end

    local function getFormationCF(mode,i,n,origin,cf,t)
        if mode=="heart" then
            local a=((i-1)/math.max(n,1))*math.pi*2
            local hx=16*math.sin(a)^3; local hz=-(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))
            return CFrame.new(origin+cf:VectorToWorldSpace(Vector3.new(hx*(radius/16),0,hz*(radius/16))))
        elseif mode=="rings" then
            local a=((i-1)/math.max(n,1))*math.pi*2+t*1.4
            return CFrame.new(origin+Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius))
        elseif mode=="wall" then
            local cols=math.max(1,math.ceil(math.sqrt(n))); local col=((i-1)%cols)-math.floor(cols/2); local row=math.floor((i-1)/cols)-1
            return CFrame.new(origin+cf.LookVector*radius+cf.RightVector*(col*1.8)+cf.UpVector*(row*1.8+1))
        elseif mode=="box" then
            local fV={cf.LookVector,-cf.LookVector,cf.RightVector,-cf.RightVector,cf.UpVector,-cf.UpVector}
            local fA={cf.RightVector,cf.RightVector,cf.LookVector,cf.LookVector,cf.RightVector,cf.RightVector}
            local fB={cf.UpVector,cf.UpVector,cf.UpVector,cf.UpVector,cf.LookVector,cf.LookVector}
            local fi=((i-1)%6)+1; local si=math.floor((i-1)/6); local col=(si%2)-0.5; local row=math.floor(si/2)-0.5; local sp=radius*0.45
            return CFrame.new(origin+fV[fi]*radius+fA[fi]*(col*sp)+fB[fi]*(row*sp))
        elseif mode=="wings" then
            local half=math.ceil(n/2); local side,ptIdx
            if i<=half then side=1;ptIdx=i else side=-1;ptIdx=i-half end
            return getWingCF(((ptIdx-1)%WING_POINT_COUNT)+1,side,cf,t)
        end
        return CFrame.new(origin)
    end

    local function getGasterCF(slotIdx,side,cf,gt)
        local slot=ALL_HAND_SLOTS[slotIdx]; if not slot then return CFrame.new(0,-5000,0) end
        local sx=slot.x*HAND_SCALE; local sy=slot.y*HAND_SCALE; local floatY=math.sin(gt*2.0+side*1.2)*1.0
        if not slot.isPalm then
            if gasterAnim=="pointing" then sy=sy+(POINTING_BIAS[slotIdx] or 0)*HAND_SCALE
            elseif gasterAnim=="punching" then sy=sy+(PUNCH_BIAS[slotIdx] or 0)*HAND_SCALE end
        end
        local waveAng=(gasterAnim=="waving") and math.sin(gt*2.2)*0.5 or 0
        local punchZ=(gasterAnim=="punching" and not slot.isPalm) and (math.sin(gt*10)*0.5+0.5)*8 or 0
        local base=(side==1) and HAND_RIGHT or HAND_LEFT; local palmOff=slot.isPalm and 1.5 or 0
        return CFrame.new(cf:PointToWorldSpace(Vector3.new(base.X+sx*math.cos(waveAng)*side,base.Y+sy+floatY,base.Z+sx*math.sin(waveAng)-punchZ+palmOff)))
    end

    -- ════════════════════════════════════════════════════════════
    -- TANK
    -- ════════════════════════════════════════════════════════════

    -- RaycastParams that ignores tank parts (so ground snap doesn't
    -- accidentally snap to a tank block floating below)
    local tankRayParams=RaycastParams.new()
    tankRayParams.FilterType=Enum.RaycastFilterType.Exclude

    local function buildTankFromParts(position,cf)
        local pl={}
        for part,_ in pairs(controlled) do if part and part.Parent then table.insert(pl,part) end end
        if #pl<25 then sweepMap(); task.wait(0.3); pl={}
            for part,_ in pairs(controlled) do if part and part.Parent then table.insert(pl,part) end end
            if #pl<25 then print("[ManipKii] Tank needs 25+ parts (found "..#pl..")"); return false end
        end
        table.sort(pl,function(a,b)return a.Size.Magnitude>b.Size.Magnitude end)
        tks.tankParts={}; tks.partOffsets={}; tks.turretPartIdx=nil; tks.barrelPartIdx=nil

        local idx=1
        -- Hull
        local hull=pl[idx]; hull.CFrame=cf*CFrame.new(0,TANK_H/2,0)
        tks.tankBase=hull; tks.tankParts[idx]=hull; tks.partOffsets[idx]=CFrame.new(0,TANK_H/2,0); idx=idx+1

        for i=1,4 do if pl[idx] then local off=CFrame.new(-TANK_W/2-0.5,-0.5,-TANK_L/3+i*3.5)
            pl[idx].CFrame=hull.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end end
        for i=1,4 do if pl[idx] then local off=CFrame.new(TANK_W/2+0.5,-0.5,-TANK_L/3+i*3.5)
            pl[idx].CFrame=hull.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end end
        if pl[idx] then local off=CFrame.new(0,-0.5,TANK_L/2+1)
            pl[idx].CFrame=hull.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end
        if pl[idx] then local off=CFrame.new(0,-0.5,-TANK_L/2-1)
            pl[idx].CFrame=hull.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end
        for i=1,3 do if pl[idx] then local off=CFrame.new(-TANK_W/2,0.5,-TANK_L/3+i*4)
            pl[idx].CFrame=hull.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end end
        for i=1,3 do if pl[idx] then local off=CFrame.new(TANK_W/2,0.5,-TANK_L/3+i*4)
            pl[idx].CFrame=hull.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end end
        for i=1,5 do if pl[idx] then local off=CFrame.new(-TANK_W/2-1,-1,-TANK_L/2+i*3.2)
            pl[idx].CFrame=hull.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end end
        for i=1,5 do if pl[idx] then local off=CFrame.new(TANK_W/2+1,-1,-TANK_L/2+i*3.2)
            pl[idx].CFrame=hull.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end end
        local tBase=nil
        if pl[idx] then tBase=pl[idx]; local off=CFrame.new(0,TANK_H/2+0.5,0)
            tBase.CFrame=hull.CFrame*off; tks.tankParts[idx]=tBase; tks.partOffsets[idx]=off; idx=idx+1 end
        if pl[idx] and tBase then
            local tb=pl[idx]; local off=CFrame.new(0,TANK_H/2+2.0,0)
            tb.CFrame=hull.CFrame*off; tks.turretPart=tb; tks.turretPartIdx=idx
            tks.tankParts[idx]=tb; tks.partOffsets[idx]=off; idx=idx+1
        end
        if pl[idx] and tks.turretPart then local off=CFrame.new(-2.5,0,0)
            pl[idx].CFrame=tks.turretPart.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end
        if pl[idx] and tks.turretPart then local off=CFrame.new(2.5,0,0)
            pl[idx].CFrame=tks.turretPart.CFrame*off; tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end
        if pl[idx] and tks.turretPart then local off=CFrame.new(0,1.5,-0.5)
            pl[idx].CFrame=tks.turretPart.CFrame*off; tks.tankHatch=pl[idx]
            tks.tankParts[idx]=pl[idx]; tks.partOffsets[idx]=off; idx=idx+1 end
        for i=idx,math.min(idx+6,#pl) do
            if pl[i] and tks.turretPart and pl[i].Size.Z>pl[i].Size.X and pl[i].Size.Z>pl[i].Size.Y then
                local off=CFrame.new(0,0.3,5.5)
                pl[i].CFrame=tks.turretPart.CFrame*off
                tks.barrelPart=pl[i]; tks.barrelPartIdx=i; tks.tankParts[i]=pl[i]; tks.partOffsets[i]=off; break
            end
        end

        -- ▶ CRITICAL: strip BodyPosition/BodyGyro from ALL tank parts.
        -- If we don't do this, BP movers (MaxForce=1e12) fight the CFrame
        -- sets in updateTank and launch parts (and player) into the sky.
        local filterList={}
        for _,part in ipairs(tks.tankParts) do
            if part and part.Parent then
                stripMotors(part)
                table.insert(filterList,part)
            end
        end
        tankRayParams.FilterDescendantsInstances=filterList

        frozenTankCF=nil
        return true
    end

    destroyTank=function()
        if tks.tankBase then
            pcall(function()
                local e=Instance.new("Explosion"); e.Position=tks.tankBase.Position
                e.BlastRadius=15; e.BlastPressure=300000; e.Parent=workspace
            end)
        end
        for _,part in ipairs(tks.tankParts) do
            if part and part.Parent and controlled[part] then
                releasePart(part,controlled[part]); controlled[part]=nil; partCount=math.max(0,partCount-1)
            end
        end
        tks={forward=0,turn=0,hatchOpen=false,insideTank=false,tankBase=nil,turretPart=nil,barrelPart=nil,turretPartIdx=nil,barrelPartIdx=nil,tankParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0,tankHatch=nil}
        frozenTankCF=nil; tankActive=false; cameraOrbitAngle=0; cameraPitchAngle=math.rad(25)
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        thawPlayer()
    end

    local function shootProjectile()
        if not tankActive or not tks.barrelPart or not tks.insideTank then return end
        local now=tick(); if now-lastShot<SHOOT_CD then return end; lastShot=now
        local shell=Instance.new("Part")
        shell.Name="TankShell"; shell.Size=Vector3.new(0.35,0.35,2.0)
        shell.BrickColor=BrickColor.new("Dark grey metallic"); shell.Material=Enum.Material.Metal
        shell.CanCollide=true; shell.CastShadow=false
        local barrelCF=tks.barrelPart.CFrame
        shell.CFrame=barrelCF*CFrame.new(0,0,tks.barrelPart.Size.Z/2+1.2); shell.Parent=workspace
        local pitchBias=math.sin(cameraPitchAngle*0.15)*PROJ_SPEED*0.2
        local arcDir=(barrelCF.LookVector+Vector3.new(0,pitchBias/PROJ_SPEED,0)).Unit
        pcall(function()shell.AssemblyLinearVelocity=arcDir*PROJ_SPEED end)
        pcall(function()
            local fl=Instance.new("PointLight"); fl.Brightness=10; fl.Range=20; fl.Color=Color3.fromRGB(255,220,100); fl.Parent=shell; Debris:AddItem(fl,0.08)
        end)
        local hitConn; hitConn=shell.Touched:Connect(function(hit)
            if hit==tks.barrelPart or hit==tks.turretPart then return end
            local c2=player.Character; if c2 and hit:IsDescendantOf(c2) then return end
            pcall(function()
                local ex=Instance.new("Explosion"); ex.Position=shell.Position; ex.BlastRadius=10; ex.BlastPressure=150000; ex.DestroyJointRadiusPercent=0; ex.Parent=workspace
            end)
            hitConn:Disconnect(); pcall(function()shell:Destroy()end)
        end)
        Debris:AddItem(shell,12)
        if tks.tankBase then
            pcall(function()tks.tankBase.AssemblyLinearVelocity=tks.tankBase.AssemblyLinearVelocity-barrelCF.LookVector*4 end)
        end
    end

    local function toggleHatch()
        if not tks.tankBase then return end
        if not tks.hatchOpen then
            tks.hatchOpen=true; tks.insideTank=false
            frozenTankCF=tks.tankBase.CFrame
            if tks.tankHatch then pcall(function()tks.tankHatch.CFrame=tks.tankHatch.CFrame*CFrame.new(0,2.5,0)*CFrame.Angles(math.rad(65),0,0)end)end
            thawPlayer(tks.tankBase.CFrame*CFrame.new(0,TANK_H+4,0))
            pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        else
            tks.hatchOpen=false; tks.insideTank=true; frozenTankCF=nil
            if tks.tankHatch then pcall(function()tks.tankHatch.CFrame=tks.tankHatch.CFrame*CFrame.Angles(math.rad(-65),0,0)*CFrame.new(0,-2.5,0)end)end
            freezePlayer(tks.tankBase.CFrame*CFrame.new(0,TANK_INTERIOR_Y,0))
        end
    end

    local function updateTank(dt)
        if not tankActive or not tks.tankBase then return end

        -- Outside: freeze formation
        if not tks.insideTank then
            if frozenTankCF then
                pcall(function()
                    tks.tankBase.CFrame=frozenTankCF
                    tks.tankBase.AssemblyLinearVelocity=Vector3.zero
                    tks.tankBase.AssemblyAngularVelocity=Vector3.zero
                end)
                for i,part in ipairs(tks.tankParts) do
                    if part and part.Parent and tks.partOffsets[i] then
                        pcall(function()
                            part.CFrame=frozenTankCF*tks.partOffsets[i]
                            part.AssemblyLinearVelocity=Vector3.zero
                            part.AssemblyAngularVelocity=Vector3.zero
                        end)
                    end
                end
            end
            return
        end

        -- Drive
        if tks.forward~=0 then
            tks.currentSpeed=math.clamp(tks.currentSpeed+tks.forward*TANK_ACCEL*dt,-TANK_SPEED,TANK_SPEED)
        else
            tks.currentSpeed=tks.currentSpeed*TANK_FRIC
        end
        tks.currentTurnSpeed=tks.turn~=0 and tks.turn*TANK_TURN or 0

        local moveVec=tks.tankBase.CFrame.LookVector*tks.currentSpeed*dt
        local newCF=tks.tankBase.CFrame*CFrame.new(moveVec)*CFrame.Angles(0,tks.currentTurnSpeed*dt,0)

        -- Ground snap (exclude tank parts from raycast)
        local ray=workspace:Raycast(newCF.Position+Vector3.new(0,6,0),Vector3.new(0,-20,0),tankRayParams)
        if ray then
            newCF=CFrame.new(Vector3.new(newCF.Position.X,ray.Position.Y+TANK_H/2,newCF.Position.Z))*newCF.Rotation
        end

        pcall(function()
            tks.tankBase.CFrame=newCF
            tks.tankBase.AssemblyLinearVelocity=Vector3.zero
            tks.tankBase.AssemblyAngularVelocity=Vector3.zero
        end)

        -- Body parts follow hull
        for i,part in ipairs(tks.tankParts) do
            if part and part.Parent and tks.partOffsets[i]
            and part~=tks.turretPart and part~=tks.barrelPart then
                local off=tks.partOffsets[i]
                local isTurretDec=(math.abs(off.Position.X)>2 and math.abs(off.Position.X)<3 and math.abs(off.Position.Y)<0.2)
                if not isTurretDec then
                    pcall(function()
                        part.CFrame=newCF*off
                        part.AssemblyLinearVelocity=Vector3.zero
                        part.AssemblyAngularVelocity=Vector3.zero
                    end)
                end
            end
        end

        -- Turret: hull Y-pos + camera orbit yaw
        if tks.turretPart and tks.turretPartIdx then
            pcall(function()
                local hullOff=tks.partOffsets[tks.turretPartIdx]
                local anchor=newCF*hullOff
                local _,tankYaw=select(2,newCF:ToEulerAnglesYXZ())
                tankYaw=select(2,newCF:ToEulerAnglesYXZ())
                tks.turretPart.CFrame=CFrame.new(anchor.Position)*CFrame.Angles(0,tankYaw+cameraOrbitAngle,0)
                tks.turretPart.AssemblyLinearVelocity=Vector3.zero
                tks.turretPart.AssemblyAngularVelocity=Vector3.zero
            end)
        end

        -- Turret decorators follow turret
        if tks.turretPart then
            for i,part in ipairs(tks.tankParts) do
                local off=tks.partOffsets[i]
                if off and part and part.Parent and part~=tks.turretPart and part~=tks.barrelPart then
                    if math.abs(off.Position.X)>2 and math.abs(off.Position.X)<3 and math.abs(off.Position.Y)<0.2 then
                        pcall(function()part.CFrame=tks.turretPart.CFrame*off; part.AssemblyLinearVelocity=Vector3.zero; part.AssemblyAngularVelocity=Vector3.zero end)
                    end
                end
            end
        end

        -- Barrel elevation
        if tks.barrelPart and tks.turretPart and tks.barrelPartIdx then
            pcall(function()
                local bp2=math.clamp(-math.rad(10)+cameraPitchAngle*0.35,math.rad(-5),math.rad(25))
                local off=tks.partOffsets[tks.barrelPartIdx]
                if off then
                    tks.barrelPart.CFrame=tks.turretPart.CFrame*CFrame.Angles(bp2,0,0)*CFrame.new(off.Position)
                    tks.barrelPart.AssemblyLinearVelocity=Vector3.zero
                    tks.barrelPart.AssemblyAngularVelocity=Vector3.zero
                end
            end)
        end

        -- Player: HRP is Anchored, update CFrame so player moves with tank
        local char=player.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.Anchored then
                pcall(function()hrp.CFrame=newCF*CFrame.new(0,TANK_INTERIOR_Y,0)end)
            end
            for _,p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then pcall(function()p.CanCollide=false end)end
            end
        end

        -- Orbit camera: look forward along tank direction + orbit offset
        pcall(function()
            workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
            local tankPos=newCF.Position
            local _,tankYaw=select(2,newCF:ToEulerAnglesYXZ()); tankYaw=select(2,newCF:ToEulerAnglesYXZ())
            local pitch=math.clamp(cameraPitchAngle,CAM_PITCH_MIN,CAM_PITCH_MAX)
            local worldAngle=tankYaw+math.pi+cameraOrbitAngle
            local camX=tankPos.X+math.sin(worldAngle)*math.cos(pitch)*CAMERA_DIST
            local camY=tankPos.Y+math.sin(pitch)*CAMERA_DIST+1
            local camZ=tankPos.Z+math.cos(worldAngle)*math.cos(pitch)*CAMERA_DIST
            local orbitFwdAngle=worldAngle+math.pi
            local lookAt=Vector3.new(tankPos.X+math.sin(orbitFwdAngle)*14,tankPos.Y+2,tankPos.Z+math.cos(orbitFwdAngle)*14)
            workspace.CurrentCamera.CFrame=CFrame.new(Vector3.new(camX,camY,camZ),lookAt)
        end)
    end

    -- ════════════════════════════════════════════════════════════
    -- CAR
    -- ════════════════════════════════════════════════════════════
    -- 26 fixed offsets relative to the car base (hull)
    local CAR_OFFSETS={
        CFrame.new(0,0,0),           -- [1] hull
        CFrame.new(-5,-1.2,-6.5),    -- [2] LF wheel
        CFrame.new(5,-1.2,-6.5),     -- [3] RF wheel
        CFrame.new(-5,-1.2,6.5),     -- [4] LR wheel
        CFrame.new(5,-1.2,6.5),      -- [5] RR wheel
        CFrame.new(-4.8,0.5,-2),     -- [6] L side mid
        CFrame.new(4.8,0.5,-2),      -- [7] R side mid
        CFrame.new(-4.8,0.5,3),      -- [8] L side rear
        CFrame.new(4.8,0.5,3),       -- [9] R side rear
        CFrame.new(0,-0.5,-8.5),     -- [10] front bumper
        CFrame.new(0,-0.5,8.5),      -- [11] rear bumper
        CFrame.new(0,1.4,-5),        -- [12] hood
        CFrame.new(0,1.4,5),         -- [13] trunk
        CFrame.new(0,2.8,0),         -- [14] roof
        CFrame.new(0,2.4,-3.5),      -- [15] windshield
        CFrame.new(0,2.4,3.5),       -- [16] rear glass
        CFrame.new(-4,2.4,-2.5),     -- [17] L A-pillar
        CFrame.new(4,2.4,-2.5),      -- [18] R A-pillar
        CFrame.new(-4,2.4,2.5),      -- [19] L C-pillar
        CFrame.new(4,2.4,2.5),       -- [20] R C-pillar
        CFrame.new(0,0.4,-8),        -- [21] grille
        CFrame.new(-2,-1.2,8),       -- [22] L exhaust
        CFrame.new(2,-1.2,8),        -- [23] R exhaust
        CFrame.new(0,3.2,6),         -- [24] spoiler
        CFrame.new(0,1.0,-1.5),      -- [25] dashboard
        CFrame.new(-5,1.4,-2.5),     -- [26] driver door
    }

    local carRayParams=RaycastParams.new()
    carRayParams.FilterType=Enum.RaycastFilterType.Exclude

    local function buildCarFromParts(position,cf)
        local pl={}
        for part,_ in pairs(controlled) do if part and part.Parent then table.insert(pl,part) end end
        local needed=#CAR_OFFSETS
        if #pl<needed then sweepMap(); task.wait(0.3); pl={}
            for part,_ in pairs(controlled) do if part and part.Parent then table.insert(pl,part) end end
            if #pl<needed then print("[ManipKii] Car needs "..needed.."+ parts (found "..#pl..")"); return false end
        end
        table.sort(pl,function(a,b)return a.Size.Magnitude>b.Size.Magnitude end)
        cs.carParts={}; cs.partOffsets={}; cs.carBase=nil; cs.carDoor=nil
        cs.carBase=pl[1]; pl[1].CFrame=cf*CFrame.new(0,CAR_H/2,0)
        cs.carParts[1]=pl[1]; cs.partOffsets[1]=CFrame.new(0,CAR_H/2,0)
        for i=2,math.min(needed,#pl) do
            local off=CAR_OFFSETS[i]
            pl[i].CFrame=pl[1].CFrame*off
            cs.carParts[i]=pl[i]; cs.partOffsets[i]=off
            if i==26 then cs.carDoor=pl[i] end
        end
        -- Strip BP/BG so CFrame drive doesn't fight movers
        local filterList={}
        for _,part in ipairs(cs.carParts) do
            if part and part.Parent then stripMotors(part); table.insert(filterList,part) end
        end
        carRayParams.FilterDescendantsInstances=filterList
        frozenCarCF=nil
        return true
    end

    destroyCar=function()
        for _,part in ipairs(cs.carParts) do
            if part and part.Parent and controlled[part] then
                releasePart(part,controlled[part]); controlled[part]=nil; partCount=math.max(0,partCount-1)
            end
        end
        cs={doorOpen=false,carBase=nil,carDoor=nil,carParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0}
        frozenCarCF=nil; carActive=false
        carJoy.active=false; carJoy.forward=0; carJoy.turn=0
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        thawPlayer()
    end

    local function toggleCarDoor()
        if not cs.carBase then return end
        if not cs.doorOpen then
            cs.doorOpen=true; frozenCarCF=nil
            if cs.carDoor then pcall(function()cs.carDoor.CFrame=cs.carDoor.CFrame*CFrame.Angles(0,math.rad(70),0)end)end
            freezePlayer(cs.carBase.CFrame*CFrame.new(-2,CAR_INTERIOR_Y,-1.5))
            pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        else
            cs.doorOpen=false; frozenCarCF=cs.carBase.CFrame
            if cs.carDoor then pcall(function()cs.carDoor.CFrame=cs.carDoor.CFrame*CFrame.Angles(0,math.rad(-70),0)end)end
            thawPlayer(cs.carBase.CFrame*CFrame.new(-5.5,CAR_H+2,-1.5))
        end
    end

    local function updateCar(dt)
        if not carActive or not cs.carBase then return end
        if not cs.doorOpen then
            if frozenCarCF then
                pcall(function()cs.carBase.CFrame=frozenCarCF; cs.carBase.AssemblyLinearVelocity=Vector3.zero; cs.carBase.AssemblyAngularVelocity=Vector3.zero end)
                for i,part in ipairs(cs.carParts) do
                    if part and part.Parent and cs.partOffsets[i] then
                        pcall(function()part.CFrame=frozenCarCF*cs.partOffsets[i]; part.AssemblyLinearVelocity=Vector3.zero; part.AssemblyAngularVelocity=Vector3.zero end)
                    end
                end
            end
            return
        end
        local fwd=carJoy.forward; local trn=carJoy.turn
        if fwd~=0 then cs.currentSpeed=math.clamp(cs.currentSpeed+fwd*CAR_ACCEL*dt,-CAR_SPEED,CAR_SPEED)
        else cs.currentSpeed=cs.currentSpeed*CAR_FRIC end
        cs.currentTurnSpeed=trn~=0 and trn*CAR_TURN or 0
        local moveVec=cs.carBase.CFrame.LookVector*cs.currentSpeed*dt
        local newCF=cs.carBase.CFrame*CFrame.new(moveVec)*CFrame.Angles(0,cs.currentTurnSpeed*dt,0)
        local ray=workspace:Raycast(newCF.Position+Vector3.new(0,5,0),Vector3.new(0,-15,0),carRayParams)
        if ray then newCF=CFrame.new(Vector3.new(newCF.Position.X,ray.Position.Y+CAR_H/2,newCF.Position.Z))*newCF.Rotation end
        pcall(function()cs.carBase.CFrame=newCF; cs.carBase.AssemblyLinearVelocity=Vector3.zero; cs.carBase.AssemblyAngularVelocity=Vector3.zero end)
        for i,part in ipairs(cs.carParts) do
            if part and part.Parent and cs.partOffsets[i] then
                pcall(function()part.CFrame=newCF*cs.partOffsets[i]; part.AssemblyLinearVelocity=Vector3.zero; part.AssemblyAngularVelocity=Vector3.zero end)
            end
        end
        local char=player.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.Anchored then pcall(function()hrp.CFrame=newCF*CFrame.new(-2,CAR_INTERIOR_Y,-1.5)end)end
            for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then pcall(function()p.CanCollide=false end)end end
        end
        pcall(function()workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
    end

    -- ════════════════════════════════════════════════════════════
    -- DE SHRINE  (Domain Expansion: Malevolent Shrine)
    -- Sphere of blocks around player → closes → shrine center
    -- + 6 fast cutting slashes bouncing inside
    -- ════════════════════════════════════════════════════════════

    -- Build a dark torii/shrine from new Parts (server will see them)
    local function buildShrineStructure(center)
        local parts={}
        local function mkPart(sz,pos,col,mat,trans)
            local p=Instance.new("Part")
            p.Anchored=false; p.CanCollide=false
            p.Size=sz; p.CFrame=CFrame.new(center+pos)
            p.Color=col; p.Material=mat or Enum.Material.SmoothPlastic
            p.Transparency=trans or 0; p.CastShadow=true; p.Parent=workspace
            -- Give it a BodyPosition so it stays put (live for all players)
            local bp=Instance.new("BodyPosition")
            bp.MaxForce=Vector3.new(1e12,1e12,1e12); bp.P=60000; bp.D=3000
            bp.Position=center+pos; bp.Parent=p
            local bg=Instance.new("BodyGyro")
            bg.MaxTorque=Vector3.new(1e12,1e12,1e12); bg.P=60000; bg.D=3000
            bg.CFrame=CFrame.new(center+pos); bg.Parent=p
            table.insert(parts,p)
            return p
        end
        local darkStone=Color3.fromRGB(35,28,28)
        local redWood  =Color3.fromRGB(130,25,18)
        local darkWood =Color3.fromRGB(50,32,22)
        local gold     =Color3.fromRGB(200,160,30)
        -- Ground platform tiers
        mkPart(Vector3.new(10,0.5,10), Vector3.new(0,0.25,0),   darkStone)
        mkPart(Vector3.new(7,0.5,7),   Vector3.new(0,0.75,0),   darkStone)
        mkPart(Vector3.new(5,0.5,5),   Vector3.new(0,1.25,0),   darkStone)
        mkPart(Vector3.new(3,0.5,3),   Vector3.new(0,1.75,0),   darkWood)
        -- Central pillar / shrine body
        mkPart(Vector3.new(2,4,2),     Vector3.new(0,4,0),       redWood)
        mkPart(Vector3.new(3,0.5,3),   Vector3.new(0,6.25,0),    redWood)
        mkPart(Vector3.new(4,0.4,0.4), Vector3.new(0,6.6,0),     darkWood)  -- roof beam
        mkPart(Vector3.new(0.4,0.4,4), Vector3.new(0,6.6,0),     darkWood)  -- roof beam 2
        mkPart(Vector3.new(3.5,0.6,3.5),Vector3.new(0,7,0),      redWood)   -- roof
        -- Torii gate (two pillars + beam)
        mkPart(Vector3.new(0.5,5,0.5), Vector3.new(-3,2.5,6.5), darkWood)
        mkPart(Vector3.new(0.5,5,0.5), Vector3.new(3,2.5,6.5),  darkWood)
        mkPart(Vector3.new(7,0.6,0.5), Vector3.new(0,5,6.5),    redWood)
        mkPart(Vector3.new(6,0.4,0.4), Vector3.new(0,4.2,6.5),  redWood)
        -- Glowing eye / curse rune in center (floating above shrine)
        local eye=mkPart(Vector3.new(1.5,1.5,0.2),Vector3.new(0,9,0),Color3.fromRGB(255,50,0))
        eye.Material=Enum.Material.Neon
        -- Step lanterns
        for _,side in ipairs({{-1.8,0},{1.8,0},{0,-1.8},{0,1.8}}) do
            local lanternBase=mkPart(Vector3.new(0.6,1,0.6),Vector3.new(side[1],0.5+1.25,side[2]),darkStone)
            local flame=mkPart(Vector3.new(0.4,0.5,0.4),Vector3.new(side[1],1.4+1.25,side[2]),Color3.fromRGB(255,120,0))
            flame.Material=Enum.Material.Neon; flame.Transparency=0.2
        end
        -- Curse marks / black lines radiating on ground
        for i=0,5 do
            local ang=i*math.pi/3
            mkPart(Vector3.new(0.15,0.05,8),Vector3.new(math.cos(ang)*4,0.02,math.sin(ang)*4),Color3.fromRGB(20,0,0),Enum.Material.Neon,0.5)
        end
        return parts
    end

    local function buildSlash(center,slashIdx)
        local p=Instance.new("Part")
        p.Name="ShrineSlash"
        p.Size=Vector3.new(12,0.15,0.5)   -- long thin blade
        p.Color=Color3.fromRGB(255,255,240)
        p.Material=Enum.Material.Neon
        p.Transparency=0.1
        p.CanCollide=false
        p.CastShadow=false
        -- Random starting position inside sphere
        local startPos=center+Vector3.new(
            math.random(-15,15),
            math.random(-8,8),
            math.random(-15,15))
        p.CFrame=CFrame.new(startPos)*CFrame.Angles(math.random()*math.pi*2,math.random()*math.pi*2,0)
        p.Parent=workspace
        -- Random velocity direction
        local dir=Vector3.new(math.random()-0.5,math.random()-0.5,math.random()-0.5).Unit
        local bv=Instance.new("BodyVelocity")
        bv.MaxForce=Vector3.new(1e9,1e9,1e9)
        bv.Velocity=dir*SLASH_SPEED
        bv.Parent=p
        -- Glow
        pcall(function()
            local light=Instance.new("PointLight",p); light.Brightness=4; light.Range=12
            light.Color=Color3.fromRGB(220,220,255)
        end)
        -- Trail
        pcall(function()
            local a0=Instance.new("Attachment",p); a0.Position=Vector3.new(-6,0,0)
            local a1=Instance.new("Attachment",p); a1.Position=Vector3.new(6,0,0)
            local tr=Instance.new("Trail")
            tr.Attachment0=a0; tr.Attachment1=a1; tr.Lifetime=0.12; tr.MinLength=0
            tr.Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(200,200,255))
            tr.Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)}
            tr.WidthScale=NumberSequence.new{NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)}
            tr.Parent=p
        end)
        table.insert(shrineSlashes,p)
        table.insert(slashVelocities,dir*SLASH_SPEED)
        table.insert(shrineNewParts,p)
        return p
    end

    local function buildDomainSphere(center)
        -- Use existing controlled parts for the sphere wall.
        -- Arrange them in a big sphere shell (radius DOMAIN_RADIUS).
        local shellParts={}
        for part,_ in pairs(controlled) do
            if part and part.Parent then table.insert(shellParts,part) end
        end
        -- Set initial CanCollide=false (domain not closed yet)
        for _,part in ipairs(shellParts) do
            pcall(function()part.CanCollide=false end)
        end
        return shellParts
    end

    local function initDeShrine(pos,cf)
        shrineCenter=pos
        -- Sweep to get as many parts as possible
        sweepMap(); task.wait(0.1)
        -- Build sphere of existing parts (no CanCollide yet)
        buildDomainSphere(pos)
        -- Build shrine
        local shrParts=buildShrineStructure(pos)
        for _,p in ipairs(shrParts) do table.insert(shrineNewParts,p) end
        -- Build 6 cutting slashes
        shrineSlashes={}; slashVelocities={}
        for i=1,6 do buildSlash(pos,i) end
        -- State
        domainOpen=true; domainClosed=false; domainTimer=0
        shrineActive=true
    end

    local function updateDeShrine(dt)
        if not shrineActive then return end
        local char=player.Character
        local root=char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local rootPos=root and root.Position or shrineCenter

        -- Update sphere shell position (formation = giant sphere around player)
        local arr={}
        for part,data in pairs(controlled) do
            if part and part.Parent then table.insert(arr,{p=part,d=data}) end
        end
        local n=#arr
        local t=tick()
        for i,item in ipairs(arr) do
            local phi=(1+math.sqrt(5))/2
            local idx=i-1; local total=math.max(n,1)
            local theta2=math.acos(math.clamp(1-2*(idx+0.5)/total,-1,1))
            local ang=2*math.pi*idx/phi
            local r=DOMAIN_RADIUS*(0.9+math.sin(t*0.4+i*0.1)*0.08)  -- slight breathing pulse
            local offset=Vector3.new(r*math.sin(theta2)*math.cos(ang),r*math.sin(theta2)*math.sin(ang),r*math.cos(theta2))
            local targetPos=shrineCenter+offset
            local data=item.d
            pcall(function()
                if data.bp and data.bp.Parent then
                    data.bp.Position=targetPos
                    -- Face outward (normal pointing away from center)
                    data.bg.CFrame=CFrame.new(targetPos,shrineCenter)*CFrame.Angles(0,math.pi,0)
                else
                    item.p.CFrame=CFrame.new(targetPos)
                    item.p.AssemblyLinearVelocity=Vector3.zero
                    item.p.AssemblyAngularVelocity=Vector3.zero
                end
            end)
        end

        -- Domain close timer
        if domainOpen and not domainClosed then
            domainTimer=domainTimer+dt
            if domainTimer>=DOMAIN_OPEN_TIME then
                domainClosed=true; domainOpen=false
                -- Slam shut: set CanCollide=true on all sphere parts
                for part,_ in pairs(controlled) do
                    pcall(function()part.CanCollide=true end)
                end
            end
        end

        -- Slash movement: bounce off sphere wall
        for i,slash in ipairs(shrineSlashes) do
            if slash and slash.Parent then
                local slashPos=slash.Position
                local dist=(slashPos-shrineCenter).Magnitude
                if dist>DOMAIN_RADIUS*0.82 then
                    -- Bounce: reflect velocity off sphere normal
                    local normal=(shrineCenter-slashPos).Unit
                    local vel=slashVelocities[i]
                    if vel then
                        local reflected=vel-2*(vel:Dot(normal))*normal
                        -- Add slight random deviation so slashes don't loop predictably
                        reflected=(reflected.Unit+Vector3.new((math.random()-0.5)*0.3,(math.random()-0.5)*0.2,(math.random()-0.5)*0.3)).Unit*SLASH_SPEED
                        slashVelocities[i]=reflected
                        pcall(function()
                            local bv=slash:FindFirstChildOfClass("BodyVelocity")
                            if bv then bv.Velocity=reflected end
                        end)
                    end
                end
                -- Rotate slash to face its travel direction (looks like a blade)
                if slashVelocities[i] and slashVelocities[i].Magnitude>0 then
                    pcall(function()
                        local dir=slashVelocities[i].Unit
                        slash.CFrame=CFrame.new(slashPos,slashPos+dir)*CFrame.Angles(0,0,math.pi/2)
                    end)
                end
            end
        end
    end

    destroyShrine=function()
        -- Release sphere parts back to normal CanCollide
        for part,_ in pairs(controlled) do
            pcall(function()part.CanCollide=true end)
        end
        -- Destroy shrine structure + slashes
        for _,p in ipairs(shrineNewParts) do
            pcall(function()if p and p.Parent then p:Destroy() end end)
        end
        shrineNewParts={}; shrineSlashes={}; slashVelocities={}
        domainOpen=false; domainClosed=false; domainTimer=0
        shrineActive=false; shrineCenter=Vector3.zero
    end

    -- ════════════════════════════════════════════════════════════
    -- SUB-GUIS (Gaster, Sphere, SphereBender, Tank, Car, Shrine)
    -- ════════════════════════════════════════════════════════════

    local function destroyGasterGui() if gasterSubGui and gasterSubGui.Parent then gasterSubGui:Destroy() end; gasterSubGui=nil end
    local function createGasterGui()
        destroyGasterGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="GasterSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; gasterSubGui=sg
        local W,H=195,180; local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(W,H); panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-100); panel.BackgroundColor3=Color3.fromRGB(6,6,18); panel.BorderSizePixel=0; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,7); local ps=Instance.new("UIStroke",panel); ps.Color=Color3.fromRGB(180,60,255); ps.Thickness=1.2
        local tBar=Instance.new("Frame"); tBar.Size=UDim2.new(1,0,0,28); tBar.BackgroundColor3=Color3.fromRGB(20,8,45); tBar.BorderSizePixel=0; tBar.ZIndex=10; tBar.Parent=panel; Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,7)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="GASTER FORM"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(6,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(200,120,255); tLbl.TextSize=11; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=tBar
        local animLbl=Instance.new("TextLabel"); animLbl.Text="FORM: "..gasterAnim:upper(); animLbl.Size=UDim2.new(1,-10,0,14); animLbl.Position=UDim2.fromOffset(6,31); animLbl.BackgroundTransparency=1; animLbl.TextColor3=Color3.fromRGB(130,130,255); animLbl.TextSize=9; animLbl.Font=Enum.Font.GothamBold; animLbl.TextXAlignment=Enum.TextXAlignment.Left; animLbl.Parent=panel
        for idx,anim in ipairs({{txt="POINTING",key="pointing",col=Color3.fromRGB(100,200,255)},{txt="WAVING",key="waving",col=Color3.fromRGB(100,255,160)},{txt="PUNCHING",key="punching",col=Color3.fromRGB(255,120,120)}}) do
            local btn=Instance.new("TextButton"); btn.Text=anim.txt; btn.Size=UDim2.new(1,-12,0,30); btn.Position=UDim2.fromOffset(6,48+(idx-1)*36); btn.BackgroundColor3=Color3.fromRGB(22,10,48); btn.TextColor3=anim.col; btn.TextSize=11; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.Parent=panel; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()gasterAnim=anim.key; gasterT=0; animLbl.Text="FORM: "..anim.key:upper()end)
        end
        makeDraggable(tBar,panel,false)
    end

    local function destroySphereGui() if sphereSubGui and sphereSubGui.Parent then sphereSubGui:Destroy() end; sphereSubGui=nil end
    local function createSphereGui()
        destroySphereGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="SphereSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; sphereSubGui=sg
        local W,H=195,172; local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(W,H); panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-100); panel.BackgroundColor3=Color3.fromRGB(4,12,20); panel.BorderSizePixel=0; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,7); local ps=Instance.new("UIStroke",panel); ps.Color=Color3.fromRGB(60,180,255); ps.Thickness=1.2
        local tBar=Instance.new("Frame"); tBar.Size=UDim2.new(1,0,0,28); tBar.BackgroundColor3=Color3.fromRGB(8,20,45); tBar.BorderSizePixel=0; tBar.ZIndex=10; tBar.Parent=panel; Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,7)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="SPHERE CONTROL"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(6,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(80,200,255); tLbl.TextSize=11; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=tBar
        local mLbl=Instance.new("TextLabel"); mLbl.Text="STATE: "..sphereMode:upper(); mLbl.Size=UDim2.new(1,-10,0,14); mLbl.Position=UDim2.fromOffset(6,31); mLbl.BackgroundTransparency=1; mLbl.TextColor3=Color3.fromRGB(80,180,255); mLbl.TextSize=9; mLbl.Font=Enum.Font.GothamBold; mLbl.TextXAlignment=Enum.TextXAlignment.Left; mLbl.Parent=panel
        for idx,sb in ipairs({{txt="ORBIT",key="orbit",col=Color3.fromRGB(80,220,255)},{txt="FOLLOW",key="follow",col=Color3.fromRGB(120,255,160)},{txt="STAY",key="stay",col=Color3.fromRGB(255,200,80)}}) do
            local btn=Instance.new("TextButton"); btn.Text=sb.txt; btn.Size=UDim2.new(1,-12,0,30); btn.Position=UDim2.fromOffset(6,48+(idx-1)*36); btn.BackgroundColor3=Color3.fromRGB(8,22,44); btn.TextColor3=sb.col; btn.TextSize=11; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.Parent=panel; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()sphereMode=sb.key; sphereVel=Vector3.zero; mLbl.Text="STATE: "..sb.key:upper()end)
        end
        makeDraggable(tBar,panel,false)
    end

    local function destroySphereBenderGui() if sbSubGui and sbSubGui.Parent then sbSubGui:Destroy() end; sbSubGui=nil end
    rebuildSBGui=function()
        destroySphereBenderGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="SphereBenderGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1001; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; sbSubGui=sg
        local W=205; local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(W,300); panel.Position=UDim2.new(0.5,-W-10,0.5,-150); panel.BackgroundColor3=Color3.fromRGB(5,8,20); panel.BorderSizePixel=0; panel.ClipsDescendants=false; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8); local stk=Instance.new("UIStroke",panel); stk.Color=Color3.fromRGB(0,200,255); stk.Thickness=1.4
        local tBar=Instance.new("Frame"); tBar.Size=UDim2.new(1,0,0,28); tBar.BackgroundColor3=Color3.fromRGB(4,18,40); tBar.BorderSizePixel=0; tBar.ZIndex=10; tBar.Parent=panel; Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="SPHERE BENDER"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(8,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(0,220,255); tLbl.TextSize=12; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=tBar
        local yOff=32
        local function getSelMode()for _,sp in ipairs(sbSpheres)do if sp.selected then return sp.mode end end;return "orbit"end
        local mLbl=Instance.new("TextLabel"); mLbl.Text="STATE: "..getSelMode():upper(); mLbl.Size=UDim2.new(1,-10,0,16); mLbl.Position=UDim2.fromOffset(6,yOff); mLbl.BackgroundTransparency=1; mLbl.TextColor3=Color3.fromRGB(0,180,255); mLbl.TextSize=9; mLbl.Font=Enum.Font.GothamBold; mLbl.TextXAlignment=Enum.TextXAlignment.Left; mLbl.Parent=panel; yOff=yOff+18
        for _,mb in ipairs({{txt="ORBIT",key="orbit",col=Color3.fromRGB(80,220,255)},{txt="FOLLOW",key="follow",col=Color3.fromRGB(120,255,160)},{txt="STAY",key="stay",col=Color3.fromRGB(255,200,80)}}) do
            local btn=Instance.new("TextButton"); btn.Text=mb.txt; btn.Size=UDim2.new(1,-12,0,28); btn.Position=UDim2.fromOffset(6,yOff); btn.BackgroundColor3=Color3.fromRGB(6,18,36); btn.TextColor3=mb.col; btn.TextSize=11; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.Parent=panel; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()
                for _,sp in ipairs(sbSpheres)do if sp.selected then sp.mode=mb.key;sp.stopped=false;sp.vel=Vector3.zero end end; mLbl.Text="STATE: "..mb.key:upper()
            end); yOff=yOff+32
        end
        local div=Instance.new("Frame"); div.Size=UDim2.new(1,-12,0,1); div.Position=UDim2.fromOffset(6,yOff+2); div.BackgroundColor3=Color3.fromRGB(0,100,160); div.BorderSizePixel=0; div.Parent=panel; yOff=yOff+10
        local function sBtn2(t2,x,w,yp,bg,fg)local b=Instance.new("TextButton");b.Text=t2;b.Size=UDim2.fromOffset(w,26);b.Position=UDim2.fromOffset(x,yp);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=11;b.Font=Enum.Font.GothamBold;b.BorderSizePixel=0;b.Parent=panel;Instance.new("UICorner",b);return b end
        local stopBtn=sBtn2("STOP",6,(W-18)/2,yOff,Color3.fromRGB(60,8,8),Color3.fromRGB(255,60,60))
        local goBtn=sBtn2("GO",10+(W-18)/2,(W-18)/2,yOff,Color3.fromRGB(8,50,8),Color3.fromRGB(60,255,100)); yOff=yOff+30
        stopBtn.MouseButton1Click:Connect(function()for _,sp in ipairs(sbSpheres)do if sp.selected then sp.stopped=true;sp.vel=Vector3.zero end end;mLbl.Text="STATE: STOPPED"end)
        goBtn.MouseButton1Click:Connect(function()for _,sp in ipairs(sbSpheres)do if sp.selected then sp.stopped=false;sp.vel=Vector3.zero end end;mLbl.Text="STATE: "..getSelMode():upper()end)
        local splitBtn=sBtn2("SPLIT SPHERE",6,W-12,yOff,Color3.fromRGB(10,30,55),Color3.fromRGB(0,200,255)); yOff=yOff+30
        splitBtn.MouseButton1Click:Connect(function()
            local char=player.Character; local root=char and(char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local s=newSBSphere((root and root.Position or Vector3.new(0,5,0))+Vector3.new(math.random(-4,4),2,math.random(-4,4)));table.insert(sbSpheres,s);rebuildSBGui()
        end)
        local hdr=Instance.new("TextLabel"); hdr.Text="SPHERES"; hdr.Size=UDim2.new(1,-10,0,16); hdr.Position=UDim2.fromOffset(6,yOff); hdr.BackgroundTransparency=1; hdr.TextColor3=Color3.fromRGB(0,160,220); hdr.TextSize=9; hdr.Font=Enum.Font.GothamBold; hdr.TextXAlignment=Enum.TextXAlignment.Left; hdr.Parent=panel; yOff=yOff+18
        for idx,sp in ipairs(sbSpheres) do
            local sBtn=Instance.new("TextButton"); sBtn.Text="SPHERE "..idx..(sp.stopped and"  [STOP]"or"  ["..sp.mode:upper().."]"); sBtn.Size=UDim2.new(1,-12,0,26); sBtn.Position=UDim2.fromOffset(6,yOff); sBtn.BackgroundColor3=sp.selected and Color3.fromRGB(0,60,120) or Color3.fromRGB(6,18,36); sBtn.TextColor3=sp.selected and Color3.fromRGB(80,200,255) or Color3.fromRGB(140,140,180); sBtn.TextSize=9; sBtn.Font=Enum.Font.GothamBold; sBtn.BorderSizePixel=0; sBtn.Parent=panel; Instance.new("UICorner",sBtn)
            local sBtkS=Instance.new("UIStroke",sBtn); sBtkS.Color=sp.selected and Color3.fromRGB(0,180,255) or Color3.fromRGB(30,60,100); sBtkS.Thickness=sp.selected and 1.5 or 0.8
            local cSp,cBtn,cStk=sp,sBtn,sBtkS
            sBtn.MouseButton1Click:Connect(function()cSp.selected=not cSp.selected;cBtn.BackgroundColor3=cSp.selected and Color3.fromRGB(0,60,120) or Color3.fromRGB(6,18,36);cBtn.TextColor3=cSp.selected and Color3.fromRGB(80,200,255) or Color3.fromRGB(140,140,180);cStk.Color=cSp.selected and Color3.fromRGB(0,180,255) or Color3.fromRGB(30,60,100);cStk.Thickness=cSp.selected and 1.5 or 0.8;mLbl.Text="STATE: "..getSelMode():upper()end)
            yOff=yOff+30
        end
        panel.Size=UDim2.fromOffset(W,yOff+8); makeDraggable(tBar,panel,false)
    end

    -- ── Tank GUI ──────────────────────────────────────────────
    destroyTankGui=function() if tankSubGui and tankSubGui.Parent then tankSubGui:Destroy() end; tankSubGui=nil end
    local function createTankGui()
        destroyTankGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="TankSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; tankSubGui=sg
        local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(185,280); panel.Position=UDim2.new(0,10,0.5,-140); panel.BackgroundColor3=Color3.fromRGB(18,18,18); panel.BorderSizePixel=0; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8); local stk=Instance.new("UIStroke",panel); stk.Color=Color3.fromRGB(90,90,90); stk.Thickness=1.5
        local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=Color3.fromRGB(30,30,30); titleBar.BorderSizePixel=0; titleBar.ZIndex=10; titleBar.Parent=panel; Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="🪖 TANK"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(8,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(210,210,210); tLbl.TextSize=12; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=titleBar
        local sLbl=Instance.new("TextLabel"); sLbl.Text="INSIDE  |  READY"; sLbl.Size=UDim2.new(1,-10,0,16); sLbl.Position=UDim2.fromOffset(6,30); sLbl.BackgroundTransparency=1; sLbl.TextColor3=Color3.fromRGB(130,200,130); sLbl.TextSize=9; sLbl.Font=Enum.Font.GothamBold; sLbl.TextXAlignment=Enum.TextXAlignment.Left; sLbl.Parent=panel
        local dLbl=Instance.new("TextLabel"); dLbl.Text="MOVEMENT"; dLbl.Size=UDim2.new(1,-10,0,12); dLbl.Position=UDim2.fromOffset(6,49); dLbl.BackgroundTransparency=1; dLbl.TextColor3=Color3.fromRGB(100,100,150); dLbl.TextSize=8; dLbl.Font=Enum.Font.GothamBold; dLbl.TextXAlignment=Enum.TextXAlignment.Left; dLbl.Parent=panel
        local cx=(185-36)/2; local dy0=63; local bs=36; local gap=2
        local function dpBtn(t2,xp,yp) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.fromOffset(bs,bs); b.Position=UDim2.fromOffset(xp,yp); b.BackgroundColor3=Color3.fromRGB(40,40,55); b.TextColor3=Color3.fromRGB(200,200,255); b.TextSize=16; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.Parent=panel; Instance.new("UICorner",b).CornerRadius=UDim.new(0,6); Instance.new("UIStroke",b).Color=Color3.fromRGB(80,80,130); return b end
        local upBtn=dpBtn("▲",cx,dy0); local leftBtn=dpBtn("◀",cx-bs-gap,dy0+bs+gap); local rightBtn=dpBtn("▶",cx+bs+gap,dy0+bs+gap); local downBtn=dpBtn("▼",cx,dy0+bs*2+gap*2)
        local function setP(btn,on) btn.BackgroundColor3=on and Color3.fromRGB(60,60,100) or Color3.fromRGB(40,40,55) end
        upBtn.MouseButton1Down:Connect(function()tks.forward=1;setP(upBtn,true)end); upBtn.MouseButton1Up:Connect(function()tks.forward=0;setP(upBtn,false)end)
        downBtn.MouseButton1Down:Connect(function()tks.forward=-1;setP(downBtn,true)end); downBtn.MouseButton1Up:Connect(function()tks.forward=0;setP(downBtn,false)end)
        leftBtn.MouseButton1Down:Connect(function()tks.turn=-1;setP(leftBtn,true)end); leftBtn.MouseButton1Up:Connect(function()tks.turn=0;setP(leftBtn,false)end)
        rightBtn.MouseButton1Down:Connect(function()tks.turn=1;setP(rightBtn,true)end); rightBtn.MouseButton1Up:Connect(function()tks.turn=0;setP(rightBtn,false)end)
        local ay=dy0+bs*3+gap*2+10
        local function aBtn(t2,yp,bg,fg) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.new(1,-12,0,28); b.Position=UDim2.fromOffset(6,yp); b.BackgroundColor3=bg; b.TextColor3=fg; b.TextSize=11; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.Parent=panel; Instance.new("UICorner",b); return b end
        local fireBtn=aBtn("🔥 FIRE",ay,Color3.fromRGB(65,35,12),Color3.fromRGB(255,200,80))
        local hatchBtn=aBtn("🚪 OPEN HATCH",ay+32,Color3.fromRGB(30,45,60),Color3.fromRGB(120,200,255))
        local destructBtn=aBtn("💥 DESTRUCT",ay+64,Color3.fromRGB(75,12,12),Color3.fromRGB(255,80,80))
        fireBtn.MouseButton1Click:Connect(function()shootProjectile();sLbl.Text="FIRING!";sLbl.TextColor3=Color3.fromRGB(255,200,80);task.wait(0.4);if sLbl.Parent then sLbl.Text="INSIDE  |  READY";sLbl.TextColor3=Color3.fromRGB(130,200,130)end end)
        hatchBtn.MouseButton1Click:Connect(function()toggleHatch();if tks.hatchOpen then hatchBtn.Text="🚪 CLOSE HATCH";sLbl.Text="OUTSIDE  |  FREE";sLbl.TextColor3=Color3.fromRGB(200,200,100) else hatchBtn.Text="🚪 OPEN HATCH";sLbl.Text="INSIDE  |  READY";sLbl.TextColor3=Color3.fromRGB(130,200,130)end end)
        destructBtn.MouseButton1Click:Connect(function()task.spawn(function()destroyTank();destroyTankGui()end)end)
        -- Aim joystick
        local jR=rightJoy.radius
        local jBase=Instance.new("Frame"); jBase.Size=UDim2.fromOffset(jR*2,jR*2); jBase.Position=UDim2.new(1,-(jR*2+18),0.36,-jR); jBase.BackgroundColor3=Color3.fromRGB(50,50,80); jBase.BackgroundTransparency=0.35; jBase.BorderSizePixel=0; jBase.Parent=sg; Instance.new("UICorner",jBase).CornerRadius=UDim.new(1,0); local jStk=Instance.new("UIStroke",jBase); jStk.Color=Color3.fromRGB(100,120,200); jStk.Thickness=1.5
        local jAimLbl=Instance.new("TextLabel"); jAimLbl.Text="AIM"; jAimLbl.Size=UDim2.new(1,0,0,14); jAimLbl.Position=UDim2.new(0,0,0,4); jAimLbl.BackgroundTransparency=1; jAimLbl.TextColor3=Color3.fromRGB(180,180,255); jAimLbl.TextSize=8; jAimLbl.Font=Enum.Font.GothamBold; jAimLbl.ZIndex=5; jAimLbl.Parent=jBase
        local jThumb=Instance.new("Frame"); jThumb.Size=UDim2.fromOffset(28,28); jThumb.Position=UDim2.new(0.5,-14,0.5,-14); jThumb.BackgroundColor3=Color3.fromRGB(140,150,230); jThumb.BackgroundTransparency=0.2; jThumb.BorderSizePixel=0; jThumb.Parent=jBase; Instance.new("UICorner",jThumb).CornerRadius=UDim.new(1,0)
        local function updAimThumb() if rightJoy.active then local off=rightJoy.current-rightJoy.origin;local dist=math.min(off.Magnitude,jR);local dir=off.Magnitude>0 and off.Unit or Vector2.zero;jThumb.Position=UDim2.new(0.5,dir.X*dist-14,0.5,dir.Y*dist-14) else jThumb.Position=UDim2.new(0.5,-14,0.5,-14)end end
        local conKBB=UserInputService.InputBegan:Connect(function(inp,proc) if proc then return end; if inp.KeyCode==Enum.KeyCode.W then tks.forward=1 elseif inp.KeyCode==Enum.KeyCode.S then tks.forward=-1 elseif inp.KeyCode==Enum.KeyCode.A then tks.turn=-1 elseif inp.KeyCode==Enum.KeyCode.D then tks.turn=1 elseif inp.KeyCode==Enum.KeyCode.F then if tks.insideTank then shootProjectile()end elseif inp.KeyCode==Enum.KeyCode.H then toggleHatch()end end)
        local conKBE=UserInputService.InputEnded:Connect(function(inp,_) if inp.KeyCode==Enum.KeyCode.W or inp.KeyCode==Enum.KeyCode.S then tks.forward=0 elseif inp.KeyCode==Enum.KeyCode.A or inp.KeyCode==Enum.KeyCode.D then tks.turn=0 end end)
        local conTS=UserInputService.TouchStarted:Connect(function(touch,proc) if proc then return end; local pos=Vector2.new(touch.Position.X,touch.Position.Y); local center=Vector2.new(jBase.AbsolutePosition.X+jBase.AbsoluteSize.X/2,jBase.AbsolutePosition.Y+jBase.AbsoluteSize.Y/2); if(pos-center).Magnitude<jR*1.6 then rightJoy.active=true;rightJoy.origin=pos;rightJoy.current=pos;rightJoy.touchId=touch end end)
        local conTM=UserInputService.TouchMoved:Connect(function(touch,_) if not rightJoy.active or rightJoy.touchId~=touch then return end; local pos=Vector2.new(touch.Position.X,touch.Position.Y); rightJoy.current=pos; local off=pos-rightJoy.origin; local dist=math.min(off.Magnitude,jR); if dist>rightJoy.deadzone then local dir=off.Unit; cameraOrbitAngle=cameraOrbitAngle+dir.X*CAM_ORBIT_SENS*0.018; cameraPitchAngle=math.clamp(cameraPitchAngle+dir.Y*CAM_PITCH_SENS*0.014,CAM_PITCH_MIN,CAM_PITCH_MAX)end;updAimThumb()end)
        local conTE=UserInputService.TouchEnded:Connect(function(touch,_) if rightJoy.touchId==touch then rightJoy.active=false;rightJoy.touchId=nil;updAimThumb()end end)
        sg.AncestryChanged:Connect(function(_,par) if not par then pcall(function()conKBB:Disconnect()end);pcall(function()conKBE:Disconnect()end);pcall(function()conTS:Disconnect()end);pcall(function()conTM:Disconnect()end);pcall(function()conTE:Disconnect()end);tks.forward=0;tks.turn=0;rightJoy.active=false end end)
        makeDraggable(titleBar,panel,false)
    end

    -- ── Car GUI ───────────────────────────────────────────────
    destroyCarGui=function() if carSubGui and carSubGui.Parent then carSubGui:Destroy() end; carSubGui=nil end
    local function createCarGui()
        destroyCarGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="CarSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; carSubGui=sg
        local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(165,130); panel.Position=UDim2.new(0,10,0.5,-65); panel.BackgroundColor3=Color3.fromRGB(14,18,14); panel.BorderSizePixel=0; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8); local stk=Instance.new("UIStroke",panel); stk.Color=Color3.fromRGB(60,160,60); stk.Thickness=1.5
        local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=Color3.fromRGB(20,35,20); titleBar.BorderSizePixel=0; titleBar.ZIndex=10; titleBar.Parent=panel; Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="🚗 CAR"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(8,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(120,220,120); tLbl.TextSize=12; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=titleBar
        local sLbl=Instance.new("TextLabel"); sLbl.Text="PARKED  |  OPEN DOOR"; sLbl.Size=UDim2.new(1,-10,0,16); sLbl.Position=UDim2.fromOffset(6,30); sLbl.BackgroundTransparency=1; sLbl.TextColor3=Color3.fromRGB(180,180,100); sLbl.TextSize=9; sLbl.Font=Enum.Font.GothamBold; sLbl.TextXAlignment=Enum.TextXAlignment.Left; sLbl.Parent=panel
        local function aBtn2(t2,yp,bg,fg) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.new(1,-12,0,30); b.Position=UDim2.fromOffset(6,yp); b.BackgroundColor3=bg; b.TextColor3=fg; b.TextSize=11; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.Parent=panel; Instance.new("UICorner",b); return b end
        local doorBtn=aBtn2("🚪 OPEN DOOR",50,Color3.fromRGB(25,45,25),Color3.fromRGB(80,240,80))
        local destBtn=aBtn2("🔧 DESTROY",   86,Color3.fromRGB(70,10,10), Color3.fromRGB(255,70,70))
        doorBtn.MouseButton1Click:Connect(function()toggleCarDoor();if cs.doorOpen then doorBtn.Text="🚪 CLOSE DOOR";sLbl.Text="DRIVING  |  INSIDE";sLbl.TextColor3=Color3.fromRGB(100,230,100) else doorBtn.Text="🚪 OPEN DOOR";sLbl.Text="PARKED  |  OPEN DOOR";sLbl.TextColor3=Color3.fromRGB(180,180,100)end end)
        destBtn.MouseButton1Click:Connect(function()task.spawn(function()destroyCar();destroyCarGui()end)end)
        -- Drive joystick (left, large, sensitive)
        local jR2=carJoy.radius
        local jBase2=Instance.new("Frame"); jBase2.Size=UDim2.fromOffset(jR2*2,jR2*2); jBase2.Position=UDim2.new(0,18,0.62,-jR2); jBase2.BackgroundColor3=Color3.fromRGB(30,60,30); jBase2.BackgroundTransparency=0.3; jBase2.BorderSizePixel=0; jBase2.Parent=sg; Instance.new("UICorner",jBase2).CornerRadius=UDim.new(1,0); local jStk2=Instance.new("UIStroke",jBase2); jStk2.Color=Color3.fromRGB(60,180,60); jStk2.Thickness=2
        local jDLbl=Instance.new("TextLabel"); jDLbl.Text="DRIVE"; jDLbl.Size=UDim2.new(1,0,0,16); jDLbl.Position=UDim2.new(0,0,0,4); jDLbl.BackgroundTransparency=1; jDLbl.TextColor3=Color3.fromRGB(100,220,100); jDLbl.TextSize=9; jDLbl.Font=Enum.Font.GothamBold; jDLbl.ZIndex=5; jDLbl.Parent=jBase2
        local jThumb2=Instance.new("Frame"); jThumb2.Size=UDim2.fromOffset(36,36); jThumb2.Position=UDim2.new(0.5,-18,0.5,-18); jThumb2.BackgroundColor3=Color3.fromRGB(80,200,80); jThumb2.BackgroundTransparency=0.2; jThumb2.BorderSizePixel=0; jThumb2.Parent=jBase2; Instance.new("UICorner",jThumb2).CornerRadius=UDim.new(1,0)
        local function updCarJoy() if carJoy.active then local off=carJoy.current-carJoy.origin;local dist=math.min(off.Magnitude,jR2);local dir=off.Magnitude>0 and off.Unit or Vector2.zero;jThumb2.Position=UDim2.new(0.5,dir.X*dist-18,0.5,dir.Y*dist-18) else jThumb2.Position=UDim2.new(0.5,-18,0.5,-18)end end
        local conCTS=UserInputService.TouchStarted:Connect(function(touch,proc) if proc or not cs.doorOpen then return end; local pos=Vector2.new(touch.Position.X,touch.Position.Y); local center=Vector2.new(jBase2.AbsolutePosition.X+jBase2.AbsoluteSize.X/2,jBase2.AbsolutePosition.Y+jBase2.AbsoluteSize.Y/2); if(pos-center).Magnitude<jR2*1.7 then carJoy.active=true;carJoy.origin=pos;carJoy.current=pos;carJoy.touchId=touch end end)
        local conCTM=UserInputService.TouchMoved:Connect(function(touch,_) if not carJoy.active or carJoy.touchId~=touch then return end; local pos=Vector2.new(touch.Position.X,touch.Position.Y); carJoy.current=pos; local off=pos-carJoy.origin; local dist=math.min(off.Magnitude,jR2); if dist>carJoy.deadzone then local dir=off.Unit;carJoy.forward=-dir.Y;carJoy.turn=dir.X else carJoy.forward=0;carJoy.turn=0 end;updCarJoy()end)
        local conCTE=UserInputService.TouchEnded:Connect(function(touch,_) if carJoy.touchId==touch then carJoy.active=false;carJoy.touchId=nil;carJoy.forward=0;carJoy.turn=0;updCarJoy()end end)
        local conCKBB=UserInputService.InputBegan:Connect(function(inp,proc) if proc or not cs.doorOpen then return end; if inp.KeyCode==Enum.KeyCode.W then carJoy.forward=1 elseif inp.KeyCode==Enum.KeyCode.S then carJoy.forward=-1 elseif inp.KeyCode==Enum.KeyCode.A then carJoy.turn=-1 elseif inp.KeyCode==Enum.KeyCode.D then carJoy.turn=1 end end)
        local conCKBE=UserInputService.InputEnded:Connect(function(inp,_) if inp.KeyCode==Enum.KeyCode.W or inp.KeyCode==Enum.KeyCode.S then carJoy.forward=0 elseif inp.KeyCode==Enum.KeyCode.A or inp.KeyCode==Enum.KeyCode.D then carJoy.turn=0 end end)
        sg.AncestryChanged:Connect(function(_,par) if not par then pcall(function()conCTS:Disconnect()end);pcall(function()conCTM:Disconnect()end);pcall(function()conCTE:Disconnect()end);pcall(function()conCKBB:Disconnect()end);pcall(function()conCKBE:Disconnect()end);carJoy.forward=0;carJoy.turn=0;carJoy.active=false end end)
        makeDraggable(titleBar,panel,false)
    end

    -- ── Shrine GUI ────────────────────────────────────────────
    destroyShrineGui=function() if shrineSubGui and shrineSubGui.Parent then shrineSubGui:Destroy() end; shrineSubGui=nil end
    local function createShrineGui()
        destroyShrineGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="ShrineSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; shrineSubGui=sg
        local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(175,115); panel.Position=UDim2.new(0,10,0.5,-57); panel.BackgroundColor3=Color3.fromRGB(12,4,4); panel.BorderSizePixel=0; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8)
        local stk=Instance.new("UIStroke",panel); stk.Color=Color3.fromRGB(180,20,20); stk.Thickness=1.5
        local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=Color3.fromRGB(40,8,8); titleBar.BorderSizePixel=0; titleBar.ZIndex=10; titleBar.Parent=panel; Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="⛩ DE SHRINE"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(8,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(255,80,50); tLbl.TextSize=12; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=titleBar
        local sLbl=Instance.new("TextLabel"); sLbl.Text="DOMAIN OPENING..."; sLbl.Size=UDim2.new(1,-10,0,16); sLbl.Position=UDim2.fromOffset(6,31); sLbl.BackgroundTransparency=1; sLbl.TextColor3=Color3.fromRGB(255,160,60); sLbl.TextSize=9; sLbl.Font=Enum.Font.GothamBold; sLbl.TextXAlignment=Enum.TextXAlignment.Left; sLbl.Parent=panel
        -- Update status label based on domain state
        task.spawn(function()
            while sg.Parent and shrineActive do
                if domainClosed then sLbl.Text="DOMAIN CLOSED  |  TRAPPED"; sLbl.TextColor3=Color3.fromRGB(255,60,60)
                elseif domainOpen then sLbl.Text="DOMAIN OPENING..."; sLbl.TextColor3=Color3.fromRGB(255,160,60) end
                task.wait(0.3)
            end
        end)
        local function aBtn3(t2,yp,bg,fg) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.new(1,-12,0,30); b.Position=UDim2.fromOffset(6,yp); b.BackgroundColor3=bg; b.TextColor3=fg; b.TextSize=11; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.Parent=panel; Instance.new("UICorner",b); return b end
        local closeBtn2=aBtn3("🔓 OPEN DOMAIN",51,Color3.fromRGB(60,20,8),Color3.fromRGB(255,130,60))
        local cancelBtn=aBtn3("💀 CANCEL",83,Color3.fromRGB(60,10,10),Color3.fromRGB(255,60,60))
        closeBtn2.MouseButton1Click:Connect(function()
            -- Toggle domain closed/open manually
            if domainClosed then
                domainClosed=false; domainOpen=true; domainTimer=0
                for part,_ in pairs(controlled) do pcall(function()part.CanCollide=false end)end
                closeBtn2.Text="🔒 CLOSE DOMAIN"; sLbl.Text="DOMAIN OPEN"
            else
                domainClosed=true; domainOpen=false
                for part,_ in pairs(controlled) do pcall(function()part.CanCollide=true end)end
                closeBtn2.Text="🔓 OPEN DOMAIN"; sLbl.Text="DOMAIN CLOSED"
            end
        end)
        cancelBtn.MouseButton1Click:Connect(function()
            destroyShrine(); destroyShrineGui()
            activeMode="none"; isActivated=false
        end)
        makeDraggable(titleBar,panel,false)
    end

    -- ════════════════════════════════════════════════════════════
    -- MAIN LOOP (Stepped = fires BEFORE physics step, min lag)
    -- ════════════════════════════════════════════════════════════
    local function mainLoop()
        RunService.Stepped:Connect(function(_, dt)
            if not scriptAlive then return end
            snakeT=snakeT+dt; gasterT=gasterT+dt

            -- Clean 360° spin: accumulate a single angle, apply as AxisAngle
            if spinSpeed~=0 then
                spinAngle=spinAngle+spinSpeed*dt
                if spinAngle>math.pi*200 then spinAngle=spinAngle-math.pi*400 end
            end

            local char=player.Character
            local root=char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            if not root then return end
            local pos=root.Position; local cf=root.CFrame; local t=tick()

            if activeMode=="sphere"       then updateSphereTarget(dt,pos) end
            if activeMode=="spherebender" then updateSphereBenderTargets(dt,pos) end
            if activeMode=="tank"         then updateTank(dt) end
            if activeMode=="car"          then updateCar(dt) end
            if activeMode=="de_shrine"    then updateDeShrine(dt) end

            table.insert(snakeHistory,1,pos)
            if #snakeHistory>SNAKE_HIST_MAX then table.remove(snakeHistory,SNAKE_HIST_MAX+1) end

            -- Mode transitions
            if activeMode~=lastMode then
                if GASTER_MODES[activeMode]       then createGasterGui()      else destroyGasterGui() end
                if SPHERE_MODES[activeMode] then spherePos=pos+Vector3.new(0,1.5,4);sphereVel=Vector3.zero;createSphereGui() else destroySphereGui() end
                if SPHERE_BENDER_MODES[activeMode] then
                    if #sbSpheres==0 then local s=newSBSphere(pos+Vector3.new(0,1.5,4));s.selected=true;table.insert(sbSpheres,s) end
                    rebuildSBGui()
                else destroySphereBenderGui(); sbSpheres={} end
                if TANK_MODES[activeMode] then
                    tankActive=true; cameraOrbitAngle=0; cameraPitchAngle=math.rad(25); createTankGui()
                    local ok=buildTankFromParts(pos,cf)
                    if ok then tks.insideTank=true; tks.hatchOpen=false; freezePlayer(tks.tankBase.CFrame*CFrame.new(0,TANK_INTERIOR_Y,0)) end
                else if tankActive then destroyTank(); destroyTankGui() end end
                if CAR_MODES[activeMode] then
                    carActive=true; createCarGui()
                    local ok=buildCarFromParts(pos,cf)
                    if ok then frozenCarCF=cs.carBase.CFrame end
                else if carActive then destroyCar(); destroyCarGui() end end
                if SHRINE_MODES[activeMode] then
                    shrineActive=true; sweepMap(); task.spawn(function() initDeShrine(pos,cf) end); createShrineGui()
                else if shrineActive then destroyShrine(); destroyShrineGui() end end
                lastMode=activeMode
            end

            -- DE Shrine handles its own formation in updateDeShrine — skip standard loop
            if not isActivated or activeMode=="none" or partCount==0 then return end
            if activeMode=="tank" or activeMode=="car" or activeMode=="de_shrine" then return end

            -- Standard formation loop
            local arr={}
            for part,data in pairs(controlled) do
                if part and part.Parent then table.insert(arr,{p=part,d=data})
                else controlled[part]=nil; partCount=math.max(0,partCount-1) end
            end
            local n=#arr

            for i,item in ipairs(arr) do
                local part=item.p; local targetCF=nil
                if activeMode=="snake" then
                    targetCF=CFrame.new(getSnakeTarget(i))
                elseif activeMode=="gasterhand" then
                    targetCF=(i<=HAND_SLOTS_COUNT) and getGasterCF(i,1,cf,gasterT) or CFrame.new(pos+Vector3.new(0,-5000,0))
                elseif activeMode=="gaster2hands" then
                    if i<=HAND_SLOTS_COUNT then targetCF=getGasterCF(i,1,cf,gasterT)
                    elseif i<=HAND_SLOTS_COUNT*2 then targetCF=getGasterCF(i-HAND_SLOTS_COUNT,-1,cf,gasterT)
                    else targetCF=CFrame.new(pos+Vector3.new(0,-5000,0)) end
                elseif activeMode=="sphere" then
                    local off=getSphereShellPos(i,n); local st=t*3
                    targetCF=CFrame.new(spherePos)*CFrame.Angles(st,st*1.3,st*0.7)*CFrame.new(off)
                elseif activeMode=="spherebender" then
                    local ns=math.max(1,#sbSpheres); local pps=math.max(1,math.ceil(n/ns))
                    local si=math.min(math.ceil(i/pps),ns); local sp=sbSpheres[si]
                    local li=((i-1)%pps)+1; local lt=math.max(math.min(pps,n-(si-1)*pps),1)
                    local off=getSphereShellPos(li,lt); local st=t*3
                    targetCF=CFrame.new(sp.pos)*CFrame.Angles(st,st*1.3,st*0.7)*CFrame.new(off)
                elseif CFRAME_MODES[activeMode] then
                    targetCF=getFormationCF(activeMode,i,n,pos,cf,t)
                end

                if targetCF then
                    -- ── CLEAN SPIN: single-axis rotation around a fixed axis ──
                    -- Each part spins a full 360° continuously. Phase offset per
                    -- part index so they don't all look identical (like a debris field).
                    local finalCF=targetCF
                    if spinSpeed~=0 then
                        -- Choose a slightly different axis per part for organic feel
                        local phaseOffset=i*(math.pi*2/math.max(n,1))
                        local axisX=math.sin(phaseOffset)*0.15
                        local axisZ=math.cos(phaseOffset)*0.15
                        local spinAxis=Vector3.new(axisX,1,axisZ).Unit
                        -- Apply rotation AROUND the target position (not offset from it)
                        local spinRot=CFrame.fromAxisAngle(spinAxis, spinAngle+phaseOffset)
                        finalCF=CFrame.new(targetCF.Position)*spinRot
                    end
                    local data=item.d
                    pcall(function()
                        if data.bp and data.bp.Parent then
                            data.bp.Position=finalCF.Position
                            data.bg.CFrame  =finalCF
                        else
                            part.CFrame=finalCF
                            part.AssemblyLinearVelocity=Vector3.zero
                            part.AssemblyAngularVelocity=Vector3.zero
                        end
                    end)
                end
            end
        end)
    end

    -- ── Scan loop ─────────────────────────────────────────────
    local function scanLoop()
        while scriptAlive do
            if isActivated and activeMode~="none" and activeMode~="tank" and activeMode~="car" then sweepMap() end
            task.wait(1.5)
        end
    end

    -- ════════════════════════════════════════════════════════════
    -- MAIN GUI
    -- ════════════════════════════════════════════════════════════
    local function createGUI()
        local pg=player:WaitForChild("PlayerGui")
        local old=pg:FindFirstChild("ManipGUI"); if old then old:Destroy() end
        local gui=Instance.new("ScreenGui"); gui.Name="ManipGUI"; gui.ResetOnSpawn=false; gui.DisplayOrder=999; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=pg
        local W,H=195,365
        local panel=Instance.new("Frame"); panel.Name="Panel"; panel.Size=UDim2.fromOffset(W,H); panel.Position=UDim2.new(0.5,-W/2,0.5,-H/2); panel.BackgroundColor3=Color3.fromRGB(10,10,25); panel.BorderSizePixel=0; panel.ClipsDescendants=true; panel.Parent=gui; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8); local pS=Instance.new("UIStroke",panel); pS.Color=Color3.fromRGB(90,40,180); pS.Thickness=1.5
        local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,30); titleBar.BackgroundColor3=Color3.fromRGB(20,10,48); titleBar.BorderSizePixel=0; titleBar.ZIndex=10; titleBar.Parent=panel; Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tTxt=Instance.new("TextLabel"); tTxt.Text="MANIPULATOR KII"; tTxt.Size=UDim2.new(1,-60,1,0); tTxt.Position=UDim2.fromOffset(8,0); tTxt.BackgroundTransparency=1; tTxt.TextColor3=Color3.fromRGB(195,140,255); tTxt.TextSize=11; tTxt.Font=Enum.Font.GothamBold; tTxt.TextXAlignment=Enum.TextXAlignment.Left; tTxt.ZIndex=10; tTxt.Parent=titleBar
        local closeBtn=Instance.new("TextButton"); closeBtn.Text="✕"; closeBtn.Size=UDim2.fromOffset(24,22); closeBtn.Position=UDim2.new(1,-28,0,4); closeBtn.BackgroundColor3=Color3.fromRGB(150,25,25); closeBtn.TextColor3=Color3.fromRGB(255,255,255); closeBtn.TextSize=10; closeBtn.Font=Enum.Font.GothamBold; closeBtn.BorderSizePixel=0; closeBtn.ZIndex=11; closeBtn.Parent=titleBar; Instance.new("UICorner",closeBtn)
        makeDraggable(titleBar,panel,false); makeDraggable(panel,panel,true)
        local scroll=Instance.new("ScrollingFrame"); scroll.Size=UDim2.new(1,0,1,-30); scroll.Position=UDim2.fromOffset(0,30); scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=3; scroll.ScrollBarImageColor3=Color3.fromRGB(90,40,180); scroll.CanvasSize=UDim2.fromOffset(0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
        local lay=Instance.new("UIListLayout",scroll); lay.Padding=UDim.new(0,3); lay.HorizontalAlignment=Enum.HorizontalAlignment.Center; lay.SortOrder=Enum.SortOrder.LayoutOrder
        local pad=Instance.new("UIPadding",scroll); pad.PaddingTop=UDim.new(0,4); pad.PaddingBottom=UDim.new(0,6); pad.PaddingLeft=UDim.new(0,5); pad.PaddingRight=UDim.new(0,5)
        local function sLbl2(t2,ord) local l=Instance.new("TextLabel"); l.Text=t2; l.Size=UDim2.new(1,0,0,16); l.BackgroundTransparency=1; l.TextColor3=Color3.fromRGB(160,110,255); l.TextSize=9; l.Font=Enum.Font.GothamBold; l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=ord; l.Parent=scroll end
        local function sBtn3(t2,bg,fg,ord) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.new(1,0,0,28); b.BackgroundColor3=bg; b.TextColor3=fg; b.TextSize=9; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.LayoutOrder=ord; b.Parent=scroll; Instance.new("UICorner",b); return b end

        -- Settings
        sLbl2("⚙ SETTINGS",0)
        local function makeSettingRow(labelTxt,defaultVal,accentCol,order,onApply)
            local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,38); row.BackgroundColor3=Color3.fromRGB(14,12,32); row.BorderSizePixel=0; row.LayoutOrder=order; row.Parent=scroll; Instance.new("UICorner",row).CornerRadius=UDim.new(0,6); local rowStk=Instance.new("UIStroke",row); rowStk.Color=Color3.fromRGB(50,35,90); rowStk.Thickness=1
            local lbl=Instance.new("TextLabel"); lbl.Text=labelTxt; lbl.Size=UDim2.new(0.48,0,0,16); lbl.Position=UDim2.fromOffset(6,3); lbl.BackgroundTransparency=1; lbl.TextColor3=accentCol; lbl.TextSize=8; lbl.Font=Enum.Font.GothamBold; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=row
            local tb=Instance.new("TextBox"); tb.Text=tostring(defaultVal); tb.Size=UDim2.new(0.52,-36,0,22); tb.Position=UDim2.new(0.46,0,0,8); tb.BackgroundColor3=Color3.fromRGB(22,18,50); tb.TextColor3=Color3.fromRGB(255,255,255); tb.TextSize=10; tb.Font=Enum.Font.GothamBold; tb.ClearTextOnFocus=false; tb.BorderSizePixel=0; tb.Parent=row; Instance.new("UICorner",tb).CornerRadius=UDim.new(0,4)
            local applyBtn=Instance.new("TextButton"); applyBtn.Text="✓"; applyBtn.Size=UDim2.fromOffset(28,22); applyBtn.Position=UDim2.new(1,-32,0,8); applyBtn.BackgroundColor3=accentCol; applyBtn.TextColor3=Color3.fromRGB(0,0,0); applyBtn.TextSize=11; applyBtn.Font=Enum.Font.GothamBold; applyBtn.BorderSizePixel=0; applyBtn.Parent=row; Instance.new("UICorner",applyBtn).CornerRadius=UDim.new(0,4)
            local function flash(ok) applyBtn.BackgroundColor3=ok and Color3.fromRGB(80,255,120) or Color3.fromRGB(255,80,80); task.wait(0.25); if applyBtn.Parent then applyBtn.BackgroundColor3=accentCol end end
            applyBtn.MouseButton1Click:Connect(function() local num=tonumber(tb.Text); if num then onApply(num); task.spawn(function()flash(true)end) else task.spawn(function()flash(false)end)end end)
            tb.FocusLost:Connect(function(enter) if enter then local num=tonumber(tb.Text); if num then onApply(num) end end end)
            local hint=Instance.new("TextLabel"); hint.Size=UDim2.new(1,-6,0,10); hint.Position=UDim2.fromOffset(6,26); hint.BackgroundTransparency=1; hint.TextColor3=Color3.fromRGB(80,75,120); hint.TextSize=7; hint.Font=Enum.Font.Gotham; hint.TextXAlignment=Enum.TextXAlignment.Left; hint.Parent=row
            return tb,hint
        end
        local _,psHint=makeSettingRow("PULL STRENGTH",pullStrength,Color3.fromRGB(255,180,60),1,function(v) pullStrength=math.clamp(v,1,1e8); applyStrengthToAll(); sweepMap(); psHint.Text="current: "..tostring(pullStrength) end)
        psHint.Text="current: "..tostring(pullStrength).."  higher=faster"
        local _,radHint=makeSettingRow("RADIUS",radius,Color3.fromRGB(80,200,255),2,function(v) radius=math.clamp(v,0.5,500); radHint.Text="current: "..tostring(radius).." studs" end)
        radHint.Text="current: "..tostring(radius).." studs"
        local _,spinHint=makeSettingRow("SPIN SPEED",spinSpeed,Color3.fromRGB(180,100,255),3,function(v) spinSpeed=v; if v==0 then spinAngle=0 end; spinHint.Text="current: "..tostring(v).." rad/s  (0=off)" end)
        spinHint.Text="current: 0 rad/s  (0=off)"

        sLbl2("STATUS",4)
        local stLbl=Instance.new("TextLabel"); stLbl.Text="IDLE  |  PARTS: 0"; stLbl.Size=UDim2.new(1,0,0,16); stLbl.BackgroundTransparency=1; stLbl.TextColor3=Color3.fromRGB(80,255,140); stLbl.TextSize=9; stLbl.Font=Enum.Font.GothamBold; stLbl.TextXAlignment=Enum.TextXAlignment.Left; stLbl.LayoutOrder=5; stLbl.Parent=scroll
        local modLbl=Instance.new("TextLabel"); modLbl.Text="MODE: NONE"; modLbl.Size=UDim2.new(1,0,0,14); modLbl.BackgroundTransparency=1; modLbl.TextColor3=Color3.fromRGB(130,130,255); modLbl.TextSize=9; modLbl.Font=Enum.Font.GothamBold; modLbl.TextXAlignment=Enum.TextXAlignment.Left; modLbl.LayoutOrder=6; modLbl.Parent=scroll
        task.spawn(function()
            while gui.Parent and scriptAlive do stLbl.Text=isActivated and("ACTIVE  |  PARTS: "..partCount) or "IDLE  |  PARTS: 0"; task.wait(0.5) end
        end)

        sLbl2("STANDARD MODES",7)
        local stdModes={{txt="SNAKE",mode="snake",col=Color3.fromRGB(160,110,255)},{txt="HEART",mode="heart",col=Color3.fromRGB(255,100,150)},{txt="RINGS",mode="rings",col=Color3.fromRGB(80,210,255)},{txt="WALL",mode="wall",col=Color3.fromRGB(255,200,90)},{txt="BOX",mode="box",col=Color3.fromRGB(160,255,100)},{txt="WINGS",mode="wings",col=Color3.fromRGB(100,220,255)}}
        local sRows=math.ceil(#stdModes/2); local sFrame=Instance.new("Frame"); sFrame.Size=UDim2.new(1,0,0,sRows*28+(sRows-1)*3); sFrame.BackgroundTransparency=1; sFrame.LayoutOrder=8; sFrame.Parent=scroll
        local sGL=Instance.new("UIGridLayout",sFrame); sGL.CellSize=UDim2.new(0.5,-3,0,28); sGL.CellPadding=UDim2.fromOffset(3,3); sGL.HorizontalAlignment=Enum.HorizontalAlignment.Left; sGL.SortOrder=Enum.SortOrder.LayoutOrder
        for idx,m in ipairs(stdModes) do
            local btn=Instance.new("TextButton"); btn.Text=m.txt; btn.BackgroundColor3=Color3.fromRGB(26,14,55); btn.TextColor3=m.col; btn.TextSize=9; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.LayoutOrder=idx; btn.Parent=sFrame; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()
                destroyGasterGui();destroySphereGui();destroySphereBenderGui()
                if tankActive then destroyTank();destroyTankGui()end
                if carActive  then destroyCar();destroyCarGui()end
                if shrineActive then destroyShrine();destroyShrineGui()end
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
        }
        local spRows=math.ceil(#spModes/2); local spFrame=Instance.new("Frame"); spFrame.Size=UDim2.new(1,0,0,spRows*28+(spRows-1)*3); spFrame.BackgroundTransparency=1; spFrame.LayoutOrder=10; spFrame.Parent=scroll
        local spGL=Instance.new("UIGridLayout",spFrame); spGL.CellSize=UDim2.new(0.5,-3,0,28); spGL.CellPadding=UDim2.fromOffset(3,3); spGL.HorizontalAlignment=Enum.HorizontalAlignment.Left; spGL.SortOrder=Enum.SortOrder.LayoutOrder
        for idx,m in ipairs(spModes) do
            local btn=Instance.new("TextButton"); btn.Text=m.txt; btn.BackgroundColor3=Color3.fromRGB(30,8,58); btn.TextColor3=m.col; btn.TextSize=9; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.LayoutOrder=idx; btn.Parent=spFrame; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()
                destroyGasterGui();destroySphereGui();destroySphereBenderGui()
                if tankActive   then destroyTank();destroyTankGui()end
                if carActive    then destroyCar();destroyCarGui()end
                if shrineActive then destroyShrine();destroyShrineGui()end
                activeMode=m.mode;isActivated=true;modLbl.Text="MODE: "..m.mode:upper()
                if GASTER_MODES[m.mode] then createGasterGui()
                elseif SPHERE_MODES[m.mode] then
                    local r2=player.Character and(player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"))
                    spherePos=(r2 and r2.Position or Vector3.new(0,5,0))+Vector3.new(0,1.5,4);sphereVel=Vector3.zero;createSphereGui()
                elseif SPHERE_BENDER_MODES[m.mode] then
                    sbSpheres={}; local r2=player.Character and(player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"))
                    local s=newSBSphere((r2 and r2.Position or Vector3.new(0,5,0))+Vector3.new(0,2,4));s.selected=true;table.insert(sbSpheres,s);rebuildSBGui()
                end
                sweepMap()
            end)
        end

        sLbl2("ACTIONS",11)
        local scanBtn=sBtn3("SCAN PARTS", Color3.fromRGB(18,55,20),Color3.fromRGB(80,255,120),12)
        local relBtn =sBtn3("RELEASE ALL",Color3.fromRGB(55,30,8), Color3.fromRGB(255,155,55),13)
        local deaBtn =sBtn3("DEACTIVATE", Color3.fromRGB(70,8,8),  Color3.fromRGB(255,55,55), 14)
        scanBtn.MouseButton1Click:Connect(function()sweepMap()end)
        relBtn.MouseButton1Click:Connect(function()releaseAll();activeMode="none";isActivated=false;modLbl.Text="MODE: NONE"end)
        deaBtn.MouseButton1Click:Connect(function()releaseAll();scriptAlive=false;gui:Destroy();local icon=pg:FindFirstChild("ManipIcon");if icon then icon:Destroy()end end)
        closeBtn.MouseButton1Click:Connect(function()
            gui:Destroy(); local mini=Instance.new("ScreenGui"); mini.Name="ManipIcon"; mini.ResetOnSpawn=false; mini.DisplayOrder=999; mini.Parent=pg
            local ib=Instance.new("TextButton"); ib.Text="M"; ib.Size=UDim2.fromOffset(34,34); ib.Position=UDim2.new(1,-42,0,8); ib.BackgroundColor3=Color3.fromRGB(22,10,50); ib.TextColor3=Color3.fromRGB(195,140,255); ib.TextSize=13; ib.Font=Enum.Font.GothamBold; ib.BorderSizePixel=0; ib.Parent=mini; Instance.new("UICorner",ib)
            ib.MouseButton1Click:Connect(function()mini:Destroy();createGUI()end)
        end)
    end

    createGUI(); task.spawn(mainLoop); task.spawn(scanLoop)
end

main()
