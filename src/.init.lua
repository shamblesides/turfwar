function IntToIPString(n)
    return string.format("%d.%d.%d.%d",
        (n >> 24) & 255,
        (n >> 16) & 255,
        (n >> 8) & 255,
        (n >> 0) & 255)
end

-- Redbean's global route handler
function OnHttpRequest()
    local path = GetPath()
    if path == "/ip" then
        Route(GetHost(), "/ip.lua")
    elseif path == "/summary" then
        Route(GetHost(), "/summary.lua")
    elseif path == "/claim" then
        Route(GetHost(), "/claim.lua")
    else
        -- Default redbean route handling
        Route()
    end
end

-- Setup() isn't called by the server,
-- you just call it yourself in the
-- redbean REPL
function Setup()
    local sqlite3 = require "lsqlite3"
    local db = sqlite3.open("db.sqlite3", sqlite3.OPEN_READWRITE + sqlite3.OPEN_CREATE)
    local res = db:exec[[
        CREATE TABLE "land" (
            ip INTEGER PRIMARY KEY,
            nick TEXT NOT NULL CHECK (length(nick) = 8),
            created_at TEXT DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW'))
        );
    ]]
    if res == sqlite3.OK then
        print("Done!")
    else
        print(db:errmsg())
    end
end
