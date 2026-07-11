local UEHelpers = require("UEHelpers")

print("[MultiplayerSync] Mod riavviata con Hook di Rete!\n")

local DummyActor = nil
local lastSyncX = 0
local lastSyncY = 0
local lastSyncZ = 0
local lastSyncYaw = 0
local lastSpawnAttempt = 0

-- ESTRAZIONE E INIEZIONE CONTINUA (10 FPS)
LoopAsync(100, function()
    ExecuteInGameThread(function()
        -- 1. ESTRAZIONE PROPRIE COORDINATE -> coords_out.txt
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
                        
                        -- Solo se c'è un movimento reale (risparmia CPU e scritture disco)
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

        -- 2. LETTURA COORDINATE AMICO -> Applicazione
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
                                            print("[MultiplayerSync] Genero l'Avatar dell'Amico!\n")
                                            local spawnLoc = {X = x, Y = y, Z = z + 50} -- Alzato leggermente per non incastrarsi
                                            local spawnRot = {Pitch = 0, Yaw = yaw, Roll = 0}
                                            
                                            -- Sintassi corretta per UE4SS
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

        -- 3. LETTURA EVENTI (PORTE) DAL TUO AMICO
        pcall(function()
            local file = io.open("event_in.txt", "r")
            if file then
                local data = file:read("*a")
                file:close()
                -- Svuota il file IMMEDIATAMENTE per evitare loop di crash se c'è un errore
                io.open("event_in.txt", "w"):close()
                
                if data and data ~= "" then
                    for line in data:gmatch("[^\r\n]+") do
                        -- Parsing a 4 blocchi per supportare future estensioni
                        local evType, evP1, evP2, evP3 = string.match(line, "([^,]+),([^,]+),([^,]*),?(.*)")
                        
                        if evType == "DOOR" and evP1 then
                            local stateInt = tonumber(evP2)
                            -- Previene il rimbalzo infinito (loop) se lo stato è identico all'ultimo ricevuto
                            if stateInt and lastReceivedDoorStates[evP1] ~= stateInt then
                                lastReceivedDoorStates[evP1] = stateInt
                                print("[MULTIPLAYER] Sincronizzo la porta nel tuo mondo: " .. evP1 .. " -> " .. tostring(stateInt) .. "\n")
                                local doors = FindAllOf("VoyageDoorActor")
                                if doors then
                                    for _, d in pairs(doors) do
                                        if d:IsValid() and d:GetFName():ToString() == evP1 then
                                            -- Dobbiamo aggiornare la mente del gioco OLTRE alla visuale
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
-- SISTEMA DI INTERCETTAZIONE (HACKING MULTIPLO)
print("Tentativo di registrazione Hook Multipli (Fase 2)...\n")
pcall(function()
    
    -- HOOK SPECIFICO PER LO STATO
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
                
                -- Previene l'invio multiplo
                if lastSentDoorStates[doorName] ~= stateVal then
                    lastSentDoorStates[doorName] = stateVal
                    
                    print("[EVENTO RETE] Hai toccato la porta: " .. doorName .. " -> " .. tostring(stateVal) .. "\n")
                    
                    local file = io.open("event_out.txt", "a")
                    if file then
                        file:write("DOOR," .. doorName .. "," .. tostring(stateVal) .. "\n")
                        file:close()
                    end
                end
            end
        end)
    end)

    print("Hook Multipli Registrati con successo (No Crash)!\n")
end)
