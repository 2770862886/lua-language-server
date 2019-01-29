local mt = {}
mt.__index = mt

function mt:compileVM(uri)
    if not self.set[uri] and not self.get[uri] then
        return
    end
end

function mt:markSet(uri)
    self.set[uri] = true
end

function mt:markGet(uri)
    self.get[uri] = true
end

function mt:clearGlobal(uri)
    self.get[uri] = nil
    if not self.set[uri] then
        return
    end
    self.set[uri] = nil
    local globalValue = self.lsp.globalValue
    if not globalValue then
        return
    end
    globalValue:removeUri(uri)
end

function mt:getAllUris()
    local uris = {}
    for uri in pairs(self.set) do
        uris[#uris+1] = uri
    end
    for uri in pairs(self.get) do
        if not self.set[uri] then
            uris[#uris+1] = uri
        end
    end
    return uris
end

return function (lsp)
    return setmetatable({
        get = {},
        set = {},
        lsp = lsp,
    }, mt)
end
