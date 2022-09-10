SetHeader("Access-Control-Allow-Origin", "*")

local ip = GetRemoteAddr()
local name = GetParam("name")

if name == nil or name == "" then
    return ServeError(400, "Name query param was blank")
elseif #name ~= 8 then
    return ServeError(400, "Name must be exactly 8 characters")
elseif re.search([[^[a-zA-Z0-9]{8}$]], name) ~= name then
    return ServeError(400, "Name must be ASCII alphanumeric")
end

ConnectDb()
local stmt = db:prepare([[
    INSERT INTO land (ip, nick) VALUES (?1, ?2)
    ON CONFLICT (ip) DO UPDATE SET (nick) = (?2)
]])
if stmt:bind_values(GetRemoteAddr(), name) ~= sqlite3.OK then
    return ServeError(500, string.format("Internal error (stmt:bind_values): %s", db:errmsg()))
elseif stmt:step() ~= sqlite3.DONE then
    return ServeError(500, string.format("Internal error (stmt:step): %s", db:errmsg()))
end

local ip_str = FormatIp(ip)
local time, nanos = unix.clock_gettime()
local timestamp = string.format("%s.%.3dZ", os.date("!%Y-%m-%dT%H:%M:%S", time), math.floor(nanos / 1000000))
local log_line = string.format("%s\t%s\t%s\n", timestamp, ip_str, name)
unix.write(claims_log, log_line)

SetHeader("Content-Type", "text/html")
Write(string.format([[
    <!doctype html>
    <title>The land at %s was claimed for %s.</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    The land at %s was claimed for %s.
    <p>
    <a href=/>Back to homepage</a>
]], ip_str, name, ip_str, name))
