local InstallLocation = require("mason-core.installer.InstallLocation").global()
local log = require("mason-auto-install.log")
local registry = require("mason-registry")
local util = require("mason-auto-install.util")

---@alias MasonPackage Package

---@class MasonAutoInstall.Package
---@field name string The Mason package name
---@field version string The package version to install (defaults to latest)
---@field filetypes string[] File types that trigger this package's installation
---@field dependencies MasonAutoInstall.Package[] Other packages this package depends on
---@field post_install_hooks (fun(pkg: MasonAutoInstall.Package): boolean?|string[])[] Functions or shell commands to run after installation
---@field mason MasonPackage The underlying Mason package instance
---@field lspconfig_name? string The LSP server name for lspconfig integration
---@field lspconfig? vim.lsp.Config The LSP configuration if this package provides an LSP server
local M = {}
M.__index = M

---@class MasonAutoInstall.Package.Config.SchemaEntry
---@field field string|number Field name in the configuration
---@field validator vim.validate.Validator Validation function for the field
---@field optional boolean Whether the field is optional
---@field message? string Custom error message for validation failures

--- Run post-installation hooks
--- Executes shell commands or Lua functions after package installation.
--- Shell commands run in the package's installation directory.
--- Lua functions receive the package instance and can return boolean for success/failure.
---@param on_done? fun(success: boolean) Called when all hooks complete
function M:run_post_install_hooks(on_done)
    if #self.post_install_hooks == 0 then
        if on_done then
            on_done(true)
        end
        return
    end

    log.info("Running post install hooks for %s", self.name)

    local total_hooks = #self.post_install_hooks
    local completed_hooks = 0
    local success = true

    local function on_hook_complete(hook_success)
        if not hook_success then
            success = false
        end

        completed_hooks = completed_hooks + 1
        if completed_hooks == total_hooks then
            if success then
                log.info("Finished all post install hooks for %s", self.name)
            end
            if on_done then
                on_done(success)
            end
        end
    end

    -- Run all hooks
    for _, hook in ipairs(self.post_install_hooks) do
        local cwd = InstallLocation:package(self.name)

        if type(hook) == "function" then
            -- Execute Lua function hook
            vim.schedule(function()
                local hook_success = true
                local ok, result = pcall(hook, self)

                if not ok then
                    -- Function threw an error
                    log.error(
                        "Post install hook function failed for %s: %s",
                        self.name,
                        result
                    )
                    hook_success = false
                elseif result ~= nil and not result then
                    -- Function explicitly returned false
                    log.error(
                        "Post install hook function returned false for %s",
                        self.name
                    )
                    hook_success = false
                end

                on_hook_complete(hook_success)
            end)
        elseif util.is_list(hook, "string") then
            local cmd = hook
            vim.system(cmd, { cwd = cwd }, function(resp)
                if resp.code ~= 0 then
                    local stdout = ""
                    if resp.stdout then
                        stdout = "\nstdout:\n" .. resp.stdout
                    end

                    local stderr = ""
                    if resp.stderr then
                        stderr = "\nstderr:\n" .. resp.stderr
                    end

                    log.error(
                        "command failed with non-zero exit status (%d): %s%s%s",
                        resp.code,
                        table.concat(cmd, " "),
                        stdout,
                        stderr
                    )
                end

                vim.schedule(function()
                    on_hook_complete(resp.code == 0)
                end)
            end)
        end
    end
end

--- Handle package installation or update
--- Installs the package if not present, or updates it if the version differs.
--- Runs post-installation hooks after successful installation.
---@param on_done? fun(success: boolean, was_updated: boolean) Called when installation completes
function M:install(on_done)
    -- Skip if already installing to avoid conflicts
    if self.mason:is_installing() then
        if on_done then
            on_done(true, false)
        end

        return
    end

    local previous = self.mason:get_installed_version()
    local version_str
    if previous then
        version_str = string.format("%s -> %s", previous, self.version)
    else
        version_str = self.version
    end

    log.info("Installing %s %s", self.name, version_str)
    local stderr = ""
    self.mason
        :install({ version = self.version })
        :on(
            "stderr",
            vim.schedule_wrap(function(msg)
                stderr = stderr .. msg
            end)
        )
        :once(
            "closed",
            vim.schedule_wrap(function()
                local is_installed = self.mason:is_installed()
                local was_updated = previous
                    ~= self.mason:get_installed_version()

                if not is_installed then
                    log.error("Failed to install %s: %s", self.name, stderr)
                    if on_done then
                        on_done(false, was_updated)
                    end
                else
                    log.info("Successfully installed %s", self.name)
                    self:run_post_install_hooks(function(success)
                        if on_done then
                            on_done(success, was_updated)
                        end
                    end)
                end
            end)
        )
end

--- Ensure package is installed with the correct version
--- Only installs if the package is missing or has a different version than specified.
---@param on_done? fun(success: boolean, was_updated: boolean) Called when check/installation completes
function M:ensure_installed(on_done)
    if self.mason:get_installed_version() ~= self.version then
        self:install(on_done)
    elseif on_done then
        on_done(true, false)
    end
end

--- Ensure all package dependencies are installed
--- Recursively installs all dependencies.
---@param on_done? fun(success: boolean, was_updated: boolean) Called when all dependencies has been processed
function M:ensure_dependencies(on_done)
    local total = #self.dependencies
    local completed = 0
    local all_successful = true
    local any_updated = false

    local function handle_result(success, was_updated)
        completed = completed + 1

        if not success then
            all_successful = false
        end

        if not any_updated and was_updated then
            any_updated = true
        end

        if completed == total and on_done then
            on_done(all_successful, any_updated)
        end
    end

    -- Install all dependencies in parallel
    for _, dep in ipairs(self.dependencies) do
        dep:ensure_all(handle_result)
    end
end

--- Ensure package and all dependencies are installed
--- This is the main entry point for package installation. It:
--- 1. Refreshes the Mason registry
--- 2. Installs all dependencies first
--- 3. Installs the main package
---@param on_done? fun(success: boolean, was_updated: boolean) Called when everything is complete
function M:ensure_all(on_done)
    registry.refresh(function()
        if self.dependencies and #self.dependencies ~= 0 then
            -- Install dependencies first
            self:ensure_dependencies(function(deps_success, deps_was_updated)
                if deps_success then
                    -- Dependencies succeeded, install main package
                    self:ensure_installed(function(success, was_updated)
                        if on_done then
                            on_done(success, deps_was_updated or was_updated)
                        end
                    end)
                elseif on_done then
                    -- Dependencies failed, don't install main package
                    on_done(false, deps_was_updated)
                end
            end)
        else
            -- No dependencies, install main package directly
            self:ensure_installed(on_done)
        end
    end)
end

--- Validate package configuration
--- Ensures all fields in the package configuration are valid before creating the package.
---@param opts MasonAutoInstall.Package.Config Configuration to validate
---@return string? error_message Error message on failure, nil on success
function M.validate(opts)
    ---@type MasonAutoInstall.Package.Config.SchemaEntry[]
    local schema = {
        { field = 1, optional = true, validator = "string" },
        { field = "name", optional = true, validator = "string" },
        { field = "version", optional = true, validator = "string" },
        {
            field = "filetypes",
            optional = true,
            validator = function(v)
                return util.is_list(v, "string")
            end,
        },
        {
            field = "dependencies",
            optional = true,
            message = "list of PackageConfig",
            validator = function(v)
                if not vim.islist(v) then
                    return false, "dependencies must be a list"
                end

                -- Validate each dependency
                for i, dep in ipairs(v) do
                    if type(dep) == "string" then
                        goto continue
                    elseif type(dep) == "table" then
                        local err = M.validate(dep)
                        if err then
                            return false,
                                string.format(
                                    "invalid dependency [%d]: %s",
                                    i,
                                    err
                                )
                        end
                    else
                        return false,
                            string.format(
                                "dependency [%d] must be a string or table, got %s",
                                i,
                                type(dep)
                            )
                    end
                    ::continue::
                end

                return true
            end,
        },
        {
            field = "post_install_hooks",
            optional = true,
            message = "list of functions or shell commands",
            validator = function(v)
                if not vim.islist(v) then
                    return false
                end

                for _, hook in ipairs(v) do
                    if type(hook) == "function" then
                        goto continue
                    elseif util.is_list(hook, "string") and #hook > 0 then
                        goto continue
                    else
                        return false,
                            "hook must be a shell command (list of strings) or a function"
                    end
                    ::continue::
                end

                return true
            end,
        },
    }

    -- Validate each field according to its schema
    for _, spec in ipairs(schema) do
        local name = spec.field
        local ok, err = pcall(
            vim.validate,
            name,
            opts[spec.field],
            spec.validator,
            spec.optional,
            spec.message
        )
        if not ok then
            return err
        end
    end
end

---@class MasonAutoInstall.Package.Config
---@field [1]? string Shorthand for package name
---@field name? string Package name as it appears in Mason registry
---@field version? string Package version constraint or tag (defaults to latest)
---@field filetypes? string[] Filetypes that trigger installations (defaults to LSP filetypes if available)
---@field dependencies? (string|MasonAutoInstall.Package.Config)[] Other packages this package requires
---@field post_install_hooks? (fun(pkg: MasonAutoInstall.Package): boolean?|string[])[] Functions or shell commands to execute after installation

--- Create a new Package instance
--- Validates the configuration and creates a Package object with all necessary metadata.
---@param opts MasonAutoInstall.Package.Config|string Package configuration or package name
---@return MasonAutoInstall.Package? package The created package instance
---@return string? error Error message on failure
function M.new(opts)
    -- Handle shorthand string format
    if type(opts) == "string" then
        opts = { opts }
    elseif type(opts) ~= "table" then
        return nil, "expected string or table, got " .. type(opts)
    end

    -- Support both opts[1] and opts.name for package name
    if opts[1] and not opts.name then
        opts.name = opts[1]
    end

    -- Validate configuration
    local err = M.validate(opts)
    if err then
        return nil, "invalid options: " .. err
    end

    -- Create base package structure
    local package = {
        name = opts[1] or opts.name,
        version = opts.version,
        dependencies = {},
        post_install_hooks = opts.post_install_hooks or {},
    }

    -- Get the Mason package from registry
    local success, result = pcall(registry.get_package, package.name)
    if not success then
        return nil,
            string.format(
                "Failed to get package %s from mason registry: %s",
                package.name,
                result
            )
    end
    package.mason = result

    -- Use specified version or default to latest
    package.version = package.version or package.mason:get_latest_version()

    -- Check if this package provides an LSP server
    package.lspconfig_name =
        vim.tbl_get(package.mason, "spec", "neovim", "lspconfig")
    if package.lspconfig_name then
        package.lspconfig = vim.tbl_get(vim.lsp.config, package.lspconfig_name)
    end

    -- Determine filetypes that trigger installation
    if not opts.filetypes and package.lspconfig then
        -- Use LSP filetypes if available and not overridden
        package.filetypes = package.lspconfig.filetypes or {}
    else
        -- Use specified filetypes or empty list (triggers on any filetype)
        package.filetypes = opts.filetypes or {}
    end

    -- Create dependency packages
    if opts.dependencies then
        for i, dep_opts in ipairs(opts.dependencies) do
            local dep
            dep, err = M.new(dep_opts)
            if not dep then
                return nil, ("invalid dependency [%d]: %s"):format(i, err)
            end

            package.dependencies[i] = dep
        end
    end

    return setmetatable(package, M), nil
end

return M
