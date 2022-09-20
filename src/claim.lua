SetHeader("Access-Control-Allow-Origin", "*")

if GetMethod() ~= 'GET' and GetMethod() ~= 'POST' and GetMethod() ~= 'HEAD' then
    Log(kLogWarn, "got %s request from %s" % {GetMethod(), FormatIp(GetRemoteAddr() or "0.0.0.0")})
    ServeError(405)
    SetHeader('Allow', 'GET, POST, HEAD')
    return
end

local ip = GetRemoteAddr()
if not ip then
    return ClientError("IPv4 Games only supports IPv4 right now")
end

local ip_str = FormatIp(ip)
local name = GetParam("name")
local escaped_name = EscapeHtml(name)

if name == nil or name == "" then
    return ClientError("Name query param was blank")
elseif #name > 40 then
    return ClientError("name must be no more than 40 characters")
else
    local invalid_char = re.search("[^!-~]", name)
    if invalid_char ~= nil then
        return ClientError([[Invalid character in name: "%s"]] % invalid_char, kLogWarn)
    end
end

local stmt, err = db:prepare[[SELECT nick FROM land WHERE ip = ?1]]

if not stmt then
    return InternalError(string.format("Failed to prepare select query: %s / %s", err or "(null)", db:errmsg()))
end

if stmt:bind_values(ip) ~= sqlite3.OK then
    stmt:finalize()
    return InternalError(string.format("Internal error (stmt:bind_values): %s", db:errmsg()))
end

local res = stmt:step()
local already = false
if res == sqlite3.DONE then
    -- no record; we should insert
elseif res == sqlite3.ROW then
    local prev_name = stmt:get_value(0)
    if prev_name == name then
        stmt:finalize()
        SetHeader("Content-Type", "text/html")
        Write(string.format([[
            <!doctype html>
            <title>The land at %s already belongs to %s.</title>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            The land at %s already belongs to <a href="/user.html?name=%s">%s</a>.
            <p>
            <a href=/>Back to homepage</a>
        ]], ip_str, escaped_name, ip_str, EscapeHtml(EscapeParam(name)), escaped_name))
        return
    else
        -- record exists and should be updated
    end
else
    stmt:finalize()
    return InternalError(string.format("Internal error (stmt:step): %s", db:errmsg()))
end
stmt:finalize()

local stmt = db:prepare([[
    INSERT INTO land (ip, nick) VALUES (?1, ?2)
    ON CONFLICT (ip) DO UPDATE SET (nick) = (?2) WHERE nick != ?2
]])
if stmt:bind_values(ip, name) ~= sqlite3.OK then
    stmt:finalize()
    return InternalError(string.format("Internal error (stmt:bind_values): %s", db:errmsg()))
elseif stmt:step() ~= sqlite3.DONE then
    stmt:finalize()
    return InternalError(string.format("Internal error (stmt:step): %s", db:errmsg()))
end
stmt:finalize()

local time, nanos = unix.clock_gettime()
local timestamp = string.format("%s.%.3dZ", os.date("!%Y-%m-%dT%H:%M:%S", time), math.floor(nanos / 1000000))
local log_line = string.format("%s\t%s\t%s\n", timestamp, ip_str, name)
unix.write(claims_log, log_line)

SetHeader("Content-Type", "text/html")
SetHeader("Cache-Control", "private")
Write(string.format([[
    <!doctype html>
    <title>The land at %s was claimed for %s.</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    The land at %s was claimed for <a href="/user.html?name=%s">%s</a>.
    <p>
    <a href=/>Back to homepage</a>
]], ip_str, escaped_name, ip_str, EscapeHtml(EscapeParam(name)), escaped_name))
