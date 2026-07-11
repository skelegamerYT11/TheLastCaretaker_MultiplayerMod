local UEHelpers = require("UEHelpers")

print("[MultiplayerSync] Mod restarted with Network Hooks!\n")

local DummyActor = nil
local lastSyncX = 0
local lastSyncY = 0
local lastSyncZ = 0
local lastSyncYaw = 0
local lastSpawnAttempt = 0

-- CONTINUOUS EXTRACTION AND INJECTION (10 FPS)
LoopAsync(100, function()
    ExecuteInGameThread(function()
        -- 1. EXTRACT OWN COORDINATES -> coords_out.txt
        pcall(function()
            local PC = UEHelpers.GetPlayerController()
            if PC and PC:IsValid() then
                local pawn = PC.Pawn
                if pawn and pawn:IsValid() then
                    local loc = pawn:K2_GetActorLocation()
                    local rot = pawn:K2_GetActorRotation()
                    if loc then
                        local x = loc.X or loc.x or 0
                        local y = loc.Y or loc.y or 0
                        local z = loc.Z or loc.z or 0
                        local yaw = rot and (rot.Yaw or rot.yaw or 0) or 0
                        
                        -- Only if there is real movement (saves CPU and disk writes)
                        if x ~= lastSyncX or y ~= lastSyncY or z ~= lastSyncZ or yaw ~= lastSyncYaw then
                            lastSyncX = x
                            lastSyncY = y
                            lastSyncZ = z
                            lastSyncYaw = yaw
                            
                            local file = io.open("coords_out.txt", "w")
                            if file then
                                file:write(tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. "," .. tostring(yaw) .. "\n")
                                file:close()
                            end
                        end
                    end
                end
            end
        end)

        -- 2. READ FRIEND COORDINATES -> Apply
        pcall(function()
            local file = io.open("coords_in.txt", "r")
            if file then
                local data = file:read("*a")
                file:close()
                
                if data and data ~= "" then
                    local x_str, y_str, z_str, yaw_str = string.match(data, "([^,]+),([^,]+),([^,]+),([^,]+)")
                    if x_str and y_str and z_str and yaw_str then
                        local x = tonumber(x_str)
                        local y = tonumber(y_str)
                        local z = tonumber(z_str)
                        local yaw = tonumber(yaw_str)
                        
                        local PC = UEHelpers.GetPlayerController()
                        if PC and PC:IsValid() then
                            local myPawn = PC.Pawn
                            if myPawn and myPawn:IsValid() then
                                
                                if not DummyActor or not DummyActor:IsValid() then
                                    if not lastSpawnAttempt or (os.time() - lastSpawnAttempt > 2) then
                                        lastSpawnAttempt = os.time()
                                        local World = PC:GetWorld()
                                        if World and World:IsValid() then
                                            print("[MultiplayerSync] Spawning Friend's Avatar!\n")
                                            local spawnLoc = {X = x, Y = y, Z = z + 50} -- Raised slightly to avoid getting stuck
                                            local spawnRot = {Pitch = 0, Yaw = yaw, Roll = 0}
                                            
                                            -- Correct syntax for UE4SS
                                            DummyActor = World:SpawnActor(myPawn:GetClass(), spawnLoc, spawnRot)
                                        end
                                    end
                                else
                                    local currentLoc = DummyActor:K2_GetActorLocation()
                                    local targetLoc = {X=x, Y=y, Z=z}
                                    local targetRot = {Pitch=0.0, Yaw=yaw, Roll=0.0}
                                    
                                    local velX = (x - currentLoc.X) * 10.0
                                    local velY = (y - currentLoc.Y) * 10.0
                                    local velZ = (z - currentLoc.Z) * 10.0

                                    pcall(function() DummyActor:K2_TeleportTo(targetLoc, targetRot) end)
                                    
                                    pcall(function()
                                        local movement = DummyActor.CharacterMovement
                                        if movement and movement:IsValid() then
                                            movement.Velocity = {X=velX, Y=velY, Z=velZ}
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end)
local lastReceivedDoorStates = {}

        -- 3. READ EVENTS (DOORS) FROM FRIEND
        pcall(function()
            local file = io.open("event_in.txt", "r")
            if file then
                local data = file:read("*a")
                file:close()
                -- Clear file IMMEDIATELY to prevent crash loops on errors
                io.open("event_in.txt", "w"):close()
                
                if data and data ~= "" then
                    for line in data:gmatch("[^\r\n]+") do
                        -- 4-block parsing to support future extensions
                        local evType, evP1, evP2, evP3 = string.match(line, "([^,]+),([^,]+),([^,]*),?(.*)")
                        
                        if evType == "DOOR" and evP1 then
                            local stateInt = tonumber(evP2)
                            -- Prevent infinite bounce (loop) if state is identical to last received
                            if stateInt and lastReceivedDoorStates[evP1] ~= stateInt then
                                lastReceivedDoorStates[evP1] = stateInt
                                print("[MULTIPLAYER] Syncing door in your world: " .. evP1 .. " -> " .. tostring(stateInt) .. "\n")
                                local doors = FindAllOf("VoyageDoorActor")
                                if doors then
                                    for _, d in pairs(doors) do
                                        if d:IsValid() and d:GetFName():ToString() == evP1 then
                                            -- Must update game logic BESIDES visual state
                                            pcall(function()
                                                d.DoorStateDesired = stateInt
                                                d.DoorState = stateInt
                                                if stateInt == 0 then
                                                    d:SetDoorPosition(0.0, true)
                                                else
                                                    d:SetDoorPosition(1.0, true)
                                                end
                                            end)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end)
    return false
end)

local lastSentDoorStates = {}
-- INTERCEPTION SYSTEM (MULTIPLE HOOKING)
print("Attempting to register Multiple Hooks (Phase 2)...\n")
pcall(function()
    
    -- STATE SPECIFIC HOOK
    RegisterHook("/Script/Voyage.VoyageDoorActor:SetDoorState", function(Context, StateParam)
        pcall(function()
            local obj = Context:get()
            if obj and obj:IsValid() then
                local doorName = obj:GetFName():ToString()
                
                local stateVal = -1
                pcall(function() stateVal = obj.DoorStateDesired end)
                if stateVal == -1 or not stateVal then
                    pcall(function() stateVal = obj.DoorState end)
                end
                
                -- Prevent multiple sending
                if lastSentDoorStates[doorName] ~= stateVal then
                    lastSentDoorStates[doorName] = stateVal
                    
                    print("[NETWORK EVENT] You touched the door: " .. doorName .. " -> " .. tostring(stateVal) .. "\n")
                    
                    local file = io.open("event_out.txt", "a")
                    if file then
                        file:write("DOOR," .. doorName .. "," .. tostring(stateVal) .. "\n")
                        file:close()
                    end
                end
            end
        end)
    end)

    print("Multiple Hooks successfully registered (No Crash)!\n")
end)
