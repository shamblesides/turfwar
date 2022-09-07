SetHeader("Access-Control-Allow-Origin", "*")

local ip = GetRemoteAddr()
local name = GetParam("name")

if name == nil or name == "" then
    SetStatus(400)
    Write("Name query param was blank")
elseif #name ~= 8 then
    SetStatus(400)
    Write("Name must be exactly 8 characters")
elseif re.search([[^[a-zA-Z0-9]{8}$]], name) ~= name then
    SetStatus(400)
    Write("Name must be ASCII alphanumeric")
else
    local sqlite3 = require "lsqlite3"
    local db = sqlite3.open("db.sqlite3", sqlite3.OPEN_READWRITE)
    db:exec[[PRAGMA writable_schema=ON]] -- until redbean supports strict
    local stmt = db:prepare([[
        INSERT INTO land (ip, nick) VALUES (?1, ?2)
        ON CONFLICT (ip) DO UPDATE SET (nick) = (?2)
    ]])
    if stmt:bind_values(GetRemoteAddr(), name) ~= sqlite3.OK then
        SetStatus(500)
        Write("Internal error(stmt:bind_values)")
    elseif stmt:step() ~= sqlite3.DONE then
        SetStatus(500)
        Write("Internal error (stmt:step)")
        return
    else
        SetHeader("Content-Type", "text/html")
        Write(string.format([[
            <!doctype html>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            The land at %s was claimed for %s.
            <p>
            <a href=/>Back to homepage</a>
        ]], FormatIp(ip), name))
    end
end
