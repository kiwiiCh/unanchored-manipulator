-- Copy this entire script into Delta executor and run it directly:

local player = game:GetService("Players").LocalPlayer
local runService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local userInput = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")

print("⚔️ UNANCHORED MANIPULATOR KII VERSION")
print("🛡️ GALAXY THEMED MANIPULATOR INITIALIZED")
print("🎯 FOR: " .. player.Name)

-- Configuration variables
local pullStrength = 200
local radius = 5
local isActivated = false
local activeMode = "none"
local manipulatorParts = {}
local galaxyColor = Color3.fromRGB(100, 50, 200)

-- Create galaxy-themed GUI
local function createGalaxyGUI()
    -- Main GUI container
    local mainGui = Instance.new("ScreenGui")
    mainGui.Name = "UnanchoredManipulatorGUI"
    mainGui.ResetOnSpawn = false
    mainGui.Parent = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
    
    -- Galaxy background
    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.new(0, 350, 0, 300)
    background.Position = UDim2.new(0.5, -175, 0.5, -150)
    background.BackgroundColor3 = Color3.fromRGB(10, 10, 30)
    background.BorderSizePixel = 0
    background.BackgroundTransparency = 0.3
    background.Parent = mainGui
    
    -- Title bar with galaxy style
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundColor3 = Color3.fromRGB(30, 20, 60)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = background
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Text = "🌌 UNANCHORED MANIPULATOR KII"
    title.Size = UDim2.new(1, -40, 1, 0)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(200, 150, 255)
    title.TextSize = 16
    title.Font = Enum.Font.SourceSansBold
    title.Parent = titleBar
    
    -- Close button
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Text = "✕"
    closeButton.Size = UDim2.new(0, 30, 0, 30)
    closeButton.Position = UDim2.new(1, -35, 0, 5)
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.TextSize = 18
    closeButton.Font = Enum.Font.SourceSansBold
    closeButton.Parent = titleBar
    
    -- Star decoration
    local star = Instance.new("ImageLabel")
    star.Name = "Star"
    star.Size = UDim2.new(0, 20, 0, 20)
    star.Position = UDim2.new(0, 10, 0, 10)
    star.BackgroundTransparency = 1
    star.Image = "rbxasset://textures/ui/star.png"
    star.ImageColor3 = Color3.fromRGB(255, 255, 200)
    star.Parent = titleBar
    
    -- Mode selection buttons (galaxy themed)
    local modesFrame = Instance.new("Frame")
    modesFrame.Name = "ModesFrame"
    modesFrame.Size = UDim2.new(0, 330, 0, 120)
    modesFrame.Position = UDim2.new(0, 10, 0, 50)
    modesFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
    modesFrame.BorderSizePixel = 1
    modesFrame.BorderColor3 = Color3.fromRGB(100, 50, 200)
    modesFrame.Parent = background
    
    local snakeButton = Instance.new("TextButton")
    snakeButton.Name = "SnakeButton"
    snakeButton.Text = "🐍 SNAKE"
    snakeButton.Size = UDim2.new(0, 70, 0, 30)
    snakeButton.Position = UDim2.new(0, 10, 0, 10)
    snakeButton.BackgroundColor3 = Color3.fromRGB(50, 30, 80)
    snakeButton.TextColor3 = Color3.fromRGB(150, 100, 255)
    snakeButton.TextSize = 12
    snakeButton.Font = Enum.Font.SourceSansBold
    snakeButton.Parent = modesFrame
    
    local heartButton = Instance.new("TextButton")
    heartButton.Name = "HeartButton"
    heartButton.Text = "💕 HEART"
    heartButton.Size = UDim2.new(0, 70, 0, 30)
    heartButton.Position = UDim2.new(0, 90, 0, 10)
    heartButton.BackgroundColor3 = Color3.fromRGB(50, 30, 80)
    heartButton.TextColor3 = Color3.fromRGB(255, 100, 150)
    heartButton.TextSize = 12
    heartButton.Font = Enum.Font.SourceSansBold
    heartButton.Parent = modesFrame
    
    local ringsButton = Instance.new("TextButton")
    ringsButton.Name = "RingsButton"
    ringsButton.Text = "🛰️ RINGS"
    ringsButton.Size = UDim2.new(0, 70, 0, 30)
    ringsButton.Position = UDim2.new(0, 170, 0, 10)
    ringsButton.BackgroundColor3 = Color3.fromRGB(50, 30, 80)
    ringsButton.TextColor3 = Color3.fromRGB(100, 200, 255)
    ringsButton.TextSize = 12
    ringsButton.Font = Enum.Font.SourceSansBold
    ringsButton.Parent = modesFrame
    
    local wallButton = Instance.new("TextButton")
    wallButton.Name = "WallButton"
    wallButton.Text = "🧱 WALL"
    wallButton.Size = UDim2.new(0, 70, 0, 30)
    wallButton.Position = UDim2.new(0, 250, 0, 10)
    wallButton.BackgroundColor3 = Color3.fromRGB(50, 30, 80)
    wallButton.TextColor3 = Color3.fromRGB(255, 200, 100)
    wallButton.TextSize = 12
    wallButton.Font = Enum.Font.SourceSansBold
    wallButton.Parent = modesFrame
    
    local boxButton = Instance.new("TextButton")
    boxButton.Name = "BoxButton"
    boxButton.Text = "⬜ BOX"
    boxButton.Size = UDim2.new(0, 70, 0, 30)
    boxButton.Position = UDim2.new(0, 10, 0, 50)
    boxButton.BackgroundColor3 = Color3.fromRGB(50, 30, 80)
    boxButton.TextColor3 = Color3.fromRGB(200, 255, 100)
    boxButton.TextSize = 12
    boxButton.Font = Enum.Font.SourceSansBold
    boxButton.Parent = modesFrame
    
    local blackHoleButton = Instance.new("TextButton")
    blackHoleButton.Name = "BlackHoleButton"
    blackHoleButton.Text = "🕳️ BLACK HOLE"
    blackHoleButton.Size = UDim2.new(0, 70, 0, 30)
    blackHoleButton.Position = UDim2.new(0, 90, 0, 50)
    blackHoleButton.BackgroundColor3 = Color3.fromRGB(50, 30, 80)
    blackHoleButton.TextColor3 = Color3.fromRGB(100, 100, 100)
    blackHoleButton.TextSize = 12
    blackHoleButton.Font = Enum.Font.SourceSansBold
    blackHoleButton.Parent = modesFrame
    
    local modeLabel = Instance.new("TextLabel")
    modeLabel.Name = "ModeLabel"
    modeLabel.Text = "CURRENT MODE: NONE"
    modeLabel.Size = UDim2.new(0, 320, 0, 20)
    modeLabel.Position = UDim2.new(0, 10, 0, 90)
    modeLabel.BackgroundTransparency = 1
    modeLabel.TextColor3 = Color3.fromRGB(150, 150, 255)
    modeLabel.TextSize = 14
    modeLabel.Font = Enum.Font.SourceSansBold
    modeLabel.Parent = modesFrame
    
    -- Pull strength input
    local pullFrame = Instance.new("Frame")
    pullFrame.Name = "PullFrame"
    pullFrame.Size = UDim2.new(0, 330, 0, 50)
    pullFrame.Position = UDim2.new(0, 10, 0, 180)
    pullFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
    pullFrame.BorderSizePixel = 1
    pullFrame.BorderColor3 = Color3.fromRGB(100, 50, 200)
    pullFrame.Parent = background
    
    local pullLabel = Instance.new("TextLabel")
    pullLabel.Name = "PullLabel"
    pullLabel.Text = "PULL STRENGTH:"
    pullLabel.Size = UDim2.new(0, 120, 0, 20)
    pullLabel.Position = UDim2.new(0, 10, 0, 10)
    pullLabel.BackgroundTransparency = 1
    pullLabel.TextColor3 = Color3.fromRGB(150, 150, 255)
    pullLabel.TextSize = 12
    pullLabel.Font = Enum.Font.SourceSansBold
    pullLabel.Parent = pullFrame
    
    local pullInput = Instance.new("TextBox")
    pullInput.Name = "PullInput"
    pullInput.Text = "200"
    pullInput.Size = UDim2.new(0, 100, 0, 25)
    pullInput.Position = UDim2.new(0, 130, 0, 5)
    pullInput.BackgroundColor3 = Color3.fromRGB(40, 40, 70)
    pullInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    pullInput.TextSize = 14
    pullInput.ClearTextOnFocus = false
    pullInput.Parent = pullFrame
    
    local radiusLabel = Instance.new("TextLabel")
    radiusLabel.Name = "RadiusLabel"
    radiusLabel.Text = "RADIUS:"
    radiusLabel.Size = UDim2.new(0, 120, 0, 20)
    radiusLabel.Position = UDim2.new(0, 10, 0, 30)
    radiusLabel.BackgroundTransparency = 1
    radiusLabel.TextColor3 = Color3.fromRGB(150, 150, 255)
    radiusLabel.TextSize = 12
    radiusLabel.Font = Enum.Font.SourceSansBold
    radiusLabel.Parent = pullFrame
    
    local radiusInput = Instance.new("TextBox")
    radiusInput.Name = "RadiusInput"
    radiusInput.Text = "5"
    radiusInput.Size = UDim2.new(0, 100, 0, 25)
    radiusInput.Position = UDim2.new(0, 130, 0, 25)
    radiusInput.BackgroundColor3 = Color3.fromRGB(40, 40, 70)
    radiusInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    radiusInput.TextSize = 14
    radiusInput.ClearTextOnFocus = false
    radiusInput.Parent = pullFrame
    
    -- Deactivate button
    local deactivateButton = Instance.new("TextButton")
    deactivateButton.Name = "DeactivateButton"
    deactivateButton.Text = "🛑 DEACTIVATE"
    deactivateButton.Size = UDim2.new(0, 150, 0, 35)
    deactivateButton.Position = UDim2.new(0, 90, 0, 240)
    deactivateButton.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
    deactivateButton.TextColor3 = Color3.fromRGB(255, 100, 100)
    deactivateButton.TextSize = 14
    deactivateButton.Font = Enum.Font.SourceSansBold
    deactivateButton.Parent = background
    
    -- Make GUI draggable
    local dragging = false
    local dragStart = Vector2.new()
    local dragObject = nil
    
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            dragObject = background
        end
    end)
    
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragObject = nil
        end
    end)
    
    runService.Stepped:Connect(function()
        if dragging and dragObject then
            local mousePos = player:GetMouse().Position
            local delta = mousePos - dragStart
            dragObject.Position = UDim2.new(
                dragObject.Position.X.Scale,
                dragObject.Position.X.Offset + delta.X,
                dragObject.Position.Y.Scale,
                dragObject.Position.Y.Offset + delta.Y
            )
        end
    end)
    
    -- Close functionality
    closeButton.MouseButton1Click:Connect(function()
        mainGui.Enabled = false
        createMiniIcon()
    end)
    
    -- Mode selection
    snakeButton.MouseButton1Click:Connect(function()
        activeMode = "snake"
        modeLabel.Text = "CURRENT MODE: SNAKE"
        isActivated = true
    end)
    
    heartButton.MouseButton1Click:Connect(function()
        activeMode = "heart"
        modeLabel.Text = "CURRENT MODE: HEART"
        isActivated = true
    end)
    
    ringsButton.MouseButton1Click:Connect(function()
        activeMode = "rings"
        modeLabel.Text = "CURRENT MODE: RINGS"
        isActivated = true
    end)
    
    wallButton.MouseButton1Click:Connect(function()
        activeMode = "wall"
        modeLabel.Text = "CURRENT MODE: WALL"
        isActivated = true
    end)
    
    boxButton.MouseButton1Click:Connect(function()
        activeMode = "box"
        modeLabel.Text = "CURRENT MODE: BOX"
        isActivated = true
    end)
    
    blackHoleButton.MouseButton1Click:Connect(function()
        activeMode = "blackhole"
        modeLabel.Text = "CURRENT MODE: BLACK HOLE"
        isActivated = true
    end)
    
    -- Deactivate
    deactivateButton.MouseButton1Click:Connect(function()
        isActivated = false
        activeMode = "none"
        modeLabel.Text = "CURRENT MODE: NONE"
        removeManipulatorParts()
    end)
    
    -- Update pull strength
    pullInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local value = tonumber(pullInput.Text)
            if value then
                pullStrength = value
            end
        end
    end)
    
    -- Update radius
    radiusInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local value = tonumber(radiusInput.Text)
            if value then
                radius = value
            end
        end
    end)
    
    -- Hide when closing
    mainGui.Enabled = true
    return mainGui
end

-- Create mini icon when GUI is closed
local function createMiniIcon()
    local iconGui = Instance.new("ScreenGui")
    iconGui.Name = "UnanchoredIcon"
    iconGui.ResetOnSpawn = false
    iconGui.Parent = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
    
    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "IconFrame"
    iconFrame.Size = UDim2.new(0, 50, 0, 50)
    iconFrame.Position = UDim2.new(0.9, -60, 0.1, 10)
    iconFrame.BackgroundColor3 = Color3.fromRGB(50, 30, 80)
    iconFrame.BorderSizePixel = 2
    iconFrame.BorderColor3 = Color3.fromRGB(150, 100, 255)
    iconFrame.Parent = iconGui
    
    local star = Instance.new("ImageLabel")
    star.Name = "Star"
    star.Size = UDim2.new(1, 0, 1, 0)
    star.Position = UDim2.new(0, 0, 0, 0)
    star.BackgroundTransparency = 1
    star.Image = "rbxasset://textures/ui/star.png"
    star.ImageColor3 = Color3.fromRGB(255, 255, 200)
    star.Parent = iconFrame
    
    -- Click to reopen
    iconFrame.MouseButton
    iconFrame.MouseButton1Click:Connect(function()
        iconGui:Destroy()
        createGalaxyGUI()
    end)
    
    return iconGui
end

-- Remove all manipulator parts
local function removeManipulatorParts()
    for _, part in pairs(manipulatorParts) do
        if part and part.Parent then
            part:Destroy()
        end
    end
    manipulatorParts = {}
end

-- Create unanchored parts for manipulation
local function createManipulatorParts()
    -- Remove existing parts first
    removeManipulatorParts()
    
    -- Create 15 unanchored parts for manipulation
    for i = 1, 15 do
        local part = Instance.new("Part")
        part.Name = "ManipulatorPart_" .. i
        part.Size = Vector3.new(1, 1, 1)
        part.Material = Enum.Material.Neon
        part.BrickColor = BrickColor.random()
        part.Anchored = false
        part.CanCollide = false
        part.Parent = workspace
        
        -- Add glow effect
        local glow = Instance.new("BillboardGui")
        glow.Name = "Glow"
        glow.Size = UDim2.new(0, 10, 0, 10)
        glow.AlwaysOnTop = true
        glow.StUD = true
        glow.Parent = part
        
        local glowPart = Instance.new("Frame")
        glowPart.Name = "GlowFrame"
        glowPart.Size = UDim2.new(1, 0, 1, 0)
        glowPart.BackgroundTransparency = 0.5
        glowPart.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        glowPart.BorderSizePixel = 0
        glowPart.Parent = glow
        
        table.insert(manipulatorParts, part)
    end
end

-- Apply the selected manipulation mode
local function applyManipulation()
    if not isActivated or activeMode == "none" then return end
    
    local character = player.Character or player.CharacterAdded:Wait(2)
    if not character then return end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
    if not rootPart then return end
    
    local characterPosition = rootPart.Position
    
    -- Update pull strength and radius from GUI
    local pullInput = nil
    local radiusInput = nil
    
    -- Find GUI elements if they exist
    local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("UnanchoredManipulatorGUI")
    if gui then
        local pullFrame = gui:FindFirstChild("PullFrame")
        if pullFrame then
            pullInput = pullFrame:FindFirstChild("PullInput")
            radiusInput = pullFrame:FindFirstChild("RadiusInput")
        end
    end
    
    if pullInput and pullInput.Text then
        local value = tonumber(pullInput.Text)
        if value then pullStrength = value end
    end
    
    if radiusInput and radiusInput.Text then
        local value = tonumber(radiusInput.Text)
        if value then radius = value end
    end
    
    -- Apply different manipulation modes
    for i, part in ipairs(manipulatorParts) do
        if part and part.Parent then
            local targetPosition = characterPosition
            
            if activeMode == "snake" then
                -- Snake-like trail
                local offset = Vector3.new(
                    math.sin(i * 0.5 + tick()) * radius,
                    0,
                    math.cos(i * 0.5 + tick()) * radius
                )
                targetPosition = characterPosition + offset
                
            elseif activeMode == "heart" then
                -- Heart orbit pattern
                local angle = (i * 0.3 + tick()) * 2
                local x = 16 * math.sin(angle)^3
                local y = 13 * math.cos(angle) - 5 * math.cos(2*angle) - 2 * math.cos(3*angle) - math.cos(4*angle)
                local z = math.sin(angle) * 5
                targetPosition = characterPosition + Vector3.new(x, y, z) * 0.1
                
            elseif activeMode == "rings" then
                -- Ring formation
                local angle = (i * 0.4 + tick())
                local x = math.cos(angle) * radius
                local z = math.sin(angle) * radius
                targetPosition = characterPosition + Vector3.new(x, 0, z)
                
            elseif activeMode == "wall" then
                -- Wall formation (in front of player)
                local front = character.CFrame:VectorToObjectSpace(Vector3.new(0, 0, -radius))
                local offset = Vector3.new(
                    math.sin(i * 0.3) * 2,
                    0,
                    0
                )
                targetPosition = characterPosition + front + offset
                
            elseif activeMode == "box" then
                -- Box formation around player
                local angle = (i * 0.2 + tick()) * 0.5
                local side = math.floor((i - 1) / 5) % 4
                local offset = Vector3.new(0, 0, 0)
                
                if side == 0 then offset = Vector3.new(radius, 0, 0)  -- Right
                elseif side == 1 then offset = Vector3.new(-radius, 0, 0)  -- Left
                elseif side == 2 then offset = Vector3.new(0, radius, 0)  -- Top
                else offset = Vector3.new(0, -radius, 0)  -- Bottom
                end
                
                targetPosition = characterPosition + offset
                
            elseif activeMode == "blackhole" then
                -- Black hole effect (pull with rotation)
                local direction = (characterPosition - part.Position).unit
                local force = direction * pullStrength * 0.1
                local rotation = Vector3.new(
                    math.sin(tick() * 10) * 10,
                    math.cos(tick() * 10) * 10,
                    math.sin(tick() * 10) * 10
                )
                
                part.Velocity = force + rotation
                part.RotVelocity = rotation * 2
                continue
            end
            
            -- Apply physics for normal modes
            if activeMode ~= "blackhole" then
                -- Pull towards target
                local direction = (targetPosition - part.Position).unit
                local force = direction * pullStrength * 0.1
                
                part.Velocity = force
                part.RotVelocity = Vector3.new(0, 0, 0)
            end
        end
    end
end

-- Main manipulation loop
local function manipulationLoop()
    while true do
        if isActivated then
            applyManipulation()
        end
        wait(0.05)  -- 20 FPS for better performance
    end
end

-- Create all manipulator parts on start
createManipulatorParts()

-- Special effects system
local function createEffects()
    -- Create particles for galaxy effect
    local galaxyParticles = Instance.new("ParticleEmitter")
    galaxyParticles.Name = "GalaxyParticles"
    galaxyParticles.Size = NumberRange.new(0.5, 2)
    galaxyParticles.Speed = NumberRange.new(0, 5)
    galaxyParticles.Rate = 100
    galaxyParticles.Lifetime = NumberRange.new(1, 3)
    galaxyParticles.Color = ColorSequence.new(
        Color3.fromRGB(100, 50, 200),
        Color3.fromRGB(150, 100, 255),
        Color3.fromRGB(200, 150, 255)
    )
    galaxyParticles.Parent = workspace
    
    -- Create visual effect for black hole
    local blackHoleEffect = Instance.new("Part")
    blackHoleEffect.Name = "BlackHoleEffect"
    blackHoleEffect.Size = Vector3.new(0.5, 0.5, 0.5)
    blackHoleEffect.Material = Enum.Material.Neon
    blackHoleEffect.BrickColor = BrickColor.new("Dark gray")
    blackHoleEffect.Anchored = true
    blackHoleEffect.CanCollide = false
    blackHoleEffect.Parent = workspace
    
    -- Make it invisible but functional
    blackHoleEffect.Transparency = 1
end

-- Initialize the system
local function initializeSystem()
    -- Create main GUI
    local gui = createGalaxyGUI()
    
    -- Create special effects
    createEffects()
    
    -- Start manipulation loop
    spawn(manipulationLoop)
    
    print("✅ UNANCHORED MANIPULATOR KII READY")
    print("🌌 GALAXY MODE ACTIVE")
    print("📍 AUTO-CREATED UNANCHORED PARTS")
    print("⚙️ MODES: SNAKE, HEART, RINGS, WALL, BOX, BLACK HOLE")
    print("🔧 USE GUI TO CONFIGURE")
end

-- Initialize everything
initializeSystem()
