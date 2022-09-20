local maxmind = require "maxmind"

local geodb, asndb

if unix.stat('/usr/local/share/maxmind') then
    geodb = maxmind.open('/usr/local/share/maxmind/GeoLite2-City.mmdb')
    asndb = maxmind.open('/usr/local/share/maxmind/GeoLite2-ASN.mmdb')
else
    Log(kLogWarn, "Maxmind database missing")
end

local function GetAsn(ip)
    local as = asndb:lookup(ip)
    if as then
        local asnum = as:get("autonomous_system_number")
        local asorg = as:get("autonomous_system_organization")
        if asnum and asorg then
            return '%s[%d]' % {asorg, asnum}
        end
    end
    return 'unknown'
end

local function GetGeo(ip)
    local g = geodb:lookup(ip)
    if g then
        local country = g:get("country", "names", "en")
        if country then
            local city = g:get("city", "names", "en") or ''
            local region = g:get("subdivisions", "0", "names", "en") or ''
            local accuracy = g:get('location', 'accuracy_radius') or 9999
            return '%s %s %s (%d km)' % {city, region, country, accuracy}
        end
    end
    return 'unknown'
end

return function (path, ip)
    if geodb and asndb then
        Log(kLogInfo, '%s requested by %s from %s %s' % {path, FormatIp(ip), GetAsn(ip), GetGeo(ip)})
    end
end