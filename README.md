# mason-auto-install.nvim

Automatically install and update
[Mason](https://github.com/mason-org/mason.nvim) packages.

## Features

- **On-demand installation**: Packages are installed only when buffers of
  relevant filetypes are opened
- **Automatic updates**: Keeps packages updated
- **Version pinning**: Lock packages to specific versions to avoid undesired
  updates
- **Post-install hooks**: Run shell commands or functions after package
  installation
- **LSP integration**: Automatically restart any LSP clients after updates

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'owallb/mason-auto-install.nvim',
    dependencies = {
        'williamboman/mason.nvim',
        -- Optional: LSP configurations in `vim.lsp.config` needs to be loaded
        -- first to find associated filetypes automatically. If you use
        -- lspconfig for that, add it as a dependency.
        'neovim/nvim-lspconfig',
    },
    opts = {
        packages = { 'lua_ls', 'stylua', 'prettier' }
    },
}
```

## Configuration

### Example

```lua
require('mason-auto-install').setup({
    packages = {
        'lua_ls',
        { 'stylua', version = '0.20.0' },
        {
            'typescript-language-server',
            dependencies = { 'prettier' },
            post_install_hooks = {
                function(pkg)
                    print("Installed " .. pkg.name)
                    return true
                end,
                { 'npm', 'install', '-g', '@types/node' }
            }
        }
    }
})
```

### Options

#### packages

List of packages to manage. Each entry can be a string (package name) or a table with detailed configuration.

#### Package Configuration

Each package can be configured with the following options:

| Option | Type | Description |
|--------|------|-------------|
| `[1]` or `name` | `string` (required) | Mason package name as it appears in the registry |
| `version` | `string?` | Specific version to install (defaults to latest) |
| `filetypes` | `string[]?` | File types that trigger installation (defaults to LSP filetypes if available, otherwise triggers on any filetype) |
| `dependencies` | `(string\|table)[]?` | Other packages this package depends on |
| `post_install_hooks` | `(function\|string[])[]?` | Functions or shell commands to run after installation |

### Dependencies

Dependencies are treated the same as any package and can be configured in the
same way. The only difference is they will be handled before the packages that
depend on them. It is useful for grouping related packages together, and even
works on multiple levels:

```lua
{
    'typescript-language-server',
    dependencies = {
        'prettier',
        'eslint_d',
        {
            'tailwindcss-language-server',
            version = "0.14.20",
            dependencies = {
                'css-lsp',
                'html-lsp'
            }
        }
    }
}
```

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
    ---@param pkg MasonAutoInstall.Package
    function(pkg)
        print("Setting up " .. pkg.name)
        -- Your custom setup logic here
        return true  -- or false to indicate failure
    end
}
```

#### Mixed Hooks

You can mix shell commands and functions in the same package:

```lua
post_install_hooks = {
    { 'npm', 'install', '-g', '@types/node' },
    ---@param pkg MasonAutoInstall.Package
    function(pkg)
        vim.notify("TypeScript setup complete!")
        return true
    end
}
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

BSD-3 Clause - see [LICENSE](LICENSE) file for details.
