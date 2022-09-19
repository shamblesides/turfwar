maxmind = require "maxmind"
sqlite3 = require "lsqlite3"

unix.chdir('/opt/turfwar')

TrustProxy(ParseIp("127.0.0.0"), 8);
TrustProxy(ParseIp("103.21.244.0"), 22);
TrustProxy(ParseIp("103.22.200.0"), 22);
TrustProxy(ParseIp("103.31.4.0"), 22);
TrustProxy(ParseIp("104.16.0.0"), 13);
TrustProxy(ParseIp("104.24.0.0"), 14);
TrustProxy(ParseIp("108.162.192.0"), 18);
TrustProxy(ParseIp("131.0.72.0"), 22);
TrustProxy(ParseIp("141.101.64.0"), 18);
TrustProxy(ParseIp("162.158.0.0"), 15);
TrustProxy(ParseIp("172.64.0.0"), 13);
TrustProxy(ParseIp("173.245.48.0"), 20);
TrustProxy(ParseIp("188.114.96.0"), 20);
TrustProxy(ParseIp("190.93.240.0"), 20);
TrustProxy(ParseIp("197.234.240.0"), 22);
TrustProxy(ParseIp("198.41.128.0"), 17);
assert(IsTrustedProxy(ParseIp("103.21.244.0")))
assert(not IsTrustedProxy(ParseIp("166.21.244.0")))

geodb = maxmind.open('/usr/local/share/maxmind/GeoLite2-City.mmdb')
asndb = maxmind.open('/usr/local/share/maxmind/GeoLite2-ASN.mmdb')

if IsDaemon() then
    ProgramPort(80)
    ProgramPort(443)
    ProgramUid(65534)
    ProgramGid(65534)
    ProgramLogPath('redbean.log')
    ProgramPidPath('redbean.pid')
    ProgramPrivateKey(Slurp('/home/jart/mykey.key'))
    ProgramCertificate(Slurp('/home/jart/mykey.crt'))
end

gotterm = false

function OnTerm(sig)
    gotterm = true
end

function ConnectDb()
    local db = sqlite3.open("db.sqlite3")
    db:busy_timeout(1000)
    db:exec[[PRAGMA journal_mode=WAL]]
    db:exec[[PRAGMA synchronous=NORMAL]]
    return db
end

function UpdateBoardCrawl(db, output, stmt)
    local smallest, res
    for smallest = 0, 0xFF000000, 0x1000000 do
        if stmt:bind_values(smallest, smallest + 0xFFFFFF) ~= sqlite3.OK then
            Log(kLogWarn, "BOARD Internal error (stmt:bind_values): %s" % {db:errmsg()})
            return
        end
        res = stmt:step()
        if res == sqlite3.ROW then
            table.insert(output["leaders"], stmt:get_named_values())
            if stmt:step() ~= sqlite3.DONE then
                Log(kLogWarn, "BOARD Internal error (stmt:step after row): %s" % {db:errmsg()})
                return
            end
        elseif res == sqlite3.DONE then
            table.insert(output["leaders"], false)
        else
            Log(kLogWarn, "BOARD Internal error (stmt:step returned %d): %s" % {res, db:errmsg()})
            return
        end
        stmt:reset()
    end
end

function UpdateBoardImpl(db)
    local stmt, err, output, board
    stmt, err = db:prepare([[
        SELECT nick As name, COUNT(ip) AS count
        FROM land
        WHERE ip >= ?1 AND ip <= ?2
        GROUP BY nick
        ORDER BY count DESC
        LIMIT 1
    ]])
    if not stmt then
        Log(kLogWarn, "BOARD prepare board query: %s / %s" % {err or "(null)", db:errmsg()})
        return
    end
    output = {["leaders"]={}}
    UpdateBoardCrawl(db, output, stmt)
    stmt:finalize()
    board = EncodeJson(output)
    stmt, err = db:prepare([[
        INSERT INTO cache (key, val) VALUES (?1, ?2)
        ON CONFLICT (key) DO UPDATE SET (val) = (?2)
    ]])
    if not stmt then
        Log(kLogWarn, "BOARD prepare insert: %s / %s" % {err or "(null)", db:errmsg()})
        return
    elseif stmt:bind_values("/board", board) ~= sqlite3.OK then
        Log(kLogWarn, "BOARD insert bind: %s" % {db:errmsg()})
    elseif stmt:step() ~= sqlite3.DONE then
        Log(kLogWarn, "BOARD insert step: %s" % {db:errmsg()})
    else
        Log(kLogInfo, "BOARD successfully updated")
    end
    stmt:finalize()
end

function UpdateBoard()
    local db = ConnectDb()
    UpdateBoardImpl(db)
    db:close()
end

function UpdateBoardWorker()
    assert(unix.unveil(".", "rwc"))
    assert(unix.unveil("/var/tmp", "rwc"))
    assert(unix.unveil("/tmp", "rwc"))
    assert(unix.unveil(nil, nil))
    assert(unix.pledge("stdio flock rpath wpath cpath", nil, unix.PLEDGE_PENALTY_RETURN_EPERM))
    assert(unix.sigaction(unix.SIGINT, OnTerm))
    assert(unix.sigaction(unix.SIGTERM, OnTerm))
    while not gotterm do
        UpdateBoard()
        unix.nanosleep(30)
    end
    Log(kLogInfo, "UpdateBoardWorker() terminating")
end

function OnServerStart()
    local err
    claims_log, err = unix.open("claims.log", unix.O_WRONLY | unix.O_APPEND | unix.O_CREAT, 0644)
    if err ~= nil then
        Log(kLogFatal, string.format("error opening claim log: %s", err))
    end
    local pid = assert(unix.fork())
    if pid == 0 then
        UpdateBoardWorker()
        unix.exit(0)
    end
end

function OnWorkerStart()
    db = ConnectDb()

    -- TODO(jart): Must we do this?
    local stmt, err = db:prepare([[
      SELECT
        ip
      FROM
        land
      WHERE
        ip = 16812277
    ]])
    if not stmt then
        Log(kLogWarn, string.format("Failed to prepare warmup query: %s", db:errmsg()))
        unix.exit(1)
    end
    stmt:step()
    stmt:finalize()

    assert(unix.setrlimit(unix.RLIMIT_RSS, 100 * 1024 * 1024))
    assert(unix.setrlimit(unix.RLIMIT_CPU, 4))
    assert(unix.unveil("/var/tmp", "rwc"))
    assert(unix.unveil("/tmp", "rwc"))
    assert(unix.unveil(nil, nil))
    assert(unix.pledge("stdio flock rpath wpath cpath", nil, unix.PLEDGE_PENALTY_RETURN_EPERM))
end

function StartsWith(str, start)
    return str:sub(1, #start) == start
end

function EndsWith(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

function GetAsn(ip)
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

function GetGeo(ip)
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

-- Redbean's global route handler
function OnHttpRequest()
    local params = GetParams()
    local ip = GetRemoteAddr()
    local path = GetPath()

    if ip then
        Log(kLogInfo, '%s requested by %s from %s %s' % {path, FormatIp(ip), GetAsn(ip), GetGeo(ip)})
    end

    if #params > 1 then
        SetStatus(400, 'too many params')
        Write('too many params\r\n')
        return
    end

    if path == "/ip" then
        if GetMethod() ~= 'GET' and GetMethod() ~= 'HEAD' then
            Log(kLogWarn, "got %s request from %s" % {GetMethod(), FormatIp(GetRemoteAddr() or "0.0.0.0")})
            ServeError(405)
            SetHeader('Allow', 'GET, HEAD')
            SetHeader("Cache-Control", "private")
            return
        end
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
    elseif path == "/claim" then
        Route(GetHost(), "/claim.lua")
    elseif path == "/board" then
        Route(GetHost(), "/board.lua")
    elseif path == "/user" then
        Route(GetHost(), "/user.lua")
    elseif path == "/summary" then
        Route(GetHost(), "/summary.lua")
    else
        -- Default redbean route handling
        Route()
        if EndsWith(path, ".html") then
            SetHeader("Cache-Control", "public, max-age=300, must-revalidate")
        elseif EndsWith(path, ".png") then
            SetHeader("Cache-Control", "public, max-age=3600, must-revalidate")
        end
    end
end
