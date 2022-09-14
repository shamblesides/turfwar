SetHeader("Access-Control-Allow-Origin", "*")

local smallest, biggest
local cidr = GetParam("subnet")
if cidr ~= nil and cidr ~= "" then
    local full, ip, mask = re.search([[^([0-9.]{7,15})/([0-9]{1,2})$]], cidr)
    if full == nil then
        return ServeError(400, "Invalid CIDR")
    end
    ip = ParseIp(ip)
    if ip < 0 then
        return ServeError(400, "Invalid CIDR")
    end
    mask = tonumber(mask)
    if mask > 8 then
        return ServeError(400, "Mask >8 not supported")
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
    return ServeError(500, string.format("Internal error (stmt:bind_values): %s", db:errmsg()))
end

local res = {}
for row in stmt:nrows() do
    res[row.nick] = row.score
end

SetHeader("Content-Type", "application/json")
Write(EncodeJson(res))
