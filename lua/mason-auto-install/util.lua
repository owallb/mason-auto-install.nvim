local M = {}

--- Check if a value is a list containing only elements of a specific type
---@param val any Value to check
---@param t? type Expected type for all list elements (optional)
---@return boolean result true if val is a valid list
function M.is_list(val, t)
    -- First check if it's a list at all
    if not vim.islist(val) then
        return false
    end

    -- If no type specified, any list is valid
    if not t then
        return true
    end

    -- Check that all elements match the expected type
    for _, v in ipairs(val) do
        if type(v) ~= t then
            return false
        end
    end

    return true
end

return M
