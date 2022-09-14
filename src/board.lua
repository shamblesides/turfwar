SetHeader("Access-Control-Allow-Origin", "*")

local output = {["ip"]=FormatIp(GetRemoteAddr()), ["leaders"]={}}

ConnectDb()
local stmt = db:prepare([[
    SELECT nick As name, COUNT(ip) AS count FROM land WHERE ip >= ?1 AND ip <= ?2 GROUP BY nick ORDER BY count DESC LIMIT 1;
]])
for smallest = 0, 0xFF000000, 0x1000000 do
    if stmt:bind_values(smallest, smallest + 0xFFFFFF) ~= sqlite3.OK then
        stmt:finalize()
        return ServeError(500, string.format("Internal error (stmt:bind_values): %s", db:errmsg()))
    end
    local res = stmt:step()
    if res == sqlite3.ROW then
        table.insert(output["leaders"], stmt:get_named_values())
        if stmt:step() ~= sqlite3.DONE then
            stmt:finalize()
            return ServeError(500, string.format("Internal error (stmt:step after row): %s", db:errmsg()))
        end
    elseif res == sqlite3.DONE then
        table.insert(output["leaders"], false)
    else
        stmt:finalize()
        return ServeError(500, string.format("Internal error (stmt:step returned %d): %s", res, db:errmsg()))
    end
    stmt:reset()
end
stmt:finalize()

SetHeader("Content-Type", "application/json")
Write(EncodeJson(output))
