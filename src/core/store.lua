return function(A)
    local PATH = "AnimationPlayer/saved.json"
    local records = {}      -- array of {name, id}

    local function persist()
        if not A.Config.hasPersistence then return end
        A.fs.makefolder("AnimationPlayer")
        A.fs.write(PATH, A.json.encode(records))
    end

    local function load()
        if A.Config.hasPersistence and A.fs.isfile(PATH) then
            local raw = A.fs.read(PATH)
            local decoded = raw and A.json.decode(raw) or nil
            if type(decoded) == "table" then
                records = {}
                for _, r in ipairs(decoded) do
                    if type(r) == "table" and r.name and r.id then
                        records[#records + 1] = { name = tostring(r.name), id = tostring(r.id) }
                    end
                end
            end
        end
    end

    local Store = { path = PATH }

    function Store.list() return records end

    function Store.get(name)
        for _, r in ipairs(records) do
            if r.name == name then return r end
        end
        return nil
    end

    function Store.add(name, id)
        name = name and (tostring(name):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        id = id and (tostring(id):gsub("%s+", "")) or ""
        if name == "" then return false, "name required" end
        if id == "" then return false, "id required" end
        if Store.get(name) then return false, "name already exists" end
        records[#records + 1] = { name = name, id = id }
        persist()
        return true
    end

    function Store.remove(name)
        for i, r in ipairs(records) do
            if r.name == name then
                table.remove(records, i)
                persist()
                return true
            end
        end
        return false
    end

    load()
    A.Store = Store
end
