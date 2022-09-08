SetHeader("Access-Control-Allow-Origin", "*")

local smallest, biggest
local cidr = GetParam("subnet")
if cidr ~= nil and cidr ~= "" then
    local full, ip, mask = re.search([[^([0-9.]{7,15})/([0-9]{1,2})$]], cidr)
    if full == nil then
        SetStatus(400)
        Write("Invalid CIDR")
        return
    end
    ip = ParseIp(ip)
    mask = tonumber(mask)
    if ip < 0 or mask > 32 then
        SetStatus(400)
        Write("Invalid CIDR")
        return
    end
    mask = 0xFFFFFFFF >> mask
    biggest = ip | mask
    smallest = biggest ~ mask
else
    smallest = 0
    biggest = 0xFFFFFFFF
end

ConnectDb()
local stmt = db:prepare([[
    SELECT nick, COUNT(ip) as score FROM land WHERE ip >= ?1 AND ip <= ?2 GROUP BY nick;
]])
if stmt:bind_values(smallest, biggest) ~= sqlite3.OK then
    SetStatus(500)
    Write("Internal error (stmt:bind_values): ")
    Write(db:errmsg())
    return
end

local res = {}
for row in stmt:nrows() do
    res[row.nick] = row.score
end

SetHeader("Content-Type", "application/json")
Write(EncodeJson(res))
