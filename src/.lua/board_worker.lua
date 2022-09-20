--[[
    We could be generating this fresh every time someone
    hits the /board route, but since it's a bit expensive
    (it has to process the entire claim table!) we just
    update it periodically and cache it instead.
]]

local function UpdateBoardImpl(db)
    local stmt, err, smallest, res, output, success
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

    output = {["leaders"]={}, ["now"]=os.time()}
    err = nil
    for smallest = 0, 0xFF000000, 0x1000000 do
        if stmt:bind_values(smallest, smallest + 0xFFFFFF) ~= sqlite3.OK then
            err = "BOARD Internal error (stmt:bind_values): %s" % {db:errmsg()}
            break
        end
        res = stmt:step()
        if res == sqlite3.ROW then
            table.insert(output["leaders"], stmt:get_named_values())
            if stmt:step() ~= sqlite3.DONE then
                err = "BOARD Internal error (stmt:step after row): %s" % {db:errmsg()}
                break
            end
        elseif res == sqlite3.DONE then
            table.insert(output["leaders"], false)
        else
            err = "BOARD Internal error (stmt:step returned %d): %s" % {res, db:errmsg()}
            break
        end
        stmt:reset()
    end
    stmt:finalize()

    if not err then
        stmt, err = db:prepare([[
            INSERT INTO cache (key, val) VALUES ('/board', ?1)
            ON CONFLICT (key) DO UPDATE SET (val) = (?1)
        ]])
        if not stmt then
            Log(kLogWarn, "BOARD prepare insert: %s / %s" % {err or "(null)", db:errmsg()})
            return
        elseif stmt:bind_values(EncodeJson(output)) ~= sqlite3.OK then
            Log(kLogWarn, "BOARD insert bind: %s" % {db:errmsg()})
        elseif stmt:step() ~= sqlite3.DONE then
            Log(kLogWarn, "BOARD insert step: %s" % {db:errmsg()})
        else
            Log(kLogInfo, "BOARD successfully updated")
        end
        stmt:finalize()
    else
        Log(kLogWarn, err)
    end
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
