SetHeader("Access-Control-Allow-Origin", "*")

if GetMethod() ~= 'GET' and GetMethod() ~= 'HEAD' then
    Log(kLogWarn, "got %s request from %s" % {GetMethod(), FormatIp(GetRemoteAddr() or "0.0.0.0")})
    ServeError(405)
    SetHeader('Allow', 'GET, HEAD')
    return
end

local params = GetParams()
if #params > 0 then
    SetStatus(400, 'too many parameters')
    Write('too many parameters\r\n')
    return
end

local params = GetParams()
if #params > 0 then
    SetStatus(400, 'too many parameters')
    Write('too many parameters\r\n')
    return
end

local stmt, err = db:prepare[[SELECT val FROM cache WHERE key = ?1]]

if not stmt then
    Log(kLogWarn, "Failed to prepare board query: %s / %s" % {err or "(null)", db:errmsg()})
    SetHeader('Connection', 'close')
    return ServeError(500)
end

if stmt:bind_values("/board") ~= sqlite3.OK then
    stmt:finalize()
    Log(kLogWarn, "Internal error (stmt:bind_values): %s" % {db:errmsg()})
    SetHeader('Connection', 'close')
    return ServeError(500)
end

if stmt:step() ~= sqlite3.ROW then
    stmt:finalize()
    Log(kLogWarn, "Internal error (stmt:step): %s" % {db:errmsg()})
    SetHeader('Connection', 'close')
    return ServeError(500)
end

SetHeader("Content-Type", "application/json")
SetHeader("Cache-Control", "public, max-age=60, must-revalidate")
Write(stmt:get_value(0))

stmt:finalize()
