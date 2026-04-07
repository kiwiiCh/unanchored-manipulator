-- UNANCHORED MANIPULATOR KII — GASTER UPDATE (COMPLETE)
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local function main()
    print("MANIPULATOR KII LOADED — " .. player.Name)

    -- ── CONFIG ───────────────────────────────────────────────────────────
    local pullStrength   = 1500
    local radius         = 7
    local detectionRange = 9999
    local isActivated    = false
    local activeMode     = "none"
    local scriptAlive    = true

    local gasterAnim   = "pointing"
    local gasterT      = 0
    local gasterSubGui = nil

    local CFRAME_MODES = {
        heart=true, rings=true, wall=true, box=true,
        gasterhand=true, gaster2hands=true
    }
    local GASTER_MODES = { gasterhand=true, gaster2hands=true }

    -- ── GASTER HAND SLOT TABLE ───────────────────────────────────────────
    --[[
        19 slots that form a hand with a hollow centre (the hole).
        x = horizontal column, y = vertical row.
        Scale: each unit = HAND_SCALE studs.

              col: -2  -1   0   1   2
        row  4:        [F]     [F]
        row  3:   [K] [P] [P] [P] [K]
        row  2:   [P]           [P]
        row  1:   [P]           [P]
        row  0:   [K] [P] [P] [P] [K]
        row -1:       [W] [W] [W]
    ]]
    local HAND_SLOTS = {
        {x=-1,y=4},{x=1,y=4},
        {x=-2,y=3},{x=-1,y=3},{x=0,y=3},{x=1,y=3},{x=2,y=3},
        {x=-2,y=2},{x=2,y=2},
        {x=-2,y=1},{x=2,y=1},
        {x=-2,y=0},{x=-1,y=0},{x=0,y=0},{x=1,y=0},{x=2,y=0},
        {x=-1,y=-1},{x=0,y=-1},{x=1,y=-1},
    }
    local HAND_SLOTS_COUNT = #HAND_SLOTS  -- 19

    -- Per-slot Y bias for POINTING (left finger up, right finger tucked)
    local POINTING_BIAS = { [1]=1.2, [2]=-0.5 }
    -- Per-slot Y bias for PUNCHING (fingers fold down)
    local PUNCH_BIAS    = {
        [1]=-1.5,[2]=-1.5,
        [3]=-0.4,[4]=-0.4,[5]=-0.4,[6]=-0.4,[7]=-0.4
    }

    local HAND_SCALE = 1.4
    -- Local-space offsets for each hand centre (far enough to never clip avatar)
    local HAND_RIGHT = Vector3.new( 7, 1.5, 0.5)
    local HAND_LEFT  = Vector3.new(-7, 1.5, 0.5)

    -- ── STATE ────────────────────────────────────────────────────────────
    local controlled    = {}
    local partCount     = 0
    local snakeT        = 0
    local snakeHistory  = {}
    local SNAKE_HIST_MAX= 600
    local SNAKE_GAP     = 8

    -- ── NO-COLLISION (local player only) ─────────────────────────────────
    local function applyNoCollision(part, data)
        local char = player.Character
        if not char then return end
        data.ncc = data.ncc or {}
        for _, limb in ipairs(char:GetDescendants()) do
            if limb:IsA("BasePart") then
                local nc  = Instance.new("NoCollisionConstraint")
                nc.Part0  = part
                nc.Part1  = limb
                nc.Parent = part
                table.insert(data.ncc, nc)
            end
        end
    end

    local function clearNoCollision(data)
        if not data.ncc then return end
        for _, nc in ipairs(data.ncc) do
            if nc and nc.Parent then nc:Destroy() end
        end
        data.ncc = {}
    end

    player.CharacterAdded:Connect(function()
        task.wait(0.6)
        for part, data in pairs(controlled) do
            clearNoCollision(data)
            applyNoCollision(part, data)
        end
    end)

    -- ── VALIDATION ───────────────────────────────────────────────────────
    local function isValid(obj)
        if not obj:IsA("BasePart") then return false end
        if obj.Anchored then return false end
        local p = obj.Parent
        while p and p ~= workspace do
            if p:FindFirstChildOfClass("Humanoid") then return false end
            p = p.Parent
        end
        return true
    end

    -- ── RELEASE ──────────────────────────────────────────────────────────
    local function releasePart(part, data)
        clearNoCollision(data)
        if data.touchConn then data.touchConn:Disconnect() end
        if data.bav and data.bav.Parent then data.bav:Destroy() end
        if data.bp  and data.bp.Parent  then data.bp:Destroy()  end
        if part and part.Parent then
            pcall(function() part.CanCollide = data.origCC end)
        end
    end

    local function releaseAll()
        for part, data in pairs(controlled) do releasePart(part, data) end
        controlled   = {}
        partCount    = 0
        snakeT       = 0
        snakeHistory = {}
    end

    -- ── BLACK HOLE FLING ─────────────────────────────────────────────────
    local function enableFling(part, data)
        if data.bav and data.bav.Parent then
            data.bav.MaxTorque       = Vector3.new(1e6,1e6,1e6)
            data.bav.AngularVelocity = Vector3.new(
                math.random(-50,50), math.random(60,100), math.random(-50,50))
        end
        if data.touchConn then data.touchConn:Disconnect() end
        data.touchConn = part.Touched:Connect(function(hit)
            local hc = hit.Parent
            if Players:GetPlayerFromCharacter(hc) == player then return end
            local hum = hc:FindFirstChildOfClass("Humanoid")
            local hrp = hc:FindFirstChild("HumanoidRootPart")
            if hum and hrp then
                local dir = (hrp.Position - part.Position).Unit
                hrp.AssemblyLinearVelocity = (dir + Vector3.new(0,0.9,0)).Unit * 160
            end
        end)
    end

    local function disableFling(data)
        if data.touchConn then data.touchConn:Disconnect(); data.touchConn = nil end
        if data.bav and data.bav.Parent then
            data.bav.MaxTorque       = Vector3.zero
            data.bav.AngularVelocity = Vector3.zero
        end
    end

    -- ── GRAB ─────────────────────────────────────────────────────────────
    local function grabPart(part)
        if controlled[part] then return end
        local char = player.Character
        local root = char and (
            char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if root and (part.Position - root.Position).Magnitude > detectionRange then
            return
        end

        local origCC    = part.CanCollide
        part.CanCollide = true

        local bp = Instance.new("BodyPosition")
        bp.Name     = "ManipBP"
        bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bp.P        = pullStrength
        bp.D        = pullStrength * 0.12
        bp.Position = part.Position
        bp.Parent   = part

        local bav = Instance.new("BodyAngularVelocity")
        bav.Name            = "ManipBAV"
        bav.MaxTorque       = Vector3.zero
        bav.AngularVelocity = Vector3.zero
        bav.P               = 1e5
        bav.Parent          = part

        local data = { bp=bp, bav=bav, touchConn=nil, origCC=origCC, ncc={} }
        applyNoCollision(part, data)

        if CFRAME_MODES[activeMode] then bp.MaxForce = Vector3.zero end
        if activeMode == "blackhole"  then enableFling(part, data) end

        controlled[part] = data
        partCount = partCount + 1
    end

    local function sweepMap()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isValid(obj) then grabPart(obj) end
        end
    end

    -- ── SNAKE CHAIN ──────────────────────────────────────────────────────
    local function getSnakeTarget(i)
        local idx = math.clamp(i * SNAKE_GAP, 1, math.max(1, #snakeHistory))
        return snakeHistory[idx] or snakeHistory[#snakeHistory] or Vector3.zero
    end

    -- ── STANDARD FORMATION CFrames ───────────────────────────────────────
    local function getFormationCF(mode, i, n, origin, cf, t)
        if mode == "heart" then
            local a  = ((i-1)/math.max(n,1)) * math.pi * 2
            local hx =  16 * math.sin(a)^3
            local hz = -(13*math.cos(a) - 5*math.cos(2*a)
                       - 2*math.cos(3*a) - math.cos(4*a))
            local s  = radius / 16
            return CFrame.new(origin + cf:VectorToWorldSpace(Vector3.new(hx*s, 0, hz*s)))

        elseif mode == "rings" then
            local a = ((i-1)/math.max(n,1)) * math.pi*2 + t*1.4
            return CFrame.new(origin + Vector3.new(
                math.cos(a)*radius, 0, math.sin(a)*radius))

        elseif mode == "wall" then
            local cols = math.max(1, math.ceil(math.sqrt(n)))
            local col  = ((i-1) % cols) - math.floor(cols/2)
            local row  = math.floor((i-1) / cols) - 1
            return CFrame.new(
                origin
                + cf.LookVector  * radius
                + cf.RightVector * (col * 1.8)
                + cf.UpVector    * (row * 1.8 + 1))

        elseif mode == "box" then
            local fV  = {cf.LookVector,-cf.LookVector,cf.RightVector,
                         -cf.RightVector,cf.UpVector,-cf.UpVector}
            local fTa = {cf.RightVector,cf.RightVector,cf.LookVector,
                         cf.LookVector,cf.RightVector,cf.RightVector}
            local fTb = {cf.UpVector,cf.UpVector,cf.UpVector,
                         cf.UpVector,cf.LookVector,cf.LookVector}
            local fi  = ((i-1) % 6) + 1
            local si  = math.floor((i-1) / 6)
            local col = (si % 2) - 0.5
            local row = math.floor(si / 2) - 0.5
            local sp  = radius * 0.45
            return CFrame.new(
                origin + fV[fi]*radius + fTa[fi]*(col*sp) + fTb[fi]*(row*sp))
        end

        return CFrame.new(origin)
    end

    -- ── GASTER HAND CFrame ───────────────────────────────────────────────
    --[[
        slotIndex : 1-based index into HAND_SLOTS (1..19)
        sideSign  :  1 = right hand,  -1 = left hand
        cf        : player root CFrame
        gt        : gaster animation timer
    ]]
    local function getGasterCF(slotIndex, sideSign, cf, gt)
        local slot = HAND_SLOTS[slotIndex]
        if not slot then
            return CFrame.new(0, -5000, 0)
        end

        local sx = slot.x * HAND_SCALE
        local sy = slot.y * HAND_SCALE

        -- Apply animation Y bias
        if gasterAnim == "pointing" then
            sy = sy + (POINTING_BIAS[slotIndex] or 0) * HAND_SCALE
        elseif gasterAnim == "punching" then
            sy = sy + (PUNCH_BIAS[slotIndex] or 0) * HAND_SCALE
        end

        -- Waving: rotate slot X around the hand centre Y axis
        local waveAngle = 0
        if gasterAnim == "waving" then
            waveAngle = math.sin(gt * 2.2) * 0.6
        end

        -- Punching: pulse hand forward (0 to 4.5 studs)
        local punchZ = 0
        if gasterAnim == "punching" then
            punchZ = (math.sin(gt * 4) * 0.5 + 0.5) * 4.5
        end

        -- Rotate sx around Y for waving
        local rotX = sx * math.cos(waveAngle)
        local rotZ = sx * math.sin(waveAngle)

        -- Base centre in local space (flipped for left hand)
        local base = (sideSign == 1) and HAND_RIGHT or HAND_LEFT

        -- Compose local offset using the player's own axes
        local localOffset = Vector3.new(
            base.X + rotX * sideSign,
            base.Y + sy,
            base.Z + rotZ - punchZ
        )

        return CFrame.new(cf:PointToWorldSpace(localOffset))
    end

    -- ── BLACK HOLE PET TARGET ────────────────────────────────────────────
    local function getBHTarget(i, cf)
        local pet = cf:PointToWorldSpace(Vector3.new(3, 1, -5))
        return pet + Vector3.new(
            math.sin(i * 73.1) * 0.2,
            math.cos(i * 53.7) * 0.2,
            math.sin(i * 31.9) * 0.2)
    end

    -- ── GASTER SUB-GUI ───────────────────────────────────────────────────
    local function destroyGasterGui()
        if gasterSubGui and gasterSubGui.Parent then
            gasterSubGui:Destroy()
        end
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

        local W, H = 220, 182
        local panel = Instance.new("Frame")
        panel.Size             = UDim2.fromOffset(W, H)
        panel.Position         = UDim2.new(0.5, 30, 0.5, -(H/2) - 130)
        panel.BackgroundColor3 = Color3.fromRGB(6, 6, 18)
        panel.BorderSizePixel  = 0
        panel.Parent           = sg
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
        local ps = Instance.new("UIStroke", panel)
        ps.Color     = Color3.fromRGB(180, 60, 255)
        ps.Thickness = 1.5

        -- Title bar / drag handle
        local tBar = Instance.new("Frame")
        tBar.Size             = UDim2.new(1, 0, 0, 36)
        tBar.BackgroundColor3 = Color3.fromRGB(20, 8, 45)
        tBar.BorderSizePixel  = 0
        tBar.ZIndex           = 10
        tBar.Parent           = panel
        Instance.new("UICorner", tBar).CornerRadius = UDim.new(0, 8)

        local tLbl = Instance.new("TextLabel")
        tLbl.Text             = "GASTER HAND FORM"
        tLbl.Size             = UDim2.new(1, -10, 1, 0)
        tLbl.Position         = UDim2.fromOffset(8, 0)
        tLbl.BackgroundTransparency = 1
        tLbl.TextColor3       = Color3.fromRGB(200, 120, 255)
        tLbl.TextSize         = 12
        tLbl.Font             = Enum.Font.GothamBold
        tLbl.TextXAlignment   = Enum.TextXAlignment.Left
        tLbl.ZIndex           = 10
        tLbl.Parent           = tBar

        local animLbl = Instance.new("TextLabel")
        animLbl.Text           = "FORM: " .. gasterAnim:upper()
        animLbl.Size           = UDim2.new(1, -16, 0, 18)
        animLbl.Position       = UDim2.fromOffset(8, 42)
        animLbl.BackgroundTransparency = 1
        animLbl.TextColor3     = Color3.fromRGB(130, 130, 255)
        animLbl.TextSize       = 11
        animLbl.Font           = Enum.Font.GothamBold
        animLbl.TextXAlignment = Enum.TextXAlignment.Left
        animLbl.Parent         = panel

        local animList = {
            { txt="POINTING", key="pointing", col=Color3.fromRGB(100,200,255) },
            { txt="WAVING",   key="waving",   col=Color3.fromRGB(100,255,160) },
            { txt="PUNCHING", key="punching", col=Color3.fromRGB(255,120,120) },
        }

        for idx, anim in ipairs(animList) do
            local btn = Instance.new("TextButton")
            btn.Text             = anim.txt
            btn.Size             = UDim2.new(1, -16, 0, 32)
            btn.Position         = UDim2.fromOffset(8, 60 + (idx-1) * 38)
            btn.BackgroundColor3 = Color3.fromRGB(22, 10, 48)
            btn.TextColor3       = anim.col
            btn.TextSize         = 12
            btn.Font             = Enum.Font.GothamBold
            btn.BorderSizePixel  = 0
            btn.Parent           = panel
            Instance.new("UICorner", btn)

            btn.MouseButton1Click:Connect(function()
                gasterAnim    = anim.key
                gasterT       = 0
                animLbl.Text  = "FORM: " .. anim.key:upper()
            end)
        end

        -- Drag
        local dragging, dragStartM, dragStartPos = false, Vector2.zero, UDim2.new()

        tBar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging     = true
                dragStartM   = Vector2.new(inp.Position.X, inp.Position.Y)
                dragStartPos = panel.Position
            end
        end)
        panel.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                if not dragging then
                    dragging     = true
                    dragStartM   = Vector2.new(inp.Position.X, inp.Position.Y)
                    dragStartPos = panel.Position
                end
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

    -- ── MAIN LOOP ────────────────────────────────────────────────────────
    local lastMode = "none"

    local function mainLoop()
        while scriptAlive do
            local dt = task.wait(0.016)
            snakeT  = snakeT  + dt
            gasterT = gasterT + dt

            local char = player.Character
            local root = char and (
                char:FindFirstChild("HumanoidRootPart") or
                char:FindFirstChild("Torso"))
            if not root then continue end

            local pos = root.Position
            local cf  = root.CFrame
            local t   = tick()

            -- Snake history ring buffer
            table.insert(snakeHistory, 1, pos)
            if #snakeHistory > SNAKE_HIST_MAX then
                table.remove(snakeHistory, SNAKE_HIST_MAX + 1)
            end

            -- Mode transition handling
            if activeMode ~= lastMode then
                if lastMode == "blackhole" then
                    for _, d in pairs(controlled) do disableFling(d) end
                end
                if activeMode == "blackhole" then
                    for p, d in pairs(controlled) do enableFling(p, d) end
                end
                if CFRAME_MODES[activeMode] then
                    for _, d in pairs(controlled) do
                        if d.bp and d.bp.Parent then
                            d.bp.MaxForce = Vector3.zero
                        end
                    end
                end
                if not CFRAME_MODES[activeMode] and CFRAME_MODES[lastMode] then
                    for _, d in pairs(controlled) do
                        if d.bp and d.bp.Parent then
                            d.bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                        end
                    end
                end
                -- Gaster sub-GUI visibility
                if GASTER_MODES[activeMode] then
                    createGasterGui()
                else
                    destroyGasterGui()
                end
                lastMode = activeMode
            end

            if not isActivated or activeMode == "none" or partCount == 0 then
                continue
            end

            -- Build ordered array from dictionary
            local arr = {}
            for part, data in pairs(controlled) do
                if part.Parent and data.bp and data.bp.Parent then
                    table.insert(arr, {p=part, d=data})
                else
                    if data.touchConn then data.touchConn:Disconnect() end
                    clearNoCollision(data)
                    controlled[part] = nil
                    partCount = math.max(0, partCount - 1)
                end
            end

            local n = #arr

            for i, item in ipairs(arr) do
                local part = item.p
                local data = item.d

                if activeMode == "snake" then
                    local tgt = getSnakeTarget(i)
                    data.bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                    data.bp.Position = tgt
                    data.bp.P        = pullStrength
                    data.bp.D        = pullStrength * 0.12

                elseif activeMode == "blackhole" then
                    local tgt = getBHTarget(i, cf)
                    data.bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                    data.bp.Position = tgt
                    data.bp.P        = pullStrength
                    data.bp.D        = pullStrength * 0.12

                elseif activeMode == "gasterhand" then
                    --[[
                        Single right hand.
                        Slots 1-19 → right hand.
                        Any extra blocks → parked at Y=-5000.
                    ]]
                    data.bp.MaxForce = Vector3.zero
                    if i <= HAND_SLOTS_COUNT then
                        part.CFrame = getGasterCF(i, 1, cf, gasterT)
                    else
                        part.CFrame = CFrame.new(0, -5000, 0)
                    end

                elseif activeMode == "gaster2hands" then
                    --[[
                        Two hands:
                        Blocks  1-19  → right hand (sideSign =  1)
                        Blocks 20-38  → left  hand (sideSign = -1)
                        Blocks 39+    → parked
                    ]]
                    data.bp.MaxForce = Vector3.zero
                    if i <= HAND_SLOTS_COUNT then
                        part.CFrame = getGasterCF(i, 1, cf, gasterT)
                    elseif i <= HAND_SLOTS_COUNT * 2 then
                        part.CFrame = getGasterCF(i - HAND_SLOTS_COUNT, -1, cf, gasterT)
                    else
                        part.CFrame = CFrame.new(0, -5000, 0)
                    end

                elseif CFRAME_MODES[activeMode] then
                    data.bp.MaxForce = Vector3.zero
                    part.CFrame = getFormationCF(activeMode, i, n, pos, cf, t)
                end
            end
        end
    end

    -- ── AUTO-SCAN LOOP ───────────────────────────────────────────────────
    local function scanLoop()
        while scriptAlive do
            if isActivated and activeMode ~= "none" then
                sweepMap()
                if CFRAME_MODES[activeMode] then
                    for _, d in pairs(controlled) do
                        if d.bp and d.bp.Parent then
                            d.bp.MaxForce = Vector3.zero
                        end
                    end
                end
            end
            task.wait(1.5)
        end
    end

    -- ── MAIN GUI ─────────────────────────────────────────────────────────
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

        local W, H = 320, 570
        local panel = Instance.new("Frame")
        panel.Name               = "Panel"
        panel.Size               = UDim2.fromOffset(W, H)
        panel.Position           = UDim2.new(0.5, -W/2, 0.5, -H/2)
        panel.BackgroundColor3   = Color3.fromRGB(10, 10, 25)
        panel.BorderSizePixel    = 0
        panel.ClipsDescendants   = true
        panel.Parent             = gui
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
        local pStroke = Instance.new("UIStroke", panel)
        pStroke.Color     = Color3.fromRGB(90, 40, 180)
        pStroke.Thickness = 1.5

        -- Title bar
        local titleBar = Instance.new("Frame")
        titleBar.Size             = UDim2.new(1, 0, 0, 40)
        titleBar.BackgroundColor3 = Color3.fromRGB(20, 10, 48)
        titleBar.BorderSizePixel  = 0
        titleBar.ZIndex           = 10
        titleBar.Parent           = panel
        Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

        local titleTxt = Instance.new("TextLabel")
        titleTxt.Text             = "MANIPULATOR KII"
        titleTxt.Size             = UDim2.new(1, -80, 1, 0)
        titleTxt.Position         = UDim2.fromOffset(10, 0)
        titleTxt.BackgroundTransparency = 1
        titleTxt.TextColor3       = Color3.fromRGB(195, 140, 255)
        titleTxt.TextSize         = 14
        titleTxt.Font             = Enum.Font.GothamBold
        titleTxt.TextXAlignment   = Enum.TextXAlignment.Left
        titleTxt.ZIndex           = 10
        titleTxt.Parent           = titleBar

        local closeBtn = Instance.new("TextButton")
        closeBtn.Text             = "X"
        closeBtn.Size             = UDim2.fromOffset(30, 28)
        closeBtn.Position         = UDim2.new(1, -36, 0, 6)
        closeBtn.BackgroundColor3 = Color3.fromRGB(150, 25, 25)
        closeBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
        closeBtn.TextSize         = 13
        closeBtn.Font             = Enum.Font.GothamBold
        closeBtn.BorderSizePixel  = 0
        closeBtn.ZIndex           = 11
        closeBtn.Parent           = titleBar
        Instance.new("UICorner", closeBtn)

        -- Scroll area
        local scroll = Instance.new("ScrollingFrame")
        scroll.Size                   = UDim2.new(1, 0, 1, -40)
        scroll.Position               = UDim2.fromOffset(0, 40)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel        = 0
        scroll.ScrollBarThickness     = 3
        scroll.ScrollBarImageColor3   = Color3.fromRGB(90, 40, 180)
        scroll.CanvasSize             = UDim2.fromOffset(0, 0)
        scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
        scroll.Parent                 = panel

        local layout = Instance.new("UIListLayout", scroll)
        layout.Padding             = UDim.new(0, 5)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.SortOrder           = Enum.SortOrder.LayoutOrder

        local pad = Instance.new("UIPadding", scroll)
        pad.PaddingTop    = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, 10)
        pad.PaddingLeft   = UDim.new(0, 8)
        pad.PaddingRight  = UDim.new(0, 8)

        -- ── GUI HELPERS ──────────────────────────────────────────────────
        local function sLabel(txt, order)
            local l = Instance.new("TextLabel")
            l.Text             = txt
            l.Size             = UDim2.new(1, 0, 0, 20)
            l.BackgroundTransparency = 1
            l.TextColor3       = Color3.fromRGB(180, 130, 255)
            l.TextSize         = 12
            l.Font             = Enum.Font.GothamBold
            l.TextXAlignment   = Enum.TextXAlignment.Left
            l.LayoutOrder      = order
            l.Parent           = scroll
        end

        local function makeSingleBtn(txt, bgCol, txtCol, order)
            local b = Instance.new("TextButton")
            b.Text             = txt
            b.Size             = UDim2.new(1, 0, 0, 36)
            b.BackgroundColor3 = bgCol
            b.TextColor3       = txtCol
            b.TextSize         = 12
            b.Font             = Enum.Font.GothamBold
            b.BorderSizePixel  = 0
            b.LayoutOrder      = order
            b.Parent           = scroll
            Instance.new("UICorner", b)
            return b
        end

        local function makeSettingRow(labelTxt, default, hint, order)
            local row = Instance.new("Frame")
            row.Size             = UDim2.new(1, 0, 0, 44)
            row.BackgroundColor3 = Color3.fromRGB(16, 16, 38)
            row.BorderSizePixel  = 0
            row.LayoutOrder      = order
            row.Parent           = scroll
            Instance.new("UICorner", row)

            local lbl = Instance.new("TextLabel")
            lbl.Text            = labelTxt
            lbl.Size            = UDim2.new(0.55, 0, 0, 22)
            lbl.Position        = UDim2.fromOffset(8, 4)
            lbl.BackgroundTransparency = 1
            lbl.TextColor3      = Color3.fromRGB(155, 155, 255)
            lbl.TextSize        = 11
            lbl.Font            = Enum.Font.GothamBold
            lbl.TextXAlignment  = Enum.TextXAlignment.Left
            lbl.TextWrapped     = true
            lbl.Parent          = row

            local tb = Instance.new("TextBox")
            tb.Text             = tostring(default)
            tb.Size             = UDim2.new(0.38, 0, 0, 22)
            tb.Position         = UDim2.new(0.59, 0, 0, 4)
            tb.BackgroundColor3 = Color3.fromRGB(28, 28, 55)
            tb.TextColor3       = Color3.fromRGB(255, 255, 255)
            tb.TextSize         = 12
            tb.Font             = Enum.Font.Gotham
            tb.ClearTextOnFocus = false
            tb.BorderSizePixel  = 0
            tb.Parent           = row
            Instance.new("UICorner", tb)

            local hintLbl = Instance.new("TextLabel")
            hintLbl.Text           = hint
            hintLbl.Size           = UDim2.new(1, -8, 0, 14)
            hintLbl.Position       = UDim2.fromOffset(8, 27)
            hintLbl.BackgroundTransparency = 1
            hintLbl.TextColor3     = Color3.fromRGB(80, 80, 130)
            hintLbl.TextSize       = 9
            hintLbl.Font           = Enum.Font.Gotham
            hintLbl.TextXAlignment = Enum.TextXAlignment.Left
            hintLbl.Parent         = row

            return tb
        end

        -- Helper to build a 2-column mode grid
        local function makeModeGrid(modeList, order, bgCol, strokeCol)
            local rows  = math.ceil(#modeList / 2)
            local gridH = rows * 36 + math.max(0, rows-1) * 4

            local frame = Instance.new("Frame")
            frame.Size             = UDim2.new(1, 0, 0, gridH)
            frame.BackgroundTransparency = 1
            frame.LayoutOrder      = order
            frame.Parent           = scroll

            local gl = Instance.new("UIGridLayout", frame)
            gl.CellSize            = UDim2.new(0.5, -3, 0, 36)
            gl.CellPadding         = UDim2.fromOffset(4, 4)
            gl.HorizontalAlignment = Enum.HorizontalAlignment.Left
            gl.SortOrder           = Enum.SortOrder.LayoutOrder

            return frame
        end

        -- ── STATUS ───────────────────────────────────────────────────────
        sLabel("STATUS", 1)

        local statusLbl = Instance.new("TextLabel")
        statusLbl.Text            = "IDLE  |  PARTS: 0"
        statusLbl.Size            = UDim2.new(1, 0, 0, 22)
        statusLbl.BackgroundTransparency = 1
        statusLbl.TextColor3      = Color3.fromRGB(80, 255, 140)
        statusLbl.TextSize        = 12
        statusLbl.Font            = Enum.Font.GothamBold
        statusLbl.TextXAlignment  = Enum.TextXAlignment.Left
        statusLbl.LayoutOrder     = 2
        statusLbl.Parent          = scroll

        local modeLbl = Instance.new("TextLabel")
        modeLbl.Text            = "MODE: NONE"
        modeLbl.Size            = UDim2.new(1, 0, 0, 18)
        modeLbl.BackgroundTransparency = 1
        modeLbl.TextColor3      = Color3.fromRGB(130, 130, 255)
        modeLbl.TextSize        = 11
        modeLbl.Font            = Enum.Font.GothamBold
        modeLbl.TextXAlignment  = Enum.TextXAlignment.Left
        modeLbl.LayoutOrder     = 3
        modeLbl.Parent          = scroll

        task.spawn(function()
            while panel.Parent and scriptAlive do
                statusLbl.Text = isActivated
                    and ("ACTIVE  |  PARTS: " .. partCount)
                    or  "IDLE  |  PARTS: 0"
                task.wait(0.5)
            end
        end)

        -- ── STANDARD MODES ───────────────────────────────────────────────
        sLabel("STANDARD MODES", 4)

        local stdRows  = 3
        local stdGridH = stdRows * 36 + (stdRows-1) * 4
        local stdFrame = Instance.new("Frame")
        stdFrame.Size             = UDim2.new(1, 0, 0, stdGridH)
        stdFrame.BackgroundTransparency = 1
        stdFrame.LayoutOrder      = 5
        stdFrame.Parent           = scroll

        local stdGL = Instance.new("UIGridLayout", stdFrame)
        stdGL.CellSize            = UDim2.new(0.5, -3, 0, 36)
        stdGL.CellPadding         = UDim2.fromOffset(4, 4)
        stdGL.HorizontalAlignment = Enum.HorizontalAlignment.Left
        stdGL.SortOrder           = Enum.SortOrder.LayoutOrder

        local stdModes = {
            { txt="SNAKE",      mode="snake",     col=Color3.fromRGB(160,110,255) },
            { txt="HEART",      mode="heart",     col=Color3.fromRGB(255,100,150) },
            { txt="RINGS",      mode="rings",     col=Color3.fromRGB(80, 210,255) },
            { txt="WALL",       mode="wall",      col=Color3.fromRGB(255,200, 90) },
            { txt="BOX CAGE",   mode="box",       col=Color3.fromRGB(160,255,100) },
            { txt="BLACK HOLE", mode="blackhole", col=Color3.fromRGB(220,220,220) },
        }

        for idx, m in ipairs(stdModes) do
            local btn = Instance.new("TextButton")
            btn.Text             = m.txt
            btn.BackgroundColor3 = Color3.fromRGB(26, 14, 55)
            btn.TextColor3       = m.col
            btn.TextSize         = 11
            btn.Font             = Enum.Font.GothamBold
            btn.BorderSizePixel  = 0
            btn.LayoutOrder      = idx
            btn.Parent           = stdFrame
            Instance.new("UICorner", btn)

            btn.MouseButton1Click:Connect(function()
                -- Leaving a Gaster mode
                if GASTER_MODES[activeMode] then
                    destroyGasterGui()
                end
                -- MaxForce management
                if CFRAME_MODES[m.mode] then
                    for _, d in pairs(controlled) do
                        if d.bp and d.bp.Parent then
                            d.bp.MaxForce = Vector3.zero
                        end
                    end
                else
                    for _, d in pairs(controlled) do
                        if d.bp and d.bp.Parent then
                            d.bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                        end
                    end
                end
                activeMode   = m.mode
                isActivated  = true
                modeLbl.Text = "MODE: " .. m.mode:upper()
                sweepMap()
            end)
        end

        -- ── SPECIAL MODES ────────────────────────────────────────────────
        sLabel("SPECIAL MODES", 6)

        local spGridH = 36
        local spFrame = Instance.new("Frame")
        spFrame.Size             = UDim2.new(1, 0, 0, spGridH)
        spFrame.BackgroundTransparency = 1
        spFrame.LayoutOrder      = 7
        spFrame.Parent           = scroll

        local spGL = Instance.new("UIGridLayout", spFrame)
        spGL.CellSize            = UDim2.new(0.5, -3, 0, 36)
        spGL.CellPadding         = UDim2.fromOffset(4, 4)
        spGL.HorizontalAlignment = Enum.HorizontalAlignment.Left
        spGL.SortOrder           = Enum.SortOrder.LayoutOrder

        local specialModes = {
            { txt="GASTER HAND",    mode="gasterhand",   col=Color3.fromRGB(180, 80,255) },
            { txt="2 GASTER HANDS", mode="gaster2hands", col=Color3.fromRGB(220,110,255) },
        }

        for idx, m in ipairs(specialModes) do
            local btn = Instance.new("TextButton")
            btn.Text             = m.txt
            btn.BackgroundColor3 = Color3.fromRGB(30, 8, 58)
            btn.TextColor3       = m.col
            btn.TextSize         = 11
            btn.Font             = Enum.Font.GothamBold
            btn.BorderSizePixel  = 0
            btn.LayoutOrder      = idx
            btn.Parent           = spFrame
            Instance.new("UICorner", btn)
            local bs = Instance.new("UIStroke", btn)
            bs.Color     = Color3.fromRGB(160, 50, 255)
            bs.Thickness = 1

            btn.MouseButton1Click:Connect(function()
                for _, d in pairs(controlled) do
                    if d.bp and d.bp.Parent then
                        d.bp.MaxForce = Vector3.zero
                    end
                end
                activeMode   = m.mode
                isActivated  = true
                modeLbl.Text = "MODE: " .. m.mode:upper()
                createGasterGui()
                sweepMap()
            end)
        end

        -- ── SETTINGS ─────────────────────────────────────────────────────
        sLabel("SETTINGS", 8)

        local pullTB  = makeSettingRow("PULL STRENGTH",  1500, "snake + blackhole speed", 9)
        local radTB   = makeSettingRow("RADIUS (studs)", 7,    "formation spread size",   10)
        local rangeTB = makeSettingRow("DETECT RANGE",   9999, "studs (9999 = full map)", 11)

        pullTB.FocusLost:Connect(function()
            local v = tonumber(pullTB.Text:match("^%s*(.-)%s*$"))
            if v and v > 0 then
                pullStrength = v
                for _, d in pairs(controlled) do
                    if d.bp and d.bp.Parent then
                        d.bp.P = v
                        d.bp.D = v * 0.12
                    end
                end
                pullTB.Text = tostring(v)
            else
                pullTB.Text = tostring(pullStrength)
            end
        end)

        radTB.FocusLost:Connect(function()
            local v = tonumber(radTB.Text:match("^%s*(.-)%s*$"))
            if v and v > 0 then radius = v; radTB.Text = tostring(v)
            else radTB.Text = tostring(radius) end
        end)

        rangeTB.FocusLost:Connect(function()
            local v = tonumber(rangeTB.Text:match("^%s*(.-)%s*$"))
            if v and v > 0 then detectionRange = v; rangeTB.Text = tostring(v)
            else rangeTB.Text = tostring(detectionRange) end
        end)

        -- ── ACTIONS ──────────────────────────────────────────────────────
        sLabel("ACTIONS", 12)

        local scanBtn = makeSingleBtn(
            "SCAN PARTS",
            Color3.fromRGB(18, 60, 22), Color3.fromRGB(80, 255, 120), 13)

        local releaseBtn = makeSingleBtn(
            "RELEASE ALL",
            Color3.fromRGB(60, 32, 8), Color3.fromRGB(255, 155, 55), 14)

        local deactivateBtn = makeSingleBtn(
            "DEACTIVATE",
            Color3.fromRGB(75, 8, 8), Color3.fromRGB(255, 55, 55), 15)

        scanBtn.MouseButton1Click:Connect(function()
            sweepMap()
        end)

        releaseBtn.MouseButton1Click:Connect(function()
            releaseAll()
            destroyGasterGui()
            isActivated  = false
            activeMode   = "none"
            lastMode     = "none"
            modeLbl.Text = "MODE: NONE"
        end)

        deactivateBtn.MouseButton1Click:Connect(function()
            releaseAll()
            destroyGasterGui()
            isActivated = false
            activeMode  = "none"
            scriptAlive = false
            gui:Destroy()
            local icon = pg:FindFirstChild("ManipIcon")
            if icon then icon:Destroy() end
            print("Deactivated.")
        end)

        -- Close → mini icon
        closeBtn.MouseButton1Click:Connect(function()
            gui:Destroy()

            local miniGui = Instance.new("ScreenGui")
            miniGui.Name         = "ManipIcon"
            miniGui.ResetOnSpawn = false
            miniGui.DisplayOrder = 999
            miniGui.Parent       = pg

            local ib = Instance.new("TextButton")
            ib.Text             = "M"
            ib.Size             = UDim2.fromOffset(44, 44)
            ib.Position         = UDim2.new(1, -54, 0, 10)
            ib.BackgroundColor3 = Color3.fromRGB(22, 10, 50)
            ib.TextColor3       = Color3.fromRGB(195, 140, 255)
            ib.TextSize         = 16
            ib.Font             = Enum.Font.GothamBold
            ib.BorderSizePixel  = 0
            ib.Parent           = miniGui
            Instance.new("UICorner", ib)
            local ibStroke = Instance.new("UIStroke", ib)
            ibStroke.Color     = Color3.fromRGB(90, 40, 180)
            ibStroke.Thickness = 1.5

            ib.MouseButton1Click:Connect(function()
                miniGui:Destroy()
                createGUI()
                -- If still in a Gaster mode, reopen its sub-GUI
                if GASTER_MODES[activeMode] then
                    createGasterGui()
                end
            end)
        end)

        -- ── DRAG (main panel) ─────────────────────────────────────────────
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
    end  -- end createGUI

    -- ── BOOT ─────────────────────────────────────────────────────────────
    createGUI()
    task.spawn(mainLoop)
    task.spawn(scanLoop)
    print("MANIPULATOR KII — Ready.")
end  -- end main

local ok, err = pcall(main)
if not ok then warn("MANIPULATOR KII ERROR: " .. tostring(err)) end
