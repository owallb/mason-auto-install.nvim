# mason-auto-install

Automatically install [Mason](https://github.com/mason-org/mason.nvim) packages on demand based on file types.

## Overview

Instead of pre-installing all LSP servers, formatters, and linters, `mason-auto-install` installs Mason packages only when you actually need them. When you open a file of a specific type, the plugin automatically installs the required tools in the background.

## Features

- **On-demand installation**: Packages are installed only when files of relevant types are opened
- **Dependency management**: Automatically install package dependencies
- **Version pinning**: Lock packages to specific versions
- **Post-install hooks**: Run shell commands or functions after package installation
- **LSP integration**: Automatically restart LSP clients after updates

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'owallb/mason-auto-install.nvim',
    dependencies = {
        'williamboman/mason.nvim',
    },
    config = function()
        require('mason-auto-install').setup({
            -- your configuration here
        })
    end,
}
```

## Configuration

### Basic Usage

```lua
require('mason-auto-install').setup({
    packages = {
        -- Simple package names (installs latest version)
        'lua_ls',
        'stylua',
        'prettier',
    }
})
```

### Advanced Configuration

```lua
require('mason-auto-install').setup({
    packages = {
        -- Simple package
        'lua_ls',
        
        -- Package with specific version
        {
            'stylua',
            version = '0.20.0'
        },
        
        -- Package with custom filetypes
        {
            'prettier',
            filetypes = { 'javascript', 'typescript', 'json', 'markdown' }
        },
        
        -- Package with dependencies
        {
            'rust_analyzer',
            dependencies = {
                'codelldb',
                { 'cargo', version = 'latest' }
            }
        },
        
        -- Package with shell command hooks
        {
            name = 'pyright',
            post_install_hooks = {
                -- Shell commands run in package directory
                { 'pip', 'install', '--upgrade', 'python-lsp-server' },
                { 'pip', 'install', 'black', 'isort' }
            }
        },
        
        -- Package with function hooks
        {
            name = 'typescript-language-server',
            post_install_hooks = {
                -- functions receive the package instance
                function(pkg)
                    print("Installed " .. pkg.name .. " version " .. pkg.version)
                    -- Return false to indicate failure, true/nil for success
                    return true
                end,
                -- Mix shell commands and functions
                { 'npm', 'install', '-g', '@types/node' }
            }
        },
        
        -- Complex example with everything
        {
            name = 'rust_analyzer',
            version = '2024-01-01',
            filetypes = { 'rust' },
            dependencies = {
                'codelldb',
                { 'cargo', version = 'latest' }
            },
            post_install_hooks = {
                -- Shell command
                { 'rustup', 'component', 'add', 'rust-analyzer' },
                -- function
                function(pkg)
                    vim.notify("Rust Analyzer setup complete!")
                    return true
                end
            }
        }
    }
})
```

## Configuration Options

### Package Configuration

Each package can be configured with the following options:

| Option | Type | Description |
|--------|------|-------------|
| `[1]` or `name` | `string` | Mason package name (required) |
| `version` | `string?` | Specific version to install (defaults to latest) |
| `filetypes` | `string[]?` | File types that trigger installation (defaults to LSP filetypes) |
| `dependencies` | `(string\|table)[]?` | Other packages this package depends on |
| `post_install_hooks` | `(function\|string[])[]?` | Functions or shell commands to run after installation |

### Post-Install Hooks

Post-install hooks can be either shell commands or functions:

#### Shell Commands
- Must be arrays of strings (command + arguments)
- Run in the package's installation directory
- Failure indicated by non-zero exit code

```lua
post_install_hooks = {
    { 'npm', 'install', '-g', 'some-package' },
    { 'pip', 'install', 'additional-tool' }
}
```

#### Functions
- Receive the package instance as parameter
- Return `false` to indicate failure, `true` or `nil` for success
- Can access package properties like `name`, `version`, etc.

```lua
post_install_hooks = {
    function(pkg)
        print("Setting up " .. pkg.name)
        -- Your custom setup logic here
        return true  -- or false to indicate failure
    end
}
```

### Dependencies

Dependencies can be specified as:
- **Strings**: `'package_name'` (uses latest version)
- **Tables**: `{ 'package_name', version = '1.0.0' }` (full config)

```lua
dependencies = {
    'package1',
    { 'package2', version = '2.1.0' }
}
```

## How It Works

1. **Setup**: When you call `setup()`, the plugin creates FileType autocmds for each package
2. **Trigger**: When you open a file matching configured filetypes, the autocmd fires
3. **Installation**: The plugin checks if the package is installed with the correct version
4. **Dependencies**: If not, it first installs any dependencies recursively, and then the main package
5. **Post-hooks**: After successful installation, runs any post-install hooks
6. **LSP Restart**: If the package provides an LSP server, restarts relevant clients

## Troubleshooting

### Common Issues

1. **Package not found**: Ensure the package name matches exactly what's in the Mason registry
2. **Version conflicts**: Check that the specified version exists for the package
3. **Post-install hooks failing**: 
   Shell commands:
   - Run in the package installation directory
   - Check error output in notifications
   - Ensure commands are in PATH or use full paths

   Functions:
   - Should return boolean values (true/false/nil)
   - Use `pcall()` for error handling in complex functions
4. **LSP not restarting**: The plugin only restarts LSPs for packages that provide lspconfig integration. Manual restart may be needed for some packages.

### Debugging

Enable Mason's debug logging to see installation details:

```lua
require('mason').setup({
    log_level = vim.log.levels.DEBUG
})
```

Check the Mason registry for available packages:
```vim
:Mason
```

View Mason logs:
```vim
:MasonLog
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

BSD-3 Clause - see [LICENSE](LICENSE) file for details.
