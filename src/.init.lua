local log_request_origin = require "log_request_origin"
sqlite3 = require "lsqlite3"

TrustProxy(ParseIp("127.0.0.0"), 8);

-- Cloudflare proxy ranges
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

if IsDaemon() then
    assert(unix.chdir('/opt/turfwar'))
    ProgramPort(80)
    ProgramPort(443)
    ProgramUid(65534)
    ProgramGid(65534)
    ProgramLogPath('redbean.log')
    ProgramPidPath('redbean.pid')
    ProgramPrivateKey(Slurp('/home/jart/mykey.key'))
    ProgramCertificate(Slurp('/home/jart/mykey.crt'))
end

local function ConnectDb()
    local db = sqlite3.open("db.sqlite3")
    db:busy_timeout(1000)
    db:exec[[PRAGMA journal_mode=WAL]]
    db:exec[[PRAGMA synchronous=NORMAL]]
    db:exec[[SELECT ip FROM land WHERE ip = 0x7f000001]] -- We have to do this warmup query for SQLite to work after doing unveil
    return db
end

function OnServerStart()
    if assert(unix.fork()) == 0 then
        local worker = require("board_worker")
        local db = ConnectDb()
        worker(db)
        db:close()
        unix.exit(0)
    end

    local err
    claims_log, err = unix.open("claims.log", unix.O_WRONLY | unix.O_APPEND | unix.O_CREAT, 0644)
    if err ~= nil then
        Log(kLogFatal, string.format("error opening claim log: %s", err))
    end
end

function OnWorkerStart()
    db = ConnectDb()
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

-- Redbean's global route handler
function OnHttpRequest()
    local params = GetParams()
    local ip = GetRemoteAddr()
    local path = GetPath()

    if ip then
        log_request_origin(path, ip)
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
