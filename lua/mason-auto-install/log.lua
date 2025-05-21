local M = {}

--- Log an error message
---@param fmt string Format string (supports string.format placeholders)
---@param ... any Arguments for format string
function M.error(fmt, ...)
    vim.notify(
        fmt:format(...),
        vim.log.levels.ERROR,
        { title = "mason-auto-install" }
    )
end

--- Log an informational message
---@param fmt string Format string (supports string.format placeholders)
---@param ... any Arguments for format string
function M.info(fmt, ...)
    vim.notify(
        fmt:format(...),
        vim.log.levels.INFO,
        { title = "mason-auto-install" }
    )
end

return M
