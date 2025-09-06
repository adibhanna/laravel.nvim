local M = {}
local config = require("laravel.config")
local livewire = require("laravel.livewire")
local translations = require("laravel.translations")
local Path = require("plenary.path")

-- Cache geral
local completion_cache = {
    routes = {},
    views = {},
    configs = {},
    env = {},
    timestamp = 0,
}

-- Limpar cache
function M.clear_cache()
    completion_cache = {
        routes = {},
        views = {},
        configs = {},
        env = {},
        timestamp = 0,
    }
    vim.notify("Laravel completion cache cleared", vim.log.levels.INFO)
end

-- Atualizar cache
local function update_cache()
    local current_time = os.time()
    if current_time - completion_cache.timestamp > config.options.cache_ttl then
        -- Cache routes
        local routes_cmd = "php artisan route:list --json 2>/dev/null"
        local routes_result = vim.fn.system(routes_cmd)
        if vim.v.shell_error == 0 then
            local ok, routes = pcall(vim.json.decode, routes_result)
            if ok then
                completion_cache.routes = {}
                for _, route in ipairs(routes) do
                    if route.name then
                        table.insert(completion_cache.routes, {
                            label = route.name,
                            kind = vim.lsp.protocol.CompletionItemKind.Reference,
                            detail = route.uri or "",
                        })
                    end
                end
            end
        end

        -- Cache views
        completion_cache.views = {}
        local views_path = Path:new(vim.fn.getcwd(), "resources/views")
        if views_path:exists() then
            local files = vim.fn.globpath(views_path:absolute(), "**/*.blade.php", false, true)
            for _, file in ipairs(files) do
                local view_name = file:gsub(views_path:absolute() .. "/", "")
                    :gsub("%.blade%.php$", "")
                    :gsub("/", ".")
                table.insert(completion_cache.views, {
                    label = view_name,
                    kind = vim.lsp.protocol.CompletionItemKind.File,
                    detail = "Blade view",
                })
            end
        end

        -- Cache configs
        completion_cache.configs = {}
        local config_path = Path:new(vim.fn.getcwd(), "config")
        if config_path:exists() then
            local files = vim.fn.globpath(config_path:absolute(), "*.php", false, true)
            for _, file in ipairs(files) do
                local config_name = vim.fn.fnamemodify(file, ":t:r")

                -- Tentar extrair chaves do arquivo
                local content = Path:new(file):read()
                if content then
                    for key in content:gmatch("'([%w_]+)'%s*=>") do
                        table.insert(completion_cache.configs, {
                            label = config_name .. "." .. key,
                            kind = vim.lsp.protocol.CompletionItemKind.Property,
                            detail = "Config key",
                        })
                    end
                end
            end
        end

        -- Cache environment variables
        completion_cache.env = {}
        local env_path = Path:new(vim.fn.getcwd(), ".env")
        if env_path:exists() then
            local content = env_path:read()
            if content then
                for key in content:gmatch("([%w_]+)=") do
                    table.insert(completion_cache.env, {
                        label = key,
                        kind = vim.lsp.protocol.CompletionItemKind.Variable,
                        detail = "Environment variable",
                    })
                end
            end
        end

        completion_cache.timestamp = current_time
    end
end

-- Obter completions baseado no contexto
function M.get_completions(context)
    update_cache()

    local line = context.line or vim.api.nvim_get_current_line()
    local col = context.col or vim.api.nvim_win_get_cursor(0)[2]

    -- Detectar contexto
    local before_cursor = line:sub(1, col)

    -- Completions para Livewire
    if before_cursor:match("@livewire%(s*['\"]%w*$") or
        before_cursor:match("Livewire::component%(s*['\"]%w*$") or
        before_cursor:match("<livewire:%w*$") then
        return livewire.get_completions()
    end

    -- Completions para traduções
    if before_cursor:match("__%(s*['\"]%w*$") or
        before_cursor:match("trans%(s*['\"]%w*$") then
        return translations.get_completions()
    end

    -- Completions para rotas
    if before_cursor:match("route%(s*['\"]%w*$") then
        return completion_cache.routes
    end

    -- Completions para views
    if before_cursor:match("view%(s*['\"]%w*$") then
        return completion_cache.views
    end

    -- Completions para Inertia
    if before_cursor:match("Inertia::render%(s*['\"]%w*$") or
        before_cursor:match("inertia%(s*['\"]%w*$") then
        local inertia_completions = {}
        local pages_path = Path:new(vim.fn.getcwd(), "resources/js/Pages")
        if pages_path:exists() then
            local files = vim.fn.globpath(pages_path:absolute(), "**/*.{jsx,tsx,vue,svelte}", false, true)
            for _, file in ipairs(files) do
                local component_name = file:gsub(pages_path:absolute() .. "/", "")
                    :gsub("%.[^.]+$", "")
                    :gsub("/", ".")
                table.insert(inertia_completions, {
                    label = component_name,
                    kind = vim.lsp.protocol.CompletionItemKind.Module,
                    detail = "Inertia component",
                })
            end
        end
        return inertia_completions
    end

    -- Completions para configurações
    if before_cursor:match("config%(s*['\"]%w*$") then
        return completion_cache.configs
    end

    -- Completions para variáveis de ambiente
    if before_cursor:match("env%(s*['\"]%w*$") then
        return completion_cache.env
    end

    return {}
end

-- Setup do módulo
function M.setup()
    -- Registrar fonte de completion para nvim-cmp
    local has_cmp, cmp = pcall(require, "cmp")
    if has_cmp then
        local source = {}

        source.new = function()
            return setmetatable({}, { __index = source })
        end

        source.get_trigger_characters = function()
            return { "'", '"', ".", ":" }
        end

        source.complete = function(self, params, callback)
            local completions = M.get_completions({
                line = params.context.cursor_line,
                col = params.context.cursor.col,
            })
            callback(completions)
        end

        require("cmp").register_source("laravel", source.new())
    end
end

return M
