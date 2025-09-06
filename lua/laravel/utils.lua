local M = {}
local Path = require("plenary.path")

-- Verificar se é um projeto Laravel
function M.is_laravel_project()
    local artisan = Path:new(vim.fn.getcwd(), "artisan")
    local composer = Path:new(vim.fn.getcwd(), "composer.json")

    if artisan:exists() and composer:exists() then
        local composer_content = composer:read()
        if composer_content and composer_content:match('"laravel/framework"') then
            return true
        end
    end

    return false
end

-- Mostrar status do plugin
function M.show_status()
    local status = {
        "Laravel.nvim Status",
        "==================",
        "",
        "Project: " .. (M.is_laravel_project() and "✓ Laravel project detected" or "✗ Not a Laravel project"),
        "Working directory: " .. vim.fn.getcwd(),
        "",
        "Features:",
        "  • Livewire support: ✓ Enabled",
        "  • Multi-language translations: ✓ Enabled",
        "  • Smart navigation: ✓ Active",
        "  • Auto-completion: ✓ Active",
        "",
        "Keybindings:",
        "  gd - Go to definition",
        "  <leader>La - Artisan command",
        "  <leader>Lr - Show routes",
        "  <leader>Lm - Make command",
        "  <leader>Lw - Livewire components",
        "  <leader>Lwc - Go to Livewire component",
        "  <leader>Lwv - Go to Livewire view",
        "",
    }

    -- Criar buffer temporário
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, status)
    vim.api.nvim_set_current_buf(buf)
end

return M
