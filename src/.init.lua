sqlite3 = require "lsqlite3"

function ConnectDb()
    if not db then
        db = sqlite3.open("db.sqlite3")
        db:busy_timeout(1000)
        db:exec[[PRAGMA journal_mode=WAL]]
        db:exec[[PRAGMA synchronous=NORMAL]]
    end
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
