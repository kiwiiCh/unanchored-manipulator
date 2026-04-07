-- UNANCHORED MANIPULATOR KII — FINAL
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local player = Players.LocalPlayer

local function main()
    print("MANIPULATOR KII LOADED — " .. player.Name)

    -- CONFIG
    local pullStrength   = 1500
    local radius         = 7
    local detectionRange = 9999
    local isActivated    = false
    local activeMode     = "none"
    local scriptAlive    = true

    -- STATE
    local controlled = {}
    local partCount  = 0
    local snakeT     = 0

    -- Modes that use direct CFrame (zero lag, truly fixed to player)
    local CFRAME_MODES = { heart = true, rings = true, wall = true, box = true }

    -- ── NO-COLLISION: blocks pass through YOU, hit everyone else ─────────
    --[[
        NoCollisionConstraint between a controlled part and every limb of
        the LOCAL player only.  Other players are untouched so blocks still
        physically collide with them.
    ]]
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

    -- Refresh on respawn
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
            pcall(function() part.CanCollide = data.origCanCollide end)
        end
    end

    local function releaseAll()
        for part, data in pairs(controlled) do releasePart(part, data) end
        controlled = {}
        partCount  = 0
        snakeT     = 0
    end

    -- ── BLACK HOLE FLING ─────────────────────────────────────────────────
    local function enableFling(part, data)
        if data.bav and data.bav.Parent then
            data.bav.MaxTorque       = Vector3.new(1e6, 1e6, 1e6)
            data.bav.AngularVelocity = Vector3.new(
                math.random(-50, 50),
                math.random(60, 100),
                math.random(-50, 50)
            )
        end
        if data.touchConn then data.touchConn:Disconnect() end
        data.touchConn = part.Touched:Connect(function(hit)
            local hc  = hit.Parent
            local hp  = Players:GetPlayerFromCharacter(hc)
            if hp == player then return end
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
            char:FindFirstChild("HumanoidRootPart") or
            char:FindFirstChild("Torso")
        )
        if root and (part.Position - root.Position).Magnitude > detectionRange then
            return
        end

        local origCC    = part.CanCollide
        part.CanCollide = true   -- keep collisions on for other players

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

        local data = {
            bp            = bp,
            bav           = bav,
            touchConn     = nil,
            origCanCollide= origCC,
            ncc           = {}
        }

        applyNoCollision(part, data)

        -- CFrame modes: disable BodyPosition force immediately
        if CFRAME_MODES[activeMode] then
            bp.MaxForce = Vector3.zero
        end

        if activeMode == "blackhole" then enableFling(part, data) end

        controlled[part] = data
        partCount = partCount + 1
    end

    local function sweepMap()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isValid(obj) then grabPart(obj) end
        end
    end

    -- ── SNAKE: classic chain — each link follows the previous link's
    --    position history, giving a true chain/rope trailing effect ────────
    --[[
        We store a rolling history of the ROOT's world position.
        Link 1 follows a position N frames ago.
        Link 2 follows a position 2N frames ago.
        etc.
        This produces the old "chain" look where every segment
        smoothly trails the one before it.
    ]]
    local SNAKE_HIST_MAX  = 600   -- frames of history kept
    local SNAKE_GAP       = 8     -- frames between each link
    local snakeHistory    = {}    -- {Vector3, ...}

    local function getSnakeTarget(i)
        local idx = i * SNAKE_GAP
        idx = math.clamp(idx, 1, math.max(1, #snakeHistory))
        return snakeHistory[idx] or snakeHistory[#snakeHistory] or Vector3.zero
    end

    -- ── FORMATION (CFrame modes) ──────────────────────────────────────────
    local function getFormationCF(mode, i, n, origin, cf, t)
        if mode == "heart" then
            local a  = ((i-1) / math.max(n,1)) * math.pi * 2
            local hx =  16 * math.sin(a)^3
            local hz = -(13*math.cos(a) - 5*math.cos(2*a) - 2*math.cos(3*a) - math.cos(4*a))
            local s  = radius / 16
            return CFrame.new(origin + cf:VectorToWorldSpace(Vector3.new(hx*s, 0, hz*s)))

        elseif mode == "rings" then
            local a   = ((i-1) / math.max(n,1)) * math.pi*2 + t*1.4
            return CFrame.new(origin + Vector3.new(math.cos(a)*radius, 0, math.sin(a)*radius))

        elseif mode == "wall" then
            local cols = math.max(1, math.ceil(math.sqrt(n)))
            local col  = ((i-1) % cols) - math.floor(cols/2)
            local row  = math.floor((i-1) / cols) - 1
            return CFrame.new(
                origin
                + cf.LookVector  * radius
                + cf.RightVector * (col * 1.8)
                + cf.UpVector    * (row * 1.8 + 1)
            )

        elseif mode == "box" then
            local fV  = { cf.LookVector,-cf.LookVector, cf.RightVector,-cf.RightVector, cf.UpVector,-cf.UpVector }
            local fTa = { cf.RightVector,cf.RightVector,cf.LookVector,cf.LookVector,cf.RightVector,cf.RightVector }
            local fTb = { cf.UpVector,cf.UpVector,cf.UpVector,cf.UpVector,cf.LookVector,cf.LookVector }
            local fi  = ((i-1) % 6) + 1
            local si  = math.floor((i-1) / 6)
            local col = (si % 2) - 0.5
            local row = math.floor(si / 2) - 0.5
            local sp  = radius * 0.45
            return CFrame.new(origin + fV[fi]*radius + fTa[fi]*(col*sp) + fTb[fi]*(row*sp))
        end

        return CFrame.new(origin)
    end

    -- Black hole pet target: offset OUTSIDE the avatar, follows player
    local function getBHTarget(i, cf)
        --[[
            PointToWorldSpace maps a LOCAL offset into world space.
            The offset (3, 1, -5) places the cluster:
              3 studs to the right
              1 stud above the waist
              5 studs behind the player
            so it hovers beside/behind like a companion, never inside.
        ]]
        local pet = cf:PointToWorldSpace(Vector3.new(3, 1, -5))
        return pet + Vector3.new(
            math.sin(i * 73.1) * 0.2,
            math.cos(i * 53.7) * 0.2,
            math.sin(i * 31.9) * 0.2
        )
    end

    -- ── MAIN LOOP ────────────────────────────────────────────────────────
    local lastMode = "none"

    local function mainLoop()
        while scriptAlive do
            local dt = task.wait(0.016)
            snakeT   = snakeT + dt

            local char = player.Character
            local root = char and (
                char:FindFirstChild("HumanoidRootPart") or
                char:FindFirstChild("Torso")
            )
            if not root then continue end

            local pos = root.Position
            local cf  = root.CFrame
            local t   = tick()

            -- Update snake chain history every frame
            table.insert(snakeHistory, 1, pos)
            if #snakeHistory > SNAKE_HIST_MAX then
                table.remove(snakeHistory, SNAKE_HIST_MAX + 1)
            end

            -- Mode transitions
            if activeMode ~= lastMode then
                if lastMode == "blackhole" then
                    for _, d in pairs(controlled) do disableFling(d) end
                end
                if activeMode == "blackhole" then
                    for p, d in pairs(controlled) do enableFling(p, d) end
                end
                -- CFrame mode entered: zero out BodyPosition force
                if CFRAME_MODES[activeMode] then
                    for _, d in pairs(controlled) do
                        if d.bp and d.bp.Parent then
                            d.bp.MaxForce = Vector3.zero
                        end
                    end
                end
                -- Physics mode entered: restore BodyPosition force
                if not CFRAME_MODES[activeMode] and CFRAME_MODES[lastMode] then
                    for _, d in pairs(controlled) do
                        if d.bp and d.bp.Parent then
                            d.bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                        end
                    end
                end
                lastMode = activeMode
            end

            if not isActivated or activeMode == "none" or partCount == 0 then
                continue
            end

            -- Build array (dict has no order guarantee)
            local arr = {}
            for part, data in pairs(controlled) do
                if part.Parent and data.bp and data.bp.Parent then
                    table.insert(arr, { p = part, d = data })
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
                    -- Chain: each link chases a progressively older position
                    local target = getSnakeTarget(i)
                    data.bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                    data.bp.Position = target
                    data.bp.P        = pullStrength
                    data.bp.D        = pullStrength * 0.12

                elseif activeMode == "blackhole" then
                    local target = getBHTarget(i, cf)
                    data.bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                    data.bp.Position = target
                    data.bp.P        = pullStrength
                    data.bp.D        = pullStrength * 0.12

                elseif CFRAME_MODES[activeMode] then
                    data.bp.MaxForce = Vector3.zero
                    local targetCF   = getFormationCF(activeMode, i, n, pos, cf, t)
                    part.CFrame      = targetCF
                end
            end
        end
    end

    -- ── AUTO-SCAN ────────────────────────────────────────────────────────
    local function scanLoop()
        while scriptAlive do
            if isActivated and activeMode ~= "none" then
                sweepMap()
            end
            task.wait(1.5)
        end
    end

    -- ── GUI ──────────────────────────────────────────────────────────────
    local function createGUI()
        local pg  = player:WaitForChild("PlayerGui")
        local old = pg:FindFirstChild("ManipGUI")
        if old then old:Destroy() end

        local gui = Instance.new("ScreenGui")
        gui.Name           = "ManipGUI"
        gui.ResetOnSpawn   = false
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder   = 999
        gui.Parent         = pg

        -- ── MAIN PANEL ───────────────────────────────────────────────────
        --[[
            Fixed pixel size small enough for mobile (320 wide).
            Anchored to screen centre so it starts visible on all devices.
        ]]
        local W, H = 320, 460
        local panel = Instance.new("Frame")
        panel.Name               = "Panel"
        panel.Size               = UDim2.fromOffset(W, H)
        panel.Position           = UDim2.new(0.5, -W/2, 0.5, -H/2)
        panel.BackgroundColor3   = Color3.fromRGB(10, 10, 25)
        panel.BorderSizePixel    = 0
        panel.ClipsDescendants   = true
        panel.Parent             = gui
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
        local panelStroke        = Instance.new("UIStroke", panel)
        panelStroke.Color        = Color3.fromRGB(90, 40, 180)
        panelStroke.Thickness    = 1.5

        -- Title bar (also the drag handle — full width)
        local titleBar = Instance.new("Frame")
        titleBar.Name             = "TitleBar"
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

        -- ── SCROLL CONTENT ───────────────────────────────────────────────
        --[[
            Everything below the title bar lives in a ScrollingFrame so
            small screens can scroll to reach all controls.
        ]]
        local scroll = Instance.new("ScrollingFrame")
        scroll.Name                    = "Scroll"
        scroll.Size                    = UDim2.new(1, 0, 1, -40)
        scroll.Position                = UDim2.fromOffset(0, 40)
        scroll.BackgroundTransparency  = 1
        scroll.BorderSizePixel         = 0
        scroll.ScrollBarThickness      = 3
        scroll.ScrollBarImageColor3    = Color3.fromRGB(90, 40, 180)
        scroll.CanvasSize              = UDim2.fromOffset(0, 400)
        scroll.AutomaticCanvasSize     = Enum.AutomaticSize.Y
        scroll.Parent                  = panel

        local layout = Instance.new("UIListLayout", scroll)
        layout.Padding            = UDim.new(0, 6)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.SortOrder          = Enum.SortOrder.LayoutOrder

        local padding = Instance.new("UIPadding", scroll)
        padding.PaddingTop    = UDim.new(0, 6)
        padding.PaddingBottom = UDim.new(0, 6)
        padding.PaddingLeft   = UDim.new(0, 8)
        padding.PaddingRight  = UDim.new(0, 8)

        -- Helper: section label
        local function sectionLabel(txt, order)
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
            return l
        end

        -- Helper: generic button
        local function makeBtn(txt, bgCol, txtCol, order, h)
            h = h or 36
            local b = Instance.new("TextButton")
            b.Text             = txt
            b.Size             = UDim2.new(1, 0, 0, h)
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

        -- Helper: setting row (label + textbox)
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

        -- ── STATUS ───────────────────────────────────────────────────────
        sectionLabel("STATUS", 1)

        local statusLbl = Instance.new("TextLabel")
        statusLbl.Text            = "IDLE  |  PARTS: 0"
        statusLbl.Size            = UDim2.new(1, 0, 0, 24)
        statusLbl.BackgroundTransparency = 1
        statusLbl.TextColor3      = Color3.fromRGB(80, 255, 140)
        statusLbl.TextSize        = 12
        statusLbl.Font            = Enum.Font.GothamBold
        statusLbl.TextXAlignment  = Enum.TextXAlignment.Left
        statusLbl.LayoutOrder     = 2
        statusLbl.Parent          = scroll

        local modeLbl = Instance.new("TextLabel")
        modeLbl.Text            = "MODE: NONE"
        modeLbl.Size            = UDim2.new(1, 0, 0, 20)
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

        -- ── MODE BUTTONS ─────────────────────────────────────────────────
        sectionLabel("MODE", 4)

        local modeGrid = Instance.new("Frame")
        modeGrid.Size             = UDim2.new(1, 0, 0, 84)
        modeGrid.BackgroundTransparency = 1
        modeGrid.LayoutOrder      = 5
        modeGrid.Parent           = scroll

        local gl = Instance.new("UIGridLayout", modeGrid)
        gl.CellSize            = UDim2.new(0.5, -4, 0, 36)
        gl.CellPadding         = UDim2.fromOffset(4, 4)
        gl.HorizontalAlignment = Enum.HorizontalAlignment.Left
        gl.SortOrder           = Enum.SortOrder.LayoutOrder

        local modeList = {
            { txt = "SNAKE",      mode = "snake",     col = Color3.fromRGB(160, 110, 255) },
            { txt = "HEART",      mode = "heart",     col = Color3.fromRGB(255, 100, 150) },
            { txt = "RINGS",      mode = "rings",     col = Color3.fromRGB(80,  210, 255) },
            { txt = "WALL",       mode = "wall",      col = Color3.fromRGB(255, 200,  90) },
            { txt = "BOX CAGE",   mode = "box",       col = Color3.fromRGB(160, 255, 100) },
            { txt = "BLACK HOLE", mode = "blackhole", col = Color3.fromRGB(220, 220, 220) },
        }

        for idx, m in ipairs(modeList) do
            local btn = Instance.new("TextButton")
            btn.Text             = m.txt
            btn.BackgroundColor3 = Color3.fromRGB(26, 14, 55)
            btn.TextColor3       = m.col
            btn.TextSize         = 11
            btn.Font             = Enum.Font.GothamBold
            btn.BorderSizePixel  = 0
            btn.LayoutOrder      = idx
            btn.Parent           = modeGrid
            Instance.new("UICorner", btn)

            btn.MouseButton1Click:Connect(function()
                -- Restore/zero MaxForce on mode swap
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

        -- ── SETTINGS ─────────────────────────────────────────────────────
        sectionLabel("SETTINGS", 6)

        local pullTB  = makeSettingRow("PULL STRENGTH",  1500, "snake + black hole speed", 7)
        local radTB   = makeSettingRow("RADIUS (studs)", 7,    "formation spread",         8)
        local rangeTB = makeSettingRow("DETECT RANGE",   9999, "studs  (9999 = full map)", 9)

        -- Bulletproof parse: trim whitespace, validate positive number, apply live
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

        -- ── ACTION BUTTONS ────────────────────────────────────────────────
        sectionLabel("ACTIONS", 10)

        local scanBtn = makeBtn(
            "SCAN PARTS",
            Color3.fromRGB(18, 60, 22), Color3.fromRGB(80, 255, 120),
            11
        )
        local releaseBtn = makeBtn(
            "RELEASE ALL",
            Color3.fromRGB(60, 32, 8), Color3.fromRGB(255, 155, 55),
            12
        )
        local deactivateBtn = makeBtn(
            "DEACTIVATE",
            Color3.fromRGB(75, 8, 8), Color3.fromRGB(255, 55, 55),
            13
        )

        scanBtn.MouseButton1Click:Connect(function()
            sweepMap()
        end)

        releaseBtn.MouseButton1Click:Connect(function()
            releaseAll()
            isActivated  = false
            activeMode   = "none"
            lastMode     = "none"
            modeLbl.Text = "MODE: NONE"
        end)

        deactivateBtn.MouseButton1Click:Connect(function()
            releaseAll()
            isActivated = false
            activeMode  = "none"
            scriptAlive = false
            gui:Destroy()
            local icon = pg:FindFirstChild("ManipIcon")
            if icon then icon:Destroy() end
            print("Deactivated.")
        end)

        -- ── CLOSE → MINI ICON ─────────────────────────────────────────────
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
            Instance.new("UIStroke", ib)

            ib.MouseButton1Click:Connect(function()
                miniGui:Destroy()
                createGUI()
            end)
        end)

        -- ── DRAG — attached to the FULL PANEL, not just title bar ─────────
        --[[
            Listening on the PANEL itself for InputBegan/Changed/Ended
            means ANY tap/click anywhere on the window starts a drag.
            We guard against the scroll frame consuming the input by also
            connecting directly to titleBar which is on top (ZIndex 10).

            Strategy:
              InputBegan on titleBar → start drag
              InputChanged on UserInputService → move panel
              InputEnded on UserInputService → stop drag

            This is the most reliable cross-platform approach.
        ]]
        local dragging     = false
        local dragStartM   = Vector2.zero
        local dragStartPos = UDim2.new()

        local function startDrag(inp)
            dragging     = true
            dragStartM   = Vector2.new(inp.Position.X, inp.Position.Y)
            dragStartPos = panel.Position
        end

        -- Title bar input (primary drag target)
        titleBar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                startDrag(inp)
            end
        end)

        -- Also allow dragging from the panel background edges
        panel.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                -- Only start if not already dragging (scroll may fire this too)
                if not dragging then startDrag(inp) end
            end
        end)

        UserInputService.InputChanged:Connect(function(inp)
            if not dragging then return end
            if inp.UserInputType == Enum.UserInputType.MouseMovement
                or inp.UserInputType == Enum.UserInputType.Touch then
                local delta = Vector2.new(inp.Position.X, inp.Position.Y) - dragStartM
                panel.Position = UDim2.new(
                    dragStartPos.X.Scale, dragStartPos.X.Offset + delta.X,
                    dragStartPos.Y.Scale, dragStartPos.Y.Offset + delta.Y
                )
            end
        end)

        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        return gui
    end

    -- Boot
    createGUI()
    task.spawn(mainLoop)
    task.spawn(scanLoop)
    print("Ready.")
end

local ok, err = pcall(main)
if not ok then warn("Error: " .. tostring(err)) end
