-- =========================================================
-- FS25 Fertilizer Depot - Settings Sync Network Event
-- =========================================================
-- Client → Server: request a setting change (admin validated)
-- Server → All: broadcast full settings on change or join

---@class DepotSettingsEvent
DepotSettingsEvent = {}
DepotSettingsEvent_mt = Class(DepotSettingsEvent, Event)

InitEventClass(DepotSettingsEvent, "DepotSettingsEvent")

function DepotSettingsEvent.emptyNew()
    return Event.new(DepotSettingsEvent_mt)
end

function DepotSettingsEvent.new(key, value)
    local self  = DepotSettingsEvent.emptyNew()
    self.key    = key    -- string: "seasonalPricing"|"storageCapacity"|"sellRatio"|"buyMultiplier"
    self.value  = value  -- serialized as string for flexibility
    return self
end

function DepotSettingsEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.key   or "")
    streamWriteString(streamId, tostring(self.value) or "")
end

function DepotSettingsEvent:readStream(streamId, connection)
    self.key   = streamReadString(streamId)
    self.value = streamReadString(streamId)
    self:run(connection)
end

function DepotSettingsEvent:run(connection)
    if not g_server then return end
    if not g_DepotManager then return end

    -- Admin check: connection is nil when executed locally (SP / direct server call).
    -- g_currentMission.isMasterUser is always true on a dedicated server process, so
    -- it cannot be used to validate the connecting CLIENT's admin status.
    -- On a listen-server (host+client same process, g_client ~= nil), isMasterUser
    -- reflects the host player correctly and is safe to check.
    -- On a dedicated server (g_client == nil), block client-initiated changes until
    -- a per-connection admin API is verified via LUADOC.
    if connection and not connection:getIsServer() then
        local listenServer = (g_client ~= nil)
        if listenServer then
            if not g_currentMission.isMasterUser then
                DepotLogger.warning("Non-admin setting change blocked (listen server)")
                return
            end
        else
            DepotLogger.warning("Non-admin setting change blocked (dedicated server)")
            return
        end
    end

    local s = g_DepotManager.settings
    if self.key == "seasonalPricing" then
        s.seasonalPricing = (self.value == "true")
    elseif self.key == "storageCapacity" then
        s.storageCapacity = tonumber(self.value) or s.storageCapacity
    elseif self.key == "sellRatio" then
        s.sellRatio = tonumber(self.value) or s.sellRatio
    elseif self.key == "buyMultiplier" then
        s.buyMultiplier = tonumber(self.value) or s.buyMultiplier
    elseif self.key == "debugLogging" then
        s.debugLogging = (self.value == "true")
        DepotLogger._debug = s.debugLogging
    end

    -- Broadcast the full settings table to all clients
    DepotSettingsSyncEvent.broadcast()
end

function DepotSettingsEvent.sendToServer(key, value)
    if g_server then
        -- On server/SP, apply directly
        local event = DepotSettingsEvent.new(key, value)
        event:run(nil)
        DepotSettingsSyncEvent.broadcast()
    else
        g_client:getServerConnection():sendEvent(DepotSettingsEvent.new(key, value))
    end
end

-- ─── Sync Event (Server → All clients) ──────────────────

---@class DepotSettingsSyncEvent
DepotSettingsSyncEvent = {}
DepotSettingsSyncEvent_mt = Class(DepotSettingsSyncEvent, Event)

InitEventClass(DepotSettingsSyncEvent, "DepotSettingsSyncEvent")

function DepotSettingsSyncEvent.emptyNew()
    return Event.new(DepotSettingsSyncEvent_mt)
end

function DepotSettingsSyncEvent.new()
    return DepotSettingsSyncEvent.emptyNew()
end

function DepotSettingsSyncEvent:writeStream(streamId, connection)
    if g_DepotManager then
        g_DepotManager.settings:writeStream(streamId)
    end
end

function DepotSettingsSyncEvent:readStream(streamId, connection)
    if g_DepotManager then
        g_DepotManager.settings:readStream(streamId)
        DepotLogger._debug = g_DepotManager.settings.debugLogging
    end
    -- Refresh settings dialog if open
    DepotSettingsDialog.refreshIfOpen()
end

function DepotSettingsSyncEvent:run(connection)
    -- all logic in readStream
end

function DepotSettingsSyncEvent.broadcast()
    if not g_server then return end
    g_server:broadcastEvent(DepotSettingsSyncEvent.new())
end

function DepotSettingsSyncEvent.sendToClient(connection)
    if not g_server then return end
    connection:sendEvent(DepotSettingsSyncEvent.new())
end
