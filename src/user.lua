if not EnforceMethod({'GET', 'HEAD'}) then return end
if not EnforceParams({'name'}) then return end

local name = GetParam("name")

if name == nil or name == "" then
    return ClientError("name query param was blank")
elseif #name > 40 then
    return ClientError("name must be no more than 40 characters")
end

local stmt, err = db:prepare[[SELECT COUNT(*) FROM land WHERE nick = ?1]]

if not stmt then
    return InternalError(string.format("Failed to prepare select query: %s / %s", err or "(null)", db:errmsg()))
end

if stmt:bind_values(name) ~= sqlite3.OK then
    stmt:finalize()
    return InternalError(string.format("Internal error (stmt:bind_values): %s", db:errmsg()))
elseif stmt:step() ~= sqlite3.ROW then
    stmt:finalize()
    return InternalError(string.format("Internal error (stmt:step): %s", db:errmsg()))
else
    local out = {["total"] = stmt:get_value(0)}
    if stmt:step() ~= sqlite3.DONE then
        stmt:finalize()
        return InternalError(string.format("Internal error (stmt:step after row): %s", db:errmsg()))
    end
    stmt:finalize()
    SetHeader("Content-Type", "application/json")
    SetHeader("Cache-Control", "public, max-age=60, must-revalidate")
    Write(EncodeJson(out))
end
