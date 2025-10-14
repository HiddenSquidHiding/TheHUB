-- farm.lua (snippet for brevity; replace full file if needed, but focus on runAutoFarm)
-- ... (rest of code above)

----------------------------------------------------------------------
-- Public: run auto farm (fixed: throttled label updates)
----------------------------------------------------------------------
function M.runAutoFarm(flagGetter, setTargetText)
  if not autoAttackRemote then
    utils.notify("🌲 Auto-Farm", "RequestAttack RemoteFunction not found.", 5)
    return
  end

  local function label(text)
    if setTargetText then setTargetText(text) end
  end

  -- Initial scan for enemies
  local function refreshEnemyList()
    local enemies = {}
    for _, name in ipairs(selectedMonsterModels) do
      if name == "Weather Events" then
        local we = findWeatherEnemies()
        for _, e in ipairs(we) do table.insert(enemies, e) end
      elseif name == "To Sahur" then
        for _, node in ipairs(Workspace:GetDescendants()) do
          if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
            local h = node:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 and isSahurName(node.Name) then
              table.insert(enemies, node)
            end
          end
        end
      else
        -- Regular monster by name
        for _, node in ipairs(Workspace:GetDescendants()) do
          if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) and node.Name == name then
            local h = node:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
              table.insert(enemies, node)
            end
          end
        end
      end
    end
    -- Prioritize lowest HP
    table.sort(enemies, function(a, b)
      local ha = (a:FindFirstChildOfClass("Humanoid") and a:FindFirstChildOfClass("Humanoid").Health) or math.huge
      local hb = (b:FindFirstChildOfClass("Humanoid") and b:FindFirstChildOfClass("Humanoid").Health) or math.huge
      return ha < hb
    end)
    return enemies
  end

  while flagGetter() do
    local character = utils.waitForCharacter()
    local hum = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not hrp then
      label("Current Target: None")
      task.wait(0.05)
    else
      local enemies = refreshEnemyList()
      if #enemies == 0 then
        label("Current Target: None")
        task.wait(0.1)
      else
        for _, enemy in ipairs(enemies) do
          if flagGetter() and enemy and enemy.Parent and not Players:GetPlayerFromCharacter(enemy) then
            local eh = enemy:FindFirstChildOfClass("Humanoid")
            if eh and eh.Health > 0 then
              local ctl, humSelf, oldPS = beginEngagement(enemy)
              if ctl then
                label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(eh.Health)))

                -- timers/state
                local isWeather   = isWeatherName(enemy.Name)
                local lastHealth  = eh.Health
                local lastDropAt  = tick()
                local startedAt   = tick()
                local lastLabelUpdate = 0  -- Throttle label

                local hcConn = eh.HealthChanged:Connect(function(h)
                  if h < lastHealth then lastDropAt = tick() end
                  lastHealth = h
                  local now = tick()
                  if now - lastLabelUpdate > 0.5 then  -- Throttle to 0.5s
                    label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(h)))
                    lastLabelUpdate = now
                  end
                end)

                -- attack loop (with weather preemption + FastLevel stall override + death recovery)
                local lastWeatherPoll = 0

                while flagGetter() and enemy.Parent and eh.Health > 0 do
                  -- death recovery: if we died or HRP missing, respawn + return to same enemy
                  local ch = player.Character
                  local myHum = ch and ch:FindFirstChildOfClass("Humanoid")
                  local myHRP = ch and ch:FindFirstChild("HumanoidRootPart")

                  if not ch or not myHum or myHum.Health <= 0 or not myHRP then
                    pcall(function() ctl.destroy() end)
                    label(("Respawning… returning to %s"):format(enemy.Name))
                    local newChar = utils.waitForCharacter()
                    if not enemy.Parent or eh.Health <= 0 then break end
                    ctl, humSelf, oldPS = beginEngagement(enemy)
                    if not ctl then break end
                  end

                  -- normal follow/attack
                  local partNow = findBasePart(enemy)
                  if not partNow then
                    local t0 = tick()
                    repeat
                      RunService.Heartbeat:Wait()
                      partNow = findBasePart(enemy)
                    until partNow or (tick() - t0) > 1 or not enemy.Parent or eh.Health <= 0
                    if not partNow then break end
                  end

                  local desired = partNow.CFrame * CFrame.new(ABOVE_OFFSET)
                  ctl.setGoal(desired)

                  local hrpTarget = enemy:FindFirstChild("HumanoidRootPart")
                  if hrpTarget and autoAttackRemote then
                    pcall(function() autoAttackRemote:InvokeServer(hrpTarget.CFrame) end)
                  end

                  local now = tick()

                  -- Weather timeout (always applies for weather)
                  if isWeather and (now - startedAt) > WEATHER_TIMEOUT then
                    utils.notify("🌲 Auto-Farm", ("Weather Event timeout on %s after %ds."):format(enemy.Name, WEATHER_TIMEOUT), 3)
                    break
                  end

                  -- Stall detection (disabled in FastLevel mode for non-weather)
                  if not isWeather and not FASTLEVEL_MODE and (now - lastDropAt) > NON_WEATHER_STALL_TIMEOUT then
                    utils.notify("🌲 Auto-Farm", ("Skipping %s (no HP change for %0.1fs)"):format(enemy.Name, NON_WEATHER_STALL_TIMEOUT), 3)
                    break
                  end

                  -- Weather preemption with TTK (only if not already on weather)
                  if not isWeather and (now - lastWeatherPoll) >= WEATHER_PREEMPT_POLL and isWeatherSelected() then
                    lastWeatherPoll = now
                    local candidate = pickLowestHPWeather()
                    if candidate and candidate ~= enemy then
                      local ttk = estimateTTK(candidate, WEATHER_PROBE_TIME)
                      if ttk <= WEATHER_TTK_LIMIT then
                        utils.notify("🌲 Auto-Farm", ("Weather target detected (TTK≈%0.1fs) — switching."):format(ttk), 2)
                        break
                      end
                    end
                  end

                  RunService.Heartbeat:Wait()
                end

                if hcConn then hcConn:Disconnect() end
                label("Current Target: None")

                -- cleanup + restore
                pcall(function() ctl.destroy() end)
                local curChar = player.Character
                local curHum  = curChar and curChar:FindFirstChildOfClass("Humanoid")
                local curHRP  = curChar and curChar:FindFirstChild("HumanoidRootPart")
                if curHum and curHRP and curHum.Parent then
                  curHum.PlatformStand = false
                  zeroVel(curHRP)
                end
              end
            end
          end
          RunService.Heartbeat:Wait()
        end
      end
    end
    RunService.Heartbeat:Wait()
  end
end

return M
