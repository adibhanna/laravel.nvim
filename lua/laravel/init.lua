local M = {}
local config = require("laravel.config")
local navigation = require("laravel.navigation")
local completion = require("laravel.completion")
local artisan = require("laravel.artisan")
local livewire = require("laravel.livewire")
local translations = require("laravel.translations")
local utils = require("laravel.utils")

M.setup = function(opts)
    config.setup(opts or {})

    -- Detectar projeto Laravel
    if utils.is_laravel_project() then
        -- Inicializar módulos
        navigation.setup()
        completion.setup()
        artisan.setup()
        livewire.setup()
        translations.setup()

        -- Comandos
        vim.api.nvim_create_user_command("LaravelArtisan", artisan.run, {})
        vim.api.nvim_create_user_command("LaravelRoute", navigation.show_routes, {})
        vim.api.nvim_create_user_command("LaravelMake", artisan.make_interactive, {})
        vim.api.nvim_create_user_command("LaravelStatus", utils.show_status, {})
        vim.api.nvim_create_user_command("LaravelClearCache", completion.clear_cache, {})

        -- Comandos Livewire
        vim.api.nvim_create_user_command("LivewireComponent", livewire.navigate_to_component, { nargs = 1 })
        vim.api.nvim_create_user_command("LivewireMake", livewire.make_component, { nargs = 1 })
        vim.api.nvim_create_user_command("LivewireList", livewire.list_components, {})

        -- Keymaps
        local opts = { noremap = true, silent = true }
        vim.keymap.set('n', 'gd', navigation.go_to_definition, opts)
        vim.keymap.set('n', '<leader>La', ':LaravelArtisan<CR>', opts)
        vim.keymap.set('n', '<leader>Lr', ':LaravelRoute<CR>', opts)
        vim.keymap.set('n', '<leader>Lm', ':LaravelMake<CR>', opts)
        vim.keymap.set('n', '<leader>Lw', ':LivewireList<CR>', opts)
        vim.keymap.set('n', '<leader>Lwc', livewire.go_to_component, opts)
        vim.keymap.set('n', '<leader>Lwv', livewire.go_to_view, opts)

        if config.options.notifications then
            vim.notify("Laravel.nvim loaded with Livewire support", vim.log.levels.INFO)
        end
    end
end

return M
