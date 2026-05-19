-- =========================================================
-- FS25 Fertilizer Depot - Logger
-- =========================================================

DepotLogger = {}
DepotLogger._debug = false

function DepotLogger.setDebug(enabled)
    DepotLogger._debug = enabled
end

function DepotLogger.info(fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print(DepotConstants.LOG_PREFIX .. " " .. msg)
end

function DepotLogger.warning(fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print(DepotConstants.LOG_PREFIX .. " WARNING: " .. msg)
end

function DepotLogger.error(fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print(DepotConstants.LOG_PREFIX .. " ERROR: " .. msg)
end

function DepotLogger.debug(fmt, ...)
    if not DepotLogger._debug then return end
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print(DepotConstants.LOG_PREFIX .. " [DEBUG] " .. msg)
end
