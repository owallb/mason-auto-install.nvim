local Package = require("mason-auto-install.package")
local log = require("mason-auto-install.log")
local registry = require("mason-registry")

local M = {}

---@class MasonAutoInstall.Config
---@field packages? (string|MasonAutoInstall.Package.Config)[] List of packages to manage. Can be package names as strings or configuration tables.

---@type MasonAutoInstall.Config
local config = {
    packages = {},
}

---@type MasonAutoInstall.Package[]
local packages = {}

--- Restart all LSP clients associated with a Package, if any
---@param pkg MasonAutoInstall.Package
local function restart_lsp_clients(pkg)
    -- Only restart if this package provides an LSP server
    if not pkg.lspconfig then
        return
    end

    -- Stop all running clients for this LSP server
    for _, client in ipairs(vim.lsp.get_clients({ name = pkg.lspconfig_name })) do
        client:stop(true)
    end

    -- Restart LSP clients after a brief delay to ensure clean shutdown
    vim.defer_fn(function()
        local filetypes = pkg.lspconfig.filetypes

        -- Trigger FileType autocmd for all relevant buffers to restart LSP
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if
                vim.api.nvim_buf_is_valid(buf)
                and vim.api.nvim_buf_is_loaded(buf)
                and (
                    not filetypes -- no filetypes == all filetypes
                    or vim.tbl_contains(filetypes, vim.bo[buf].filetype)
                )
            then
                vim.api.nvim_exec_autocmds("FileType", {
                    buffer = buf,
                    group = "nvim.lsp.enable",
                })
            end
        end
    end, 500)
end

--- Validate setup options
---@param opts MasonAutoInstall.Config
---@return string? error message on failure
function M.validate(opts)
    local ok, err =
        pcall(vim.validate, "packages", opts.packages, "table", true)

    if not ok then
        return err
    end

    -- Validate that packages is actually a list (array-like table)
    if opts.packages then
        if not vim.islist(opts.packages) then
            return "packages must be a list"
        end

        -- Validate each package entry
        for i, pkg in ipairs(opts.packages) do
            local pkg_type = type(pkg)
            if pkg_type ~= "string" and pkg_type ~= "table" then
                return string.format(
                    "packages[%d] must be a string or table, got %s",
                    i,
                    pkg_type
                )
            end
        end
    end

    return nil
end

--- Setup the mason-auto-install plugin
--- Creates autocmds that trigger package installation when files of specific
--- types are opened
---@param opts? MasonAutoInstall.Config Configuration options
function M.setup(opts)
    opts = opts or {}

    -- Validate configuration before proceeding
    local err = M.validate(opts)
    if err then
        log.error("Invalid setup options: %s", err)
        return
    end

    -- Merge user config with defaults
    config = vim.tbl_deep_extend("force", config, opts)

    registry.refresh(function()
        -- Create Package instances from configuration
        packages = {}
        for i, pkg_opts in ipairs(config.packages) do
            local pkg
            pkg, err = Package.new(pkg_opts)
            if pkg then
                table.insert(packages, pkg)
            else
                log.error("Failed to create package [%d]: %s", i, err)
            end
        end

        -- Create autocommand group (clear existing to allow reloading)
        local group =
            vim.api.nvim_create_augroup("MasonAutoInstall", { clear = true })

        -- Set up FileType autocmds for each package
        for _, pkg in ipairs(packages) do
            local ft
            -- Use package-specific filetypes if defined, otherwise trigger on
            -- any filetypes
            if #pkg.filetypes > 0 then
                ft = pkg.filetypes
            end

            vim.api.nvim_create_autocmd("FileType", {
                group = group,
                pattern = ft,
                once = true,
                callback = function()
                    -- Install package and dependencies, restart LSP if updated
                    pkg:ensure_all(function(success, was_updated)
                        if success and was_updated then
                            restart_lsp_clients(pkg)
                        end
                    end)
                end,
            })
        end
    end)
end

return M
