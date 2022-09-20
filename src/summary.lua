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
        return ClientError("need subnet=x.x.x.x/y parameter")
    end
    ip = ParseIp(ip)
    if ip < 0 then
        return ClientError("invalid ip address")
    end
    mask = tonumber(mask)
    if mask < 24 or mask > 31 then
        return ClientError("subnet size must be 24..31")
    end
    smallest = ip & ( (0xFFFFFFFF << (32 - 24)) & 0xffffffff)
    biggest  = ip | (~(0xFFFFFFFF << (32 - 24)) & 0xffffffff)
else
    return ClientError("need subnet=x.x.x.x/y parameter")
end

local stmt, err = db:prepare([[
    SELECT nick, COUNT(ip) as score FROM land WHERE ip >= ?1 AND ip <= ?2 GROUP BY nick;
]])

if not stmt then
    return InternalError(string.format("Failed to prepare select query: %s / %s", err or "(null)", db:errmsg()))
end

if stmt:bind_values(smallest, biggest) ~= sqlite3.OK then
    return InternalError(string.format("Internal error (stmt:bind_values): %s", db:errmsg()))
end

local res = {}
for row in stmt:nrows() do
    res[row.nick] = row.score
end

SetHeader("Content-Type", "application/json")
SetHeader("Cache-Control", "public, max-age=60, must-revalidate")
Write(EncodeJson(res))
