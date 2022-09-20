if not EnforceMethod({'GET', 'HEAD'}) then return end
if not EnforceParams({}) then return end

local ip = GetRemoteAddr()

if ip then
    SetHeader("Cache-Control", "private; max-age=3600; must-revalidate")
    SetHeader("Content-Type", "text/plain")
    Write(FormatIp(ip))
    return
else
    return ClientError("IPv4 Games only supports IPv4 right now")
end
