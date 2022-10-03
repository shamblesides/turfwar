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

local function Lockdown()
    assert(unix.unveil("/var/tmp", "rwc"))
    assert(unix.unveil("/tmp", "rwc"))
    assert(unix.unveil(nil, nil))
    assert(unix.pledge("stdio flock rpath wpath cpath", nil, unix.PLEDGE_PENALTY_RETURN_EPERM))
end

function ClientError(msg, loglevel)
    if loglevel ~= nil then
        Log(loglevel, string.format(msg))
    end
    SetStatus(400, msg)
    SetHeader('Content-Type', 'text/plain')
    Write(msg..'\r\n')
    return msg
end

function InternalError(msg)
    Log(kLogWarn, msg)
    SetHeader('Connection', 'close')
    return ServeError(500)
end

function EnforceMethod(allowed_methods)
    local method = GetMethod()
    for i,val in ipairs(allowed_methods) do
        if method == val then
            return true
        end
    end
    Log(kLogWarn, "got %s request from %s" % {method, FormatIp(GetRemoteAddr() or "0.0.0.0")})
    ServeError(405)
    SetHeader("Cache-Control", "private")
    SetHeader('Allow', table.concat(allowed_methods, ', '))
    return false
end

function EnforceParams(exact_params)
    local params = GetParams()
    if #params > #exact_params then
        ClientError('too many params')
        return false
    end
    for i,val in ipairs(exact_params) do
        if GetParam(val) == nil then
            ClientError('Missing query param: %s' % {val})
            return false
        end
    end
    return true
end

function OnServerStart()
    if assert(unix.fork()) == 0 then
        local worker = require("board_worker")
        local db = ConnectDb()
        Lockdown()
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
    assert(unix.setrlimit(unix.RLIMIT_RSS, 100 * 1024 * 1024))
    assert(unix.setrlimit(unix.RLIMIT_CPU, 4))
    Lockdown()
    db = ConnectDb()
end

function StartsWith(str, start)
    return str:sub(1, #start) == start
end

function EndsWith(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

-- Redbean's global route handler
function OnHttpRequest()
    local ip = GetRemoteAddr()
    local path = GetPath()

    if ip then
        log_request_origin(path, ip)
    end

    if path == "/ip" then
        Route(GetHost(), "/ip.lua")
    elseif path == "/claim" then
        Route(GetHost(), "/claim.lua")
    elseif path == "/score" then
        Route(GetHost(), "/score.lua")
    else
        if #GetParams() > 1 then
            return ClientError('too many params')
        end
        -- Default redbean route handling
        Route()
        if EndsWith(path, ".html") then
            SetHeader("Cache-Control", "public, max-age=300, must-revalidate")
        elseif EndsWith(path, ".png") then
            SetHeader("Cache-Control", "public, max-age=3600, must-revalidate")
        end
    end
end
