-- Laravel-specific keymaps and utilities
--
-- To disable all Laravel keymaps and create your own, use:
-- require('laravel').setup({ keymaps = false })
--
-- Then you can create custom keymaps using the available commands:
-- vim.keymap.set('n', '<your-key>', ':Artisan<CR>')
-- vim.keymap.set('n', '<your-key>', ':Composer<CR>')
-- vim.keymap.set('n', '<your-key>', function() require('laravel.navigate').goto_controller() end)
-- etc.
local M = {}

-- Setup Laravel-specific keymaps
-- All Laravel keymaps use <leader>L prefix for organization:
--
-- Global Laravel commands:
--   <leader>Lc - Go to controller
--   <leader>Lm - Go to model
--   <leader>Lv - Go to view
--   <leader>Lr - Go to route file
--   <leader>LR - Show routes
--   <leader>La - Run artisan command
--   <leader>Lk - Laravel make command
--   <leader>Ls - Show Laravel status
--   <leader>LS - Show schema diagram
--   <leader>LE - Export schema diagram
--   <leader>LA - Show architecture diagram
--
-- Laravel Sail commands:
--   <leader>Lsu - Sail up (start containers)
--   <leader>Lsd - Sail down (stop containers)
--   <leader>Lsr - Sail restart
--   <leader>Lst - Sail test
--   <leader>Lss - Sail status
--   <leader>Lsh - Sail shell
--   <leader>Lsl - Sail logs
--
-- Model-specific (in model files):
--   <leader>LR - Show model relationships
--   <leader>LA - Show model attributes
--
-- Migration-specific (in migration files):
--   <leader>Li - Show migration info
--   <leader>LM - Run migration command
--
local function setup_laravel_keymaps()
    -- Setup global Laravel keymaps for PHP files
    vim.api.nvim_create_autocmd('FileType', {
        pattern = 'php',
        callback = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local bufopts = { noremap = true, silent = true, buffer = bufnr }

            -- Enhanced gd mapping for Laravel string navigation
            vim.keymap.set('n', 'gd', function()
                -- Check if we're in a Laravel project
                if not (_G.laravel_nvim and _G.laravel_nvim.project_root) then
                    -- Not in Laravel project, use default LSP
                    if vim.lsp.buf.definition then
                        vim.lsp.buf.definition()
                    else
                        vim.cmd('normal! gd')
                    end
                    return
                end

                -- Check if this looks like a Laravel-specific pattern first
                local navigate = require('laravel.navigate')
                if navigate.is_laravel_navigation_context() then
                    -- This is a Laravel-specific context, try Laravel navigation
                    local success = pcall(navigate.goto_laravel_string)
                    if success then
                        return -- Laravel navigation succeeded
                    end
                end

                -- Default to LSP definition for everything else
                if vim.lsp.buf.definition then
                    vim.lsp.buf.definition()
                else
                    -- Final fallback to built-in definition
                    vim.cmd('normal! gd')
                end
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Go to definition (Laravel strings or LSP)' }))

            -- Laravel-specific navigation with <leader>L prefix
            vim.keymap.set('n', '<leader>Lc', function()
                require('laravel.navigate').goto_controller()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Go to controller' }))

            vim.keymap.set('n', '<leader>Lm', function()
                require('laravel.navigate').goto_model()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Go to model' }))

            vim.keymap.set('n', '<leader>Lv', function()
                require('laravel.navigate').goto_view()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Go to view' }))

            vim.keymap.set('n', '<leader>LR', function()
                require('laravel.routes').show_routes()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Show routes' }))

            vim.keymap.set('n', '<leader>Lr', function()
                require('laravel.navigate').goto_route_file()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Go to route file' }))

            vim.keymap.set('n', '<leader>La', function()
                vim.cmd('Artisan')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Run artisan command' }))

            vim.keymap.set('n', '<leader>Lk', function()
                require('laravel.artisan').make_command()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Make command' }))

            vim.keymap.set('n', '<leader>Ls', function()
                vim.cmd('LaravelStatus')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Show status' }))

            vim.keymap.set('n', '<leader>LS', function()
                require('laravel.schema').show_schema_diagram(false)
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Show schema diagram' }))

            vim.keymap.set('n', '<leader>LE', function()
                require('laravel.schema').show_schema_diagram(true)
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Export schema diagram' }))

            vim.keymap.set('n', '<leader>LA', function()
                require('laravel.architecture').show_architecture_diagram()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Show architecture diagram' }))

            -- Laravel Sail keymaps
            vim.keymap.set('n', '<leader>Lsu', function()
                vim.cmd('SailUp')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel Sail: Start containers' }))

            vim.keymap.set('n', '<leader>Lsd', function()
                vim.cmd('SailDown')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel Sail: Stop containers' }))

            vim.keymap.set('n', '<leader>Lsr', function()
                vim.cmd('SailRestart')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel Sail: Restart containers' }))

            vim.keymap.set('n', '<leader>Lst', function()
                vim.cmd('SailTest')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel Sail: Run tests' }))

            vim.keymap.set('n', '<leader>Lss', function()
                vim.cmd('SailStatus')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel Sail: Check status' }))

            vim.keymap.set('n', '<leader>Lsh', function()
                vim.cmd('SailShell')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel Sail: Open shell' }))

            vim.keymap.set('n', '<leader>Lsl', function()
                vim.cmd('SailLogs')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel Sail: View logs' }))

            vim.keymap.set('n', '<leader>Lso', function()
                vim.cmd('SailOpen')
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel Sail: Open in browser' }))

            -- Laravel Dump Viewer keymaps
            vim.keymap.set('n', '<leader>Ld', function()
                require('laravel.dump').open()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Open dump viewer' }))

            vim.keymap.set('n', '<leader>LDi', function()
                require('laravel.dump').install()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Install dump service provider' }))

            vim.keymap.set('n', '<leader>LDe', function()
                require('laravel.dump').enable()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Install and enable dump capture' }))

            vim.keymap.set('n', '<leader>LDd', function()
                require('laravel.dump').disable()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Disable dump capture' }))

            vim.keymap.set('n', '<leader>LDt', function()
                require('laravel.dump').toggle()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Toggle dump capture' }))

            vim.keymap.set('n', '<leader>LDc', function()
                require('laravel.dump').clear()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Clear dumps' }))

            -- Manual completion trigger
            vim.keymap.set('i', '<C-x><C-l>', function()
                local line = vim.fn.getline('.')
                local col = vim.fn.col('.') - 1

                local completion_source = require('laravel.completion_source')
                local context = completion_source.get_completion_context and
                    completion_source.get_completion_context(line, col)

                if context then
                    local completions = require('laravel.completions')
                    local items = completions.get_completions(context.func, context.partial)

                    if #items > 0 then
                        vim.fn.complete(col - #context.partial + 1, items)
                    else
                        vim.notify('No Laravel completions found', vim.log.levels.WARN)
                    end
                else
                    vim.notify('Not in a Laravel helper function', vim.log.levels.WARN)
                end
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Manual completion trigger' }))
        end,
    })

    -- Setup keymaps for Blade files
    vim.api.nvim_create_autocmd('FileType', {
        pattern = 'blade',
        callback = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local bufopts = { noremap = true, silent = true, buffer = bufnr }

            -- Enhanced gd mapping for Blade files too
            vim.keymap.set('n', 'gd', function()
                -- Check if this looks like a Laravel-specific pattern first
                local navigate = require('laravel.navigate')
                if navigate.is_laravel_navigation_context() then
                    -- This is a Laravel-specific context, try Laravel navigation
                    local success = pcall(navigate.goto_laravel_string)
                    if success then
                        return -- Laravel navigation succeeded
                    end
                end

                -- Default to LSP definition for everything else
                if vim.lsp.buf.definition then
                    vim.lsp.buf.definition()
                else
                    -- Final fallback to built-in definition
                    vim.cmd('normal! gd')
                end
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Go to definition (Laravel strings or LSP)' }))

            vim.keymap.set('n', '<leader>Lc', function()
                require('laravel.navigate').goto_controller()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Go to controller' }))

            vim.keymap.set('n', '<leader>Lv', function()
                require('laravel.navigate').goto_view()
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Go to view' }))
        end,
    })

    -- Setup keymaps for JavaScript/TypeScript files (for Inertia)
    vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' },
        callback = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local bufopts = { noremap = true, silent = true, buffer = bufnr }

            -- Enhanced gd mapping for JS/TS files in Laravel projects
            vim.keymap.set('n', 'gd', function()
                -- Check if we're in a Laravel project and this looks like a Laravel pattern
                if _G.laravel_nvim and _G.laravel_nvim.project_root then
                    local navigate = require('laravel.navigate')
                    if navigate.is_laravel_navigation_context() then
                        -- This is a Laravel-specific context, try Laravel navigation
                        local success = pcall(navigate.goto_laravel_string)
                        if success then
                            return -- Laravel navigation succeeded
                        end
                    end
                end

                -- Default to LSP definition for JS/TS
                if vim.lsp.buf.definition then
                    vim.lsp.buf.definition()
                else
                    -- Final fallback to built-in definition
                    vim.cmd('normal! gd')
                end
            end, vim.tbl_extend('force', bufopts, { desc = 'Laravel: Go to definition (Laravel strings or LSP)' }))
        end,
    })
end

-- Helper: Create the Laravel-aware gd handler
local function make_gd_handler()
    return function()
        -- Check if we're in a Laravel project
        if not (_G.laravel_nvim and _G.laravel_nvim.project_root) then
            -- Not in Laravel project, use default LSP
            if vim.lsp.buf.definition then
                vim.lsp.buf.definition()
            else
                vim.cmd('normal! gd')
            end
            return
        end

        -- Check if this looks like a Laravel-specific pattern first
        local navigate = require('laravel.navigate')
        if navigate.is_laravel_navigation_context() then
            local success = pcall(navigate.goto_laravel_string)
            if success then
                return
            end
        end

        -- Default to LSP definition for everything else
        if vim.lsp.buf.definition then
            vim.lsp.buf.definition()
        else
            vim.cmd('normal! gd')
        end
    end
end

-- Re-apply gd override on LspAttach so it takes precedence over
-- LSP plugins (Snacks Picker, etc.) that set gd on the same event
local function setup_lsp_attach_override()
    vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(args)
            local bufnr = args.buf
            local ft = vim.bo[bufnr].filetype

            -- Only override for filetypes where laravel.nvim manages gd
            if ft == 'php' or ft == 'blade' or ft == 'javascript' or ft == 'typescript'
                or ft == 'javascriptreact' or ft == 'typescriptreact' then
                if _G.laravel_nvim and _G.laravel_nvim.project_root then
                    vim.keymap.set('n', 'gd', make_gd_handler(), {
                        noremap = true,
                        silent = true,
                        buffer = bufnr,
                        desc = 'Laravel: Go to definition (Laravel strings or LSP)',
                    })
                end
            end
        end,
    })
end

-- Main setup function
function M.setup()
    setup_laravel_keymaps()
    setup_lsp_attach_override()
end

return M
