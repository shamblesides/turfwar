if not EnforceMethod({'GET', 'HEAD'}) then return end
if not EnforceParams({}) then return end

local stmt, err = db:prepare[[SELECT val FROM cache WHERE key = '/board']]

if not stmt then
    return InternalError("Failed to prepare board query: %s / %s" % {err or "(null)", db:errmsg()})
elseif stmt:step() ~= sqlite3.ROW then
    stmt:finalize()
    return InternalError("Internal error (stmt:step): %s" % {db:errmsg()})
end

SetHeader("Content-Type", "application/json")
SetHeader("Content-Encoding", "deflate")
SetHeader("Cache-Control", "public, max-age=5, must-revalidate")
Write(stmt:get_value(0))

stmt:finalize()
