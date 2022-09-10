SetHeader("Access-Control-Allow-Origin", "*")

local ip = GetRemoteAddr()
local name = GetParam("name")

if name == nil or name == "" then
    return ServeError(400, "Name query param was blank")
elseif #name > 40 then
    return ServeError(400, "Name must be no more than 40 characters")
else
    local invalid_char = re.search("[^!-~]", name)
    if invalid_char ~= nil then
        return ServeError(400, string.format("Invalid character in name: \"%s\"", invalid_char))
    end
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
local escaped_name = EscapeHtml(name)
Write(string.format([[
    <!doctype html>
    <title>The land at %s was claimed for %s.</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    The land at %s was claimed for %s.
    <p>
    <a href=/>Back to homepage</a>
]], ip_str, escaped_name, ip_str, escaped_name))
