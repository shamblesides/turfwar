SetHeader("Access-Control-Allow-Origin", "*")

if GetMethod() ~= 'GET' and GetMethod() ~= 'HEAD' then
    Log(kLogWarn, "got %s request from %s" % {GetMethod(), FormatIp(GetRemoteAddr() or "0.0.0.0")})
    ServeError(405)
    SetHeader('Allow', 'GET, HEAD')
    return
end

local smallest, biggest
local cidr = GetParam("subnet")
if cidr ~= nil and cidr ~= "" then
    local full, ip, mask = re.search([[^([0-9.]{7,15})/([0-9]{1,2})$]], cidr)
    if full == nil then
        SetStatus(400, "need subnet=x.x.x.x/y parameter")
        Write("need subnet=x.x.x.x/y parameter")
        return
    end
    ip = ParseIp(ip)
    if ip < 0 then
        SetStatus(400, "invalid ip address")
        Write("invalid ip address")
        return
    end
    mask = tonumber(mask)
    if mask < 24 or mask > 31 then
        SetStatus(400, "subnet size must be 24..31")
        Write("subnet size must be 24..31")
        return
    end
    smallest = ip & ( (0xFFFFFFFF << (32 - 24)) & 0xffffffff)
    biggest  = ip | (~(0xFFFFFFFF << (32 - 24)) & 0xffffffff)
else
    SetStatus(400, "need subnet=x.x.x.x/y parameter")
    Write("need subnet=x.x.x.x/y parameter")
    return
end

local stmt, err = db:prepare([[
    SELECT nick, COUNT(ip) as score FROM land WHERE ip >= ?1 AND ip <= ?2 GROUP BY nick;
]])

if not stmt then
    Log(kLogWarn, string.format("Failed to prepare select query: %s / %s", err or "(null)", db:errmsg()))
    SetHeader('Connection', 'close')
    return ServeError(500)
end

if stmt:bind_values(smallest, biggest) ~= sqlite3.OK then
    Log(kLogWarn, string.format("Internal error (stmt:bind_values): %s", db:errmsg()))
    SetHeader('Connection', 'close')
    return ServeError(500)
end

local res = {}
for row in stmt:nrows() do
    res[row.nick] = row.score
end

SetHeader("Content-Type", "application/json")
SetHeader("Cache-Control", "public, max-age=60, must-revalidate")
Write(EncodeJson(res))
