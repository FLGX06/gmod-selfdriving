--[[
    Copyright (c) 2020 Lukáš Horáček
    https://github.com/flgx16/gmod-selfdriving

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <https://www.gnu.org/licenses/>.
--]]

--@name Self-Driving
--@author flgx
--@shared

--// Shared functions
local function getTime()
    return timer.systime()
end

---------------------------------------------
if SERVER then
    local inputs = {
        Active = "number";
        Driver = "entity";
        Speed = "number";
        Front = "number";
        Left = "number";
        Right = "number";
    }

    local outputs = {
        Engine = "number";
        Throttle = "number";
        Steer = "number";
        Brake = "number";
        Handbrake = "number";
        Lock = "number";
    }

    --// Settings
    local peakTorque = 190
    local treatAsTurn = 750
    local vehicleWidth = 62

    --// Variables
    local engineActive = false
    local swInControl = true

    local engine = 0
    local throttle = 0
    local steer = 0
    local brake = 0
    local handbrake = 0
    local lock = 0

    local speed = 0

    local front = {
        dist = 0;
    }
    local left = {
        dist = 0;
    }
    local right = {
        dist = 0;
    }

    --// Road
    local straight = false
    local leftTurn = false
    local rightTurn = false

    local leftTurnData = nil
    local rightTurnData = nil

    --// State
    local waitingToTurnLeft = false
    local waitingToTurnRight = false

    local turningLeft = false
    local turningRight = false

    local turnState = nil

    local pullOver = true

    --// Target speed
    local targetSpeed = 0

    --// Offset
    local offset = 0

    --// No turn distances
    local noTurnDist = {
        left = 0;
        right = 0;
    }

    --// Distance counters
    local activeDistanceCounters = {}

    --// Last time
    local lastTime = getTime()

    --// Functions
    local function createDistanceCounter()
        local counter = {
            createdAt = getTime();
            distance = 0;
        }

        table.insert(activeDistanceCounters, counter)
        return counter
    end

    local function processEngine()
        if engineActive then
            engine = 0
        else
            engine = 1
        end
    end

    local function processThrottle()
        if speed > targetSpeed then
            throttle = 0

            local b = (speed - targetSpeed) / 500

            if speed > 25 then
                brake = b
            else
                brake = 0
                handbrake = 1
            end
        else
            brake = 0
            throttle = math.min(0.5, (targetSpeed - speed) / targetSpeed)
        end
    end

    local function figureOutRoad()
        straight = front.dist > 250 + speed * 0.75
        if turningLeft then
            leftTurn = left.dist > treatAsTurn * 1
        else
            leftTurn = left.dist > treatAsTurn * 2
        end
        if turningRight then
            rightTurn = right.dist > treatAsTurn * 0.5
        else
            rightTurn = right.dist > treatAsTurn
        end

        if leftTurn then
            if not leftTurnData then
                leftTurnData = {
                    leftDist = noTurnDist.right;
                    rightDist = left.dist / 2;
                    maxFrontDistTravel = math.min(front.dist / 2, left.dist / 3 - vehicleWidth * 2);
                }
            end
        else
            leftTurnData = nil
        end
        if rightTurn then
            if not rightTurnData then
                rightTurnData = {
                    leftDist = right.dist / 2;
                    rightDist = noTurnDist.right;
                    maxFrontDistTravel = math.min(front.dist / 2, right.dist / 4 - vehicleWidth * 2);
                }
            end
        else
            rightTurnData = nil
        end
    end

    local function calculateOffset(leftDist, rightDist)
        leftDist = math.min(1500, leftDist)
        rightDist = math.min(1500, rightDist)

        return (leftDist / 2 - rightDist) / 1500
    end

    local function mainProcess()
        --// Cancel turning if already turned
        if turningLeft and not leftTurn and straight then turningLeft = false end
        if turningRight and not rightTurn and straight then turningRight = false end

        --// Turn if waiting to turn and turn is found
        if waitingToTurnLeft and leftTurn then turningLeft = true end
        if waitingToTurnRight and rightTurn then turningRight = true end

        --// Turn state
        if (turningLeft or turningRight) then
            if not turnState then
                turnState = {
                    data = (turningLeft and leftTurnData) or (turningRight and rightTurnData);
                    counter = createDistanceCounter();
                }
            end
        else
            turnState = nil
        end

        --// Speed
        local normalTargetSpeed = math.min(1000, front.dist)
        if front.dist < 100 then normalTargetSpeed = 0 end

        if turningLeft or turningRight then
            targetSpeed = math.min(500, normalTargetSpeed)
        else
            if rightTurn then
                targetSpeed = math.min(750, normalTargetSpeed - 100)
            else
                targetSpeed = math.min(1000, normalTargetSpeed - 100)
            end

            targetSpeed = normalTargetSpeed
        end

        --// Path
        if turningLeft then
            if turnState.counter.distance > turnState.data.maxFrontDistTravel then
                --offset = math.max(left.dist - 250, 750) / 1500
                offset = calculateOffset(left.dist, math.min(front.dist, right.dist)) + 0.5
            else
                offset = 0
            end
        elseif turningRight then
            if turnState.counter.distance > turnState.data.maxFrontDistTravel then
                --offset = -math.max(right.dist - 250, 750) / 1500
                offset = calculateOffset(math.max(front.dist, left.dist), right.dist) - 0.5
            else
                offset = 0
            end
        else
            if not leftTurn then noTurnDist.left = left.dist end
            if not rightTurn then noTurnDist.right = right.dist end

            local leftDist = left.dist
            local rightDist = right.dist

            if leftTurn then
                leftDist = noTurnDist.left
            end
            if rightTurn then
                rightDist = noTurnDist.right
            end

            --// Pull over
            if pullOver then
                offset = calculateOffset(leftDist, rightDist * 5)

                if math.abs(offset) < 0.05 + (100 - math.min(100, speed)) / 100 then
                    targetSpeed = 0

                    if speed < 50 then
                        handbrake = 1
                    end
                else
                    targetSpeed = 250
                end
            else
                offset = calculateOffset(leftDist, rightDist)
            end
        end

        --// If street is too narrow
        local streetWidth = left.dist + right.dist

        if streetWidth < vehicleWidth + speed / 10 then
            print('Street too narrow!')
            targetSpeed = 0
            throttle = 0
            brake = 1
            offset = 0
        end

        --// Lock
        if pullOver and speed < 50 then
            lock = 0
        else
            lock = 1
        end
    end

    local function processSteering()
        steer = -offset
    end

    local function exportViaWire()
        wire.ports.Engine = engine

        --// Workarounds throttle not working if the same in some situations
        if engineActive then
            wire.ports.Throttle = throttle
        else
            wire.ports.Throttle = 0
        end

        wire.ports.Steer = steer
        wire.ports.Brake = brake
        wire.ports.Handbrake = handbrake
        wire.ports.Lock = lock
    end

    local function debugOutput()
        print('Straight: ' .. tostring(straight) .. '\nLeft: ' .. tostring(leftTurn) .. '\nRight: ' .. tostring(rightTurn) .. '\nTarget speed: ' .. targetSpeed .. '\nTurning left: ' .. tostring(turningLeft) .. '\nTurning right: ' .. tostring(turningRight))

        if turnState then
            print(turnState.counter.distance, turnState.data.maxFrontDistTravel)
        end
    end

    local function process()
        engine = 0
        throttle = 0
        steer = 0
        brake = 0
        handbrake = 0
        lock = 0

        if swInControl then
            processEngine()
            figureOutRoad()
            mainProcess()
            processThrottle()
            processSteering()

            debugOutput()
        end

        exportViaWire()

        local now = getTime()
        local sinceLast = now - lastTime

        local travelled = speed * sinceLast
        for i=1,#activeDistanceCounters do
            local counter = activeDistanceCounters[i]

            counter.distance = counter.distance + travelled
        end

        lastTime = now
    end

    --// Setup wire
    hook.add('input', 'selfdriving_wire', function(name, value)
        if name == 'Active' then
            engineActive = value == 1
        elseif name == 'Speed' then
            speed = value
        elseif name == 'Front' then
            front.dist = value
        elseif name == 'Left' then
            left.dist = value
        elseif name == 'Right' then
            right.dist = value
        elseif name == 'Driver' then
            swInControl = tostring(value) == '[NULL Entity]'
        end
    end)

    wire.adjustPorts(inputs, outputs)

    --// Setup timer
    timer.create('selfdriving_timer', 0.05, 0, process)

    --// Keybinds server
    net.receive('selfdriving_keybind', function(len, plr)
        local turn = net.readUInt(3)

        if turn == 1 then
            waitingToTurnLeft = true
            waitingToTurnRight = false

            print('Waiting to turn left')
        elseif turn == 2 then
            waitingToTurnLeft = false
            waitingToTurnRight = true

            print('Waiting to turn right')
        elseif turn == 3 then
            pullOver = not pullOver
            print('Pull over: ' .. tostring(pullOver))
        else
            waitingToTurnLeft = false
            waitingToTurnRight = false

            print('Straight')
        end
    end)
elseif CLIENT then
    --// Keybinds client
    local straightKey = 19 -- I
    local turnLeftKey = 25 -- O
    local turnRightKey = 26 -- P
    local pullOverToggleKey = 22 -- L

    local lastPullOverToggleTime = 0

    local currentTurn = nil
    timer.create('selfdriving_keybinds', 0.05, 0, function()
        if input.isKeyDown(straightKey) and currentTurn ~= 0 then
            currentTurn = 0
            net.start('selfdriving_keybind')
            net.writeUInt(0, 3)
            net.send()
        elseif input.isKeyDown(turnLeftKey) and currentTurn ~= 1 then
            currentTurn = 1
            net.start('selfdriving_keybind')
            net.writeUInt(1, 3)
            net.send()
        elseif input.isKeyDown(turnRightKey) and currentTurn ~= 2 then
            currentTurn = 2
            net.start('selfdriving_keybind')
            net.writeUInt(2, 3)
            net.send()
        elseif input.isKeyDown(pullOverToggleKey) then
            if getTime() - lastPullOverToggleTime < 1.5 then return end
            lastPullOverToggleTime = getTime()

            net.start('selfdriving_keybind')
            net.writeUInt(3, 3)
            net.send()
        end
    end)
end
