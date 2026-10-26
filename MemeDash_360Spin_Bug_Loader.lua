-- MemeDash 360 Spin Bug loader (no cache)
local url = "https://raw.githubusercontent.com/hshsagaga1-commits/MemeDash_360Spin_Bug/main/MemeDash_360Spin_Bug.lua"
local ok, source = pcall(function()
    return game:HttpGet(url .. "?nocache=" .. tostring(os.time()) .. tostring(math.random(100000, 999999)))
end)
if not ok then
    warn("[MemeDash360Spin] Failed to download script:", source)
    return
end
local fn, err = loadstring(source)
if not fn then
    warn("[MemeDash360Spin] Failed to compile script:", err)
    return
end
local ran, runErr = pcall(fn)
if not ran then
    warn("[MemeDash360Spin] Runtime error:", runErr)
end
