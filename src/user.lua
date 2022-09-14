local name = GetParam("name")

if name == nil or name == "" then
    return ServeError(400, "Name query param was blank")
elseif #name > 40 then
    return ServeError(400, "Name must be no more than 40 characters")
end

ConnectDb()
local stmt = db:prepare[[SELECT COUNT(*) FROM land WHERE nick = ?1]]
if stmt:bind_values(name) ~= sqlite3.OK then
    stmt:finalize()
    return ServeError(500, string.format("Internal error (stmt:bind_values): %s", db:errmsg()))
elseif stmt:step() ~= sqlite3.ROW then
    stmt:finalize()
    return ServeError(500, string.format("Internal error (stmt:step): %s", db:errmsg()))
else
    local out = {["total"] = stmt:get_value(0)}
    if stmt:step() ~= sqlite3.DONE then
        return ServeError(500, string.format("Internal error (stmt:step after row): %s", db:errmsg()))
    end
    stmt:finalize()
    SetHeader("Content-Type", "application/json")
    Write(EncodeJson(out))
end
