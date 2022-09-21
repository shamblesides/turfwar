--[[
    We could be generating this fresh every time someone
    hits the /board route, but since it's a bit expensive
    (it has to process the entire claim table!) we just
    update it periodically and cache it instead.
]]

local function UpdateBoardImpl(db)
    local stmt, err, scores, output, success
    local scores = {} 
    err = db:exec([[SELECT nick, (ip >> 24), COUNT(*) FROM land GROUP BY nick, (ip >> 24)]], function (udata, cols, vals, names)
        scores[vals[1]] = scores[vals[1]] or {}
        scores[vals[1]][tostring(vals[2])] = tonumber(vals[3])
        return 0
    end)
    if err ~= sqlite3.OK then
        Log(kLogWarn, "BOARD select query: %s / %s" % {err or "(null)", db:errmsg()})
        return
    end

    output = EncodeJson({["scores"]=scores, ["now"]=os.time()})
    stmt, err = db:prepare([[
        INSERT INTO cache (key, val) VALUES ('/board', ?1)
        ON CONFLICT (key) DO UPDATE SET (val) = (?1)
    ]])
    if not stmt then
        Log(kLogWarn, "BOARD prepare insert: %s / %s" % {err or "(null)", db:errmsg()})
        return
    elseif stmt:bind_values(output) ~= sqlite3.OK then
        Log(kLogWarn, "BOARD insert bind: %s" % {db:errmsg()})
    elseif stmt:step() ~= sqlite3.DONE then
        Log(kLogWarn, "BOARD insert step: %s" % {db:errmsg()})
    else
        Log(kLogInfo, "BOARD successfully updated")
    end
    stmt:finalize()
end

local gotterm = false

return function(db)
    assert(unix.sigaction(unix.SIGINT, function() gotterm = true; end))
    assert(unix.sigaction(unix.SIGTERM, function() gotterm = true; end))
    while not gotterm do
        UpdateBoardImpl(db)
        unix.nanosleep(30)
    end
    Log(kLogInfo, "UpdateBoardWorker() terminating")
end
