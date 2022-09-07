SetHeader("Access-Control-Allow-Origin", "*")

local smallest, biggest
local cidr = GetParam("subnet")
if cidr ~= nil and cidr ~= "" then
    local full,a,b,c,d,mask = re.search([[^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$]], cidr)
    if full == nil then
        print(cidr)
        SetStatus(400)
        Write("Invalid CIDR")
        return
    end
    a = tonumber(a)
    b = tonumber(b)
    c = tonumber(c)
    d = tonumber(d)
    mask = tonumber(mask)
    if a > 255 or b > 255 or c > 255 or d > 255 or mask > 32 then
        SetStatus(400)
        Write("Invalid CIDR")
        return
    end
    local ip = (a << 24) + (b << 16) + (c << 8) + d
    mask = 0xFFFFFFFF >> mask
    biggest = ip | mask
    smallest = biggest ~ mask
else
    smallest = 0
    biggest = 0xFFFFFFFF
end

local sqlite3 = require "lsqlite3"
local db = sqlite3.open("db.sqlite3", sqlite3.OPEN_READONLY)
db:exec[[PRAGMA writable_schema=ON]] -- until redbean supports strict
local stmt = db:prepare([[
    SELECT nick, COUNT(ip) as score FROM land WHERE ip >= ?1 AND ip <= ?2 GROUP BY nick;
]])
if stmt:bind_values(smallest, biggest) ~= sqlite3.OK then
    SetStatus(500)
    Write("Internal error")
    return
end

local res = {}
for row in stmt:nrows() do
    res[row.nick] = row.score
end

SetHeader("Content-Type", "application/json")
Write(EncodeJson(res))
