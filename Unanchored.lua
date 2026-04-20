-- UNANCHORED MANIPULATOR KII (UMAV) 
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Create RemoteEvents (put these in ReplicatedStorage)
local RemoteEvents = ReplicatedStorage:FindFirstChild("ManipulatorEvents")
if not RemoteEvents then
    RemoteEvents = Instance.new("Folder")
    RemoteEvents.Name = "ManipulatorEvents"
    RemoteEvents.Parent = ReplicatedStorage
end

local GrabPartEvent = RemoteEvents:FindFirstChild("GrabPart") or Instance.new("RemoteEvent")
GrabPartEvent.Name = "GrabPart"
GrabPartEvent.Parent = RemoteEvents

local ReleasePartEvent = RemoteEvents:FindFirstChild("ReleasePart") or Instance.new("RemoteEvent")
ReleasePartEvent.Name = "ReleasePart"
ReleasePartEvent.Parent = RemoteEvents

local UpdatePositionEvent = RemoteEvents:FindFirstChild("UpdatePosition") or Instance.new("RemoteEvent")
UpdatePositionEvent.Name = "UpdatePosition"
UpdatePositionEvent.Parent = RemoteEvents

local SetModeEvent = RemoteEvents:FindFirstChild("SetMode") or Instance.new("RemoteEvent")
SetModeEvent.Name = "SetMode"
SetModeEvent.Parent = RemoteEvents

-- Server-side script (place in ServerScriptService)
local serverScript = [[
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:WaitForChild("ManipulatorEvents")
local GrabPartEvent = RemoteEvents:WaitForChild("GrabPart")
local ReleasePartEvent = RemoteEvents:WaitForChild("ReleasePart")
local UpdatePositionEvent = RemoteEvents:WaitForChild("UpdatePosition")
local SetModeEvent = RemoteEvents:WaitForChild("SetMode")

local controlledParts = {}
local playerModes = {}

-- Validate part
local function isValid(obj)
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

GrabPartEvent.OnServerEvent:Connect(function(player, part)
    if not part or not part.Parent then return end
    if not isValid(part) then return end
    
    local char = player.Character
    if not char then return end
    
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not root then return end
    
    if (part.Position - root.Position).Magnitude > 100 then return end
    
    if not controlledParts[player] then
        controlledParts[player] = {}
    end
    
    if not controlledParts[player][part] then
        controlledParts[player][part] = {
            originalCanCollide = part.CanCollide
        }
        part.CanCollide = false
    end
end)

ReleasePartEvent.OnServerEvent:Connect(function(player, part)
    if not part or not part.Parent then return end
    if controlledParts[player] and controlledParts[player][part] then
        part.CanCollide = controlledParts[player][part].originalCanCollide
        controlledParts[player][part] = nil
    end
end)

UpdatePositionEvent.OnServerEvent:Connect(function(player, part, targetCFrame)
    if not part or not part.Parent then return end
    if controlledParts[player] and controlledParts[player][part] then
        part.CFrame = targetCFrame
        part.Velocity = Vector3.zero
        part.RotVelocity = Vector3.zero
    end
end)

SetModeEvent.OnServerEvent:Connect(function(player, mode)
    playerModes[player] = mode
    if mode == "none" and controlledParts[player] then
        for part, data in pairs(controlledParts[player]) do
            if part and part.Parent then
                part.CanCollide = data.originalCanCollide
            end
        end
        controlledParts[player] = {}
    end
end)

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
    if controlledParts[player] then
        for part, data in pairs(controlledParts[player]) do
            if part and part.Parent then
                part.CanCollide = data.originalCanCollide
            end
        end
        controlledParts[player] = nil
    end
    playerModes[player] = nil
end)

print("Manipulator Server Handler Loaded")
]]

-- Inject server script if not already present
local serverHandler = game:GetService("ServerScriptService"):FindFirstChild("ManipulatorServerHandler")
if not serverHandler then
    serverHandler = Instance.new("Script")
    serverHandler.Name = "ManipulatorServerHandler"
    serverHandler.Source = serverScript
    serverHandler.Parent = game:GetService("ServerScriptService")
end

local function main()
    print("MANIPULATOR KII LOADED -- " .. player.Name)

    local pullStrength   = 1500
    local radius         = 7
    local detectionRange = math.huge
    local isActivated    = false
    local activeMode     = "none"
    local lastMode       = "none"
    local scriptAlive    = true

    local gasterAnim   = "pointing"
    local gasterT      = 0
    local gasterSubGui = nil
    local sphereSubGui = nil

    -- SPHERE MODE STATE
    local sphereMode       = "orbit"
    local spherePos        = Vector3.new(0, 0, 0)
    local sphereVel        = Vector3.new(0, 0, 0)
    local sphereOrbitAngle = 0
    local SPHERE_RADIUS    = 6
    local SPHERE_SPEED     = 1.2
    local SPHERE_SPRING    = 8
    local SPHERE_DAMP      = 4

    -- SPHERE BENDER STATE
    local sbSubGui  = nil
    local sbSpheres = {}
    -- each sphere = { pos, vel, orbitAngle, mode, stopped, selected }

    local function newSBSphere(startPos)
        return {
            pos        = startPos or Vector3.new(0, 0, 0),
            vel        = Vector3.zero,
            orbitAngle = 0,
            mode       = "orbit",
            stopped    = false,
            selected   = false,
        }
    end

    -- TANK MODE STATE
    local tankSubGui = nil
    local tankActive = false
    local tankParts = {}
    local tankControlState = {
        moving = false,
        forward = 0,
        turn = 0,
        turretYaw = 0,
        turretPitch = 0,
        hatchOpen = false,
        insideTank = true,
        cameraOffset = Vector3.new(0, 8, -15),
        turretPart = nil,
        barrelPart = nil,
        tankBase = nil,
        tankHatch = nil
    }

    -- Tank dimensions
    local TANK_WIDTH = 12
    local TANK_LENGTH = 16
    local TANK_HEIGHT = 6
    local TURRET_WIDTH = 8
    local TURRET_LENGTH = 10
    local TURRET_HEIGHT = 4
    local BARREL_LENGTH = 12
    local BARREL_THICKNESS = 1.2

    -- Tank movement parameters
    local TANK_SPEED = 45
    local TANK_TURN_SPEED = 2.5
    local TURRET_TURN_SPEED = 1.8

    -- Shooting parameters
    local PROJECTILE_SPEED = 350
    local SHOOT_COOLDOWN = 1.5
    local lastShootTime = 0
    local canShoot = true

    -- Joystick state
    local leftJoystick = {
        active = false,
        origin = Vector2.zero,
        current = Vector2.zero,
        radius = 80,
        deadzone = 15
    }
    local rightJoystick = {
        active = false,
        origin = Vector2.zero,
        current = Vector2.zero,
        radius = 80,
        deadzone = 15
    }

    -- MODE TABLES
    local CFRAME_MODES = {
        heart=true, rings=true, wall=true, box=true,
        gasterhand=true, gaster2hands=true, wings=true,
        sphere=true, spherebender=true, tank=true,
    }
    local GASTER_MODES        = { gasterhand=true, gaster2hands=true }
    local SPHERE_MODES        = { sphere=true }
    local SPHERE_BENDER_MODES = { spherebender=true }
    local TANK_MODES          = { tank=true }

    local HAND_SCALE = 2.8

    -- FINGER SLOTS
    local HAND_SLOTS = {
        {x=-4,y=5},{x=-4,y=4},{x=-4,y=3},{x=-4,y=2},
        {x=-2,y=6},{x=-2,y=5},{x=-2,y=4},{x=-2,y=3},
        {x= 0,y=7},{x= 0,y=6},{x= 0,y=5},{x= 0,y=4},{x= 0,y=3},
        {x= 2,y=6},{x= 2,y=5},{x= 2,y=4},{x= 2,y=3},
        {x= 5,y=2},{x= 5,y=1},{x= 5,y=0},
        {x=-4,y=1},{x=-2,y=1},{x= 0,y=1},{x= 2,y=1},
        {x=-4,y=0},{x=-2,y=0},{x= 0,y=0},{x= 2,y=0},{x= 4,y=0},
        {x=-2,y=-1},{x= 0,y=-1},{x= 2,y=-1},
    }
    local PALM_SLOTS = {
        {x=-3,y= 2},{x=-1,y= 2},{x= 1,y= 2},{x= 3,y= 2},
        {x=-3,y= 1},{x=-1,y= 1},{x= 1,y= 1},{x= 3,y= 1},
        {x=-3,y= 0},{x=-1,y= 0},{x= 1,y= 0},{x= 3,y= 0},
        {x=-2,y=-1},{x= 0,y=-1},{x= 2,y=-1},
        {x=-2,y=-2},{x= 0,y=-2},{x= 2,y=-2},
    }
    local ALL_HAND_SLOTS = {}
    for _, s in ipairs(HAND_SLOTS) do
        table.insert(ALL_HAND_SLOTS, {x=s.x, y=s.y, isPalm=false})
    end
    for _, s in ipairs(PALM_SLOTS) do
        table.insert(ALL_HAND_SLOTS, {x=s.x, y=s.y, isPalm=true})
    end
    local HAND_SLOTS_COUNT = #ALL_HAND_SLOTS

    local POINTING_BIAS = {
        [1]=-5.0,[2]=-5.0,[3]=-5.0,[4]=-5.0,
        [5]=-4.5,[6]=-4.5,[7]=-4.5,[8]=-4.5,
        [9]=-5.5,[10]=-5.0,[11]=-4.0,[12]=-2.5,[13]=-1.2,
        [18]=-0.6,[19]=-1.2,[20]=-1.2,
    }
    local PUNCH_BIAS = {
        [1]=-3.0,[2]=-2.5,[3]=-1.5,[4]=-0.5,
        [5]=-3.0,[6]=-2.5,[7]=-1.5,[8]=-0.5,
        [9]=-3.5,[10]=-3.0,[11]=-2.0,[12]=-1.0,[13]=-0.3,
        [14]=-3.0,[15]=-2.5,[16]=-1.5,[17]=-0.5,
        [18]=-0.8,[19]=-1.4,[20]=-1.4,
    }
    local HAND_RIGHT = Vector3.new( 9, 2, 1)
    local HAND_LEFT  = Vector3.new(-9, 2, 1)

    -- WING BLUEPRINT
    local WING_POINTS         = {}
    local WING_SHOULDER_RIGHT = Vector3.new( 1.0, 1.8, 0.6)
    local WING_SHOULDER_LEFT  = Vector3.new(-1.0, 1.8, 0.6)
    local WING_OPEN_ANGLE     = math.rad(82)
    local WING_CLOSE_ANGLE    = math.rad(22)
    local WING_FLAP_SPEED     = 1.8
    local WING_SPAN           = 14

    local primaryData = {
        {0.15, 2.2,0.4},{0.28, 2.8,0.5},{0.40, 3.0,0.6},
        {0.52, 2.8,0.6},{0.63, 2.2,0.5},{0.73, 1.2,0.4},
        {0.82,-0.2,0.3},{0.90,-1.8,0.2},{0.97,-3.5,0.1},
    }
    for _, f in ipairs(primaryData) do
        for seg = 1, 4 do
            local t2 = (seg - 1) / 3
            table.insert(WING_POINTS, {
                outX  = f[1] * WING_SPAN + t2 * 0.6,
                upY   = f[2] - t2 * 2.0,
                backZ = f[3] + t2 * 0.2,
                layer = 1,
            })
        end
    end
    local secondaryData = {
        {0.12,3.5,0.6},{0.22,4.4,0.7},{0.33,5.0,0.8},
        {0.44,5.0,0.8},{0.54,4.4,0.7},{0.62,3.4,0.6},
    }
    for _, f in ipairs(secondaryData) do
        for seg = 1, 3 do
            local t2 = (seg - 1) / 2
            table.insert(WING_POINTS, {
                outX  = f[1] * WING_SPAN + t2 * 0.4,
                upY   = f[2] - t2 * 1.2,
                backZ = f[3],
                layer = 2,
            })
        end
    end
    local covertData = {
        {0.04,1.5,0.5},{0.08,2.2,0.6},{0.12,2.8,0.7},{0.18,3.0,0.7},
        {0.04,0.6,0.5},{0.08,1.0,0.6},{0.14,1.2,0.6},{0.20,1.0,0.5},
    }
    for _, f in ipairs(covertData) do
        table.insert(WING_POINTS, {
            outX  = f[1] * WING_SPAN,
            upY   = f[2],
            backZ = f[3],
            layer = 3,
        })
    end
    local WING_POINT_COUNT = #WING_POINTS

    local controlled     = {}
    local partCount      = 0
    local snakeT         = 0
    local snakeHistory   = {}
    local SNAKE_HIST_MAX = 600
    local SNAKE_GAP      = 8

    -- VALIDATION
    local function isValid(obj)
        if not obj:IsA("BasePart")       then return false end
        if obj.Anchored                  then return false end
        if obj.Size.Magnitude < 0.2      then return false end
        if obj.Transparency >= 1         then return false end
        local p = obj.Parent
        while p and p ~= workspace do
            if p:FindFirstChildOfClass("Humanoid") then return false end
            p = p.Parent
        end
        return true
    end

    -- TANK CONSTRUCTION FUNCTIONS
    local function createTankBase(position, cf)
        local parts = {}
        
        -- Main hull
        local hull = Instance.new("Part")
        hull.Name = "TankHull"
        hull.Size = Vector3.new(TANK_WIDTH, TANK_HEIGHT, TANK_LENGTH)
        hull.CFrame = cf * CFrame.new(0, TANK_HEIGHT/2, 0)
        hull.BrickColor = BrickColor.new("Dark green")
        hull.Material = Enum.Material.Metal
        hull.Anchored = false
        hull.CanCollide = true
        hull.Massless = false
        hull.Parent = workspace
        table.insert(parts, hull)
        tankControlState.tankBase = hull
        
        -- Hull armor plates
        for i = 1, 4 do
            local armor = Instance.new("Part")
            armor.Size = Vector3.new(TANK_WIDTH + 0.4, 0.3, 0.8)
            armor.CFrame = hull.CFrame * CFrame.new(0, -TANK_HEIGHT/2 + 0.3 + (i-1)*1.2, TANK_LENGTH/2 - 0.5)
            armor.BrickColor = BrickColor.new("Olive")
            armor.Material = Enum.Material.Metal
            armor.Anchored = false
            armor.CanCollide = true
            armor.Parent = workspace
            table.insert(parts, armor)
            
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = hull
            weld.Part1 = armor
            weld.Parent = armor
        end
        
        -- Treads (left and right)
        for side = -1, 1, 2 do
            for i = 1, 8 do
                local tread = Instance.new("Part")
                tread.Size = Vector3.new(1.5, 1.2, 2)
                tread.CFrame = hull.CFrame * CFrame.new(side * (TANK_WIDTH/2 + 0.8), -TANK_HEIGHT/2 + 0.6, -TANK_LENGTH/2 + i * 2)
                tread.BrickColor = BrickColor.new("Black")
                tread.Material = Enum.Material.Metal
                tread.Anchored = false
                tread.CanCollide = true
                tread.Parent = workspace
                table.insert(parts, tread)
                
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = hull
                weld.Part1 = tread
                weld.Parent = tread
            end
        end
        
        -- Turret base
        local turretBase = Instance.new("Part")
        turretBase.Name = "TurretBase"
        turretBase.Size = Vector3.new(TURRET_WIDTH, 1, TURRET_LENGTH)
        turretBase.CFrame = hull.CFrame * CFrame.new(0, TANK_HEIGHT/2 + 0.5, 0)
        turretBase.BrickColor = BrickColor.new("Dark green")
        turretBase.Material = Enum.Material.Metal
        turretBase.Anchored = false
        turretBase.CanCollide = true
        turretBase.Parent = workspace
        table.insert(parts, turretBase)
        
        local weldBase = Instance.new("WeldConstraint")
        weldBase.Part0 = hull
        weldBase.Part1 = turretBase
        weldBase.Parent = turretBase
        
        -- Turret body
        local turretBody = Instance.new("Part")
        turretBody.Name = "TurretBody"
        turretBody.Size = Vector3.new(TURRET_WIDTH-1, TURRET_HEIGHT, TURRET_LENGTH-1)
        turretBody.CFrame = turretBase.CFrame * CFrame.new(0, TURRET_HEIGHT/2, 0)
        turretBody.BrickColor = BrickColor.new("Forest green")
        turretBody.Material = Enum.Material.Metal
        turretBody.Anchored = false
        turretBody.CanCollide = true
        turretBody.Parent = workspace
        table.insert(parts, turretBody)
        tankControlState.turretPart = turretBody
        
        local weldTurret = Instance.new("WeldConstraint")
        weldTurret.Part0 = turretBase
        weldTurret.Part1 = turretBody
        weldTurret.Parent = turretBody
        
        -- Turret sloped sides
        for side = -1, 1, 2 do
            local slope = Instance.new("WedgePart")
            slope.Size = Vector3.new(1.5, TURRET_HEIGHT-0.5, TURRET_LENGTH-1)
            slope.CFrame = turretBody.CFrame * CFrame.new(side * (TURRET_WIDTH/2), -0.5, 0) * CFrame.Angles(0, 0, side * math.rad(25))
            slope.BrickColor = BrickColor.new("Olive")
            slope.Material = Enum.Material.Metal
            slope.Anchored = false
            slope.CanCollide = true
            slope.Parent = workspace
            table.insert(parts, slope)
            
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = turretBody
            weld.Part1 = slope
            weld.Parent = slope
        end
        
        -- Barrel
        local barrel = Instance.new("Part")
        barrel.Name = "Barrel"
        barrel.Size = Vector3.new(BARREL_THICKNESS, BARREL_THICKNESS, BARREL_LENGTH)
        barrel.CFrame = turretBody.CFrame * CFrame.new(0, TURRET_HEIGHT/2 - 0.5, TURRET_LENGTH/2 + BARREL_LENGTH/2)
        barrel.BrickColor = BrickColor.new("Dark grey")
        barrel.Material = Enum.Material.Metal
        barrel.Anchored = false
        barrel.CanCollide = true
        barrel.Parent = workspace
        table.insert(parts, barrel)
        tankControlState.barrelPart = barrel
        
        local weldBarrel = Instance.new("WeldConstraint")
        weldBarrel.Part0 = turretBody
        weldBarrel.Part1 = barrel
        weldBarrel.Parent = barrel
        
        -- Barrel tip/muzzle brake
        local muzzle = Instance.new("Part")
        muzzle.Size = Vector3.new(BARREL_THICKNESS * 1.8, BARREL_THICKNESS * 1.8, 1.5)
        muzzle.CFrame = barrel.CFrame * CFrame.new(0, 0, BARREL_LENGTH/2 + 0.8)
        muzzle.BrickColor = BrickColor.new("Black")
        muzzle.Material = Enum.Material.Metal
        muzzle.Anchored = false
        muzzle.CanCollide = true
        muzzle.Parent = workspace
        table.insert(parts, muzzle)
        
        local weldMuzzle = Instance.new("WeldConstraint")
        weldMuzzle.Part0 = barrel
        weldMuzzle.Part1 = muzzle
        weldMuzzle.Parent = muzzle
        
        -- Hatch on top
        local hatch = Instance.new("Part")
        hatch.Name = "Hatch"
        hatch.Size = Vector3.new(3, 0.3, 2.5)
        hatch.CFrame = turretBody.CFrame * CFrame.new(0, TURRET_HEIGHT/2 + 0.2, -1)
        hatch.BrickColor = BrickColor.new("Really black")
        hatch.Material = Enum.Material.Metal
        hatch.Anchored = false
        hatch.CanCollide = true
        hatch.Transparency = 0.3
        hatch.Parent = workspace
        table.insert(parts, hatch)
        tankControlState.tankHatch = hatch
        
        local weldHatch = Instance.new("WeldConstraint")
        weldHatch.Part0 = turretBody
        weldHatch.Part1 = hatch
        weldHatch.Parent = hatch
        
        -- Hatch frame
        local hatchFrame = Instance.new("Part")
        hatchFrame.Size = Vector3.new(3.2, 0.2, 2.7)
        hatchFrame.CFrame = hatch.CFrame * CFrame.new(0, -0.1, 0)
        hatchFrame.BrickColor = BrickColor.new("Dark grey")
        hatchFrame.Material = Enum.Material.Metal
        hatchFrame.Anchored = false
        hatchFrame.CanCollide = true
        hatchFrame.Parent = workspace
        table.insert(parts, hatchFrame)
        
        local weldFrame = Instance.new("WeldConstraint")
        weldFrame.Part0 = turretBody
        weldFrame.Part1 = hatchFrame
        weldFrame.Parent = hatchFrame
        
        -- Commander's cupola
        local cupola = Instance.new("Part")
        cupola.Size = Vector3.new(2.5, 1.2, 2.5)
        cupola.CFrame = turretBody.CFrame * CFrame.new(2, TURRET_HEIGHT/2 + 0.8, 0)
        cupola.BrickColor = BrickColor.new("Dark green")
        cupola.Material = Enum.Material.Metal
        cupola.Anchored = false
        cupola.CanCollide = true
        cupola.Parent = workspace
        table.insert(parts, cupola)
        
        local weldCupola = Instance.new("WeldConstraint")
        weldCupola.Part0 = turretBody
        weldCupola.Part1 = cupola
        weldCupola.Parent = cupola
        
        -- Add to controlled list
        for _, part in ipairs(parts) do
            local data = {origCC = part.CanCollide}
            controlled[part] = data
            partCount = partCount + 1
            GrabPartEvent:FireServer(part)
        end
        
        return parts
    end

    -- TANK DESTRUCTION
    local function destroyTank()
        if not tankControlState.tankBase then return end
        
        -- Create explosion effect
        local explosion = Instance.new("Explosion")
        explosion.Position = tankControlState.tankBase.Position
        explosion.BlastRadius = 20
        explosion.BlastPressure = 500000
        explosion.DestroyJointRadiusPercent = 0
        explosion.Parent = workspace
        
        -- Remove all tank parts
        for part, data in pairs(controlled) do
            if part and part.Parent then
                if part.Name:find("Tank") or part.Name:find("Turret") or 
                   part.Name:find("Barrel") or part.Name:find("Hatch") or
                   part.Name == "TankHull" then
                    ReleasePartEvent:FireServer(part)
                    controlled[part] = nil
                    partCount = math.max(0, partCount - 1)
                    part:Destroy()
                end
            end
        end
        
        -- Reset tank state
        tankControlState = {
            moving = false,
            forward = 0,
            turn = 0,
            turretYaw = 0,
            turretPitch = 0,
            hatchOpen = false,
            insideTank = true,
            cameraOffset = Vector3.new(0, 8, -15),
            turretPart = nil,
            barrelPart = nil,
            tankBase = nil,
            tankHatch = nil
        }
        
        tankActive = false
        
        -- Restore camera
        workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        
        -- Restore player collision
        local char = player.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end

    -- SHOOT PROJECTILE
    local function shootProjectile()
        if not tankActive or not tankControlState.barrelPart then return end
        if not tankControlState.insideTank then return end
        
        local currentTime = tick()
        if currentTime - lastShootTime < SHOOT_COOLDOWN then return end
        
        lastShootTime = currentTime
        
        -- Find a projectile part from the scene or create one
        local projectile = nil
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isValid(obj) and not controlled[obj] and obj.Size.Magnitude < 3 then
                projectile = obj
                break
            end
        end
        
        if not projectile then
            -- Create a new projectile if none available
            projectile = Instance.new("Part")
            projectile.Size = Vector3.new(1.5, 1.5, 3)
            projectile.BrickColor = BrickColor.new("Bright yellow")
            projectile.Material = Enum.Material.Neon
            projectile.Anchored = false
            projectile.CanCollide = true
            projectile.Parent = workspace
        end
        
        -- Position at barrel tip
        local barrelTip = tankControlState.barrelPart.CFrame * CFrame.new(0, 0, BARREL_LENGTH/2 + 2)
        projectile.CFrame = barrelTip
        
        -- Apply velocity
        local shootDirection = tankControlState.barrelPart.CFrame.LookVector
        projectile.Velocity = shootDirection * PROJECTILE_SPEED
        projectile.RotVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
        
        -- Make projectile glow and trail
        local light = Instance.new("PointLight")
        light.Brightness = 5
        light.Range = 15
        light.Color = Color3.fromRGB(255, 200, 0)
        light.Parent = projectile
        
        -- Add to controlled for physics
        if not controlled[projectile] then
            local data = {origCC = projectile.CanCollide}
            controlled[projectile] = data
            partCount = partCount + 1
            GrabPartEvent:FireServer(projectile)
        end
        
        -- Play shoot effect
        local shootEffect = Instance.new("Part")
        shootEffect.Size = Vector3.new(0.5, 0.5, 0.5)
        shootEffect.CFrame = barrelTip
        shootEffect.BrickColor = BrickColor.new("Bright orange")
        shootEffect.Material = Enum.Material.Neon
        shootEffect.Anchored = true
        shootEffect.CanCollide = false
        shootEffect.Parent = workspace
        
        game:GetService("Debris"):AddItem(shootEffect, 0.3)
        
        -- Recoil effect
        if tankControlState.tankBase then
            local recoil = tankControlState.tankBase.CFrame.LookVector * -2
            tankControlState.tankBase.Velocity = tankControlState.tankBase.Velocity + recoil
        end
    end

    -- TOGGLE HATCH
    local function toggleHatch()
        if not tankControlState.tankHatch then return end
        
        tankControlState.hatchOpen = not tankControlState.hatchOpen
        
        if tankControlState.hatchOpen then
            -- Open hatch (move up and rotate)
            tankControlState.tankHatch.CFrame = tankControlState.tankHatch.CFrame * CFrame.new(0, 2, 0) * CFrame.Angles(math.rad(70), 0, 0)
            tankControlState.tankHatch.Transparency = 0.5
            
            -- Exit tank
            tankControlState.insideTank = false
            
            -- Teleport player to top of tank
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local exitPos = tankControlState.tankBase.Position + Vector3.new(0, TANK_HEIGHT + 3, 0)
                char:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(exitPos)
            end
            
            -- Freeze tank parts
            if tankControlState.tankBase then
                tankControlState.tankBase.Anchored = true
            end
            if tankControlState.turretPart then
                tankControlState.turretPart.Anchored = true
            end
            
            -- Restore camera
            workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        else
            -- Close hatch
            tankControlState.tankHatch.CFrame = tankControlState.tankHatch.CFrame * CFrame.Angles(math.rad(-70), 0, 0) * CFrame.new(0, -2, 0)
            tankControlState.tankHatch.Transparency = 0.3
            
            -- Enter tank
            tankControlState.insideTank = true
            
            -- Unfreeze tank parts
            if tankControlState.tankBase then
                tankControlState.tankBase.Anchored = false
            end
            if tankControlState.turretPart then
                tankControlState.turretPart.Anchored = false
            end
            
            -- Teleport player inside
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local enterPos = tankControlState.tankBase.Position + Vector3.new(0, TANK_HEIGHT/2 + 2, 0)
                char:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(enterPos)
            end
        end
    end

    -- TOGGLE DESTRUCT MODE (NOCLIP FOR TANK PARTS)
    local function toggleDestructMode()
        if not tankControlState.tankBase then return end
        
        -- Make tank parts non-collidable with player
        local char = player.Character
        if not char then return end
        
        for _, part in ipairs(workspace:GetDescendants()) do
            if part:IsA("BasePart") and (part.Name:find("Tank") or part.Name:find("Turret") or part.Name:find("Barrel")) then
                for _, limb in ipairs(char:GetDescendants()) do
                    if limb:IsA("BasePart") then
                        local nc = Instance.new("NoCollisionConstraint")
                        nc.Part0 = part
                        nc.Part1 = limb
                        nc.Parent = part
                        game:GetService("Debris"):AddItem(nc, 0.5)
                    end
                end
            end
        end
        
        -- Destroy tank after short delay
        task.wait(0.1)
        destroyTank()
    end

    -- RELEASE
    local function releasePart(part, data)
        ReleasePartEvent:FireServer(part)
        if part and part.Parent then
            pcall(function() part.CanCollide = data.origCC end)
        end
    end

    local function releaseAll()
        SetModeEvent:FireServer("none")
        for part, data in pairs(controlled) do 
            releasePart(part, data) 
        end
        controlled   = {}
        partCount    = 0
        snakeT       = 0
        snakeHistory = {}
        
        -- Cleanup tank if active
        if tankActive then
            destroyTank()
            destroyTankGui()
            workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        end
    end

    -- GRAB
    local function grabPart(part)
        if controlled[part] then return end
        local char = player.Character
        local root = char and (
            char:FindFirstChild("HumanoidRootPart") or
            char:FindFirstChild("Torso"))
        if root and
            (part.Position - root.Position).Magnitude > detectionRange then
            return
        end
        local origCC    = part.CanCollide
        part.CanCollide = false

        GrabPartEvent:FireServer(part)

        local data = {origCC=origCC}
        controlled[part] = data
        partCount = partCount + 1
    end

    local function sweepMap()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isValid(obj) then grabPart(obj) end
        end
    end

    -- SNAKE
    local function getSnakeTarget(i)
        local idx = math.clamp(i * SNAKE_GAP, 1, math.max(1, #snakeHistory))
        return snakeHistory[idx]
            or snakeHistory[#snakeHistory]
            or Vector3.zero
    end

    -- WING CFRAME
    local function getWingCF(pointIndex, sideSign, cf, t)
        local wp = WING_POINTS[pointIndex]
        if not wp then return CFrame.new(0, -5000, 0) end
        local rawSin    = math.sin(t * WING_FLAP_SPEED * math.pi)
        local flapT     = (rawSin + 1) / 2
        local flapAngle = WING_CLOSE_ANGLE
            + flapT * (WING_OPEN_ANGLE - WING_CLOSE_ANGLE)
        local cosA = math.cos(flapAngle)
        local sinA = math.sin(flapAngle)
        local rotX = (wp.outX * cosA - wp.backZ * sinA) * sideSign
        local rotZ =  wp.outX * sinA + wp.backZ * cosA + 0.5
        local shoulder = (sideSign == 1)
            and WING_SHOULDER_RIGHT or WING_SHOULDER_LEFT
        local localPos = Vector3.new(
            shoulder.X + rotX,
            shoulder.Y + wp.upY,
            shoulder.Z + rotZ)
        return CFrame.new(cf:PointToWorldSpace(localPos))
    end

    -- SPHERE PHYSICS
    local SPHERE_SHELL_SPACING = 0.8

    local function getSphereShellPos(index, total)
        local goldenRatio = (1 + math.sqrt(5)) / 2
        local i           = index - 1
        local safeTotal   = math.max(total, 1)
        local theta       = math.acos(math.clamp(1 - 2*(i+0.5)/safeTotal, -1, 1))
        local phi         = 2 * math.pi * i / goldenRatio
        local r           = SPHERE_SHELL_SPACING * (1 + math.floor(i / 12) * 0.5)
        return Vector3.new(
            r * math.sin(theta) * math.cos(phi),
            r * math.sin(theta) * math.sin(phi),
            r * math.cos(theta))
    end

    local function updateSphereTarget(dt, rootPos)
        if sphereMode == "orbit" then
            sphereOrbitAngle = sphereOrbitAngle + dt * SPHERE_SPEED
            local targetPos  = rootPos + Vector3.new(
                math.cos(sphereOrbitAngle) * SPHERE_RADIUS, 1.5,
                math.sin(sphereOrbitAngle) * SPHERE_RADIUS)
            local diff = targetPos - spherePos
            sphereVel  = sphereVel + diff * (SPHERE_SPRING * dt)
            sphereVel  = sphereVel * (1 - SPHERE_DAMP * dt)
            spherePos  = spherePos + sphereVel * dt
        elseif sphereMode == "follow" then
            local behindPlayer = rootPos + Vector3.new(0, 1.5, 4)
            local diff = behindPlayer - spherePos
            local dist = diff.Magnitude
            if dist > 3 then
                sphereVel = sphereVel
                    + diff.Unit * (dist - 3) * SPHERE_SPRING * dt
            end
            sphereVel = sphereVel * (1 - SPHERE_DAMP * dt)
            spherePos = spherePos + sphereVel * dt
        elseif sphereMode == "stay" then
            sphereVel = sphereVel * (1 - SPHERE_DAMP * 2 * dt)
            spherePos = spherePos + sphereVel * dt
        end
    end

    -- SPHERE BENDER PHYSICS
    local function updateSphereBenderTargets(dt, rootPos)
        for _, sphere in ipairs(sbSpheres) do
            if sphere.stopped then
                sphere.vel = Vector3.zero
            elseif sphere.mode == "orbit" then
                sphere.orbitAngle = sphere.orbitAngle + dt * SPHERE_SPEED
                local targetPos   = rootPos + Vector3.new(
                    math.cos(sphere.orbitAngle) * SPHERE_RADIUS, 1.5,
                    math.sin(sphere.orbitAngle) * SPHERE_RADIUS)
                local diff = targetPos - sphere.pos
                sphere.vel = sphere.vel + diff * (SPHERE_SPRING * dt)
                sphere.vel = sphere.vel * (1 - SPHERE_DAMP * dt)
                sphere.pos = sphere.pos + sphere.vel * dt
            elseif sphere.mode == "follow" then
                local behind = rootPos + Vector3.new(0, 1.5, 4)
                local diff   = behind - sphere.pos
                local dist   = diff.Magnitude
                if dist > 3 then
                    sphere.vel = sphere.vel
                        + diff.Unit * (dist - 3) * SPHERE_SPRING * dt
                end
                sphere.vel = sphere.vel * (1 - SPHERE_DAMP * dt)
                sphere.pos = sphere.pos + sphere.vel * dt
            elseif sphere.mode == "stay" then
                sphere.vel = sphere.vel * (1 - SPHERE_DAMP * 2 * dt)
                sphere.pos = sphere.pos + sphere.vel * dt
            end
        end
    end

    -- TANK UPDATE
    local function updateTank(dt, rootPos, rootCF)
        if not tankActive or not tankControlState.tankBase then return end
        
        if not tankControlState.insideTank then
            return
        end
        
        -- Update tank position (left joystick controls)
        if tankControlState.moving and tankControlState.tankBase then
            local moveDirection = tankControlState.tankBase.CFrame.LookVector * tankControlState.forward
            local turnAmount = tankControlState.turn * TANK_TURN_SPEED * dt
            
            -- Apply movement
            local newCF = tankControlState.tankBase.CFrame * CFrame.new(moveDirection * TANK_SPEED * dt)
            newCF = newCF * CFrame.Angles(0, turnAmount, 0)
            
            -- Keep tank on ground
            local rayOrigin = newCF.Position + Vector3.new(0, 5, 0)
            local raycast = workspace:Raycast(rayOrigin, Vector3.new(0, -10, 0))
            if raycast then
                newCF = CFrame.new(Vector3.new(newCF.Position.X, raycast.Position.Y + TANK_HEIGHT/2, newCF.Position.Z)) * newCF.Rotation
            end
            
            tankControlState.tankBase.CFrame = newCF
            
            -- Update turret base position
            if tankControlState.turretPart then
                local turretCF = tankControlState.turretPart.CFrame
                tankControlState.turretPart.CFrame = CFrame.new(tankControlState.tankBase.Position + Vector3.new(0, TANK_HEIGHT/2 + TURRET_HEIGHT/2 + 1, 0)) * turretCF.Rotation
            end
        end
        
        -- Update turret rotation (right joystick controls)
        if tankControlState.turretPart and (tankControlState.turretYaw ~= 0 or tankControlState.turretPitch ~= 0) then
            local yawAmount = tankControlState.turretYaw * dt
            local pitchAmount = tankControlState.turretPitch * dt
            
            -- Rotate turret horizontally
            tankControlState.turretPart.CFrame = tankControlState.turretPart.CFrame * CFrame.Angles(0, yawAmount, 0)
            
            -- Pitch barrel vertically (limited angle)
            if tankControlState.barrelPart then
                local currentPitch = select(1, tankControlState.barrelPart.CFrame:ToEulerAnglesYXZ())
                local newPitch = math.clamp(currentPitch + pitchAmount, math.rad(-15), math.rad(25))
                local barrelCF = tankControlState.barrelPart.CFrame
                local turretPos = tankControlState.turretPart.Position
                tankControlState.barrelPart.CFrame = CFrame.new(turretPos + Vector3.new(0, TURRET_HEIGHT/2 - 0.5, 0)) * 
                                                      CFrame.Angles(newPitch, select(2, barrelCF:ToEulerAnglesYXZ()), 0) * 
                                                      CFrame.new(0, 0, TURRET_LENGTH/2 + BARREL_LENGTH/2)
            end
        end
        
        -- Lock player inside tank
        if tankControlState.insideTank then
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local seatPos = tankControlState.tankBase.Position + Vector3.new(0, TANK_HEIGHT/2 + 2, -2)
                char:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(seatPos) * tankControlState.tankBase.CFrame.Rotation
                
                -- Make player noclip with tank
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
            
            -- Update camera
            workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
            local cameraPos = tankControlState.tankBase.Position + tankControlState.tankBase.CFrame:VectorToWorldSpace(tankControlState.cameraOffset)
            workspace.CurrentCamera.CFrame = CFrame.new(cameraPos, tankControlState.tankBase.Position + Vector3.new(0, TANK_HEIGHT/2, 0))
        end
    end

    -- FORMATIONS
    local function getFormationCF(mode, i, n, origin, cf, t)
        if mode == "heart" then
            local a  = ((i - 1) / math.max(n, 1)) * math.pi * 2
            local hx =  16 * math.sin(a)^3
            local hz = -(13*math.cos(a) - 5*math.cos(2*a)
                       - 2*math.cos(3*a) - math.cos(4*a))
            local s  = radius / 16
            return CFrame.new(
                origin + cf:VectorToWorldSpace(Vector3.new(hx*s, 0, hz*s)))
        elseif mode == "rings" then
            local a = ((i - 1) / math.max(n, 1)) * math.pi * 2 + t * 1.4
            return CFrame.new(origin + Vector3.new(
                math.cos(a) * radius, 0, math.sin(a) * radius))
        elseif mode == "wall" then
            local cols = math.max(1, math.ceil(math.sqrt(n)))
            local col  = ((i - 1) % cols) - math.floor(cols / 2)
            local row  = math.floor((i - 1) / cols) - 1
            return CFrame.new(
                origin
                + cf.LookVector  * radius
                + cf.RightVector * (col * 1.8)
                + cf.UpVector    * (row * 1.8 + 1))
        elseif mode == "box" then
            local fV  = {cf.LookVector, -cf.LookVector,
                         cf.RightVector, -cf.RightVector,
                         cf.UpVector, -cf.UpVector}
            local fTa = {cf.RightVector, cf.RightVector,
                         cf.LookVector,  cf.LookVector,
                         cf.RightVector, cf.RightVector}
            local fTb = {cf.UpVector, cf.UpVector,
                         cf.UpVector, cf.UpVector,
                         cf.LookVector, cf.LookVector}
            local fi  = ((i - 1) % 6) + 1
            local si  = math.floor((i - 1) / 6)
            local col = (si % 2) - 0.5
            local row = math.floor(si / 2) - 0.5
            local sp  = radius * 0.45
            return CFrame.new(
                origin
                + fV[fi]  * radius
                + fTa[fi] * (col * sp)
                + fTb[fi] * (row * sp))
        elseif mode == "wings" then
            local half = math.ceil(n / 2)
            local sideSign, ptIdx
            if i <= half then
                sideSign = 1;  ptIdx = i
            else
                sideSign = -1; ptIdx = i - half
            end
            local wpIdx = ((ptIdx - 1) % WING_POINT_COUNT) + 1
            return getWingCF(wpIdx, sideSign, cf, t)
        end
        return CFrame.new(origin)
    end

    -- GASTER HAND CFRAME
    local function getGasterCF(slotIndex, sideSign, cf, gt)
        local slot = ALL_HAND_SLOTS[slotIndex]
        if not slot then return CFrame.new(0, -5000, 0) end
        local sx     = slot.x * HAND_SCALE
        local sy     = slot.y * HAND_SCALE
        local floatY = math.sin(gt * 2.0 + sideSign * 1.2) * 1.0
        if not slot.isPalm then
            if gasterAnim == "pointing" then
                sy = sy + (POINTING_BIAS[slotIndex] or 0) * HAND_SCALE
            elseif gasterAnim == "punching" then
                sy = sy + (PUNCH_BIAS[slotIndex] or 0) * HAND_SCALE
            end
        end
        local waveAngle = 0
        if gasterAnim == "waving" then
            waveAngle = math.sin(gt * 2.2) * 0.5
        end
        local punchZ = 0
        if gasterAnim == "punching" and not slot.isPalm then
            punchZ = (math.sin(gt * 10) * 0.5 + 0.5) * 8
        end
        local rotX        = sx * math.cos(waveAngle)
        local rotZ        = sx * math.sin(waveAngle)
        local base        = (sideSign == 1) and HAND_RIGHT or HAND_LEFT
        local palmOffset  = slot.isPalm and 1.5 or 0
        local localOffset = Vector3.new(
            base.X + rotX * sideSign,
            base.Y + sy   + floatY,
            base.Z + rotZ - punchZ + palmOffset)
        return CFrame.new(cf:PointToWorldSpace(localOffset))
    end

    -- GASTER GUI
    local function destroyGasterGui()
        if gasterSubGui and gasterSubGui.Parent then gasterSubGui:Destroy() end
        gasterSubGui = nil
    end

    local function createGasterGui()
        destroyGasterGui()
        local pg = player:WaitForChild("PlayerGui")
        local sg = Instance.new("ScreenGui")
        sg.Name           = "GasterSubGUI"
        sg.ResetOnSpawn   = false
        sg.DisplayOrder   = 1000
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Parent         = pg
        gasterSubGui      = sg

        local W, H = 200, 185
        local panel = Instance.new("Frame")
        panel.Size             = UDim2.fromOffset(W, H)
        panel.Position         = UDim2.new(0.5, 30, 0.5, -(H/2) - 110)
        panel.BackgroundColor3 = Color3.fromRGB(6, 6, 18)
        panel.BorderSizePixel  = 0
        panel.Parent           = sg
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 7)
        local ps     = Instance.new("UIStroke", panel)
        ps.Color     = Color3.fromRGB(180, 60, 255)
        ps.Thickness = 1.2

        local tBar = Instance.new("Frame")
        tBar.Size             = UDim2.new(1, 0, 0, 30)
        tBar.BackgroundColor3 = Color3.fromRGB(20, 8, 45)
        tBar.BorderSizePixel  = 0
        tBar.ZIndex           = 10
        tBar.Parent           = panel
        Instance.new("UICorner", tBar).CornerRadius = UDim.new(0, 7)

        local tLbl = Instance.new("TextLabel")
        tLbl.Text                   = "GASTER FORM"
        tLbl.Size                   = UDim2.new(1, -8, 1, 0)
        tLbl.Position               = UDim2.fromOffset(6, 0)
        tLbl.BackgroundTransparency = 1
        tLbl.TextColor3             = Color3.fromRGB(200, 120, 255)
        tLbl.TextSize               = 11
        tLbl.Font                   = Enum.Font.GothamBold
        tLbl.TextXAlignment         = Enum.TextXAlignment.Left
        tLbl.ZIndex                 = 10
        tLbl.Parent                 = tBar

        local animLbl = Instance.new("TextLabel")
        animLbl.Text                   = "FORM: " .. gasterAnim:upper()
        animLbl.Size                   = UDim2.new(1, -10, 0, 16)
        animLbl.Position               = UDim2.fromOffset(6, 34)
        animLbl.BackgroundTransparency = 1
        animLbl.TextColor3             = Color3.fromRGB(130, 130, 255)
        animLbl.TextSize               = 10
        animLbl.Font                   = Enum.Font.GothamBold
        animLbl.TextXAlignment         = Enum.TextXAlignment.Left
        animLbl.Parent                 = panel

        local animList = {
            {txt="POINTING", key="pointing", col=Color3.fromRGB(100, 200, 255)},
            {txt="WAVING",   key="waving",   col=Color3.fromRGB(100, 255, 160)},
            {txt="PUNCHING", key="punching", col=Color3.fromRGB(255, 120, 120)},
        }
        for idx, anim in ipairs(animList) do
            local btn = Instance.new("TextButton")
            btn.Text             = anim.txt
            btn.Size             = UDim2.new(1, -12, 0, 30)
            btn.Position         = UDim2.fromOffset(6, 54 + (idx - 1) * 36)
            btn.BackgroundColor3 = Color3.fromRGB(22, 10, 48)
            btn.TextColor3       = anim.col
            btn.TextSize         = 11
            btn.Font             = Enum.Font.GothamBold
            btn.BorderSizePixel  = 0
            btn.Parent           = panel
            Instance.new("UICorner", btn)
            btn.MouseButton1Click:Connect(function()
                gasterAnim     = anim.key
                gasterT        = 0
                animLbl.Text   = "FORM: " .. anim.key:upper()
            end)
        end

        local dragging, dragStartM, dragStartPos = false, Vector2.zero, UDim2.new()
        tBar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging     = true
                dragStartM   = Vector2.new(inp.Position.X, inp.Position.Y)
                dragStartPos = panel.Position
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if not dragging then return end
            if inp.UserInputType == Enum.UserInputType.MouseMovement
                or inp.UserInputType == Enum.UserInputType.Touch then
                local d = Vector2.new(inp.Position.X, inp.Position.Y) - dragStartM
                panel.Position = UDim2.new(
                    dragStartPos.X.Scale, dragStartPos.X.Offset + d.X,
                    dragStartPos.Y.Scale, dragStartPos.Y.Offset + d.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    -- SPHERE GUI
    local function destroySphereGui()
        if sphereSubGui and sphereSubGui.Parent then sphereSubGui:Destroy() end
        sphereSubGui = nil
    end

    local function createSphereGui()
        destroySphereGui()
        local pg = player:WaitForChild("PlayerGui")
        local sg = Instance.new("ScreenGui")
        sg.Name           = "SphereSubGUI"
        sg.ResetOnSpawn   = false
        sg.DisplayOrder   = 1000
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Parent         = pg
        sphereSubGui      = sg

        local W, H = 200, 175
        local panel = Instance.new("Frame")
        panel.Size             = UDim2.fromOffset(W, H)
        panel.Position         = UDim2.new(0.5, 30, 0.5, -(H/2) - 110)
        panel.BackgroundColor3 = Color3.fromRGB(4, 12, 20)
        panel.BorderSizePixel  = 0
        panel.Parent           = sg
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 7)
        local ps     = Instance.new("UIStroke", panel)
        ps.Color     = Color3.fromRGB(60, 180, 255)
        ps.Thickness = 1.2

        local tBar = Instance.new("Frame")
        tBar.Size             = UDim2.new(1, 0, 0, 30)
        tBar.BackgroundColor3 = Color3.fromRGB(8, 20, 45)
        tBar.BorderSizePixel  = 0
        tBar.ZIndex           = 10
        tBar.Parent           = panel
        Instance.new("UICorner", tBar).CornerRadius = UDim.new(0, 7)

        local tLbl = Instance.new("TextLabel")
        tLbl.Text                   = "SPHERE CONTROL"
        tLbl.Size                   = UDim2.new(1, -8, 1, 0)
        tLbl.Position               = UDim2.fromOffset(6, 0)
        tLbl.BackgroundTransparency = 1
        tLbl.TextColor3             = Color3.fromRGB(80, 200, 255)
        tLbl.TextSize               = 11
        tLbl.Font                   = Enum.Font.GothamBold
        tLbl.TextXAlignment         = Enum.TextXAlignment.Left
        tLbl.ZIndex                 = 10
        tLbl.Parent                 = tBar

        local modeLblS = Instance.new("TextLabel")
        modeLblS.Text                   = "STATE: " .. sphereMode:upper()
        modeLblS.Size                   = UDim2.new(1, -10, 0, 16)
        modeLblS.Position               = UDim2.fromOffset(6, 34)
        modeLblS.BackgroundTransparency = 1
        modeLblS.TextColor3             = Color3.fromRGB(80, 180, 255)
        modeLblS.TextSize               = 10
        modeLblS.Font                   = Enum.Font.GothamBold
        modeLblS.TextXAlignment         = Enum.TextXAlignment.Left
        modeLblS.Parent                 = panel

        local sphereBtns = {
            {txt="ORBIT",  key="orbit",  col=Color3.fromRGB(80,  220, 255)},
            {txt="FOLLOW", key="follow", col=Color3.fromRGB(120, 255, 160)},
            {txt="STAY",   key="stay",   col=Color3.fromRGB(255, 200,  80)},
        }
        for idx, sb in ipairs(sphereBtns) do
            local btn = Instance.new("TextButton")
            btn.Text             = sb.txt
            btn.Size             = UDim2.new(1, -12, 0, 30)
            btn.Position         = UDim2.fromOffset(6, 54 + (idx - 1) * 36)
            btn.BackgroundColor3 = Color3.fromRGB(8, 22, 44)
            btn.TextColor3       = sb.col
            btn.TextSize         = 11
            btn.Font             = Enum.Font.GothamBold
            btn.BorderSizePixel  = 0
            btn.Parent           = panel
            Instance.new("UICorner", btn)
            local bs     = Instance.new("UIStroke", btn)
            bs.Color     = Color3.fromRGB(40, 140, 220)
            bs.Thickness = 1
            btn.MouseButton1Click:Connect(function()
                sphereMode     = sb.key
                sphereVel      = Vector3.zero
                modeLblS.Text  = "STATE: " .. sb.key:upper()
            end)
        end

        local dragging, dragStartM, dragStartPos = false, Vector2.zero, UDim2.new()
        tBar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging     = true
                dragStartM   = Vector2.new(inp.Position.X, inp.Position.Y)
                dragStartPos = panel.Position
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if not dragging then return end
            if inp.UserInputType == Enum.UserInputType.MouseMovement
                or inp.UserInputType == Enum.UserInputType.Touch then
                local d = Vector2.new(inp.Position.X, inp.Position.Y) - dragStartM
                panel.Position = UDim2.new(
                    dragStartPos.X.Scale, dragStartPos.X.Offset + d.X,
                    dragStartPos.Y.Scale, dragStartPos.Y.Offset + d.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    -- TANK GUI
    local function destroyTankGui()
        if tankSubGui and tankSubGui.Parent then tankSubGui:Destroy() end
        tankSubGui = nil
        tankActive = false
    end

    local function createTankGui()
        destroyTankGui()
        
        local pg = player:WaitForChild("PlayerGui")
        local sg = Instance.new("ScreenGui")
        sg.Name = "TankSubGUI"
        sg.ResetOnSpawn = false
        sg.DisplayOrder = 1000
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Parent = pg
        tankSubGui = sg
        
        -- Main panel
        local panel = Instance.new("Frame")
        panel.Size = UDim2.fromOffset(220, 280)
        panel.Position = UDim2.new(0.5, -350, 0.5, -140)
        panel.BackgroundColor3 = Color3.fromRGB(20, 25, 15)
        panel.BorderSizePixel = 0
        panel.Parent = sg
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
        
        local stroke = Instance.new("UIStroke", panel)
        stroke.Color = Color3.fromRGB(100, 140, 60)
        stroke.Thickness = 1.5
        
        -- Title bar
        local titleBar = Instance.new("Frame")
        titleBar.Size = UDim2.new(1, 0, 0, 30)
        titleBar.BackgroundColor3 = Color3.fromRGB(30, 40, 20)
        titleBar.BorderSizePixel = 0
        titleBar.ZIndex = 10
        titleBar.Parent = panel
        Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)
        
        local titleLbl = Instance.new("TextLabel")
        titleLbl.Text = "TANK CONTROL"
        titleLbl.Size = UDim2.new(1, -8, 1, 0)
        titleLbl.Position = UDim2.fromOffset(8, 0)
        titleLbl.BackgroundTransparency = 1
        titleLbl.TextColor3 = Color3.fromRGB(140, 200, 80)
        titleLbl.TextSize = 12
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.ZIndex = 10
        titleLbl.Parent = titleBar
        
        -- Status label
        local statusLbl = Instance.new("TextLabel")
        statusLbl.Text = "STATUS: READY"
        statusLbl.Size = UDim2.new(1, -10, 0, 20)
        statusLbl.Position = UDim2.fromOffset(6, 36)
        statusLbl.BackgroundTransparency = 1
        statusLbl.TextColor3 = Color3.fromRGB(80, 200, 80)
        statusLbl.TextSize = 10
        statusLbl.Font = Enum.Font.GothamBold
        statusLbl.TextXAlignment = Enum.TextXAlignment.Left
        statusLbl.Parent = panel
        
        -- Joystick info
        local leftJoyInfo = Instance.new("TextLabel")
        leftJoyInfo.Text = "LEFT JOYSTICK: Move Tank"
        leftJoyInfo.Size = UDim2.new(1, -10, 0, 18)
        leftJoyInfo.Position = UDim2.fromOffset(6, 60)
        leftJoyInfo.BackgroundTransparency = 1
        leftJoyInfo.TextColor3 = Color3.fromRGB(120, 120, 200)
        leftJoyInfo.TextSize = 9
        leftJoyInfo.Font = Enum.Font.Gotham
        leftJoyInfo.TextXAlignment = Enum.TextXAlignment.Left
        leftJoyInfo.Parent = panel
        
        local rightJoyInfo = Instance.new("TextLabel")
        rightJoyInfo.Text = "RIGHT JOYSTICK: Aim Turret"
        rightJoyInfo.Size = UDim2.new(1, -10, 0, 18)
        rightJoyInfo.Position = UDim2.fromOffset(6, 78)
        rightJoyInfo.BackgroundTransparency = 1
        rightJoyInfo.TextColor3 = Color3.fromRGB(200, 120, 120)
        rightJoyInfo.TextSize = 9
        rightJoyInfo.Font = Enum.Font.Gotham
        rightJoyInfo.TextXAlignment = Enum.TextXAlignment.Left
        rightJoyInfo.Parent = panel
        
        -- Divider
        local div = Instance.new("Frame")
        div.Size = UDim2.new(1, -12, 0, 1)
        div.Position = UDim2.fromOffset(6, 102)
        div.BackgroundColor3 = Color3.fromRGB(60, 100, 40)
        div.BorderSizePixel = 0
        div.Parent = panel
        
        -- Shoot button
        local shootBtn = Instance.new("TextButton")
        shootBtn.Text = "SHOOT"
        shootBtn.Size = UDim2.new(1, -12, 0, 40)
        shootBtn.Position = UDim2.fromOffset(6, 112)
        shootBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 20)
        shootBtn.TextColor3 = Color3.fromRGB(255, 200, 100)
        shootBtn.TextSize = 14
        shootBtn.Font = Enum.Font.GothamBold
        shootBtn.BorderSizePixel = 0
        shootBtn.Parent = panel
        Instance.new("UICorner", shootBtn)
        
        local shootStroke = Instance.new("UIStroke", shootBtn)
        shootStroke.Color = Color3.fromRGB(255, 150, 50)
        shootStroke.Thickness = 1.5
        
        shootBtn.MouseButton1Click:Connect(function()
            shootProjectile()
            statusLbl.Text = "STATUS: FIRING!"
            task.wait(0.3)
            statusLbl.Text = "STATUS: READY"
        end)
        
        -- Hatch toggle button
        local hatchBtn = Instance.new("TextButton")
        hatchBtn.Text = "TOGGLE HATCH"
        hatchBtn.Size = UDim2.new(1, -12, 0, 35)
        hatchBtn.Position = UDim2.fromOffset(6, 158)
        hatchBtn.BackgroundColor3 = Color3.fromRGB(40, 50, 60)
        hatchBtn.TextColor3 = Color3.fromRGB(150, 200, 255)
        hatchBtn.TextSize = 12
        hatchBtn.Font = Enum.Font.GothamBold
        hatchBtn.BorderSizePixel = 0
        hatchBtn.Parent = panel
        Instance.new("UICorner", hatchBtn)
        
        hatchBtn.MouseButton1Click:Connect(function()
            toggleHatch()
            if tankControlState.hatchOpen then
                hatchBtn.Text = "CLOSE HATCH"
                statusLbl.Text = "STATUS: HATCH OPEN"
            else
                hatchBtn.Text = "OPEN HATCH"
                statusLbl.Text = "STATUS: INSIDE TANK"
            end
        end)
        
        -- Destruct button
        local destructBtn = Instance.new("TextButton")
        destructBtn.Text = "DESTRUCT"
        destructBtn.Size = UDim2.new(1, -12, 0, 35)
        destructBtn.Position = UDim2.fromOffset(6, 199)
        destructBtn.BackgroundColor3 = Color3.fromRGB(80, 20, 20)
        destructBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
        destructBtn.TextSize = 12
        destructBtn.Font = Enum.Font.GothamBold
        destructBtn.BorderSizePixel = 0
        destructBtn.Parent = panel
        Instance.new("UICorner", destructBtn)
        
        destructBtn.MouseButton1Click:Connect(function()
            statusLbl.Text = "STATUS: DESTRUCTING..."
            toggleDestructMode()
            destroyTankGui()
        end)
        
        -- Joystick visual indicators
        -- Left joystick base
        local leftJoyBase = Instance.new("Frame")
        leftJoyBase.Size = UDim2.fromOffset(leftJoystick.radius * 2, leftJoystick.radius * 2)
        leftJoyBase.Position = UDim2.new(0, 30, 0.7, 0)
        leftJoyBase.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
        leftJoyBase.BackgroundTransparency = 0.5
        leftJoyBase.BorderSizePixel = 0
        leftJoyBase.Parent = sg
        Instance.new("UICorner", leftJoyBase).CornerRadius = UDim.new(1, 0)
        
        local leftJoyStick = Instance.new("Frame")
        leftJoyStick.Size = UDim2.fromOffset(40, 40)
        leftJoyStick.Position = UDim2.new(0.5, -20, 0.5, -20)
        leftJoyStick.BackgroundColor3 = Color3.fromRGB(80, 80, 180)
        leftJoyStick.BackgroundTransparency = 0.3
        leftJoyStick.BorderSizePixel = 0
        leftJoyStick.Parent = leftJoyBase
        Instance.new("UICorner", leftJoyStick).CornerRadius = UDim.new(1, 0)
        
        -- Right joystick base
        local rightJoyBase = Instance.new("Frame")
        rightJoyBase.Size = UDim2.fromOffset(rightJoystick.radius * 2, rightJoystick.radius * 2)
        rightJoyBase.Position = UDim2.new(1, -190, 0.7, 0)
        rightJoyBase.BackgroundColor3 = Color3.fromRGB(50, 30, 30)
        rightJoyBase.BackgroundTransparency = 0.5
        rightJoyBase.BorderSizePixel = 0
        rightJoyBase.Parent = sg
        Instance.new("UICorner", rightJoyBase).CornerRadius = UDim.new(1, 0)
        
        local rightJoyStick = Instance.new("Frame")
        rightJoyStick.Size = UDim2.fromOffset(40, 40)
        rightJoyStick.Position = UDim2.new(0.5, -20, 0.5, -20)
        rightJoyStick.BackgroundColor3 = Color3.fromRGB(180, 80, 80)
        rightJoyStick.BackgroundTransparency = 0.3
        rightJoyStick.BorderSizePixel = 0
        rightJoyStick.Parent = rightJoyBase
        Instance.new("UICorner", rightJoyStick).CornerRadius = UDim.new(1, 0)
        
        -- Joystick input handling
        local function updateJoystickVisuals()
            if leftJoystick.active then
                local offset = leftJoystick.current - leftJoystick.origin
                local dist = math.min(offset.Magnitude, leftJoystick.radius)
                local dir = offset.Unit
                local newPos = Vector2.new(leftJoyBase.Position.X.Offset, leftJoyBase.Position.Y.Offset) + dir * dist
                leftJoyStick.Position = UDim2.fromOffset(newPos.X - leftJoyBase.Position.X.Offset - 20, newPos.Y - leftJoyBase.Position.Y.Offset - 20)
            else
                leftJoyStick.Position = UDim2.new(0.5, -20, 0.5, -20)
            end
            
            if rightJoystick.active then
                local offset = rightJoystick.current - rightJoystick.origin
                local dist = math.min(offset.Magnitude, rightJoystick.radius)
                local dir = offset.Unit
                local newPos = Vector2.new(rightJoyBase.Position.X.Offset, rightJoyBase.Position.Y.Offset) + dir * dist
                rightJoyStick.Position = UDim2.fromOffset(newPos.X - rightJoyBase.Position.X.Offset - 20, newPos.Y - rightJoyBase.Position.Y.Offset - 20)
            else
                rightJoyStick.Position = UDim2.new(0.5, -20, 0.5, -20)
            end
        end
        
        -- Input handling
        UserInputService.TouchStarted:Connect(function(touch, processed)
            if processed or not tankActive or not tankControlState.insideTank then return end
            
            local pos = Vector2.new(touch.Position.X, touch.Position.Y)
            
            -- Check left joystick area
            local leftCenter = Vector2.new(leftJoyBase.AbsolutePosition.X + leftJoyBase.AbsoluteSize.X/2, 
                                           leftJoyBase.AbsolutePosition.Y + leftJoyBase.AbsoluteSize.Y/2)
            if (pos - leftCenter).Magnitude < leftJoystick.radius * 2 then
                leftJoystick.active = true
                leftJoystick.origin = pos
                leftJoystick.current = pos
            end
            
            -- Check right joystick area
            local rightCenter = Vector2.new(rightJoyBase.AbsolutePosition.X + rightJoyBase.AbsoluteSize.X/2,
                                            rightJoyBase.AbsolutePosition.Y + rightJoyBase.AbsoluteSize.Y/2)
            if (pos - rightCenter).Magnitude < rightJoystick.radius * 2 then
                rightJoystick.active = true
                rightJoystick.origin = pos
                rightJoystick.current = pos
            end
        end)
        
        UserInputService.TouchMoved:Connect(function(touch, processed)
            if not tankActive or not tankControlState.insideTank then return end
            
            local pos = Vector2.new(touch.Position.X, touch.Position.Y)
            
            if leftJoystick.active then
                leftJoystick.current = pos
                local offset = leftJoystick.current - leftJoystick.origin
                local dist = math.min(offset.Magnitude, leftJoystick.radius)
                
                if dist > leftJoystick.deadzone then
                    local dir = offset.Unit
                    tankControlState.forward = -dir.Y
                    tankControlState.turn = dir.X
                    tankControlState.moving = true
                else
                    tankControlState.forward = 0
                    tankControlState.turn = 0
                    tankControlState.moving = false
                end
            end
            
            if rightJoystick.active then
                rightJoystick.current = pos
                local offset = rightJoystick.current - rightJoystick.origin
                local dist = math.min(offset.Magnitude, rightJoystick.radius)
                
                if dist > rightJoystick.deadzone then
                    local dir = offset.Unit
                    tankControlState.turretYaw = dir.X * TURRET_TURN_SPEED
                    tankControlState.turretPitch = -dir.Y * (TURRET_TURN_SPEED * 0.5)
                else
                    tankControlState.turretYaw = 0
                    tankControlState.turretPitch = 0
                end
            end
            
            updateJoystickVisuals()
        end)
        
        UserInputService.TouchEnded:Connect(function(touch, processed)
            leftJoystick.active = false
            rightJoystick.active = false
            tankControlState.forward = 0
            tankControlState.turn = 0
            tankControlState.moving = false
            tankControlState.turretYaw = 0
            tankControlState.turretPitch = 0
            updateJoystickVisuals()
        end)
        
        -- Keyboard fallback controls
        UserInputService.InputBegan:Connect(function(input, processed)
            if processed or not tankActive or not tankControlState.insideTank then return end
            
            if input.KeyCode == Enum.KeyCode.W then
                tankControlState.forward = 1
            elseif input.KeyCode == Enum.KeyCode.S then
                tankControlState.forward = -1
            elseif input.KeyCode == Enum.KeyCode.A then
                tankControlState.turn = -1
            elseif input.KeyCode == Enum.KeyCode.D then
                tankControlState.turn = 1
            elseif input.KeyCode == Enum.KeyCode.F then
                shootProjectile()
            elseif input.KeyCode == Enum.KeyCode.H then
                toggleHatch()
            end
            
            tankControlState.moving = tankControlState.forward ~= 0 or tankControlState.turn ~= 0
        end)
        
        UserInputService.InputEnded:Connect(function(input, processed)
            if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.S then
                tankControlState.forward = 0
            elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.D then
                tankControlState.turn = 0
            end
            tankControlState.moving = tankControlState.forward ~= 0 or tankControlState.turn ~= 0
        end)
        
        -- Drag functionality
        local dragging = false
        local dragStartM = Vector2.zero
        local dragStartPos = UDim2.new()
        
        titleBar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStartM = Vector2.new(inp.Position.X, inp.Position.Y)
                dragStartPos = panel.Position
            end
        end)
        
        UserInputService.InputChanged:Connect(function(inp)
            if not dragging then return end
            if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
                local d = Vector2.new(inp.Position.X, inp.Position.Y) - dragStartM
                panel.Position = UDim2.new(dragStartPos.X.Scale, dragStartPos.X.Offset + d.X,
                                           dragStartPos.Y.Scale, dragStartPos.Y.Offset + d.Y)
            end
        end)
        
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        
        -- Activate tank
        tankActive = true
    end

    -- SPHERE BENDER GUI
    local function destroySphereBenderGui()
        if sbSubGui and sbSubGui.Parent then sbSubGui:Destroy() end
        sbSubGui = nil
    end

    local rebuildSBGui

    rebuildSBGui = function()
        destroySphereBenderGui()
        local pg = player:WaitForChild("PlayerGui")
        local sg = Instance.new("ScreenGui")
        sg.Name           = "SphereBenderGUI"
        sg.ResetOnSpawn   = false
        sg.DisplayOrder   = 1001
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Parent         = pg
        sbSubGui          = sg

        local W = 210

        local panel = Instance.new("Frame")
        panel.Size             = UDim2.fromOffset(W, 300)
        panel.Position         = UDim2.new(0.5, -W - 10, 0.5, -150)
        panel.BackgroundColor3 = Color3.fromRGB(5, 8, 20)
        panel.BorderSizePixel  = 0
        panel.ClipsDescendants = false
        panel.Parent           = sg
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

        local stroke     = Instance.new("UIStroke", panel)
        stroke.Color     = Color3.fromRGB(0, 200, 255)
        stroke.Thickness = 1.4

        local tBar = Instance.new("Frame")
        tBar.Size             = UDim2.new(1, 0, 0, 30)
        tBar.BackgroundColor3 = Color3.fromRGB(4, 18, 40)
        tBar.BorderSizePixel  = 0
        tBar.ZIndex           = 10
        tBar.Parent           = panel
        Instance.new("UICorner", tBar).CornerRadius = UDim.new(0, 8)

        local tLbl = Instance.new("TextLabel")
        tLbl.Text                   = "SPHERE BENDER"
        tLbl.Size                   = UDim2.new(1, -8, 1, 0)
        tLbl.Position               = UDim2.fromOffset(8, 0)
        tLbl.BackgroundTransparency = 1
        tLbl.TextColor3             = Color3.fromRGB(0, 220, 255)
        tLbl.TextSize               = 12
        tLbl.Font                   = Enum.Font.GothamBold
        tLbl.TextXAlignment         = Enum.TextXAlignment.Left
        tLbl.ZIndex                 = 10
        tLbl.Parent                 = tBar

        local yOff = 34

        local function getSelectedMode()
            for _, sp in ipairs(sbSpheres) do
                if sp.selected then return sp.mode end
            end
            return "orbit"
        end

        local modeLblSB = Instance.new("TextLabel")
        modeLblSB.Text                   = "STATE: " .. getSelectedMode():upper()
        modeLblSB.Size                   = UDim2.new(1, -10, 0, 18)
        modeLblSB.Position               = UDim2.fromOffset(6, yOff)
        modeLblSB.BackgroundTransparency = 1
        modeLblSB.TextColor3             = Color3.fromRGB(0, 180, 255)
        modeLblSB.TextSize               = 10
        modeLblSB.Font                   = Enum.Font.GothamBold
        modeLblSB.TextXAlignment         = Enum.TextXAlignment.Left
        modeLblSB.Parent                 = panel
        yOff = yOff + 20

        local sbModeBtns = {
            {txt="ORBIT",  key="orbit",  col=Color3.fromRGB(80,  220, 255)},
            {txt="FOLLOW", key="follow", col=Color3.fromRGB(120, 255, 160)},
            {txt="STAY",   key="stay",   col=Color3.fromRGB(255, 200,  80)},
        }
        for _, mb in ipairs(sbModeBtns) do
            local btn = Instance.new("TextButton")
            btn.Text             = mb.txt
            btn.Size             = UDim2.new(1, -12, 0, 30)
            btn.Position         = UDim2.fromOffset(6, yOff)
            btn.BackgroundColor3 = Color3.fromRGB(6, 18, 36)
            btn.TextColor3       = mb.col
            btn.TextSize         = 11
            btn.Font             = Enum.Font.GothamBold
            btn.BorderSizePixel  = 0
            btn.Parent           = panel
            Instance.new("UICorner", btn)
            local bs     = Instance.new("UIStroke", btn)
            bs.Color     = Color3.fromRGB(0, 140, 200)
            bs.Thickness = 1
            btn.MouseButton1Click:Connect(function()
                local changed = false
                for _, sp in ipairs(sbSpheres) do
                    if sp.selected then
                        sp.mode    = mb.key
                        sp.stopped = false
                        sp.vel     = Vector3.zero
                        changed    = true
                    end
                end
                if changed then
                    modeLblSB.Text = "STATE: " .. mb.key:upper()
                end
            end)
            yOff = yOff + 36
        end

        local div = Instance.new("Frame")
        div.Size             = UDim2.new(1, -12, 0, 1)
        div.Position         = UDim2.fromOffset(6, yOff + 4)
        div.BackgroundColor3 = Color3.fromRGB(0, 100, 160)
        div.BorderSizePixel  = 0
        div.Parent           = panel
        yOff = yOff + 14

        local stopBtn = Instance.new("TextButton")
        stopBtn.Text             = "STOP"
        stopBtn.Size             = UDim2.new(0.48, -6, 0, 28)
        stopBtn.Position         = UDim2.fromOffset(6, yOff)
        stopBtn.BackgroundColor3 = Color3.fromRGB(60, 8, 8)
        stopBtn.TextColor3       = Color3.fromRGB(255, 60, 60)
        stopBtn.TextSize         = 11
        stopBtn.Font             = Enum.Font.GothamBold
        stopBtn.BorderSizePixel  = 0
        stopBtn.Parent           = panel
        Instance.new("UICorner", stopBtn)

        local goBtn = Instance.new("TextButton")
        goBtn.Text             = "GO"
        goBtn.Size             = UDim2.new(0.48, -6, 0, 28)
        goBtn.Position         = UDim2.new(0.5, 3, 0, yOff)
        goBtn.BackgroundColor3 = Color3.fromRGB(8, 50, 8)
        goBtn.TextColor3       = Color3.fromRGB(60, 255, 100)
        goBtn.TextSize         = 11
        goBtn.Font             = Enum.Font.GothamBold
        goBtn.BorderSizePixel  = 0
        goBtn.Parent           = panel
        Instance.new("UICorner", goBtn)

        stopBtn.MouseButton1Click:Connect(function()
            for _, sp in ipairs(sbSpheres) do
                if sp.selected then
                    sp.stopped = true
                    sp.vel     = Vector3.zero
                end
            end
            modeLblSB.Text = "STATE: STOPPED"
        end)

        goBtn.MouseButton1Click:Connect(function()
            for _, sp in ipairs(sbSpheres) do
                if sp.selected then
                    sp.stopped = false
                    sp.vel     = Vector3.zero
                end
            end
            modeLblSB.Text = "STATE: " .. getSelectedMode():upper()
        end)
        yOff = yOff + 34

        local splitBtn = Instance.new("TextButton")
        splitBtn.Text             = "SPLIT SPHERE"
        splitBtn.Size             = UDim2.new(1, -12, 0, 28)
        splitBtn.Position         = UDim2.fromOffset(6, yOff)
        splitBtn.BackgroundColor3 = Color3.fromRGB(10, 30, 55)
        splitBtn.TextColor3       = Color3.fromRGB(0, 200, 255)
        splitBtn.TextSize         = 11
        splitBtn.Font             = Enum.Font.GothamBold
        splitBtn.BorderSizePixel  = 0
        splitBtn.Parent           = panel
        Instance.new("UICorner", splitBtn)
        local splitStroke     = Instance.new("UIStroke", splitBtn)
        splitStroke.Color     = Color3.fromRGB(0, 180, 255)
        splitStroke.Thickness = 1.2

        splitBtn.MouseButton1Click:Connect(function()
            local char = player.Character
            local root = char and (
                char:FindFirstChild("HumanoidRootPart") or
                char:FindFirstChild("Torso"))
            local startPos = root and root.Position or Vector3.new(0, 5, 0)
            local offset   = Vector3.new(
                math.random(-4, 4), 2, math.random(-4, 4))
            local newSphere = newSBSphere(startPos + offset)
            table.insert(sbSpheres, newSphere)
            rebuildSBGui()
        end)
        yOff = yOff + 34

        local listHeader = Instance.new("TextLabel")
        listHeader.Text                   = "SPHERES"
        listHeader.Size                   = UDim2.new(1, -10, 0, 18)
        listHeader.Position               = UDim2.fromOffset(6, yOff)
        listHeader.BackgroundTransparency = 1
        listHeader.TextColor3             = Color3.fromRGB(0, 160, 220)
        listHeader.TextSize               = 10
        listHeader.Font                   = Enum.Font.GothamBold
        listHeader.TextXAlignment         = Enum.TextXAlignment.Left
        listHeader.Parent                 = panel
        yOff = yOff + 20

        for idx, sp in ipairs(sbSpheres) do
            local label = "SPHERE " .. idx

            local sBtn = Instance.new("TextButton")
            sBtn.Text             = label
                .. (sp.stopped and "  [STOPPED]" or "  [" .. sp.mode:upper() .. "]")
            sBtn.Size             = UDim2.new(1, -12, 0, 28)
            sBtn.Position         = UDim2.fromOffset(6, yOff)
            sBtn.BackgroundColor3 = sp.selected
                and Color3.fromRGB(0, 60, 120)
                or  Color3.fromRGB(6, 18, 36)
            sBtn.TextColor3       = sp.selected
                and Color3.fromRGB(80, 200, 255)
                or  Color3.fromRGB(140, 140, 180)
            sBtn.TextSize         = 10
            sBtn.Font             = Enum.Font.GothamBold
            sBtn.BorderSizePixel  = 0
            sBtn.Parent           = panel
            Instance.new("UICorner", sBtn)

            local sBtnStroke     = Instance.new("UIStroke", sBtn)
            sBtnStroke.Color     = sp.selected
                and Color3.fromRGB(0, 180, 255)
                or  Color3.fromRGB(30, 60, 100)
            sBtnStroke.Thickness = sp.selected and 1.5 or 0.8

            local capturedSp     = sp
            local capturedBtn    = sBtn
            local capturedStroke = sBtnStroke

            sBtn.MouseButton1Click:Connect(function()
                capturedSp.selected      = not capturedSp.selected
                capturedBtn.BackgroundColor3 = capturedSp.selected
                    and Color3.fromRGB(0, 60, 120)
                    or  Color3.fromRGB(6, 18, 36)
                capturedBtn.TextColor3   = capturedSp.selected
                    and Color3.fromRGB(80, 200, 255)
                    or  Color3.fromRGB(140, 140, 180)
                capturedStroke.Color     = capturedSp.selected
                    and Color3.fromRGB(0, 180, 255)
                    or  Color3.fromRGB(30, 60, 100)
                capturedStroke.Thickness = capturedSp.selected and 1.5 or 0.8
                modeLblSB.Text = "STATE: " .. getSelectedMode():upper()
            end)

            yOff = yOff + 34
        end

        panel.Size = UDim2.fromOffset(W, yOff + 8)

        local dragging     = false
        local dragStartM   = Vector2.zero
        local dragStartPos = UDim2.new()

        tBar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging     = true
                dragStartM   = Vector2.new(inp.Position.X, inp.Position.Y)
                dragStartPos = panel.Position
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if not dragging then return end
            if inp.UserInputType == Enum.UserInputType.MouseMovement
                or inp.UserInputType == Enum.UserInputType.Touch then
                local d = Vector2.new(
                    inp.Position.X, inp.Position.Y) - dragStartM
                panel.Position = UDim2.new(
                    dragStartPos.X.Scale, dragStartPos.X.Offset + d.X,
                    dragStartPos.Y.Scale, dragStartPos.Y.Offset + d.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    -- MAIN LOOP
    local function mainLoop()
        RunService.Heartbeat:Connect(function(dt)
            if not scriptAlive then return end

            snakeT  = snakeT  + dt
            gasterT = gasterT + dt

            local char = player.Character
            local root = char and (
                char:FindFirstChild("HumanoidRootPart") or
                char:FindFirstChild("Torso"))
            if not root then return end

            local pos = root.Position
            local cf  = root.CFrame
            local t   = tick()

            if activeMode == "sphere" then
                updateSphereTarget(dt, pos)
            end

            if activeMode == "spherebender" then
                updateSphereBenderTargets(dt, pos)
            end

            if activeMode == "tank" then
                updateTank(dt, pos, cf)
            end

            table.insert(snakeHistory, 1, pos)
            if #snakeHistory > SNAKE_HIST_MAX then
                table.remove(snakeHistory, SNAKE_HIST_MAX + 1)
            end

            if activeMode ~= lastMode then
                SetModeEvent:FireServer(activeMode)
                
                if GASTER_MODES[activeMode] then
                    createGasterGui()
                else
                    destroyGasterGui()
                end
                if SPHERE_MODES[activeMode] then
                    spherePos = pos + Vector3.new(0, 1.5, 4)
                    sphereVel = Vector3.zero
                    createSphereGui()
                else
                    destroySphereGui()
                end
                if SPHERE_BENDER_MODES[activeMode] then
                    if #sbSpheres == 0 then
                        local startPos = pos + Vector3.new(0, 1.5, 4)
                        local s = newSBSphere(startPos)
                        s.selected = true
                        table.insert(sbSpheres, s)
                    end
                    rebuildSBGui()
                else
                    destroySphereBenderGui()
                    sbSpheres = {}
                end
                if TANK_MODES[activeMode] then
                    tankActive = true
                    createTankGui()
                    createTankBase(pos, cf)
                else
                    if tankActive then
                        destroyTank()
                        destroyTankGui()
                        workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
                    end
                end
                lastMode = activeMode
            end

            if not isActivated or activeMode == "none" or partCount == 0 then
                return
            end

            local arr = {}
            for part, data in pairs(controlled) do
                if part.Parent then
                    table.insert(arr, {p=part, d=data})
                else
                    controlled[part] = nil
                    partCount = math.max(0, partCount - 1)
                end
            end

            local n = #arr

            -- Skip position updates for tank mode (handled separately)
            if activeMode == "tank" then
                return
            end

            for i, item in ipairs(arr) do
                local part = item.p
                local data = item.d
                local targetCF

                if activeMode == "snake" then
                    local tgt = getSnakeTarget(i)
                    targetCF = CFrame.new(tgt)

                elseif activeMode == "gasterhand" then
                    if i <= HAND_SLOTS_COUNT then
                        targetCF = getGasterCF(i, 1, cf, gasterT)
                    else
                        targetCF = CFrame.new(0, -5000, 0)
                    end

                elseif activeMode == "gaster2hands" then
                    if i <= HAND_SLOTS_COUNT then
                        targetCF = getGasterCF(i, 1, cf, gasterT)
                    elseif i <= HAND_SLOTS_COUNT * 2 then
                        targetCF = getGasterCF(
                            i - HAND_SLOTS_COUNT, -1, cf, gasterT)
                    else
                        targetCF = CFrame.new(0, -5000, 0)
                    end

                elseif activeMode == "sphere" then
                    local offset = getSphereShellPos(i, n)
                    local spinT = t * 3
                    targetCF = CFrame.new(spherePos)
                        * CFrame.Angles(spinT, spinT * 1.3, spinT * 0.7)
                        * CFrame.new(offset)

                elseif activeMode == "spherebender" then
                    local numSpheres = math.max(1, #sbSpheres)
                    local partsPerSph = math.max(1, math.ceil(n / numSpheres))
                    local sphIdx = math.min(
                        math.ceil(i / partsPerSph), numSpheres)
                    local sphere = sbSpheres[sphIdx]
                    local localI = ((i - 1) % partsPerSph) + 1
                    local localTotal = math.max(
                        math.min(partsPerSph, n - (sphIdx - 1) * partsPerSph), 1)
                    local offset = getSphereShellPos(localI, localTotal)
                    local spinT = t * 3
                    targetCF = CFrame.new(sphere.pos)
                        * CFrame.Angles(spinT, spinT * 1.3, spinT * 0.7)
                        * CFrame.new(offset)

                elseif CFRAME_MODES[activeMode] then
                    targetCF = getFormationCF(activeMode, i, n, pos, cf, t)
                end

                if targetCF then
                    UpdatePositionEvent:FireServer(part, targetCF)
                end
            end
        end)
    end

    -- SCAN LOOP
    local function scanLoop()
        while scriptAlive do
            if isActivated and activeMode ~= "none" and activeMode ~= "tank" then
                sweepMap()
            end
            task.wait(1.5)
        end
    end

    -- MAIN GUI
    local function createGUI()
        local pg  = player:WaitForChild("PlayerGui")
        local old = pg:FindFirstChild("ManipGUI")
        if old then old:Destroy() end

        local gui = Instance.new("ScreenGui")
        gui.Name           = "ManipGUI"
        gui.ResetOnSpawn   = false
        gui.DisplayOrder   = 999
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent         = pg

        local W, H = 260, 540
        local panel = Instance.new("Frame")
        panel.Name             = "Panel"
        panel.Size             = UDim2.fromOffset(W, H)
        panel.Position         = UDim2.new(0.5, -W/2, 0.5, -H/2)
        panel.BackgroundColor3 = Color3.fromRGB(10, 10, 25)
        panel.BorderSizePixel  = 0
        panel.ClipsDescendants = true
        panel.Parent           = gui
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

        local pStroke     = Instance.new("UIStroke", panel)
        pStroke.Color     = Color3.fromRGB(90, 40, 180)
        pStroke.Thickness = 1.5

        local titleBar = Instance.new("Frame")
        titleBar.Size             = UDim2.new(1, 0, 0, 34)
        titleBar.BackgroundColor3 = Color3.fromRGB(20, 10, 48)
        titleBar.BorderSizePixel  = 0
        titleBar.ZIndex           = 10
        titleBar.Parent           = panel
        Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

        local titleTxt = Instance.new("TextLabel")
        titleTxt.Text                   = "MANIPULATOR KII"
        titleTxt.Size                   = UDim2.new(1, -70, 1, 0)
        titleTxt.Position               = UDim2.fromOffset(8, 0)
        titleTxt.BackgroundTransparency = 1
        titleTxt.TextColor3             = Color3.fromRGB(195, 140, 255)
        titleTxt.TextSize               = 12
        titleTxt.Font                   = Enum.Font.GothamBold
        titleTxt.TextXAlignment         = Enum.TextXAlignment.Left
        titleTxt.ZIndex                 = 10
        titleTxt.Parent                 = titleBar

        local closeBtn = Instance.new("TextButton")
        closeBtn.Text             = "X"
        closeBtn.Size             = UDim2.fromOffset(26, 24)
        closeBtn.Position         = UDim2.new(1, -30, 0, 5)
        closeBtn.BackgroundColor3 = Color3.fromRGB(150, 25, 25)
        closeBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
        closeBtn.TextSize         = 11
        closeBtn.Font             = Enum.Font.GothamBold
        closeBtn.BorderSizePixel  = 0
        closeBtn.ZIndex           = 11
        closeBtn.Parent           = titleBar
        Instance.new("UICorner", closeBtn)

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size                   = UDim2.new(1, 0, 1, -34)
        scroll.Position               = UDim2.fromOffset(0, 34)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel        = 0
        scroll.ScrollBarThickness     = 3
        scroll.ScrollBarImageColor3   = Color3.fromRGB(90, 40, 180)
        scroll.CanvasSize             = UDim2.fromOffset(0, 0)
        scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
        scroll.Parent                 = panel

        local layout = Instance.new("UIListLayout", scroll)
        layout.Padding             = UDim.new(0, 4)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.SortOrder           = Enum.SortOrder.LayoutOrder

        local pad = Instance.new("UIPadding", scroll)
        pad.PaddingTop    = UDim.new(0, 5)
        pad.PaddingBottom = UDim.new(0, 8)
        pad.PaddingLeft   = UDim.new(0, 6)
        pad.PaddingRight  = UDim.new(0, 6)

        local function sLabel(txt, order)
            local l = Instance.new("TextLabel")
            l.Text                   = txt
            l.Size                   = UDim2.new(1, 0, 0, 18)
            l.BackgroundTransparency = 1
            l.TextColor3             = Color3.fromRGB(180, 130, 255)
            l.TextSize               = 10
            l.Font                   = Enum.Font.GothamBold
            l.TextXAlignment         = Enum.TextXAlignment.Left
            l.LayoutOrder            = order
            l.Parent                 = scroll
        end

        local function makeSingleBtn(txt, bgCol, txtCol, order)
            local b = Instance.new("TextButton")
            b.Text             = txt
            b.Size             = UDim2.new(1, 0, 0, 30)
            b.BackgroundColor3 = bgCol
            b.TextColor3       = txtCol
            b.TextSize         = 10
            b.Font             = Enum.Font.GothamBold
            b.BorderSizePixel  = 0
            b.LayoutOrder      = order
            b.Parent           = scroll
            Instance.new("UICorner", b)
            return b
        end

        local function makeSettingRow(labelTxt, default, hint, order)
            local row = Instance.new("Frame")
            row.Size             = UDim2.new(1, 0, 0, 40)
            row.BackgroundColor3 = Color3.fromRGB(16, 16, 38)
            row.BorderSizePixel  = 0
            row.LayoutOrder      = order
            row.Parent           = scroll
            Instance.new("UICorner", row)

            local lbl = Instance.new("TextLabel")
            lbl.Text                   = labelTxt
            lbl.Size                   = UDim2.new(0.55, 0, 0, 20)
            lbl.Position               = UDim2.fromOffset(6, 3)
            lbl.BackgroundTransparency = 1
            lbl.TextColor3             = Color3.fromRGB(155, 155, 255)
            lbl.TextSize               = 10
            lbl.Font                   = Enum.Font.GothamBold
            lbl.TextXAlignment         = Enum.TextXAlignment.Left
            lbl.TextWrapped            = true
            lbl.Parent                 = row

            local tb = Instance.new("TextBox")
            tb.Text             = tostring(default)
            tb.Size             = UDim2.new(0.38, 0, 0, 20)
            tb.Position         = UDim2.new(0.59, 0, 0, 3)
            tb.BackgroundColor3 = Color3.fromRGB(28, 28, 55)
            tb.TextColor3       = Color3.fromRGB(255, 255, 255)
            tb.TextSize         = 10
            tb.Font             = Enum.Font.Gotham
            tb.ClearTextOnFocus = false
            tb.BorderSizePixel  = 0
            tb.Parent           = row
            Instance.new("UICorner", tb)

            local hintLbl = Instance.new("TextLabel")
            hintLbl.Text                   = hint
            hintLbl.Size                   = UDim2.new(1, -6, 0, 12)
            hintLbl.Position               = UDim2.fromOffset(6, 25)
            hintLbl.BackgroundTransparency = 1
            hintLbl.TextColor3             = Color3.fromRGB(80, 80, 130)
            hintLbl.TextSize               = 8
            hintLbl.Font                   = Enum.Font.Gotham
            hintLbl.TextXAlignment         = Enum.TextXAlignment.Left
            hintLbl.Parent                 = row

            return tb
        end

        sLabel("STATUS", 1)

        local statusLbl = Instance.new("TextLabel")
        statusLbl.Text                   = "IDLE  |  PARTS: 0"
        statusLbl.Size                   = UDim2.new(1, 0, 0, 18)
        statusLbl.BackgroundTransparency = 1
        statusLbl.TextColor3             = Color3.fromRGB(80, 255, 140)
        statusLbl.TextSize               = 10
        statusLbl.Font                   = Enum.Font.GothamBold
        statusLbl.TextXAlignment         = Enum.TextXAlignment.Left
        statusLbl.LayoutOrder            = 2
        statusLbl.Parent                 = scroll

        local modeLbl = Instance.new("TextLabel")
        modeLbl.Text                   = "MODE: NONE"
        modeLbl.Size                   = UDim2.new(1, 0, 0, 16)
        modeLbl.BackgroundTransparency = 1
        modeLbl.TextColor3             = Color3.fromRGB(130, 130, 255)
        modeLbl.TextSize               = 10
        modeLbl.Font                   = Enum.Font.GothamBold
        modeLbl.TextXAlignment         = Enum.TextXAlignment.Left
        modeLbl.LayoutOrder            = 3
        modeLbl.Parent                 = scroll

        task.spawn(function()
            while panel.Parent and scriptAlive do
                statusLbl.Text = isActivated
                    and ("ACTIVE  |  PARTS: " .. partCount)
                    or  "IDLE  |  PARTS: 0"
                task.wait(0.5)
            end
        end)

        sLabel("STANDARD MODES", 4)

        local stdRows  = math.ceil(6 / 2)
        local stdGridH = stdRows * 32 + (stdRows - 1) * 3
        local stdFrame = Instance.new("Frame")
        stdFrame.Size                   = UDim2.new(1, 0, 0, stdGridH)
        stdFrame.BackgroundTransparency = 1
        stdFrame.LayoutOrder            = 5
        stdFrame.Parent                 = scroll

        local stdGL = Instance.new("UIGridLayout", stdFrame)
        stdGL.CellSize            = UDim2.new(0.5, -3, 0, 32)
        stdGL.CellPadding         = UDim2.fromOffset(3, 3)
        stdGL.HorizontalAlignment = Enum.HorizontalAlignment.Left
        stdGL.SortOrder           = Enum.SortOrder.LayoutOrder

        local stdModes = {
            {txt="SNAKE",      mode="snake",     col=Color3.fromRGB(160, 110, 255)},
            {txt="HEART",      mode="heart",     col=Color3.fromRGB(255, 100, 150)},
            {txt="RINGS",      mode="rings",     col=Color3.fromRGB( 80, 210, 255)},
            {txt="WALL",       mode="wall",      col=Color3.fromRGB(255, 200,  90)},
            {txt="BOX CAGE",   mode="box",       col=Color3.fromRGB(160, 255, 100)},
            {txt="WINGS",      mode="wings",     col=Color3.fromRGB(100, 220, 255)},
        }

        for idx, m in ipairs(stdModes) do
            local btn = Instance.new("TextButton")
            btn.Text             = m.txt
            btn.BackgroundColor3 = Color3.fromRGB(26, 14, 55)
            btn.TextColor3       = m.col
            btn.TextSize         = 10
            btn.Font             = Enum.Font.GothamBold
            btn.BorderSizePixel  = 0
            btn.LayoutOrder      = idx
            btn.Parent           = stdFrame
            Instance.new("UICorner", btn)

            btn.MouseButton1Click:Connect(function()
                if GASTER_MODES[activeMode]       then destroyGasterGui()       end
                if SPHERE_MODES[activeMode]        then destroySphereGui()       end
                if SPHERE_BENDER_MODES[activeMode] then destroySphereBenderGui() end
                if TANK_MODES[activeMode]          then destroyTank() destroyTankGui() end
                activeMode   = m.mode
                isActivated  = true
                modeLbl.Text = "MODE: " .. m.mode:upper()
                SetModeEvent:FireServer(m.mode)
                sweepMap()
            end)
        end

        sLabel("SPECIAL MODES", 6)

        local spRows  = math.ceil(5 / 2)
        local spGridH = spRows * 32 + (spRows - 1) * 3
        local spFrame = Instance.new("Frame")
        spFrame.Size                   = UDim2.new(1, 0, 0, spGridH)
        spFrame.BackgroundTransparency = 1
        spFrame.LayoutOrder            = 7
        spFrame.Parent                 = scroll

        local spGL = Instance.new("UIGridLayout", spFrame)
        spGL.CellSize            = UDim2.new(0.5, -3, 0, 32)
        spGL.CellPadding         = UDim2.fromOffset(3, 3)
        spGL.HorizontalAlignment = Enum.HorizontalAlignment.Left
        spGL.SortOrder           = Enum.SortOrder.LayoutOrder

        local specialModes = {
            {txt="GASTER HAND",    mode="gasterhand",   col=Color3.fromRGB(180,  80, 255)},
            {txt="2 GASTER HANDS", mode="gaster2hands", col=Color3.fromRGB(220, 110, 255)},
            {txt="SPHERE",         mode="sphere",        col=Color3.fromRGB( 60, 210, 255)},
            {txt="SPHERE BENDER",  mode="spherebender",  col=Color3.fromRGB(  0, 230, 255)},
            {txt="TANK",           mode="tank",          col=Color3.fromRGB(100, 200,  80)},
        }

        for idx, m in ipairs(specialModes) do
            local btn = Instance.new("TextButton")
            btn.Text             = m.txt
            btn.BackgroundColor3 = Color3.fromRGB(30, 8, 58)
            btn.TextColor3       = m.col
            btn.TextSize         = 10
            btn.Font             = Enum.Font.GothamBold
            btn.BorderSizePixel  = 0
            btn.LayoutOrder      = idx
            btn.Parent           = spFrame
            Instance.new("UICorner", btn)

            local bs     = Instance.new("UIStroke", btn)
            bs.Color     = Color3.fromRGB(160, 50, 255)
            bs.Thickness = 1

            btn.MouseButton1Click:Connect(function()
                destroyGasterGui()
                destroySphereGui()
                destroySphereBenderGui()
                if TANK_MODES[activeMode] then destroyTank() destroyTankGui() end
                activeMode   = m.mode
                isActivated  = true
                modeLbl.Text = "MODE: " .. m.mode:upper()
                SetModeEvent:FireServer(m.mode)
                
                if GASTER_MODES[m.mode] then
                    createGasterGui()
                elseif SPHERE_MODES[m.mode] then
                    createSphereGui()
                elseif SPHERE_BENDER_MODES[m.mode] then
                    sbSpheres = {}
                    local char = player.Character
                    local root = char and (
                        char:FindFirstChild("HumanoidRootPart") or
                        char:FindFirstChild("Torso"))
                    local startPos = root and root.Position
                        or Vector3.new(0, 5, 0)
                    local s = newSBSphere(startPos + Vector3.new(0, 2, 4))
                    s.selected = true
                    table.insert(sbSpheres, s)
                    rebuildSBGui()
                elseif TANK_MODES[m.mode] then
                    tankActive = true
                    createTankGui()
                    local char = player.Character
                    local root = char and (
                        char:FindFirstChild("HumanoidRootPart") or
                        char:FindFirstChild("Torso"))
                    local startPos = root and root.Position or Vector3.new(0, 5, 0)
                    local startCF = root and root.CFrame or CFrame.new(startPos)
                    createTankBase(startPos, startCF)
                end
                sweepMap()
            end)
        end

        sLabel("SETTINGS", 8)

        local pullTB  = makeSettingRow("PULL STRENGTH",  1500, "snake speed", 9)
        local radTB   = makeSettingRow("RADIUS (studs)",    7, "formation spread", 10)
        local rangeTB = makeSettingRow("DETECT RANGE",   9999, "studs (9999=full map)", 11)

        pullTB.FocusLost:Connect(function()
            local v = tonumber(pullTB.Text:match("^%s*(.-)%s*$"))
            if v and v > 0 then
                pullStrength = v
                pullTB.Text = tostring(v)
            else
                pullTB.Text = tostring(pullStrength)
            end
        end)

        radTB.FocusLost:Connect(function()
            local v = tonumber(radTB.Text:match("^%s*(.-)%s*$"))
            if v and v > 0 then
                radius = v
                radTB.Text = tostring(v)
            else
                radTB.Text = tostring(radius)
            end
        end)

        rangeTB.FocusLost:Connect(function()
            local v = tonumber(rangeTB.Text:match("^%s*(.-)%s*$"))
            if v and v > 0 then
                detectionRange = v
                rangeTB.Text   = tostring(v)
            else
                rangeTB.Text = tostring(detectionRange)
            end
        end)

        sLabel("ACTIONS", 12)

        local scanBtn = makeSingleBtn(
            "SCAN PARTS",
            Color3.fromRGB(18, 60, 22),  Color3.fromRGB(80, 255, 120), 13)
        local releaseBtn = makeSingleBtn(
            "RELEASE ALL",
            Color3.fromRGB(60, 32, 8),   Color3.fromRGB(255, 155, 55), 14)
        local deactivateBtn = makeSingleBtn(
            "DEACTIVATE",
            Color3.fromRGB(75, 8, 8),    Color3.fromRGB(255, 55, 55),  15)

        scanBtn.MouseButton1Click:Connect(function()
            sweepMap()
        end)

        releaseBtn.MouseButton1Click:Connect(function()
            releaseAll()
            destroyGasterGui()
            destroySphereGui()
            destroySphereBenderGui()
            if TANK_MODES[activeMode] then destroyTank() destroyTankGui() end
            sbSpheres    = {}
            isActivated  = false
            activeMode   = "none"
            lastMode     = "none"
            modeLbl.Text = "MODE: NONE"
            workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        end)

        deactivateBtn.MouseButton1Click:Connect(function()
            releaseAll()
            destroyGasterGui()
            destroySphereGui()
            destroySphereBenderGui()
            if TANK_MODES[activeMode] then destroyTank() destroyTankGui() end
            sbSpheres   = {}
            isActivated = false
            activeMode  = "none"
            scriptAlive = false
            gui:Destroy()
            local icon = pg:FindFirstChild("ManipIcon")
            if icon then icon:Destroy() end
            workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
            print("MANIPULATOR KII -- Deactivated.")
        end)

        closeBtn.MouseButton1Click:Connect(function()
            gui:Destroy()
            local miniGui = Instance.new("ScreenGui")
            miniGui.Name         = "ManipIcon"
            miniGui.ResetOnSpawn = false
            miniGui.DisplayOrder = 999
            miniGui.Parent       = pg

            local ib = Instance.new("TextButton")
            ib.Text             = "M"
            ib.Size             = UDim2.fromOffset(36, 36)
            ib.Position         = UDim2.new(1, -44, 0, 8)
            ib.BackgroundColor3 = Color3.fromRGB(22, 10, 50)
            ib.TextColor3       = Color3.fromRGB(195, 140, 255)
            ib.TextSize         = 13
            ib.Font             = Enum.Font.GothamBold
            ib.BorderSizePixel  = 0
            ib.Parent           = miniGui
            Instance.new("UICorner", ib)

            local ibStroke     = Instance.new("UIStroke", ib)
            ibStroke.Color     = Color3.fromRGB(90, 40, 180)
            ibStroke.Thickness = 1.5

            ib.MouseButton1Click:Connect(function()
                miniGui:Destroy()
                createGUI()
                if GASTER_MODES[activeMode]       then createGasterGui() end
                if SPHERE_MODES[activeMode]        then createSphereGui() end
                if SPHERE_BENDER_MODES[activeMode] then rebuildSBGui()    end
                if TANK_MODES[activeMode]          then createTankGui()   end
            end)
        end)

        local dragging     = false
        local dragStartM   = Vector2.zero
        local dragStartPos = UDim2.new()

        local function startDrag(inp)
            dragging     = true
            dragStartM   = Vector2.new(inp.Position.X, inp.Position.Y)
            dragStartPos = panel.Position
        end

        titleBar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                startDrag(inp)
            end
        end)
        panel.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                if not dragging then startDrag(inp) end
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if not dragging then return end
            if inp.UserInputType == Enum.UserInputType.MouseMovement
                or inp.UserInputType == Enum.UserInputType.Touch then
                local delta = Vector2.new(
                    inp.Position.X, inp.Position.Y) - dragStartM
                panel.Position = UDim2.new(
                    dragStartPos.X.Scale, dragStartPos.X.Offset + delta.X,
                    dragStartPos.Y.Scale, dragStartPos.Y.Offset + delta.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    createGUI()
    task.spawn(mainLoop)
    task.spawn(scanLoop)
end

main()
