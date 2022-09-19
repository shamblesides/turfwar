--[[
    We could be generating this fresh every time someone
    hits the /board route, but since it's a bit expensive
    (it has to process the entire claim table!) we just
    update it periodically and cache it instead.
]]

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
    output = {["leaders"]={}, ["now"]=os.time()}
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

local gotterm = false

return function()
    assert(unix.unveil(".", "rwc"))
    assert(unix.unveil("/var/tmp", "rwc"))
    assert(unix.unveil("/tmp", "rwc"))
    assert(unix.unveil(nil, nil))
    assert(unix.pledge("stdio flock rpath wpath cpath", nil, unix.PLEDGE_PENALTY_RETURN_EPERM))
    assert(unix.sigaction(unix.SIGINT, function() gotterm = true; end))
    assert(unix.sigaction(unix.SIGTERM, function() gotterm = true; end))
    while not gotterm do
        local db = ConnectDb()
        UpdateBoardImpl(db)
        db:close()
        unix.nanosleep(30)
    end
    Log(kLogInfo, "UpdateBoardWorker() terminating")
end
