-- Numain Master Script: Optimized & Combined
-- Ported from opti.luau, joinevent+goToZone.luau, joinzone+autofarm.luau

-- 1. Configuration Check
if not _G.NumainSettings then
    _G.NumainSettings = {
        OptimizeRAM = false,
        AutoJoin = true,
        SelectedZone = 2, -- 2=Blue, 3=Red, 4=Pink, 5=Yellow
        AutoFarm = true
    }
end

local numainConfig = _G.NumainSettings

-- Internal State
local lastMoveTime = tick()
local lastZoneCheck = tick()
local connectionsSet = false

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Constants
local ZONE_CENTER = Vector3.new(-18508.49609375, 16.3377742767334, -29108.65234375)
local ZONE_RADIUS = 30
local NETWORK = ReplicatedStorage:WaitForChild("Network")
local INSTANCING_REMOTE = NETWORK:WaitForChild("Instancing_FireCustomFromClient")
local AUTOFARM_REMOTE = NETWORK:WaitForChild("AutoFarm_Enable")

-- 2. Optimization Logic (Ported from opti.luau)
local function runOptimization()
    if not numainConfig.OptimizeRAM then return end
    print("Numain: Running RAM Optimization...")

    local allowedInWorkspace = {["__THINGS"] = true, ["Camera"] = true, ["Terrain"] = true, [LocalPlayer.Name] = true}
    local allowedInThings = {["__INSTANCE_CONTAINER"] = true, ["__REMOTES"] = true, ["Breakables"] = true, ["Pets"] = true}

    local function killRAMUsage(obj)
        if not numainConfig.OptimizeRAM then return end
        if obj:IsA("BasePart") then
            obj.Material = Enum.Material.Plastic
            obj.Reflectance = 0
            obj.CastShadow = false
        elseif obj:IsA("Texture") or obj:IsA("Decal") then
            obj:Destroy()
        elseif obj:IsA("MeshPart") then
            obj.TextureID = "" 
        elseif obj:IsA("SpecialMesh") then
            obj.TextureId = ""
        end
    end

    -- Cleanup Workspace
    for _, item in ipairs(Workspace:GetChildren()) do
        if not allowedInWorkspace[item.Name] then pcall(function() item:Destroy() end) end
    end

    -- Cleanup __THINGS
    local things = Workspace:FindFirstChild("__THINGS")
    if things then
        for _, item in ipairs(things:GetChildren()) do
            if not allowedInThings[item.Name] then pcall(function() item:Destroy() end) end
        end

        -- Strip Pets and Breakables (Purge current)
        for _, folderName in pairs({"Pets", "Breakables"}) do
            local folder = things:FindFirstChild(folderName)
            if folder then
                for _, item in ipairs(folder:GetDescendants()) do killRAMUsage(item) end
                
                -- Set up background listeners ONLY ONCE
                if not connectionsSet then
                    folder.DescendantAdded:Connect(killRAMUsage)
                end
            end
        end
        connectionsSet = true
        
        -- Event Cleanup Logic
        local active = things:FindFirstChild("__INSTANCE_CONTAINER") and things.__INSTANCE_CONTAINER:FindFirstChild("Active")
        local easter = active and active:FindFirstChild("EasterHatchEvent")
        if easter then
            for _, item in ipairs(easter:GetChildren()) do
                if item.Name ~= "BREAK_ZONES" and item.Name ~= "1 | Cloud Meadow" then
                    if item:IsA("Folder") then
                        local lod = item:FindFirstChild("PARTS_LOD")
                        if lod then
                            for _, part in ipairs(lod:GetChildren()) do
                                if part.Name ~= "GROUND" then part:Destroy() end
                            end
                        end
                        for _, sub in ipairs(item:GetChildren()) do
                            if sub:IsA("Folder") and sub.Name ~= "PARTS_LOD" then sub:Destroy() end
                        end
                    end
                end
            end
        end
    end

    -- Lighting & View
    Lighting.GlobalShadows = false
    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("PostEffect") or effect:IsA("BloomEffect") or effect:IsA("BlurEffect") then
            effect.Enabled = false
        end
    end
    -- Use global settings() function carefully
    pcall(function() settings().Rendering.QualityLevel = 1 end)
    Workspace.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
end

-- 3. Utilities
local function walkToPosition(targetPos)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    humanoid:MoveTo(targetPos)
    return humanoid
end

local function getRandomZonePosition()
    local randomX = ZONE_CENTER.X + (math.random() - 0.5) * 2 * ZONE_RADIUS
    local randomZ = ZONE_CENTER.Z + (math.random() - 0.5) * 2 * ZONE_RADIUS
    return Vector3.new(randomX, ZONE_CENTER.Y, randomZ)
end

local function getLeaveButton()
    return LocalPlayer.PlayerGui:FindFirstChild("LeaveInstanceHome", true) or 
           (LocalPlayer.PlayerGui:FindFirstChild("MainLeft") and 
            LocalPlayer.PlayerGui.MainLeft:FindFirstChild("LeaveInstanceHome", true))
end

local function pressButton(button)
    if not button then return end
    pcall(function()
        if getconnections then
            for _, conn in pairs(getconnections(button.Activated)) do conn:Fire() end
            for _, conn in pairs(getconnections(button.MouseButton1Click)) do conn:Fire() end
        else
            button:Activate()
        end
    end)
end

-- 4. Main Core Logic
local function getClosestBreakable()
    local active = Workspace:FindFirstChild("__THINGS") and Workspace.__THINGS:FindFirstChild("__INSTANCE_CONTAINER") and Workspace.__THINGS.__INSTANCE_CONTAINER:FindFirstChild("Active")
    local easter = active and active:FindFirstChild("EasterHatchEvent")
    local breakZones = easter and easter:FindFirstChild("BREAK_ZONES")
    
    if not breakZones then return nil end
    
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end
    
    local myPos = character.HumanoidRootPart.Position
    local closestItem = nil
    local shortestDistance = math.huge

    for _, item in pairs(breakZones:GetChildren()) do
        local itemPos = item:IsA("Model") and item:GetPivot().Position or (item:IsA("BasePart") and item.Position)
        if itemPos then
            local distance = (myPos - itemPos).Magnitude
            if distance < shortestDistance then
                shortestDistance = distance
                closestItem = item
            end
        end
    end
    return closestItem
end

local function farmSequence()
    if not numainConfig.AutoFarm then return end
    
    local target = getClosestBreakable()
    if not target then return end

    print("Numain: Farming target...")
    local targetPos = target:GetPivot().Position
    local walkDestination = targetPos + Vector3.new(math.random(-5,5), 0, math.random(-5,5))
    
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    if humanoid then 
        humanoid:MoveTo(walkDestination)
        local timeout = 0
        repeat task.wait(0.1) timeout = timeout + 0.1 until (character.HumanoidRootPart.Position - walkDestination).Magnitude < 3 or timeout > 4
    end

    -- Enable AutoFarm
    pcall(function() AUTOFARM_REMOTE:InvokeServer() end)
    task.wait(0.5)

    -- Leave
    local leaveBtn = getLeaveButton()
    if leaveBtn then
        print("Numain: Leaving instance...")
        pressButton(leaveBtn)
        task.wait(2)
        -- Wait for teleport/reload
        if not LocalPlayer.Character or LocalPlayer.Character.Parent == nil then LocalPlayer.CharacterAdded:Wait() end
        repeat task.wait() until LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        
        -- Walk back to zone
        local resetPos = getRandomZonePosition()
        walkToPosition(resetPos)
    end
end

-- 5. Orchestration Loop
task.spawn(function()
    while true do
        local currentTime = tick()
        
        -- A. Check for Join Button (Event Entry)
        local joinBtn = LocalPlayer.PlayerGui:FindFirstChild("JoinEvent", true)
        if numainConfig.AutoJoin and joinBtn and joinBtn.Visible and joinBtn.AbsoluteSize.X > 0 then
            print("Numain: Event Detected! Joining...")
            pressButton(joinBtn)
            task.wait(5)
            
            -- Optimize after joining
            if numainConfig.OptimizeRAM then
                runOptimization()
            end
            
            -- Select Zone
            print("Numain: Selecting Zone", numainConfig.SelectedZone)
            pcall(function()
                INSTANCING_REMOTE:FireServer("EasterHatchEvent", "ZonePortal", numainConfig.SelectedZone)
            end)
            
            task.wait(5) -- Wait for teleport
            
            -- Execute Farm (includes leaving and returning to zone)
            if numainConfig.AutoFarm then
                farmSequence()
            end
            
            lastMoveTime = tick() -- Reset timers after event
        else
            -- B. idle / Wait Logic (When NOT in an event)
            local character = LocalPlayer.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            
            if hrp then
                local distFromZone = (hrp.Position - ZONE_CENTER).Magnitude
                
                -- 1. Check if user is in the zone (every 10s)
                if currentTime - lastZoneCheck > 10 then
                    if distFromZone > ZONE_RADIUS + 5 then
                        print("Numain: Outside zone! Walking back...")
                        walkToPosition(getRandomZonePosition())
                        lastMoveTime = tick()
                    end
                    lastZoneCheck = currentTime
                end
                
                -- 2. Move every 2 minutes (Anti-AFK)
                if currentTime - lastMoveTime > 120 then
                    print("Numain: Anti-AFK Move...")
                    walkToPosition(getRandomZonePosition())
                    lastMoveTime = tick()
                end
            end
        end

        task.wait(1)
    end
end)

print("Numain Master Script Loaded!")
