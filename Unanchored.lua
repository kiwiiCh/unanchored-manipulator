-- ============================================================
-- UNANCHORED MANIPULATOR KII v6 -- DELTA EXECUTOR
-- BodyPosition/BodyGyro physics movers (live for all players).
-- TANK: no flying (HRP anchored), forward camera, interior space.
-- CAR:  new mode, joystick drive, free camera, door toggle.
-- ============================================================
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Debris           = game:GetService("Debris")

local player = Players.LocalPlayer

-- ─────────────────────────────────────────────────────────────
-- Drag helper (edgeOnly = drag only near panel edges/corners)
-- ─────────────────────────────────────────────────────────────
local EDGE_MARGIN = 36
local function makeDraggable(handle, panel, edgeOnly)
    local dragging     = false
    local dragStartM   = Vector2.zero
    local dragStartPos = UDim2.new()
    local conC, conE

    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        if edgeOnly then
            local p  = Vector2.new(inp.Position.X, inp.Position.Y)
            local ap = panel.AbsolutePosition
            local as = panel.AbsoluteSize
            local nL = p.X - ap.X < EDGE_MARGIN
            local nR = ap.X + as.X - p.X < EDGE_MARGIN
            local nT = p.Y - ap.Y < EDGE_MARGIN
            local nB = ap.Y + as.Y - p.Y < EDGE_MARGIN
            if not (nL or nR or nT or nB) then return end
        end
        dragging     = true
        dragStartM   = Vector2.new(inp.Position.X, inp.Position.Y)
        dragStartPos = panel.Position
    end)
    conC = UserInputService.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = Vector2.new(inp.Position.X, inp.Position.Y) - dragStartM
        panel.Position = UDim2.new(
            dragStartPos.X.Scale, dragStartPos.X.Offset + d.X,
            dragStartPos.Y.Scale, dragStartPos.Y.Offset + d.Y)
    end)
    conE = UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    panel.AncestryChanged:Connect(function(_, par)
        if not par then
            pcall(function() conC:Disconnect() end)
            pcall(function() conE:Disconnect() end)
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- MAIN
-- ─────────────────────────────────────────────────────────────
local function main()
    print("[ManipKii v6] Loaded for "..player.Name)

    local isActivated    = false
    local activeMode     = "none"
    local lastMode       = "none"
    local scriptAlive    = true
    local radius         = 7        -- formation spread radius (studs)
    local detectionRange = math.huge

    -- ── Physics controls (user-adjustable live) ───────────────
    -- pullStrength: BodyPosition.P — how hard/fast parts snap to target.
    --   50000 = default (snappy). 999999 = instant even from far away.
    -- spinSpeed: extra rotation added to each part every second (rad/s).
    --   0 = no spin. 5 = moderate. 20 = very fast tumble.
    local pullStrength   = 50000
    local spinSpeed      = 0       -- rad/s
    local spinAccum      = 0       -- accumulates each Stepped tick

    -- Call this whenever pullStrength changes so already-grabbed parts
    -- feel the new strength immediately without needing a re-scan.
    local function applyStrengthToAll()
        local p = math.max(1, pullStrength)
        local d = math.max(50, p * 0.05)  -- damping = 5% of P (prevents oscillation)
        for _, data in pairs(controlled) do
            pcall(function()
                if data.bp and data.bp.Parent then
                    data.bp.P = p
                    data.bp.D = d
                    data.bp.MaxForce = Vector3.new(1e12, 1e12, 1e12)
                end
                if data.bg and data.bg.Parent then
                    data.bg.P = p
                    data.bg.D = d
                    data.bg.MaxTorque = Vector3.new(1e12, 1e12, 1e12)
                end
            end)
        end
    end

    local snakeT         = 0
    local snakeHistory   = {}
    local SNAKE_HIST_MAX = 600
    local SNAKE_GAP      = 8

    local gasterAnim   = "pointing"
    local gasterT      = 0
    local gasterSubGui = nil

    local sphereSubGui     = nil
    local sphereMode       = "orbit"
    local spherePos        = Vector3.new(0,0,0)
    local sphereVel        = Vector3.new(0,0,0)
    local sphereOrbitAngle = 0
    local SPHERE_RADIUS = 6
    local SPHERE_SPEED  = 1.2
    local SPHERE_SPRING = 8
    local SPHERE_DAMP   = 4

    local sbSubGui  = nil
    local sbSpheres = {}
    local function newSBSphere(p)
        return { pos=p or Vector3.zero, vel=Vector3.zero,
                 orbitAngle=0, mode="orbit", stopped=false, selected=false }
    end

    -- ── Humanoid save/restore ─────────────────────────────────
    -- When the humanoid is active, it constantly applies forces to the
    -- HumanoidRootPart. If we also set HRP.CFrame every frame, the two
    -- fight each other and the character "flies." Solution: anchor the
    -- HRP so the engine applies NO physics to it, then position it manually.
    local savedWalkSpeed  = 16
    local savedJumpPower  = 50
    local savedAutoRotate = true

    local function freezePlayer(anchorCF)
        -- Call when player enters a vehicle
        local char = player.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hum then
            savedWalkSpeed  = hum.WalkSpeed
            savedJumpPower  = hum.JumpPower
            savedAutoRotate = hum.AutoRotate
            hum.WalkSpeed   = 0
            hum.JumpPower   = 0
            hum.AutoRotate  = false
        end
        if hrp then
            hrp.Anchored = true          -- stops ALL physics on the character
            if anchorCF then hrp.CFrame = anchorCF end
        end
        -- Noclip so player passes through vehicle parts
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
        end
    end

    local function thawPlayer(exitCF)
        -- Call when player exits a vehicle
        local char = player.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hum then
            hum.WalkSpeed   = savedWalkSpeed
            hum.JumpPower   = savedJumpPower
            hum.AutoRotate  = savedAutoRotate
        end
        if hrp then
            hrp.Anchored = false
            if exitCF then hrp.CFrame = exitCF end
        end
        -- Restore collision
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
        end
    end

    -- ── Tank state ────────────────────────────────────────────
    local tankSubGui = nil
    local tankActive = false

    -- Orbit camera
    local cameraOrbitAngle = 0
    local cameraPitchAngle = math.rad(30)
    local CAM_PITCH_MIN    = math.rad(8)
    local CAM_PITCH_MAX    = math.rad(75)
    local CAMERA_DIST      = 24
    local CAM_ORBIT_SENS   = 3.0
    local CAM_PITCH_SENS   = 2.0

    local frozenTankCF     = nil

    local tankControlState = {
        forward=0, turn=0,
        hatchOpen=false, insideTank=false,  -- start OUTSIDE (enter on build)
        tankBase=nil, turretPart=nil, barrelPart=nil,
        turretPartIdx=nil, barrelPartIdx=nil,
        tankParts={}, partOffsets={},
        currentSpeed=0, currentTurnSpeed=0, tankHatch=nil
    }

    local TANK_HEIGHT      = 5
    local TANK_WIDTH       = 12
    local TANK_LENGTH      = 16
    local TANK_INTERIOR_Y  = TANK_HEIGHT/2 + 2.2   -- player HRP height inside turret ring
    local TANK_SPEED       = 35
    local TANK_TURN_SPEED  = 2.2
    local TANK_ACCEL       = 12
    local TANK_FRICTION    = 0.88
    local TURRET_TURN_SPEED= 1.8
    local PROJECTILE_SPEED = 650
    local SHOOT_COOLDOWN   = 1.5
    local lastShootTime    = 0

    local rightJoystick = {
        active=false, origin=Vector2.zero, current=Vector2.zero,
        radius=55, deadzone=10, touchId=nil
    }

    -- ── Car state ─────────────────────────────────────────────
    local carSubGui  = nil
    local carActive  = false

    local frozenCarCF = nil

    local carControlState = {
        doorOpen=false,        -- true = player inside, driving
        carBase=nil, carDoor=nil,
        carParts={}, partOffsets={},
        currentSpeed=0, currentTurnSpeed=0
    }

    local CAR_HEIGHT    = 2.5
    local CAR_WIDTH     = 10
    local CAR_LENGTH    = 18
    local CAR_INTERIOR_Y= CAR_HEIGHT/2 + 1.8
    local CAR_SPEED     = 48
    local CAR_TURN_SPEED= 2.8
    local CAR_ACCEL     = 20
    local CAR_FRICTION  = 0.88

    -- Car fixed offsets (index → CFrame relative to carBase)
    local CAR_OFFSETS = {
        CFrame.new(0,    0,     0),    -- [1]  chassis (hull)
        CFrame.new(-5.5, -1,   -6.5), -- [2]  LF wheel
        CFrame.new( 5.5, -1,   -6.5), -- [3]  RF wheel
        CFrame.new(-5.5, -1,    6.5), -- [4]  LR wheel
        CFrame.new( 5.5, -1,    6.5), -- [5]  RR wheel
        CFrame.new(-5,   0.5,  -1),   -- [6]  left side panel front
        CFrame.new( 5,   0.5,  -1),   -- [7]  right side panel front
        CFrame.new(-5,   0.5,   3.5), -- [8]  left side panel rear
        CFrame.new( 5,   0.5,   3.5), -- [9]  right side panel rear
        CFrame.new( 0,  -0.5,  -9),   -- [10] front bumper
        CFrame.new( 0,  -0.5,   9),   -- [11] rear bumper
        CFrame.new( 0,   1.5,  -5),   -- [12] hood / bonnet
        CFrame.new( 0,   1.5,   5),   -- [13] trunk / boot
        CFrame.new( 0,   3.0,   0),   -- [14] roof
        CFrame.new( 0,   2.5,  -3.5), -- [15] windshield
        CFrame.new( 0,   2.5,   3.5), -- [16] rear window
        CFrame.new(-4,   2.5,  -3),   -- [17] left A-pillar
        CFrame.new( 4,   2.5,  -3),   -- [18] right A-pillar
        CFrame.new(-4,   2.5,   2.5), -- [19] left C-pillar
        CFrame.new( 4,   2.5,   2.5), -- [20] right C-pillar
        CFrame.new( 0,   0.5,  -8.5), -- [21] front grille
        CFrame.new(-2,  -1,     8.5), -- [22] left exhaust
        CFrame.new( 2,  -1,     8.5), -- [23] right exhaust
        CFrame.new( 0,   3.5,   6.5), -- [24] rear spoiler
        CFrame.new( 0,   1.2,  -1.5), -- [25] dashboard
        CFrame.new(-5,   1.5,  -2.5), -- [26] left front door (THE door)
    }

    local carJoystick = {
        active=false, origin=Vector2.zero, current=Vector2.zero,
        radius=70, deadzone=8, touchId=nil,
        forward=0, turn=0
    }

    -- ── Mode tables ───────────────────────────────────────────
    local CFRAME_MODES = {
        heart=true, rings=true, wall=true, box=true,
        gasterhand=true, gaster2hands=true, wings=true,
        sphere=true, spherebender=true, tank=true, car=true,
    }
    local GASTER_MODES        = { gasterhand=true, gaster2hands=true }
    local SPHERE_MODES        = { sphere=true }
    local SPHERE_BENDER_MODES = { spherebender=true }
    local TANK_MODES          = { tank=true }
    local CAR_MODES           = { car=true }

    -- ── Gaster/Wing data (unchanged) ──────────────────────────
    local HAND_SCALE = 2.8
    local HAND_SLOTS = {
        {x=-4,y=5},{x=-4,y=4},{x=-4,y=3},{x=-4,y=2},
        {x=-2,y=6},{x=-2,y=5},{x=-2,y=4},{x=-2,y=3},
        {x=0,y=7},{x=0,y=6},{x=0,y=5},{x=0,y=4},{x=0,y=3},
        {x=2,y=6},{x=2,y=5},{x=2,y=4},{x=2,y=3},
        {x=5,y=2},{x=5,y=1},{x=5,y=0},
        {x=-4,y=1},{x=-2,y=1},{x=0,y=1},{x=2,y=1},
        {x=-4,y=0},{x=-2,y=0},{x=0,y=0},{x=2,y=0},{x=4,y=0},
        {x=-2,y=-1},{x=0,y=-1},{x=2,y=-1},
    }
    local PALM_SLOTS = {
        {x=-3,y=2},{x=-1,y=2},{x=1,y=2},{x=3,y=2},
        {x=-3,y=1},{x=-1,y=1},{x=1,y=1},{x=3,y=1},
        {x=-3,y=0},{x=-1,y=0},{x=1,y=0},{x=3,y=0},
        {x=-2,y=-1},{x=0,y=-1},{x=2,y=-1},
        {x=-2,y=-2},{x=0,y=-2},{x=2,y=-2},
    }
    local ALL_HAND_SLOTS = {}
    for _, s in ipairs(HAND_SLOTS) do table.insert(ALL_HAND_SLOTS, {x=s.x,y=s.y,isPalm=false}) end
    for _, s in ipairs(PALM_SLOTS) do table.insert(ALL_HAND_SLOTS, {x=s.x,y=s.y,isPalm=true}) end
    local HAND_SLOTS_COUNT = #ALL_HAND_SLOTS

    local POINTING_BIAS = {[1]=-5.0,[2]=-5.0,[3]=-5.0,[4]=-5.0,[5]=-4.5,[6]=-4.5,[7]=-4.5,[8]=-4.5,
        [9]=-5.5,[10]=-5.0,[11]=-4.0,[12]=-2.5,[13]=-1.2,[18]=-0.6,[19]=-1.2,[20]=-1.2}
    local PUNCH_BIAS   = {[1]=-3.0,[2]=-2.5,[3]=-1.5,[4]=-0.5,[5]=-3.0,[6]=-2.5,[7]=-1.5,[8]=-0.5,
        [9]=-3.5,[10]=-3.0,[11]=-2.0,[12]=-1.0,[13]=-0.3,[14]=-3.0,[15]=-2.5,[16]=-1.5,[17]=-0.5,
        [18]=-0.8,[19]=-1.4,[20]=-1.4}
    local HAND_RIGHT = Vector3.new(9,2,1)
    local HAND_LEFT  = Vector3.new(-9,2,1)

    local WING_POINTS = {}
    local WING_SHOULDER_RIGHT = Vector3.new(1.0,1.8,0.6)
    local WING_SHOULDER_LEFT  = Vector3.new(-1.0,1.8,0.6)
    local WING_OPEN_ANGLE  = math.rad(82)
    local WING_CLOSE_ANGLE = math.rad(22)
    local WING_FLAP_SPEED  = 1.8
    local WING_SPAN = 14
    for _, f in ipairs({
        {0.15,2.2,0.4},{0.28,2.8,0.5},{0.40,3.0,0.6},{0.52,2.8,0.6},
        {0.63,2.2,0.5},{0.73,1.2,0.4},{0.82,-0.2,0.3},{0.90,-1.8,0.2},{0.97,-3.5,0.1}}) do
        for seg=1,4 do
            local t2=(seg-1)/3
            table.insert(WING_POINTS,{outX=f[1]*WING_SPAN+t2*0.6,upY=f[2]-t2*2.0,backZ=f[3]+t2*0.2,layer=1})
        end
    end
    for _, f in ipairs({
        {0.12,3.5,0.6},{0.22,4.4,0.7},{0.33,5.0,0.8},{0.44,5.0,0.8},{0.54,4.4,0.7},{0.62,3.4,0.6}}) do
        for seg=1,3 do
            local t2=(seg-1)/2
            table.insert(WING_POINTS,{outX=f[1]*WING_SPAN+t2*0.4,upY=f[2]-t2*1.2,backZ=f[3],layer=2})
        end
    end
    for _, f in ipairs({
        {0.04,1.5,0.5},{0.08,2.2,0.6},{0.12,2.8,0.7},{0.18,3.0,0.7},
        {0.04,0.6,0.5},{0.08,1.0,0.6},{0.14,1.2,0.6},{0.20,1.0,0.5}}) do
        table.insert(WING_POINTS,{outX=f[1]*WING_SPAN,upY=f[2],backZ=f[3],layer=3})
    end
    local WING_POINT_COUNT = #WING_POINTS

    -- ── Part tracking ─────────────────────────────────────────
    local controlled = {}
    local partCount  = 0

    -- ── Forward declarations ──────────────────────────────────
    local sweepMap, rebuildSBGui
    local destroyTank, destroyTankGui
    local destroyCar,  destroyCarGui

    -- ── Validation ────────────────────────────────────────────
    local function isValid(obj)
        if not obj then return false end
        local ok = pcall(function() if not obj.Parent then error() end end)
        if not ok or not obj.Parent then return false end
        if not obj:IsA("BasePart") then return false end
        if obj.Anchored then return false end
        if obj.Size.Magnitude < 0.2 then return false end
        if obj.Transparency >= 1 then return false end
        local p = obj.Parent
        while p and p ~= workspace do
            if p:FindFirstChildOfClass("Humanoid") then return false end
            p = p.Parent
        end
        return true
    end

    -- ── Part grab / release (BodyPosition + BodyGyro) ─────────
    local function grabPart(part)
        if controlled[part] then return end
        if not isValid(part) then return end
        local char = player.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        -- When pullStrength is very high we grab everything regardless of distance.
        -- Below 5000 we respect detectionRange so low-strength stays local.
        local effectiveRange = (pullStrength >= 5000) and math.huge or detectionRange
        if root and (part.Position - root.Position).Magnitude > effectiveRange then return end

        local origCC   = part.CanCollide
        local origAnch = part.Anchored
        pcall(function() part.CanCollide = false end)

        local p = math.max(1, pullStrength)
        local d = math.max(50, p * 0.05)

        local bp = Instance.new("BodyPosition")
        bp.MaxForce = Vector3.new(1e12, 1e12, 1e12)
        bp.P        = p
        bp.D        = d
        bp.Position = part.Position
        bp.Parent   = part

        local bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(1e12, 1e12, 1e12)
        bg.P         = p
        bg.D         = d
        bg.CFrame    = part.CFrame
        bg.Parent    = part

        controlled[part] = { origCC=origCC, origAnch=origAnch, bp=bp, bg=bg }
        partCount = partCount + 1
    end

    local function releasePart(part, data)
        pcall(function()
            if data.bp and data.bp.Parent then data.bp:Destroy() end
            if data.bg and data.bg.Parent then data.bg:Destroy() end
        end)
        if part and part.Parent then
            pcall(function()
                part.CanCollide = data.origCC
                part.Anchored   = data.origAnch or false
            end)
        end
    end

    local function releaseAll()
        for part, data in pairs(controlled) do releasePart(part, data) end
        controlled = {}; partCount = 0
        snakeT = 0; snakeHistory = {}
        if tankActive then pcall(destroyTank); pcall(destroyTankGui) end
        if carActive  then pcall(destroyCar);  pcall(destroyCarGui)  end
        pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
    end

    sweepMap = function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isValid(obj) and not controlled[obj] then grabPart(obj) end
        end
    end

    -- ── Helpers ───────────────────────────────────────────────
    local function getSnakeTarget(i)
        local idx = math.clamp(i*SNAKE_GAP, 1, math.max(1,#snakeHistory))
        return snakeHistory[idx] or snakeHistory[#snakeHistory] or Vector3.zero
    end

    local function getWingCF(ptIdx, side, cf, t)
        local wp = WING_POINTS[ptIdx]
        if not wp then return CFrame.new(0,-5000,0) end
        local rawSin  = math.sin(t*WING_FLAP_SPEED*math.pi)
        local flapT   = (rawSin+1)/2
        local flapAng = WING_CLOSE_ANGLE + flapT*(WING_OPEN_ANGLE-WING_CLOSE_ANGLE)
        local cosA,sinA = math.cos(flapAng),math.sin(flapAng)
        local rotX = (wp.outX*cosA - wp.backZ*sinA)*side
        local rotZ = wp.outX*sinA + wp.backZ*cosA + 0.5
        local sh   = (side==1) and WING_SHOULDER_RIGHT or WING_SHOULDER_LEFT
        return CFrame.new(cf:PointToWorldSpace(Vector3.new(sh.X+rotX, sh.Y+wp.upY, sh.Z+rotZ)))
    end

    local SPHERE_SHELL_SPACING = 0.8
    local function getSphereShellPos(index, total)
        local phi = (1+math.sqrt(5))/2
        local i   = index-1
        local s   = math.max(total,1)
        local theta = math.acos(math.clamp(1-2*(i+0.5)/s,-1,1))
        local ang   = 2*math.pi*i/phi
        local r     = SPHERE_SHELL_SPACING*(1+math.floor(i/12)*0.5)
        return Vector3.new(r*math.sin(theta)*math.cos(ang),r*math.sin(theta)*math.sin(ang),r*math.cos(theta))
    end

    local function updateSphereTarget(dt, rootPos)
        if sphereMode == "orbit" then
            sphereOrbitAngle = sphereOrbitAngle + dt*SPHERE_SPEED
            local tgt = rootPos + Vector3.new(math.cos(sphereOrbitAngle)*SPHERE_RADIUS,1.5,math.sin(sphereOrbitAngle)*SPHERE_RADIUS)
            sphereVel = sphereVel + (tgt-spherePos)*(SPHERE_SPRING*dt)
            sphereVel = sphereVel*(1-SPHERE_DAMP*dt)
            spherePos = spherePos + sphereVel*dt
        elseif sphereMode == "follow" then
            local b = rootPos+Vector3.new(0,1.5,4); local d=b-spherePos; local dist=d.Magnitude
            if dist>3 then sphereVel = sphereVel+d.Unit*(dist-3)*SPHERE_SPRING*dt end
            sphereVel = sphereVel*(1-SPHERE_DAMP*dt); spherePos = spherePos+sphereVel*dt
        elseif sphereMode == "stay" then
            sphereVel = sphereVel*(1-SPHERE_DAMP*2*dt); spherePos = spherePos+sphereVel*dt
        end
    end

    local function updateSphereBenderTargets(dt, rootPos)
        for _, sp in ipairs(sbSpheres) do
            if sp.stopped then sp.vel=Vector3.zero
            elseif sp.mode=="orbit" then
                sp.orbitAngle=sp.orbitAngle+dt*SPHERE_SPEED
                local tgt=rootPos+Vector3.new(math.cos(sp.orbitAngle)*SPHERE_RADIUS,1.5,math.sin(sp.orbitAngle)*SPHERE_RADIUS)
                sp.vel=sp.vel+(tgt-sp.pos)*(SPHERE_SPRING*dt); sp.vel=sp.vel*(1-SPHERE_DAMP*dt); sp.pos=sp.pos+sp.vel*dt
            elseif sp.mode=="follow" then
                local b=rootPos+Vector3.new(0,1.5,4); local d=b-sp.pos; local dist=d.Magnitude
                if dist>3 then sp.vel=sp.vel+d.Unit*(dist-3)*SPHERE_SPRING*dt end
                sp.vel=sp.vel*(1-SPHERE_DAMP*dt); sp.pos=sp.pos+sp.vel*dt
            elseif sp.mode=="stay" then
                sp.vel=sp.vel*(1-SPHERE_DAMP*2*dt); sp.pos=sp.pos+sp.vel*dt
            end
        end
    end

    local function getFormationCF(mode, i, n, origin, cf, t)
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
            return getWingCF(((ptIdx-1)%WING_POINT_COUNT)+1, side, cf, t)
        end
        return CFrame.new(origin)
    end

    local function getGasterCF(slotIdx, side, cf, gt)
        local slot = ALL_HAND_SLOTS[slotIdx]
        if not slot then return CFrame.new(0,-5000,0) end
        local sx=slot.x*HAND_SCALE; local sy=slot.y*HAND_SCALE
        local floatY=math.sin(gt*2.0+side*1.2)*1.0
        if not slot.isPalm then
            if gasterAnim=="pointing" then sy=sy+(POINTING_BIAS[slotIdx] or 0)*HAND_SCALE
            elseif gasterAnim=="punching" then sy=sy+(PUNCH_BIAS[slotIdx] or 0)*HAND_SCALE end
        end
        local waveAng=(gasterAnim=="waving") and math.sin(gt*2.2)*0.5 or 0
        local punchZ=(gasterAnim=="punching" and not slot.isPalm) and (math.sin(gt*10)*0.5+0.5)*8 or 0
        local base=(side==1) and HAND_RIGHT or HAND_LEFT
        local palmOff=slot.isPalm and 1.5 or 0
        return CFrame.new(cf:PointToWorldSpace(Vector3.new(base.X+sx*math.cos(waveAng)*side,base.Y+sy+floatY,base.Z+sx*math.sin(waveAng)-punchZ+palmOff)))
    end

    -- ══════════════════════════════════════════════════════════
    -- TANK
    -- ══════════════════════════════════════════════════════════

    local function buildTankFromParts(position, cf)
        local pl = {}
        for part,_ in pairs(controlled) do if part and part.Parent then table.insert(pl,part) end end
        if #pl < 25 then
            sweepMap(); task.wait(0.3); pl={}
            for part,_ in pairs(controlled) do if part and part.Parent then table.insert(pl,part) end end
            if #pl < 25 then print("[ManipKii] Tank needs 25+ parts (found "..#pl..")"); return false end
        end
        table.sort(pl, function(a,b) return a.Size.Magnitude > b.Size.Magnitude end)

        tankControlState.tankParts={}; tankControlState.partOffsets={}
        tankControlState.turretPartIdx=nil; tankControlState.barrelPartIdx=nil

        local idx = 1
        -- Hull
        local hull = pl[idx]
        hull.CFrame = cf * CFrame.new(0, TANK_HEIGHT/2, 0)
        tankControlState.tankBase=hull
        tankControlState.tankParts[idx]=hull
        tankControlState.partOffsets[idx]=CFrame.new(0, TANK_HEIGHT/2, 0)
        idx=idx+1

        -- Left track links (pushed outward and slightly below hull top)
        for i=1,4 do
            if pl[idx] then
                local off=CFrame.new(-TANK_WIDTH/2-0.5, -0.5, -TANK_LENGTH/3+i*3.5)
                pl[idx].CFrame=hull.CFrame*off
                tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
            end
        end

        -- Right track links
        for i=1,4 do
            if pl[idx] then
                local off=CFrame.new(TANK_WIDTH/2+0.5, -0.5, -TANK_LENGTH/3+i*3.5)
                pl[idx].CFrame=hull.CFrame*off
                tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
            end
        end

        -- Front/back plates (low, not blocking interior)
        if pl[idx] then
            local off=CFrame.new(0, -0.5, TANK_LENGTH/2+1)
            pl[idx].CFrame=hull.CFrame*off
            tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
        end
        if pl[idx] then
            local off=CFrame.new(0, -0.5, -TANK_LENGTH/2-1)
            pl[idx].CFrame=hull.CFrame*off
            tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
        end

        -- Side armour plates (low sides, leave center clear)
        for i=1,3 do
            if pl[idx] then
                local off=CFrame.new(-TANK_WIDTH/2, 0.5, -TANK_LENGTH/3+i*4)
                pl[idx].CFrame=hull.CFrame*off
                tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
            end
        end
        for i=1,3 do
            if pl[idx] then
                local off=CFrame.new(TANK_WIDTH/2, 0.5, -TANK_LENGTH/3+i*4)
                pl[idx].CFrame=hull.CFrame*off
                tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
            end
        end

        -- Lower track detail
        for i=1,5 do
            if pl[idx] then
                local off=CFrame.new(-TANK_WIDTH/2-1, -1, -TANK_LENGTH/2+i*3.2)
                pl[idx].CFrame=hull.CFrame*off
                tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
            end
        end
        for i=1,5 do
            if pl[idx] then
                local off=CFrame.new(TANK_WIDTH/2+1, -1, -TANK_LENGTH/2+i*3.2)
                pl[idx].CFrame=hull.CFrame*off
                tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
            end
        end

        -- Turret ring (around interior space — just a ring at top of hull)
        local tBase = nil
        if pl[idx] then
            tBase=pl[idx]
            -- turret ring at hull top, wide ring leaving center open
            local off=CFrame.new(0, TANK_HEIGHT/2+0.5, 0)
            tBase.CFrame=hull.CFrame*off
            tankControlState.tankParts[idx]=tBase; tankControlState.partOffsets[idx]=off; idx=idx+1
        end

        -- Turret body (main turret, positioned above interior)
        if pl[idx] and tBase then
            local turretBody=pl[idx]
            -- Offset is hull-relative so it moves with hull
            local off=CFrame.new(0, TANK_HEIGHT/2+2.0, 0)
            turretBody.CFrame=hull.CFrame*off
            tankControlState.turretPart=turretBody
            tankControlState.turretPartIdx=idx
            tankControlState.tankParts[idx]=turretBody
            tankControlState.partOffsets[idx]=off
            idx=idx+1
        end

        -- Turret side decorators (relative to turret hull-offset)
        if pl[idx] and tankControlState.turretPart then
            local off=CFrame.new(-2.5,0,0)
            pl[idx].CFrame=tankControlState.turretPart.CFrame*off
            tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
        end
        if pl[idx] and tankControlState.turretPart then
            local off=CFrame.new(2.5,0,0)
            pl[idx].CFrame=tankControlState.turretPart.CFrame*off
            tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
        end

        -- Hatch (on top-rear of turret)
        if pl[idx] and tankControlState.turretPart then
            local off=CFrame.new(0,1.5,-0.5)
            pl[idx].CFrame=tankControlState.turretPart.CFrame*off
            tankControlState.tankHatch=pl[idx]
            tankControlState.tankParts[idx]=pl[idx]; tankControlState.partOffsets[idx]=off; idx=idx+1
        end

        -- Barrel (find long narrow part)
        for i=idx, math.min(idx+6,#pl) do
            if pl[i] and tankControlState.turretPart then
                local p=pl[i]
                if p.Size.Z>p.Size.X and p.Size.Z>p.Size.Y then
                    local off=CFrame.new(0,0.3,5.5)
                    p.CFrame=tankControlState.turretPart.CFrame*off
                    tankControlState.barrelPart=p; tankControlState.barrelPartIdx=i
                    tankControlState.tankParts[i]=p; tankControlState.partOffsets[i]=off
                    break
                end
            end
        end

        frozenTankCF=nil
        return true
    end

    destroyTank = function()
        if tankControlState.tankBase then
            pcall(function()
                local e=Instance.new("Explosion"); e.Position=tankControlState.tankBase.Position
                e.BlastRadius=15; e.BlastPressure=300000; e.Parent=workspace
            end)
        end
        for _,part in ipairs(tankControlState.tankParts) do
            if part and part.Parent and controlled[part] then
                releasePart(part,controlled[part]); controlled[part]=nil
                partCount=math.max(0,partCount-1)
            end
        end
        tankControlState={
            forward=0,turn=0,hatchOpen=false,insideTank=false,
            tankBase=nil,turretPart=nil,barrelPart=nil,turretPartIdx=nil,barrelPartIdx=nil,
            tankParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0,tankHatch=nil
        }
        frozenTankCF=nil; tankActive=false
        cameraOrbitAngle=0; cameraPitchAngle=math.rad(30)
        pcall(function() workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        thawPlayer()  -- restore humanoid & HRP anchoring
    end

    -- ── Ballistic shell ───────────────────────────────────────
    local function shootProjectile()
        if not tankActive or not tankControlState.barrelPart then return end
        if not tankControlState.insideTank then return end
        local now=tick(); if now-lastShootTime<SHOOT_COOLDOWN then return end; lastShootTime=now

        local shell=Instance.new("Part")
        shell.Name="TankShell"; shell.Size=Vector3.new(0.35,0.35,2.0)
        shell.BrickColor=BrickColor.new("Dark grey metallic"); shell.Material=Enum.Material.Metal
        shell.CanCollide=true; shell.CastShadow=false

        local barrelCF  = tankControlState.barrelPart.CFrame
        local barrelLen = tankControlState.barrelPart.Size.Z/2 + 1.2
        shell.CFrame = barrelCF * CFrame.new(0,0,barrelLen)
        shell.Parent = workspace

        local pitchBias = math.sin(cameraPitchAngle*0.15)*PROJECTILE_SPEED*0.2
        local arcDir = (barrelCF.LookVector+Vector3.new(0,pitchBias/PROJECTILE_SPEED,0)).Unit
        pcall(function() shell.AssemblyLinearVelocity=arcDir*PROJECTILE_SPEED end)

        pcall(function()
            local flash=Instance.new("PointLight"); flash.Brightness=10; flash.Range=20
            flash.Color=Color3.fromRGB(255,220,100); flash.Parent=shell; Debris:AddItem(flash,0.08)
        end)
        pcall(function()
            local a0=Instance.new("Attachment",shell); local a1=Instance.new("Attachment",shell); a1.Position=Vector3.new(0,0,-1)
            local tr=Instance.new("Trail"); tr.Attachment0=a0; tr.Attachment1=a1; tr.Lifetime=0.4; tr.MinLength=0
            tr.Color=ColorSequence.new(Color3.fromRGB(255,200,100),Color3.fromRGB(180,180,180))
            tr.Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)}
            tr.WidthScale=NumberSequence.new{NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)}
            tr.Parent=shell
        end)

        local hitConn
        hitConn=shell.Touched:Connect(function(hit)
            if hit==tankControlState.barrelPart or hit==tankControlState.turretPart then return end
            local c2=player.Character; if c2 and hit:IsDescendantOf(c2) then return end
            pcall(function()
                local ex=Instance.new("Explosion"); ex.Position=shell.Position
                ex.BlastRadius=10; ex.BlastPressure=150000; ex.DestroyJointRadiusPercent=0; ex.Parent=workspace
            end)
            hitConn:Disconnect(); pcall(function() shell:Destroy() end)
        end)
        Debris:AddItem(shell,12)
        if tankControlState.tankBase then
            pcall(function()
                tankControlState.tankBase.AssemblyLinearVelocity=
                    tankControlState.tankBase.AssemblyLinearVelocity-barrelCF.LookVector*4
            end)
        end
    end

    -- ── Hatch toggle ──────────────────────────────────────────
    local function toggleHatch()
        if not tankControlState.tankBase then return end
        if not tankControlState.hatchOpen then
            -- OPEN: player gets out, tank freezes
            tankControlState.hatchOpen=true; tankControlState.insideTank=false
            frozenTankCF=tankControlState.tankBase.CFrame
            if tankControlState.tankHatch then
                pcall(function()
                    tankControlState.tankHatch.CFrame=
                        tankControlState.tankHatch.CFrame*CFrame.new(0,2.5,0)*CFrame.Angles(math.rad(65),0,0)
                end)
            end
            -- Exit CFrame: above hatch
            local exitCF=tankControlState.tankBase.CFrame*CFrame.new(0,TANK_HEIGHT+4,0)
            thawPlayer(exitCF)  -- unanchor, restore walk, restore collision
            pcall(function() workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        else
            -- CLOSE: player gets back in, tank can move
            tankControlState.hatchOpen=false; tankControlState.insideTank=true
            frozenTankCF=nil
            if tankControlState.tankHatch then
                pcall(function()
                    tankControlState.tankHatch.CFrame=
                        tankControlState.tankHatch.CFrame*CFrame.Angles(math.rad(-65),0,0)*CFrame.new(0,-2.5,0)
                end)
            end
            -- Freeze player inside hull at interior offset
            local intCF=tankControlState.tankBase.CFrame*CFrame.new(0,TANK_INTERIOR_Y,0)
            freezePlayer(intCF)
        end
    end

    -- ── Tank update ───────────────────────────────────────────
    local function updateTank(dt)
        if not tankActive or not tankControlState.tankBase then return end

        -- OUTSIDE: freeze formation
        if not tankControlState.insideTank then
            if frozenTankCF then
                pcall(function()
                    tankControlState.tankBase.CFrame=frozenTankCF
                    tankControlState.tankBase.AssemblyLinearVelocity=Vector3.zero
                    tankControlState.tankBase.AssemblyAngularVelocity=Vector3.zero
                end)
                for i,part in ipairs(tankControlState.tankParts) do
                    if part and part.Parent and tankControlState.partOffsets[i] then
                        pcall(function()
                            part.CFrame=frozenTankCF*tankControlState.partOffsets[i]
                            part.AssemblyLinearVelocity=Vector3.zero
                            part.AssemblyAngularVelocity=Vector3.zero
                        end)
                    end
                end
            end
            return
        end

        -- INSIDE: drive
        if tankControlState.forward~=0 then
            tankControlState.currentSpeed=math.clamp(
                tankControlState.currentSpeed+tankControlState.forward*TANK_ACCEL*dt,
                -TANK_SPEED,TANK_SPEED)
        else
            tankControlState.currentSpeed=tankControlState.currentSpeed*TANK_FRICTION
        end
        tankControlState.currentTurnSpeed=tankControlState.turn~=0 and tankControlState.turn*TANK_TURN_SPEED or 0

        local moveVec=tankControlState.tankBase.CFrame.LookVector*tankControlState.currentSpeed*dt
        local newCF=tankControlState.tankBase.CFrame*CFrame.new(moveVec)*CFrame.Angles(0,tankControlState.currentTurnSpeed*dt,0)

        -- Ground snap
        local ray=workspace:Raycast(newCF.Position+Vector3.new(0,6,0),Vector3.new(0,-18,0))
        if ray then
            newCF=CFrame.new(Vector3.new(newCF.Position.X,ray.Position.Y+TANK_HEIGHT/2,newCF.Position.Z))*newCF.Rotation
        end

        pcall(function()
            tankControlState.tankBase.CFrame=newCF
            tankControlState.tankBase.AssemblyLinearVelocity=Vector3.zero
            tankControlState.tankBase.AssemblyAngularVelocity=Vector3.zero
        end)

        -- Move body parts
        for i,part in ipairs(tankControlState.tankParts) do
            if part and part.Parent and tankControlState.partOffsets[i] then
                if part~=tankControlState.turretPart and part~=tankControlState.barrelPart then
                    local isTurretDecorator = false
                    if tankControlState.turretPart then
                        local off=tankControlState.partOffsets[i]
                        if off and math.abs(off.Position.X)>2 and math.abs(off.Position.X)<3 and math.abs(off.Position.Y)<0.2 then
                            isTurretDecorator=true
                        end
                    end
                    if not isTurretDecorator then
                        pcall(function()
                            part.CFrame=newCF*tankControlState.partOffsets[i]
                            part.AssemblyLinearVelocity=Vector3.zero
                            part.AssemblyAngularVelocity=Vector3.zero
                        end)
                    end
                end
            end
        end

        -- Turret: hull-relative position + camera orbit yaw
        if tankControlState.turretPart and tankControlState.turretPartIdx then
            pcall(function()
                local hullOff=tankControlState.partOffsets[tankControlState.turretPartIdx]
                local turretAnchor=newCF*hullOff
                local _,tankYaw=select(2,newCF:ToEulerAnglesYXZ())  -- Lua pattern for middlevalue
                tankYaw = select(2, newCF:ToEulerAnglesYXZ())
                local turretWorldYaw=tankYaw+cameraOrbitAngle
                tankControlState.turretPart.CFrame=CFrame.new(turretAnchor.Position)*CFrame.Angles(0,turretWorldYaw,0)
                tankControlState.turretPart.AssemblyLinearVelocity=Vector3.zero
                tankControlState.turretPart.AssemblyAngularVelocity=Vector3.zero
            end)
        end

        -- Turret decorators follow turret
        if tankControlState.turretPart then
            for i,part in ipairs(tankControlState.tankParts) do
                local off=tankControlState.partOffsets[i]
                if off and part and part.Parent and part~=tankControlState.turretPart and part~=tankControlState.barrelPart then
                    if math.abs(off.Position.X)>2 and math.abs(off.Position.X)<3 and math.abs(off.Position.Y)<0.2 then
                        pcall(function()
                            part.CFrame=tankControlState.turretPart.CFrame*off
                            part.AssemblyLinearVelocity=Vector3.zero
                            part.AssemblyAngularVelocity=Vector3.zero
                        end)
                    end
                end
            end
        end

        -- Barrel: track camera pitch
        if tankControlState.barrelPart and tankControlState.turretPart and tankControlState.barrelPartIdx then
            pcall(function()
                local barrelPitch=math.clamp(-math.rad(10)+cameraPitchAngle*0.35, math.rad(-5),math.rad(25))
                local off=tankControlState.partOffsets[tankControlState.barrelPartIdx]
                if off then
                    tankControlState.barrelPart.CFrame=tankControlState.turretPart.CFrame*CFrame.Angles(barrelPitch,0,0)*CFrame.new(off.Position)
                    tankControlState.barrelPart.AssemblyLinearVelocity=Vector3.zero
                    tankControlState.barrelPart.AssemblyAngularVelocity=Vector3.zero
                end
            end)
        end

        -- Player: keep HRP anchored to interior position (no flying)
        local char=player.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.Anchored then
                -- Update position inside moving tank
                pcall(function() hrp.CFrame=newCF*CFrame.new(0,TANK_INTERIOR_Y,0) end)
            end
            -- Keep noclip every frame (humanoid sometimes re-enables CanCollide)
            for _,p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then pcall(function() p.CanCollide=false end) end
            end
        end

        -- Orbit camera: position behind tank, look FORWARD along tank direction
        pcall(function()
            workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
            local tankPos=newCF.Position
            local tankYaw=select(2, newCF:ToEulerAnglesYXZ())
            local pitch=math.clamp(cameraPitchAngle,CAM_PITCH_MIN,CAM_PITCH_MAX)

            -- Camera behind tank: worldAngle points AWAY from tank front (behind = front + π)
            local worldAngle=tankYaw+math.pi+cameraOrbitAngle

            local camX=tankPos.X+math.sin(worldAngle)*math.cos(pitch)*CAMERA_DIST
            local camY=tankPos.Y+math.sin(pitch)*CAMERA_DIST+1
            local camZ=tankPos.Z+math.cos(worldAngle)*math.cos(pitch)*CAMERA_DIST
            local camPos=Vector3.new(camX,camY,camZ)

            -- LookAt: a point AHEAD of the tank (in front, not at avatar)
            -- orbitFwdAngle = worldAngle + π = tankYaw + cameraOrbitAngle (tank's forward + orbit offset)
            local orbitFwdAngle=worldAngle+math.pi
            local lookDist=14
            local lookAt=Vector3.new(
                tankPos.X+math.sin(orbitFwdAngle)*lookDist,
                tankPos.Y+2,
                tankPos.Z+math.cos(orbitFwdAngle)*lookDist)

            workspace.CurrentCamera.CFrame=CFrame.new(camPos,lookAt)
        end)
    end

    -- ══════════════════════════════════════════════════════════
    -- CAR
    -- ══════════════════════════════════════════════════════════

    local function buildCarFromParts(position, cf)
        local pl={}
        for part,_ in pairs(controlled) do if part and part.Parent then table.insert(pl,part) end end
        if #pl < #CAR_OFFSETS then
            sweepMap(); task.wait(0.3); pl={}
            for part,_ in pairs(controlled) do if part and part.Parent then table.insert(pl,part) end end
            if #pl < #CAR_OFFSETS then
                print("[ManipKii] Car needs "..#CAR_OFFSETS.."+ parts (found "..#pl..")"); return false
            end
        end
        table.sort(pl, function(a,b) return a.Size.Magnitude > b.Size.Magnitude end)

        carControlState.carParts={}; carControlState.partOffsets={}
        carControlState.carBase=nil; carControlState.carDoor=nil

        local hull=pl[1]
        hull.CFrame=cf*CFrame.new(0,CAR_HEIGHT/2,0)
        carControlState.carBase=hull
        carControlState.carParts[1]=hull
        carControlState.partOffsets[1]=CFrame.new(0,CAR_HEIGHT/2,0)

        for i=2, math.min(#CAR_OFFSETS,#pl) do
            local part=pl[i]
            local off=CAR_OFFSETS[i]
            part.CFrame=hull.CFrame*off
            carControlState.carParts[i]=part
            carControlState.partOffsets[i]=off
            if i==26 then carControlState.carDoor=part end
        end

        frozenCarCF=nil
        return true
    end

    destroyCar = function()
        for _,part in ipairs(carControlState.carParts) do
            if part and part.Parent and controlled[part] then
                releasePart(part,controlled[part]); controlled[part]=nil
                partCount=math.max(0,partCount-1)
            end
        end
        carControlState={
            doorOpen=false,carBase=nil,carDoor=nil,
            carParts={},partOffsets={},currentSpeed=0,currentTurnSpeed=0
        }
        frozenCarCF=nil; carActive=false
        carJoystick.active=false; carJoystick.forward=0; carJoystick.turn=0
        pcall(function() workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        thawPlayer()
    end

    local function toggleCarDoor()
        if not carControlState.carBase then return end
        if not carControlState.doorOpen then
            -- OPEN: enter car, car moves
            carControlState.doorOpen=true
            frozenCarCF=nil
            -- Swing door open visually
            if carControlState.carDoor then
                pcall(function()
                    carControlState.carDoor.CFrame=
                        carControlState.carDoor.CFrame*CFrame.Angles(0,math.rad(70),0)
                end)
            end
            -- Enter player at driver seat
            local intCF=carControlState.carBase.CFrame*CFrame.new(-2,CAR_INTERIOR_Y,-1.5)
            freezePlayer(intCF)
            -- Camera stays Custom (free)
            pcall(function() workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
        else
            -- CLOSE: exit car, car freezes
            carControlState.doorOpen=false
            frozenCarCF=carControlState.carBase.CFrame
            -- Swing door closed
            if carControlState.carDoor then
                pcall(function()
                    carControlState.carDoor.CFrame=
                        carControlState.carDoor.CFrame*CFrame.Angles(0,math.rad(-70),0)
                end)
            end
            -- Exit to driver door side
            local exitCF=carControlState.carBase.CFrame*CFrame.new(-CAR_WIDTH/2-2, CAR_HEIGHT+2, -1.5)
            thawPlayer(exitCF)
        end
    end

    -- ── Car update ────────────────────────────────────────────
    local function updateCar(dt)
        if not carActive or not carControlState.carBase then return end

        -- DOOR CLOSED: freeze formation exactly
        if not carControlState.doorOpen then
            if frozenCarCF then
                pcall(function()
                    carControlState.carBase.CFrame=frozenCarCF
                    carControlState.carBase.AssemblyLinearVelocity=Vector3.zero
                    carControlState.carBase.AssemblyAngularVelocity=Vector3.zero
                end)
                for i,part in ipairs(carControlState.carParts) do
                    if part and part.Parent and carControlState.partOffsets[i] then
                        pcall(function()
                            part.CFrame=frozenCarCF*carControlState.partOffsets[i]
                            part.AssemblyLinearVelocity=Vector3.zero
                            part.AssemblyAngularVelocity=Vector3.zero
                        end)
                    end
                end
            end
            return
        end

        -- DOOR OPEN: drive
        local fwd=carJoystick.forward
        local trn=carJoystick.turn

        if fwd~=0 then
            carControlState.currentSpeed=math.clamp(
                carControlState.currentSpeed+fwd*CAR_ACCEL*dt,
                -CAR_SPEED,CAR_SPEED)
        else
            carControlState.currentSpeed=carControlState.currentSpeed*CAR_FRICTION
        end
        carControlState.currentTurnSpeed=trn~=0 and trn*CAR_TURN_SPEED or 0

        local moveVec=carControlState.carBase.CFrame.LookVector*carControlState.currentSpeed*dt
        local newCF=carControlState.carBase.CFrame*CFrame.new(moveVec)*CFrame.Angles(0,carControlState.currentTurnSpeed*dt,0)

        -- Ground snap
        local ray=workspace:Raycast(newCF.Position+Vector3.new(0,5,0),Vector3.new(0,-15,0))
        if ray then
            newCF=CFrame.new(Vector3.new(newCF.Position.X,ray.Position.Y+CAR_HEIGHT/2,newCF.Position.Z))*newCF.Rotation
        end

        pcall(function()
            carControlState.carBase.CFrame=newCF
            carControlState.carBase.AssemblyLinearVelocity=Vector3.zero
            carControlState.carBase.AssemblyAngularVelocity=Vector3.zero
        end)

        for i,part in ipairs(carControlState.carParts) do
            if part and part.Parent and carControlState.partOffsets[i] then
                pcall(function()
                    part.CFrame=newCF*carControlState.partOffsets[i]
                    part.AssemblyLinearVelocity=Vector3.zero
                    part.AssemblyAngularVelocity=Vector3.zero
                end)
            end
        end

        -- Keep player anchored inside car (driver seat)
        local char=player.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.Anchored then
                pcall(function() hrp.CFrame=newCF*CFrame.new(-2,CAR_INTERIOR_Y,-1.5) end)
            end
            for _,p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then pcall(function() p.CanCollide=false end) end
            end
        end

        -- Free camera (no scriptable override — Roblox default follows character)
        pcall(function() workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end)
    end

    -- ══════════════════════════════════════════════════════════
    -- SUB-GUIS
    -- ══════════════════════════════════════════════════════════

    local function destroyGasterGui()
        if gasterSubGui and gasterSubGui.Parent then gasterSubGui:Destroy() end; gasterSubGui=nil
    end
    local function createGasterGui()
        destroyGasterGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="GasterSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; gasterSubGui=sg
        local W,H=195,180; local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(W,H)
        panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-100); panel.BackgroundColor3=Color3.fromRGB(6,6,18); panel.BorderSizePixel=0; panel.Parent=sg
        Instance.new("UICorner",panel).CornerRadius=UDim.new(0,7); local ps=Instance.new("UIStroke",panel); ps.Color=Color3.fromRGB(180,60,255); ps.Thickness=1.2
        local tBar=Instance.new("Frame"); tBar.Size=UDim2.new(1,0,0,28); tBar.BackgroundColor3=Color3.fromRGB(20,8,45); tBar.BorderSizePixel=0; tBar.ZIndex=10; tBar.Parent=panel; Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,7)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="GASTER FORM"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(6,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(200,120,255); tLbl.TextSize=11; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=tBar
        local animLbl=Instance.new("TextLabel"); animLbl.Text="FORM: "..gasterAnim:upper(); animLbl.Size=UDim2.new(1,-10,0,14); animLbl.Position=UDim2.fromOffset(6,31); animLbl.BackgroundTransparency=1; animLbl.TextColor3=Color3.fromRGB(130,130,255); animLbl.TextSize=9; animLbl.Font=Enum.Font.GothamBold; animLbl.TextXAlignment=Enum.TextXAlignment.Left; animLbl.Parent=panel
        for idx,anim in ipairs({{txt="POINTING",key="pointing",col=Color3.fromRGB(100,200,255)},{txt="WAVING",key="waving",col=Color3.fromRGB(100,255,160)},{txt="PUNCHING",key="punching",col=Color3.fromRGB(255,120,120)}}) do
            local btn=Instance.new("TextButton"); btn.Text=anim.txt; btn.Size=UDim2.new(1,-12,0,30); btn.Position=UDim2.fromOffset(6,48+(idx-1)*36); btn.BackgroundColor3=Color3.fromRGB(22,10,48); btn.TextColor3=anim.col; btn.TextSize=11; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.Parent=panel; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function() gasterAnim=anim.key; gasterT=0; animLbl.Text="FORM: "..anim.key:upper() end)
        end
        makeDraggable(tBar,panel,false)
    end

    local function destroySphereGui()
        if sphereSubGui and sphereSubGui.Parent then sphereSubGui:Destroy() end; sphereSubGui=nil
    end
    local function createSphereGui()
        destroySphereGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="SphereSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; sphereSubGui=sg
        local W,H=195,172; local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(W,H)
        panel.Position=UDim2.new(0.5,30,0.5,-(H/2)-100); panel.BackgroundColor3=Color3.fromRGB(4,12,20); panel.BorderSizePixel=0; panel.Parent=sg
        Instance.new("UICorner",panel).CornerRadius=UDim.new(0,7); local ps=Instance.new("UIStroke",panel); ps.Color=Color3.fromRGB(60,180,255); ps.Thickness=1.2
        local tBar=Instance.new("Frame"); tBar.Size=UDim2.new(1,0,0,28); tBar.BackgroundColor3=Color3.fromRGB(8,20,45); tBar.BorderSizePixel=0; tBar.ZIndex=10; tBar.Parent=panel; Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,7)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="SPHERE CONTROL"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(6,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(80,200,255); tLbl.TextSize=11; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=tBar
        local mLbl=Instance.new("TextLabel"); mLbl.Text="STATE: "..sphereMode:upper(); mLbl.Size=UDim2.new(1,-10,0,14); mLbl.Position=UDim2.fromOffset(6,31); mLbl.BackgroundTransparency=1; mLbl.TextColor3=Color3.fromRGB(80,180,255); mLbl.TextSize=9; mLbl.Font=Enum.Font.GothamBold; mLbl.TextXAlignment=Enum.TextXAlignment.Left; mLbl.Parent=panel
        for idx,sb in ipairs({{txt="ORBIT",key="orbit",col=Color3.fromRGB(80,220,255)},{txt="FOLLOW",key="follow",col=Color3.fromRGB(120,255,160)},{txt="STAY",key="stay",col=Color3.fromRGB(255,200,80)}}) do
            local btn=Instance.new("TextButton"); btn.Text=sb.txt; btn.Size=UDim2.new(1,-12,0,30); btn.Position=UDim2.fromOffset(6,48+(idx-1)*36); btn.BackgroundColor3=Color3.fromRGB(8,22,44); btn.TextColor3=sb.col; btn.TextSize=11; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.Parent=panel; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function() sphereMode=sb.key; sphereVel=Vector3.zero; mLbl.Text="STATE: "..sb.key:upper() end)
        end
        makeDraggable(tBar,panel,false)
    end

    local function destroySphereBenderGui()
        if sbSubGui and sbSubGui.Parent then sbSubGui:Destroy() end; sbSubGui=nil
    end
    rebuildSBGui = function()
        destroySphereBenderGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="SphereBenderGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1001; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; sbSubGui=sg
        local W=205; local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(W,300); panel.Position=UDim2.new(0.5,-W-10,0.5,-150); panel.BackgroundColor3=Color3.fromRGB(5,8,20); panel.BorderSizePixel=0; panel.ClipsDescendants=false; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8); local stk=Instance.new("UIStroke",panel); stk.Color=Color3.fromRGB(0,200,255); stk.Thickness=1.4
        local tBar=Instance.new("Frame"); tBar.Size=UDim2.new(1,0,0,28); tBar.BackgroundColor3=Color3.fromRGB(4,18,40); tBar.BorderSizePixel=0; tBar.ZIndex=10; tBar.Parent=panel; Instance.new("UICorner",tBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="SPHERE BENDER"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(8,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(0,220,255); tLbl.TextSize=12; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=tBar
        local yOff=32
        local function getSelMode() for _,sp in ipairs(sbSpheres) do if sp.selected then return sp.mode end end; return "orbit" end
        local mLbl=Instance.new("TextLabel"); mLbl.Text="STATE: "..getSelMode():upper(); mLbl.Size=UDim2.new(1,-10,0,16); mLbl.Position=UDim2.fromOffset(6,yOff); mLbl.BackgroundTransparency=1; mLbl.TextColor3=Color3.fromRGB(0,180,255); mLbl.TextSize=9; mLbl.Font=Enum.Font.GothamBold; mLbl.TextXAlignment=Enum.TextXAlignment.Left; mLbl.Parent=panel; yOff=yOff+18
        for _,mb in ipairs({{txt="ORBIT",key="orbit",col=Color3.fromRGB(80,220,255)},{txt="FOLLOW",key="follow",col=Color3.fromRGB(120,255,160)},{txt="STAY",key="stay",col=Color3.fromRGB(255,200,80)}}) do
            local btn=Instance.new("TextButton"); btn.Text=mb.txt; btn.Size=UDim2.new(1,-12,0,28); btn.Position=UDim2.fromOffset(6,yOff); btn.BackgroundColor3=Color3.fromRGB(6,18,36); btn.TextColor3=mb.col; btn.TextSize=11; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.Parent=panel; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()
                for _,sp in ipairs(sbSpheres) do if sp.selected then sp.mode=mb.key; sp.stopped=false; sp.vel=Vector3.zero end end
                mLbl.Text="STATE: "..mb.key:upper()
            end)
            yOff=yOff+32
        end
        local div=Instance.new("Frame"); div.Size=UDim2.new(1,-12,0,1); div.Position=UDim2.fromOffset(6,yOff+2); div.BackgroundColor3=Color3.fromRGB(0,100,160); div.BorderSizePixel=0; div.Parent=panel; yOff=yOff+10
        local function sBtn2(t2,x,w,yp,bg,fg) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.fromOffset(w,26); b.Position=UDim2.fromOffset(x,yp); b.BackgroundColor3=bg; b.TextColor3=fg; b.TextSize=11; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.Parent=panel; Instance.new("UICorner",b); return b end
        local stopBtn=sBtn2("STOP",6,(W-18)/2,yOff,Color3.fromRGB(60,8,8),Color3.fromRGB(255,60,60))
        local goBtn  =sBtn2("GO",10+(W-18)/2,(W-18)/2,yOff,Color3.fromRGB(8,50,8),Color3.fromRGB(60,255,100))
        stopBtn.MouseButton1Click:Connect(function() for _,sp in ipairs(sbSpheres) do if sp.selected then sp.stopped=true; sp.vel=Vector3.zero end end; mLbl.Text="STATE: STOPPED" end)
        goBtn.MouseButton1Click:Connect(function() for _,sp in ipairs(sbSpheres) do if sp.selected then sp.stopped=false; sp.vel=Vector3.zero end end; mLbl.Text="STATE: "..getSelMode():upper() end)
        yOff=yOff+30
        local splitBtn=sBtn2("SPLIT SPHERE",6,W-12,yOff,Color3.fromRGB(10,30,55),Color3.fromRGB(0,200,255))
        splitBtn.MouseButton1Click:Connect(function()
            local char=player.Character; local root=char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local s=newSBSphere((root and root.Position or Vector3.new(0,5,0))+Vector3.new(math.random(-4,4),2,math.random(-4,4))); table.insert(sbSpheres,s); rebuildSBGui()
        end)
        yOff=yOff+30
        local hdr=Instance.new("TextLabel"); hdr.Text="SPHERES"; hdr.Size=UDim2.new(1,-10,0,16); hdr.Position=UDim2.fromOffset(6,yOff); hdr.BackgroundTransparency=1; hdr.TextColor3=Color3.fromRGB(0,160,220); hdr.TextSize=9; hdr.Font=Enum.Font.GothamBold; hdr.TextXAlignment=Enum.TextXAlignment.Left; hdr.Parent=panel; yOff=yOff+18
        for idx,sp in ipairs(sbSpheres) do
            local sBtn=Instance.new("TextButton"); sBtn.Text="SPHERE "..idx..(sp.stopped and "  [STOP]" or "  ["..sp.mode:upper().."]"); sBtn.Size=UDim2.new(1,-12,0,26); sBtn.Position=UDim2.fromOffset(6,yOff); sBtn.BackgroundColor3=sp.selected and Color3.fromRGB(0,60,120) or Color3.fromRGB(6,18,36); sBtn.TextColor3=sp.selected and Color3.fromRGB(80,200,255) or Color3.fromRGB(140,140,180); sBtn.TextSize=9; sBtn.Font=Enum.Font.GothamBold; sBtn.BorderSizePixel=0; sBtn.Parent=panel; Instance.new("UICorner",sBtn)
            local sBtkS=Instance.new("UIStroke",sBtn); sBtkS.Color=sp.selected and Color3.fromRGB(0,180,255) or Color3.fromRGB(30,60,100); sBtkS.Thickness=sp.selected and 1.5 or 0.8
            local cSp,cBtn,cStk=sp,sBtn,sBtkS
            sBtn.MouseButton1Click:Connect(function()
                cSp.selected=not cSp.selected; cBtn.BackgroundColor3=cSp.selected and Color3.fromRGB(0,60,120) or Color3.fromRGB(6,18,36); cBtn.TextColor3=cSp.selected and Color3.fromRGB(80,200,255) or Color3.fromRGB(140,140,180); cStk.Color=cSp.selected and Color3.fromRGB(0,180,255) or Color3.fromRGB(30,60,100); cStk.Thickness=cSp.selected and 1.5 or 0.8; mLbl.Text="STATE: "..getSelMode():upper()
            end)
            yOff=yOff+30
        end
        panel.Size=UDim2.fromOffset(W,yOff+8)
        makeDraggable(tBar,panel,false)
    end

    -- ── Tank GUI ──────────────────────────────────────────────
    destroyTankGui = function()
        if tankSubGui and tankSubGui.Parent then tankSubGui:Destroy() end; tankSubGui=nil
    end

    local function createTankGui()
        destroyTankGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="TankSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; tankSubGui=sg

        local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(185,275); panel.Position=UDim2.new(0,10,0.5,-137); panel.BackgroundColor3=Color3.fromRGB(18,18,18); panel.BorderSizePixel=0; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8); local stk=Instance.new("UIStroke",panel); stk.Color=Color3.fromRGB(90,90,90); stk.Thickness=1.5
        local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=Color3.fromRGB(30,30,30); titleBar.BorderSizePixel=0; titleBar.ZIndex=10; titleBar.Parent=panel; Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="🪖 TANK"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(8,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(210,210,210); tLbl.TextSize=12; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=titleBar
        local sLbl=Instance.new("TextLabel"); sLbl.Text="OUTSIDE  |  ENTER HATCH"; sLbl.Size=UDim2.new(1,-10,0,16); sLbl.Position=UDim2.fromOffset(6,30); sLbl.BackgroundTransparency=1; sLbl.TextColor3=Color3.fromRGB(200,180,100); sLbl.TextSize=9; sLbl.Font=Enum.Font.GothamBold; sLbl.TextXAlignment=Enum.TextXAlignment.Left; sLbl.Parent=panel

        -- D-pad
        local dLbl=Instance.new("TextLabel"); dLbl.Text="MOVEMENT"; dLbl.Size=UDim2.new(1,-10,0,12); dLbl.Position=UDim2.fromOffset(6,49); dLbl.BackgroundTransparency=1; dLbl.TextColor3=Color3.fromRGB(100,100,150); dLbl.TextSize=8; dLbl.Font=Enum.Font.GothamBold; dLbl.TextXAlignment=Enum.TextXAlignment.Left; dLbl.Parent=panel
        local cx=(185-36)/2; local dy0=63; local bs=36; local gap=2
        local function dpBtn(t2,xp,yp) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.fromOffset(bs,bs); b.Position=UDim2.fromOffset(xp,yp); b.BackgroundColor3=Color3.fromRGB(40,40,55); b.TextColor3=Color3.fromRGB(200,200,255); b.TextSize=16; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.Parent=panel; Instance.new("UICorner",b).CornerRadius=UDim.new(0,6); local s=Instance.new("UIStroke",b); s.Color=Color3.fromRGB(80,80,130); s.Thickness=1; return b,s end
        local upBtn,upS=dpBtn("▲",cx,dy0)
        local leftBtn,lS=dpBtn("◀",cx-bs-gap,dy0+bs+gap)
        local rightBtn,rS=dpBtn("▶",cx+bs+gap,dy0+bs+gap)
        local downBtn,dS=dpBtn("▼",cx,dy0+bs*2+gap*2)
        local function setP(btn,s,on) btn.BackgroundColor3=on and Color3.fromRGB(60,60,100) or Color3.fromRGB(40,40,55) end
        upBtn.MouseButton1Down:Connect(function()    tankControlState.forward=1;  setP(upBtn,upS,true)    end)
        upBtn.MouseButton1Up:Connect(function()      tankControlState.forward=0;  setP(upBtn,upS,false)   end)
        downBtn.MouseButton1Down:Connect(function()  tankControlState.forward=-1; setP(downBtn,dS,true)   end)
        downBtn.MouseButton1Up:Connect(function()    tankControlState.forward=0;  setP(downBtn,dS,false)  end)
        leftBtn.MouseButton1Down:Connect(function()  tankControlState.turn=-1;    setP(leftBtn,lS,true)   end)
        leftBtn.MouseButton1Up:Connect(function()    tankControlState.turn=0;     setP(leftBtn,lS,false)  end)
        rightBtn.MouseButton1Down:Connect(function() tankControlState.turn=1;     setP(rightBtn,rS,true)  end)
        rightBtn.MouseButton1Up:Connect(function()   tankControlState.turn=0;     setP(rightBtn,rS,false) end)

        -- Action buttons
        local ay=dy0+bs*3+gap*2+10
        local function aBtn(t2,yp,bg,fg) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.new(1,-12,0,28); b.Position=UDim2.fromOffset(6,yp); b.BackgroundColor3=bg; b.TextColor3=fg; b.TextSize=11; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.Parent=panel; Instance.new("UICorner",b); return b end
        local fireBtn    =aBtn("🔥 FIRE",       ay,      Color3.fromRGB(65,35,12),  Color3.fromRGB(255,200,80))
        local hatchBtn   =aBtn("🚪 OPEN HATCH", ay+32,   Color3.fromRGB(30,45,60),  Color3.fromRGB(120,200,255))
        local destructBtn=aBtn("💥 DESTRUCT",   ay+64,   Color3.fromRGB(75,12,12),  Color3.fromRGB(255,80,80))

        fireBtn.MouseButton1Click:Connect(function()
            shootProjectile()
            sLbl.Text="INSIDE  |  FIRING!"; sLbl.TextColor3=Color3.fromRGB(255,200,80)
            task.wait(0.4); if sLbl.Parent then sLbl.Text="INSIDE  |  READY"; sLbl.TextColor3=Color3.fromRGB(130,200,130) end
        end)
        hatchBtn.MouseButton1Click:Connect(function()
            toggleHatch()
            if tankControlState.hatchOpen then
                hatchBtn.Text="🚪 CLOSE HATCH"; sLbl.Text="OUTSIDE  |  FREE"; sLbl.TextColor3=Color3.fromRGB(200,200,100)
            else
                hatchBtn.Text="🚪 OPEN HATCH"; sLbl.Text="INSIDE  |  READY"; sLbl.TextColor3=Color3.fromRGB(130,200,130)
            end
        end)
        destructBtn.MouseButton1Click:Connect(function() task.spawn(function() destroyTank(); destroyTankGui() end) end)

        -- Aim joystick (right side, above Roblox jump button)
        local jR=rightJoystick.radius
        local jBase=Instance.new("Frame"); jBase.Size=UDim2.fromOffset(jR*2,jR*2); jBase.Position=UDim2.new(1,-(jR*2+18),0.36,-jR); jBase.BackgroundColor3=Color3.fromRGB(50,50,80); jBase.BackgroundTransparency=0.35; jBase.BorderSizePixel=0; jBase.Parent=sg; Instance.new("UICorner",jBase).CornerRadius=UDim.new(1,0); local jStk=Instance.new("UIStroke",jBase); jStk.Color=Color3.fromRGB(100,120,200); jStk.Thickness=1.5
        local jAimLbl=Instance.new("TextLabel"); jAimLbl.Text="AIM"; jAimLbl.Size=UDim2.new(1,0,0,14); jAimLbl.Position=UDim2.new(0,0,0,4); jAimLbl.BackgroundTransparency=1; jAimLbl.TextColor3=Color3.fromRGB(180,180,255); jAimLbl.TextSize=8; jAimLbl.Font=Enum.Font.GothamBold; jAimLbl.ZIndex=5; jAimLbl.Parent=jBase
        local jThumb=Instance.new("Frame"); jThumb.Size=UDim2.fromOffset(28,28); jThumb.Position=UDim2.new(0.5,-14,0.5,-14); jThumb.BackgroundColor3=Color3.fromRGB(140,150,230); jThumb.BackgroundTransparency=0.2; jThumb.BorderSizePixel=0; jThumb.Parent=jBase; Instance.new("UICorner",jThumb).CornerRadius=UDim.new(1,0)
        local function updJoyThumb()
            if rightJoystick.active then
                local off=rightJoystick.current-rightJoystick.origin; local dist=math.min(off.Magnitude,jR); local dir=off.Magnitude>0 and off.Unit or Vector2.zero
                jThumb.Position=UDim2.new(0.5,dir.X*dist-14,0.5,dir.Y*dist-14)
            else jThumb.Position=UDim2.new(0.5,-14,0.5,-14) end
        end

        -- KB
        local conKBB=UserInputService.InputBegan:Connect(function(inp,proc)
            if proc then return end
            if inp.KeyCode==Enum.KeyCode.W then     tankControlState.forward=1
            elseif inp.KeyCode==Enum.KeyCode.S then tankControlState.forward=-1
            elseif inp.KeyCode==Enum.KeyCode.A then tankControlState.turn=-1
            elseif inp.KeyCode==Enum.KeyCode.D then tankControlState.turn=1
            elseif inp.KeyCode==Enum.KeyCode.F then if tankControlState.insideTank then shootProjectile() end
            elseif inp.KeyCode==Enum.KeyCode.H then toggleHatch() end
        end)
        local conKBE=UserInputService.InputEnded:Connect(function(inp,_)
            if inp.KeyCode==Enum.KeyCode.W or inp.KeyCode==Enum.KeyCode.S then tankControlState.forward=0
            elseif inp.KeyCode==Enum.KeyCode.A or inp.KeyCode==Enum.KeyCode.D then tankControlState.turn=0 end
        end)

        -- Touch aim
        local conTS=UserInputService.TouchStarted:Connect(function(touch,proc)
            if proc then return end
            local pos=Vector2.new(touch.Position.X,touch.Position.Y)
            local center=Vector2.new(jBase.AbsolutePosition.X+jBase.AbsoluteSize.X/2,jBase.AbsolutePosition.Y+jBase.AbsoluteSize.Y/2)
            if (pos-center).Magnitude<jR*1.6 then rightJoystick.active=true; rightJoystick.origin=pos; rightJoystick.current=pos; rightJoystick.touchId=touch end
        end)
        local conTM=UserInputService.TouchMoved:Connect(function(touch,_)
            if not rightJoystick.active or rightJoystick.touchId~=touch then return end
            local pos=Vector2.new(touch.Position.X,touch.Position.Y); rightJoystick.current=pos
            local off=pos-rightJoystick.origin; local dist=math.min(off.Magnitude,jR)
            if dist>rightJoystick.deadzone then
                local dir=off.Unit
                cameraOrbitAngle=cameraOrbitAngle+dir.X*CAM_ORBIT_SENS*0.018
                cameraPitchAngle=math.clamp(cameraPitchAngle+dir.Y*CAM_PITCH_SENS*0.014,CAM_PITCH_MIN,CAM_PITCH_MAX)
            end
            updJoyThumb()
        end)
        local conTE=UserInputService.TouchEnded:Connect(function(touch,_)
            if rightJoystick.touchId==touch then rightJoystick.active=false; rightJoystick.touchId=nil; updJoyThumb() end
        end)

        sg.AncestryChanged:Connect(function(_,par)
            if not par then
                pcall(function() conKBB:Disconnect() end); pcall(function() conKBE:Disconnect() end)
                pcall(function() conTS:Disconnect() end);  pcall(function() conTM:Disconnect() end); pcall(function() conTE:Disconnect() end)
                tankControlState.forward=0; tankControlState.turn=0; rightJoystick.active=false
            end
        end)
        makeDraggable(titleBar,panel,false)
    end

    -- ── Car GUI ───────────────────────────────────────────────
    destroyCarGui = function()
        if carSubGui and carSubGui.Parent then carSubGui:Destroy() end; carSubGui=nil
    end

    local function createCarGui()
        destroyCarGui()
        local pg=player:WaitForChild("PlayerGui")
        local sg=Instance.new("ScreenGui"); sg.Name="CarSubGUI"; sg.ResetOnSpawn=false; sg.DisplayOrder=1000; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=pg; carSubGui=sg

        local panel=Instance.new("Frame"); panel.Size=UDim2.fromOffset(165,190); panel.Position=UDim2.new(0,10,0.5,-95); panel.BackgroundColor3=Color3.fromRGB(14,18,14); panel.BorderSizePixel=0; panel.Parent=sg; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8); local stk=Instance.new("UIStroke",panel); stk.Color=Color3.fromRGB(60,160,60); stk.Thickness=1.5
        local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=Color3.fromRGB(20,35,20); titleBar.BorderSizePixel=0; titleBar.ZIndex=10; titleBar.Parent=panel; Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tLbl=Instance.new("TextLabel"); tLbl.Text="🚗 CAR"; tLbl.Size=UDim2.new(1,-8,1,0); tLbl.Position=UDim2.fromOffset(8,0); tLbl.BackgroundTransparency=1; tLbl.TextColor3=Color3.fromRGB(120,220,120); tLbl.TextSize=12; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.ZIndex=10; tLbl.Parent=titleBar
        local sLbl=Instance.new("TextLabel"); sLbl.Text="PARKED  |  OPEN DOOR"; sLbl.Size=UDim2.new(1,-10,0,16); sLbl.Position=UDim2.fromOffset(6,30); sLbl.BackgroundTransparency=1; sLbl.TextColor3=Color3.fromRGB(180,180,100); sLbl.TextSize=9; sLbl.Font=Enum.Font.GothamBold; sLbl.TextXAlignment=Enum.TextXAlignment.Left; sLbl.Parent=panel

        local function aBtn2(t2,yp,bg,fg) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.new(1,-12,0,32); b.Position=UDim2.fromOffset(6,yp); b.BackgroundColor3=bg; b.TextColor3=fg; b.TextSize=11; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.Parent=panel; Instance.new("UICorner",b); return b end
        local doorBtn=aBtn2("🚪 OPEN DOOR", 50, Color3.fromRGB(25,45,25), Color3.fromRGB(80,240,80))
        local destBtn=aBtn2("💨 EXIT CAR", 86, Color3.fromRGB(55,30,8),   Color3.fromRGB(255,160,60))
        aBtn2("🔧 DESTROY",       122, Color3.fromRGB(70,10,10),   Color3.fromRGB(255,70,70)).MouseButton1Click:Connect(function()
            task.spawn(function() destroyCar(); destroyCarGui() end)
        end)

        doorBtn.MouseButton1Click:Connect(function()
            toggleCarDoor()
            if carControlState.doorOpen then
                doorBtn.Text="🚪 CLOSE DOOR"
                sLbl.Text="DRIVING  |  INSIDE"
                sLbl.TextColor3=Color3.fromRGB(100,230,100)
            else
                doorBtn.Text="🚪 OPEN DOOR"
                sLbl.Text="PARKED  |  OPEN DOOR"
                sLbl.TextColor3=Color3.fromRGB(180,180,100)
            end
        end)
        destBtn.MouseButton1Click:Connect(function()
            if carControlState.doorOpen then
                toggleCarDoor()  -- close = exit
                doorBtn.Text="🚪 OPEN DOOR"
                sLbl.Text="PARKED  |  OPEN DOOR"
                sLbl.TextColor3=Color3.fromRGB(180,180,100)
            end
        end)

        -- ── Drive joystick (LEFT side, large, sensitive) ──────
        local jR2 = carJoystick.radius
        local jBase2=Instance.new("Frame"); jBase2.Size=UDim2.fromOffset(jR2*2,jR2*2); jBase2.Position=UDim2.new(0,18,0.62,-jR2); jBase2.BackgroundColor3=Color3.fromRGB(30,60,30); jBase2.BackgroundTransparency=0.3; jBase2.BorderSizePixel=0; jBase2.Parent=sg; Instance.new("UICorner",jBase2).CornerRadius=UDim.new(1,0); local jStk2=Instance.new("UIStroke",jBase2); jStk2.Color=Color3.fromRGB(60,180,60); jStk2.Thickness=2
        local jDriveLbl=Instance.new("TextLabel"); jDriveLbl.Text="DRIVE"; jDriveLbl.Size=UDim2.new(1,0,0,16); jDriveLbl.Position=UDim2.new(0,0,0,4); jDriveLbl.BackgroundTransparency=1; jDriveLbl.TextColor3=Color3.fromRGB(100,220,100); jDriveLbl.TextSize=9; jDriveLbl.Font=Enum.Font.GothamBold; jDriveLbl.ZIndex=5; jDriveLbl.Parent=jBase2
        local jThumb2=Instance.new("Frame"); jThumb2.Size=UDim2.fromOffset(36,36); jThumb2.Position=UDim2.new(0.5,-18,0.5,-18); jThumb2.BackgroundColor3=Color3.fromRGB(80,200,80); jThumb2.BackgroundTransparency=0.2; jThumb2.BorderSizePixel=0; jThumb2.Parent=jBase2; Instance.new("UICorner",jThumb2).CornerRadius=UDim.new(1,0)

        local function updCarJoy()
            if carJoystick.active then
                local off=carJoystick.current-carJoystick.origin; local dist=math.min(off.Magnitude,jR2); local dir=off.Magnitude>0 and off.Unit or Vector2.zero
                jThumb2.Position=UDim2.new(0.5,dir.X*dist-18,0.5,dir.Y*dist-18)
            else jThumb2.Position=UDim2.new(0.5,-18,0.5,-18) end
        end

        local conCTS=UserInputService.TouchStarted:Connect(function(touch,proc)
            if proc or not carControlState.doorOpen then return end
            local pos=Vector2.new(touch.Position.X,touch.Position.Y)
            local center=Vector2.new(jBase2.AbsolutePosition.X+jBase2.AbsoluteSize.X/2, jBase2.AbsolutePosition.Y+jBase2.AbsoluteSize.Y/2)
            if (pos-center).Magnitude<jR2*1.7 then
                carJoystick.active=true; carJoystick.origin=pos; carJoystick.current=pos; carJoystick.touchId=touch
            end
        end)
        local conCTM=UserInputService.TouchMoved:Connect(function(touch,_)
            if not carJoystick.active or carJoystick.touchId~=touch then return end
            local pos=Vector2.new(touch.Position.X,touch.Position.Y); carJoystick.current=pos
            local off=pos-carJoystick.origin; local dist=math.min(off.Magnitude,jR2)
            if dist>carJoystick.deadzone then
                local dir=off.Unit
                carJoystick.forward=-dir.Y   -- up = forward
                carJoystick.turn   = dir.X
            else carJoystick.forward=0; carJoystick.turn=0 end
            updCarJoy()
        end)
        local conCTE=UserInputService.TouchEnded:Connect(function(touch,_)
            if carJoystick.touchId==touch then
                carJoystick.active=false; carJoystick.touchId=nil
                carJoystick.forward=0; carJoystick.turn=0; updCarJoy()
            end
        end)
        -- KB
        local conCKBB=UserInputService.InputBegan:Connect(function(inp,proc)
            if proc or not carControlState.doorOpen then return end
            if inp.KeyCode==Enum.KeyCode.W then     carJoystick.forward=1
            elseif inp.KeyCode==Enum.KeyCode.S then carJoystick.forward=-1
            elseif inp.KeyCode==Enum.KeyCode.A then carJoystick.turn=-1
            elseif inp.KeyCode==Enum.KeyCode.D then carJoystick.turn=1 end
        end)
        local conCKBE=UserInputService.InputEnded:Connect(function(inp,_)
            if inp.KeyCode==Enum.KeyCode.W or inp.KeyCode==Enum.KeyCode.S then carJoystick.forward=0
            elseif inp.KeyCode==Enum.KeyCode.A or inp.KeyCode==Enum.KeyCode.D then carJoystick.turn=0 end
        end)

        sg.AncestryChanged:Connect(function(_,par)
            if not par then
                pcall(function() conCTS:Disconnect() end); pcall(function() conCTM:Disconnect() end)
                pcall(function() conCTE:Disconnect() end); pcall(function() conCKBB:Disconnect() end)
                pcall(function() conCKBE:Disconnect() end)
                carJoystick.forward=0; carJoystick.turn=0; carJoystick.active=false
            end
        end)
        makeDraggable(titleBar,panel,false)
    end

    -- ══════════════════════════════════════════════════════════
    -- MAIN LOOP (Stepped = before physics step → no extra lag)
    -- ══════════════════════════════════════════════════════════
    local function mainLoop()
        RunService.Stepped:Connect(function(_, dt)
            if not scriptAlive then return end
            snakeT=snakeT+dt; gasterT=gasterT+dt

            -- Accumulate spin rotation angle
            if spinSpeed ~= 0 then
                spinAccum = spinAccum + spinSpeed * dt
                -- Keep in range so it doesn't overflow after long sessions
                if spinAccum > math.pi * 1000 then spinAccum = spinAccum - math.pi * 2000 end
            end

            local char=player.Character
            local root=char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            if not root then return end
            local pos=root.Position; local cf=root.CFrame; local t=tick()

            if activeMode=="sphere"       then updateSphereTarget(dt,pos) end
            if activeMode=="spherebender" then updateSphereBenderTargets(dt,pos) end
            if activeMode=="tank"         then updateTank(dt) end
            if activeMode=="car"          then updateCar(dt) end

            table.insert(snakeHistory,1,pos)
            if #snakeHistory>SNAKE_HIST_MAX then table.remove(snakeHistory,SNAKE_HIST_MAX+1) end

            -- Mode transitions
            if activeMode~=lastMode then
                if GASTER_MODES[activeMode]       then createGasterGui()      else destroyGasterGui() end
                if SPHERE_MODES[activeMode] then
                    spherePos=pos+Vector3.new(0,1.5,4); sphereVel=Vector3.zero; createSphereGui()
                else destroySphereGui() end
                if SPHERE_BENDER_MODES[activeMode] then
                    if #sbSpheres==0 then local s=newSBSphere(pos+Vector3.new(0,1.5,4)); s.selected=true; table.insert(sbSpheres,s) end
                    rebuildSBGui()
                else destroySphereBenderGui(); sbSpheres={} end
                if TANK_MODES[activeMode] then
                    tankActive=true; cameraOrbitAngle=0; cameraPitchAngle=math.rad(30)
                    createTankGui()
                    local ok=buildTankFromParts(pos,cf)
                    if ok then
                        -- Auto-enter: freeze player inside on tank activation
                        local intCF=tankControlState.tankBase.CFrame*CFrame.new(0,TANK_INTERIOR_Y,0)
                        tankControlState.insideTank=true; tankControlState.hatchOpen=false
                        freezePlayer(intCF)
                    end
                else
                    if tankActive then destroyTank(); destroyTankGui() end
                end
                if CAR_MODES[activeMode] then
                    carActive=true; createCarGui()
                    buildCarFromParts(pos,cf)
                    -- Start parked, player outside
                    frozenCarCF=carControlState.carBase and carControlState.carBase.CFrame or nil
                else
                    if carActive then destroyCar(); destroyCarGui() end
                end
                lastMode=activeMode
            end

            if not isActivated or activeMode=="none" or partCount==0 then return end
            if activeMode=="tank" or activeMode=="car" then return end

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
                    local data=item.d
                    -- Apply per-part spin: each part rotates around its own axes.
                    -- We offset each part's spin phase by its index so they don't
                    -- all look identical (visible tumble instead of locked block).
                    local spinCF = targetCF
                    if spinSpeed ~= 0 then
                        local phase = spinAccum + i * 0.18  -- stagger per part
                        spinCF = targetCF * CFrame.Angles(phase * 0.5, phase, phase * 0.3)
                    end
                    pcall(function()
                        if data.bp and data.bp.Parent then
                            data.bp.Position = spinCF.Position
                            data.bg.CFrame   = spinCF
                        else
                            part.CFrame = spinCF
                            part.AssemblyLinearVelocity  = Vector3.zero
                            part.AssemblyAngularVelocity = Vector3.zero
                        end
                    end)
                end
            end
        end)
    end

    -- ══════════════════════════════════════════════════════════
    -- SCAN LOOP
    -- ══════════════════════════════════════════════════════════
    local function scanLoop()
        while scriptAlive do
            if isActivated and activeMode~="none" and activeMode~="tank" and activeMode~="car" then
                sweepMap()
            end
            task.wait(1.5)
        end
    end

    -- ══════════════════════════════════════════════════════════
    -- MAIN GUI  (compact, scrollable, edge+title drag)
    -- ══════════════════════════════════════════════════════════
    local function createGUI()
        local pg=player:WaitForChild("PlayerGui")
        local old=pg:FindFirstChild("ManipGUI"); if old then old:Destroy() end

        local gui=Instance.new("ScreenGui"); gui.Name="ManipGUI"; gui.ResetOnSpawn=false; gui.DisplayOrder=999; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=pg

        local W,H=195,360
        local panel=Instance.new("Frame"); panel.Name="Panel"; panel.Size=UDim2.fromOffset(W,H); panel.Position=UDim2.new(0.5,-W/2,0.5,-H/2); panel.BackgroundColor3=Color3.fromRGB(10,10,25); panel.BorderSizePixel=0; panel.ClipsDescendants=true; panel.Parent=gui; Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8); local pS=Instance.new("UIStroke",panel); pS.Color=Color3.fromRGB(90,40,180); pS.Thickness=1.5

        local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,30); titleBar.BackgroundColor3=Color3.fromRGB(20,10,48); titleBar.BorderSizePixel=0; titleBar.ZIndex=10; titleBar.Parent=panel; Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,8)
        local tTxt=Instance.new("TextLabel"); tTxt.Text="MANIPULATOR KII"; tTxt.Size=UDim2.new(1,-60,1,0); tTxt.Position=UDim2.fromOffset(8,0); tTxt.BackgroundTransparency=1; tTxt.TextColor3=Color3.fromRGB(195,140,255); tTxt.TextSize=11; tTxt.Font=Enum.Font.GothamBold; tTxt.TextXAlignment=Enum.TextXAlignment.Left; tTxt.ZIndex=10; tTxt.Parent=titleBar
        local closeBtn=Instance.new("TextButton"); closeBtn.Text="✕"; closeBtn.Size=UDim2.fromOffset(24,22); closeBtn.Position=UDim2.new(1,-28,0,4); closeBtn.BackgroundColor3=Color3.fromRGB(150,25,25); closeBtn.TextColor3=Color3.fromRGB(255,255,255); closeBtn.TextSize=10; closeBtn.Font=Enum.Font.GothamBold; closeBtn.BorderSizePixel=0; closeBtn.ZIndex=11; closeBtn.Parent=titleBar; Instance.new("UICorner",closeBtn)

        makeDraggable(titleBar,panel,false)
        makeDraggable(panel,panel,true)

        local scroll=Instance.new("ScrollingFrame"); scroll.Size=UDim2.new(1,0,1,-30); scroll.Position=UDim2.fromOffset(0,30); scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=3; scroll.ScrollBarImageColor3=Color3.fromRGB(90,40,180); scroll.CanvasSize=UDim2.fromOffset(0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
        local lay=Instance.new("UIListLayout",scroll); lay.Padding=UDim.new(0,3); lay.HorizontalAlignment=Enum.HorizontalAlignment.Center; lay.SortOrder=Enum.SortOrder.LayoutOrder
        local pad=Instance.new("UIPadding",scroll); pad.PaddingTop=UDim.new(0,4); pad.PaddingBottom=UDim.new(0,6); pad.PaddingLeft=UDim.new(0,5); pad.PaddingRight=UDim.new(0,5)

        local function sLbl2(t2,ord) local l=Instance.new("TextLabel"); l.Text=t2; l.Size=UDim2.new(1,0,0,16); l.BackgroundTransparency=1; l.TextColor3=Color3.fromRGB(160,110,255); l.TextSize=9; l.Font=Enum.Font.GothamBold; l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=ord; l.Parent=scroll end
        local function sBtn3(t2,bg,fg,ord) local b=Instance.new("TextButton"); b.Text=t2; b.Size=UDim2.new(1,0,0,28); b.BackgroundColor3=bg; b.TextColor3=fg; b.TextSize=9; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.LayoutOrder=ord; b.Parent=scroll; Instance.new("UICorner",b); return b end

        -- ────────────────────────────────────────────────────────
        -- SETTINGS  (pull strength, radius, spin)
        -- ────────────────────────────────────────────────────────
        sLbl2("⚙ SETTINGS", 0)

        -- Helper: one labelled row with a TextBox + an APPLY button
        local function makeSettingRow(labelTxt, defaultVal, accentCol, order, onApply)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 38)
            row.BackgroundColor3 = Color3.fromRGB(14, 12, 32)
            row.BorderSizePixel  = 0
            row.LayoutOrder = order
            row.Parent = scroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
            local rowStroke = Instance.new("UIStroke", row)
            rowStroke.Color = Color3.fromRGB(50, 35, 90); rowStroke.Thickness = 1

            -- Label
            local lbl = Instance.new("TextLabel")
            lbl.Text = labelTxt
            lbl.Size = UDim2.new(0.48, 0, 0, 16)
            lbl.Position = UDim2.fromOffset(6, 3)
            lbl.BackgroundTransparency = 1
            lbl.TextColor3 = accentCol
            lbl.TextSize = 8; lbl.Font = Enum.Font.GothamBold
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = row

            -- TextBox
            local tb = Instance.new("TextBox")
            tb.Text = tostring(defaultVal)
            tb.Size = UDim2.new(0.52, -36, 0, 22)
            tb.Position = UDim2.new(0.46, 0, 0, 8)
            tb.BackgroundColor3 = Color3.fromRGB(22, 18, 50)
            tb.TextColor3 = Color3.fromRGB(255, 255, 255)
            tb.TextSize = 10; tb.Font = Enum.Font.GothamBold
            tb.ClearTextOnFocus = false
            tb.BorderSizePixel = 0; tb.Parent = row
            Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 4)

            -- APPLY button
            local applyBtn = Instance.new("TextButton")
            applyBtn.Text = "✓"
            applyBtn.Size = UDim2.fromOffset(28, 22)
            applyBtn.Position = UDim2.new(1, -32, 0, 8)
            applyBtn.BackgroundColor3 = accentCol
            applyBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
            applyBtn.TextSize = 11; applyBtn.Font = Enum.Font.GothamBold
            applyBtn.BorderSizePixel = 0; applyBtn.Parent = row
            Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 4)

            -- Flash feedback
            local function flash(ok)
                applyBtn.BackgroundColor3 = ok and Color3.fromRGB(80,255,120) or Color3.fromRGB(255,80,80)
                task.wait(0.25)
                if applyBtn.Parent then applyBtn.BackgroundColor3 = accentCol end
            end

            -- Apply on button press
            applyBtn.MouseButton1Click:Connect(function()
                local num = tonumber(tb.Text)
                if num then
                    onApply(num)
                    task.spawn(function() flash(true) end)
                else
                    task.spawn(function() flash(false) end)
                end
            end)

            -- Also apply when Enter/FocusLost
            tb.FocusLost:Connect(function(enterPressed)
                if enterPressed then
                    local num = tonumber(tb.Text)
                    if num then onApply(num) end
                end
            end)

            -- Current-value hint below the textbox
            local hint = Instance.new("TextLabel")
            hint.Size = UDim2.new(1, -6, 0, 10)
            hint.Position = UDim2.fromOffset(6, 26)
            hint.BackgroundTransparency = 1
            hint.TextColor3 = Color3.fromRGB(80, 75, 120)
            hint.TextSize = 7; hint.Font = Enum.Font.Gotham
            hint.TextXAlignment = Enum.TextXAlignment.Left
            hint.Parent = row

            return tb, hint
        end

        -- ── Pull Strength ─────────────────────────────────────
        local psTb, psHint = makeSettingRow(
            "PULL STRENGTH", pullStrength,
            Color3.fromRGB(255, 180, 60), 1,
            function(val)
                pullStrength = math.clamp(val, 1, 1e8)
                applyStrengthToAll()   -- update all already-grabbed parts instantly
                -- Re-sweep so far-away parts now get grabbed at new strength
                sweepMap()
                psHint.Text = "current: "..tostring(pullStrength).." | higher = faster pull"
            end
        )
        psHint.Text = "current: "..tostring(pullStrength).." | higher = faster pull"

        -- ── Radius ────────────────────────────────────────────
        local radTb, radHint = makeSettingRow(
            "RADIUS", radius,
            Color3.fromRGB(80, 200, 255), 2,
            function(val)
                radius = math.clamp(val, 0.5, 500)
                radHint.Text = "current: "..tostring(radius).." studs"
            end
        )
        radHint.Text = "current: "..tostring(radius).." studs"

        -- ── Spin Speed ────────────────────────────────────────
        local spinTb, spinHint = makeSettingRow(
            "SPIN SPEED", spinSpeed,
            Color3.fromRGB(180, 100, 255), 3,
            function(val)
                spinSpeed = val      -- rad/s; 0 = off, negative = reverse
                if val == 0 then spinAccum = 0 end  -- stop and reset angle
                spinHint.Text = "current: "..tostring(val).." rad/s  (0 = off)"
            end
        )
        spinHint.Text = "current: "..tostring(spinSpeed).." rad/s  (0 = off)"

        sLbl2("STATUS", 1)
        local stLbl=Instance.new("TextLabel"); stLbl.Text="IDLE  |  PARTS: 0"; stLbl.Size=UDim2.new(1,0,0,16); stLbl.BackgroundTransparency=1; stLbl.TextColor3=Color3.fromRGB(80,255,140); stLbl.TextSize=9; stLbl.Font=Enum.Font.GothamBold; stLbl.TextXAlignment=Enum.TextXAlignment.Left; stLbl.LayoutOrder=2; stLbl.Parent=scroll
        local modLbl=Instance.new("TextLabel"); modLbl.Text="MODE: NONE"; modLbl.Size=UDim2.new(1,0,0,14); modLbl.BackgroundTransparency=1; modLbl.TextColor3=Color3.fromRGB(130,130,255); modLbl.TextSize=9; modLbl.Font=Enum.Font.GothamBold; modLbl.TextXAlignment=Enum.TextXAlignment.Left; modLbl.LayoutOrder=3; modLbl.Parent=scroll

        task.spawn(function()
            while gui.Parent and scriptAlive do
                stLbl.Text=isActivated and ("ACTIVE  |  PARTS: "..partCount) or "IDLE  |  PARTS: 0"
                task.wait(0.5)
            end
        end)

        sLbl2("STANDARD MODES",4)
        local stdModes={{txt="SNAKE",mode="snake",col=Color3.fromRGB(160,110,255)},{txt="HEART",mode="heart",col=Color3.fromRGB(255,100,150)},{txt="RINGS",mode="rings",col=Color3.fromRGB(80,210,255)},{txt="WALL",mode="wall",col=Color3.fromRGB(255,200,90)},{txt="BOX",mode="box",col=Color3.fromRGB(160,255,100)},{txt="WINGS",mode="wings",col=Color3.fromRGB(100,220,255)}}
        local sRows=math.ceil(#stdModes/2); local sFrame=Instance.new("Frame"); sFrame.Size=UDim2.new(1,0,0,sRows*28+(sRows-1)*3); sFrame.BackgroundTransparency=1; sFrame.LayoutOrder=5; sFrame.Parent=scroll
        local sGL=Instance.new("UIGridLayout",sFrame); sGL.CellSize=UDim2.new(0.5,-3,0,28); sGL.CellPadding=UDim2.fromOffset(3,3); sGL.HorizontalAlignment=Enum.HorizontalAlignment.Left; sGL.SortOrder=Enum.SortOrder.LayoutOrder
        for idx,m in ipairs(stdModes) do
            local btn=Instance.new("TextButton"); btn.Text=m.txt; btn.BackgroundColor3=Color3.fromRGB(26,14,55); btn.TextColor3=m.col; btn.TextSize=9; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.LayoutOrder=idx; btn.Parent=sFrame; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()
                destroyGasterGui(); destroySphereGui(); destroySphereBenderGui()
                if tankActive then destroyTank(); destroyTankGui() end
                if carActive  then destroyCar();  destroyCarGui()  end
                activeMode=m.mode; isActivated=true; modLbl.Text="MODE: "..m.mode:upper(); sweepMap()
            end)
        end

        sLbl2("SPECIAL MODES",6)
        local spModes={
            {txt="GASTER",      mode="gasterhand",   col=Color3.fromRGB(180,80,255)},
            {txt="2x GASTER",   mode="gaster2hands", col=Color3.fromRGB(220,110,255)},
            {txt="SPHERE",      mode="sphere",        col=Color3.fromRGB(60,210,255)},
            {txt="SPH.BENDER",  mode="spherebender",  col=Color3.fromRGB(0,230,255)},
            {txt="TANK",        mode="tank",          col=Color3.fromRGB(190,190,190)},
            {txt="CAR",         mode="car",           col=Color3.fromRGB(80,220,80)},
        }
        local spRows=math.ceil(#spModes/2); local spFrame=Instance.new("Frame"); spFrame.Size=UDim2.new(1,0,0,spRows*28+(spRows-1)*3); spFrame.BackgroundTransparency=1; spFrame.LayoutOrder=7; spFrame.Parent=scroll
        local spGL=Instance.new("UIGridLayout",spFrame); spGL.CellSize=UDim2.new(0.5,-3,0,28); spGL.CellPadding=UDim2.fromOffset(3,3); spGL.HorizontalAlignment=Enum.HorizontalAlignment.Left; spGL.SortOrder=Enum.SortOrder.LayoutOrder
        for idx,m in ipairs(spModes) do
            local btn=Instance.new("TextButton"); btn.Text=m.txt; btn.BackgroundColor3=Color3.fromRGB(30,8,58); btn.TextColor3=m.col; btn.TextSize=9; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0; btn.LayoutOrder=idx; btn.Parent=spFrame; Instance.new("UICorner",btn)
            btn.MouseButton1Click:Connect(function()
                destroyGasterGui(); destroySphereGui(); destroySphereBenderGui()
                if tankActive then destroyTank(); destroyTankGui() end
                if carActive  then destroyCar();  destroyCarGui()  end
                activeMode=m.mode; isActivated=true; modLbl.Text="MODE: "..m.mode:upper()
                if GASTER_MODES[m.mode] then createGasterGui()
                elseif SPHERE_MODES[m.mode] then
                    local r2=player.Character and (player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"))
                    spherePos=(r2 and r2.Position or Vector3.new(0,5,0))+Vector3.new(0,1.5,4); sphereVel=Vector3.zero; createSphereGui()
                elseif SPHERE_BENDER_MODES[m.mode] then
                    sbSpheres={}
                    local r2=player.Character and (player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"))
                    local s=newSBSphere((r2 and r2.Position or Vector3.new(0,5,0))+Vector3.new(0,2,4)); s.selected=true; table.insert(sbSpheres,s); rebuildSBGui()
                end
                sweepMap()
            end)
        end

        sLbl2("ACTIONS",8)
        local scanBtn=sBtn3("SCAN PARTS",  Color3.fromRGB(18,55,20), Color3.fromRGB(80,255,120),  9)
        local relBtn =sBtn3("RELEASE ALL", Color3.fromRGB(55,30,8),  Color3.fromRGB(255,155,55), 10)
        local deaBtn =sBtn3("DEACTIVATE",  Color3.fromRGB(70,8,8),   Color3.fromRGB(255,55,55),  11)
        scanBtn.MouseButton1Click:Connect(function() sweepMap() end)
        relBtn.MouseButton1Click:Connect(function() releaseAll(); activeMode="none"; isActivated=false; modLbl.Text="MODE: NONE" end)
        deaBtn.MouseButton1Click:Connect(function()
            releaseAll(); scriptAlive=false; gui:Destroy()
            local icon=pg:FindFirstChild("ManipIcon"); if icon then icon:Destroy() end
        end)

        closeBtn.MouseButton1Click:Connect(function()
            gui:Destroy()
            local mini=Instance.new("ScreenGui"); mini.Name="ManipIcon"; mini.ResetOnSpawn=false; mini.DisplayOrder=999; mini.Parent=pg
            local ib=Instance.new("TextButton"); ib.Text="M"; ib.Size=UDim2.fromOffset(34,34); ib.Position=UDim2.new(1,-42,0,8); ib.BackgroundColor3=Color3.fromRGB(22,10,50); ib.TextColor3=Color3.fromRGB(195,140,255); ib.TextSize=13; ib.Font=Enum.Font.GothamBold; ib.BorderSizePixel=0; ib.Parent=mini; Instance.new("UICorner",ib)
            ib.MouseButton1Click:Connect(function() mini:Destroy(); createGUI() end)
        end)
    end

    createGUI()
    task.spawn(mainLoop)
    task.spawn(scanLoop)
end

main()
