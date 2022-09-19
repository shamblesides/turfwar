if GetMethod() ~= 'GET' and GetMethod() ~= 'HEAD' then
    Log(kLogWarn, "got %s request from %s" % {GetMethod(), FormatIp(GetRemoteAddr() or "0.0.0.0")})
    ServeError(405)
    SetHeader('Allow', 'GET, HEAD')
    SetHeader("Cache-Control", "private")
    return
end

local ip = GetRemoteAddr()

if ip then
    SetHeader("Cache-Control", "private; max-age=3600; must-revalidate")
    SetHeader("Content-Type", "text/plain")
    Write(FormatIp(ip))
    return
else
    SetStatus(400, "IPv4 Games only supports IPv4 right now")
    Write("IPv4 Games only supports IPv4 right now")
    return
end
