local M = {}
local config = require("laravel.config")
local utils = require("laravel.utils")
local Path = require("plenary.path")

-- Cache para componentes Livewire
local component_cache = {}
local cache_timestamp = 0

-- Atualizar cache de componentes
local function update_component_cache()
    local current_time = os.time()
    if current_time - cache_timestamp > config.options.cache_ttl then
        component_cache = {}
        local component_path = Path:new(vim.fn.getcwd(), config.options.livewire.component_path)

        if component_path:exists() then
            local files = vim.fn.globpath(component_path:absolute(), "**/*.php", false, true)
            for _, file in ipairs(files) do
                local relative = Path:new(file):make_relative(vim.fn.getcwd())
                local component_name = relative:gsub("^" .. config.options.livewire.component_path .. "/", "")
                    :gsub("%.php$", "")
                    :gsub("/", ".")

                -- Armazenar informações do componente
                component_cache[component_name] = {
                    file = file,
                    class_name = component_name:gsub("%.", "\\"),
                    view_name = "livewire." .. component_name:lower():gsub("%.", "."),
                }
            end
        end

        cache_timestamp = current_time
    end
end

-- Detectar componente Livewire no contexto atual
function M.detect_livewire_component()
    local line = vim.api.nvim_get_current_line()
    local patterns = {
        -- Routes com Livewire
        { pattern = "Livewire::component%s*%(s*['\"]([^'\"]+)['\"]", type = "route" },
        { pattern = "livewire%s*%(s*['\"]([^'\"]+)['\"]",            type = "route" },

        -- Blade directives
        { pattern = "@livewire%s*%(s*['\"]([^'\"]+)['\"]",           type = "blade" },
        { pattern = "<livewire:([%w%-%.]+)",                         type = "blade_tag" },

        -- PHP class references
        { pattern = "([%w\\]+)::class",                              type = "class" },
        { pattern = "new%s+([%w\\]+)",                               type = "class" },
    }

    for _, p in ipairs(patterns) do
        local match = line:match(p.pattern)
        if match then
            if p.type == "blade_tag" then
                -- Converter kebab-case para dot notation
                match = match:gsub("%-", ".")
            elseif p.type == "class" then
                -- Verificar se é um componente Livewire
                if match:match("^" .. config.options.livewire.namespace:gsub("\\", "\\\\")) then
                    match = match:gsub("^" .. config.options.livewire.namespace:gsub("\\", "\\\\") .. "\\", "")
                        :gsub("\\", ".")
                else
                    return nil
                end
            end

            return match, p.type
        end
    end

    return nil
end

-- Navegar para componente Livewire
function M.go_to_component()
    update_component_cache()

    local component_name, context = M.detect_livewire_component()
    if not component_name then
        vim.notify("No Livewire component detected", vim.log.levels.WARN)
        return
    end

    local component = component_cache[component_name]
    if component then
        vim.cmd("edit " .. component.file)
    else
        -- Tentar criar o componente se não existir
        local create = vim.fn.input("Component '" .. component_name .. "' not found. Create it? (y/N): ")
        if create:lower() == "y" then
            M.make_component(component_name)
        end
    end
end

-- Navegar para view do componente Livewire
function M.go_to_view()
    update_component_cache()

    local component_name = M.detect_livewire_component()
    if not component_name then
        -- Se estiver em um arquivo de componente, detectar pelo nome do arquivo
        local current_file = vim.fn.expand("%:p")
        if current_file:match(config.options.livewire.component_path) then
            component_name = current_file:gsub("^.*" .. config.options.livewire.component_path .. "/", "")
                :gsub("%.php$", "")
                :gsub("/", ".")
        else
            vim.notify("No Livewire component detected", vim.log.levels.WARN)
            return
        end
    end

    local component = component_cache[component_name]
    if component then
        local view_path = Path:new(vim.fn.getcwd(), "resources/views",
            component.view_name:gsub("%.", "/") .. ".blade.php")

        if view_path:exists() then
            vim.cmd("edit " .. view_path:absolute())
        else
            local create = vim.fn.input("View not found. Create it? (y/N): ")
            if create:lower() == "y" then
                view_path:parent():mkdir({ parents = true })
                view_path:touch()
                vim.cmd("edit " .. view_path:absolute())

                -- Template básico para view Livewire
                local template = {
                    "<div>",
                    "    {{-- " .. component_name .. " Component --}}",
                    "    ",
                    "</div>",
                }
                vim.api.nvim_buf_set_lines(0, 0, -1, false, template)
            end
        end
    end
end

-- Criar novo componente Livewire
function M.make_component(name)
    if not name or name == "" then
        name = vim.fn.input("Component name: ")
    end

    if name == "" then
        return
    end

    -- Executar comando artisan
    local cmd = "php artisan make:livewire " .. name
    local result = vim.fn.system(cmd)

    if vim.v.shell_error == 0 then
        vim.notify("Livewire component '" .. name .. "' created successfully", vim.log.levels.INFO)

        -- Limpar cache para incluir novo componente
        component_cache = {}
        cache_timestamp = 0

        -- Abrir o componente criado
        vim.defer_fn(function()
            M.navigate_to_component(name)
        end, 100)
    else
        vim.notify("Failed to create component: " .. result, vim.log.levels.ERROR)
    end
end

-- Listar todos os componentes Livewire
function M.list_components()
    update_component_cache()

    local components = {}
    for name, info in pairs(component_cache) do
        table.insert(components, {
            name = name,
            file = info.file,
            view = info.view_name,
        })
    end

    if #components == 0 then
        vim.notify("No Livewire components found", vim.log.levels.INFO)
        return
    end

    -- Ordenar por nome
    table.sort(components, function(a, b) return a.name < b.name end)

    -- Criar picker com telescope se disponível
    local ok, telescope = pcall(require, "telescope")
    if ok then
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        pickers.new({}, {
            prompt_title = "Livewire Components",
            finder = finders.new_table({
                results = components,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = entry.name,
                        ordinal = entry.name,
                    }
                end
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    vim.cmd("edit " .. selection.value.file)
                end)

                map("i", "<C-v>", function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    M.navigate_to_component(selection.value.name)
                    M.go_to_view()
                end)

                return true
            end,
        }):find()
    else
        -- Fallback sem telescope
        vim.ui.select(
            vim.tbl_map(function(c) return c.name end, components),
            { prompt = "Select Livewire Component:" },
            function(choice)
                if choice then
                    for _, c in ipairs(components) do
                        if c.name == choice then
                            vim.cmd("edit " .. c.file)
                            break
                        end
                    end
                end
            end
        )
    end
end

-- Navegar para componente específico
function M.navigate_to_component(name)
    update_component_cache()

    local component = component_cache[name]
    if component then
        vim.cmd("edit " .. component.file)
    else
        vim.notify("Component '" .. name .. "' not found", vim.log.levels.ERROR)
    end
end

-- Setup do módulo
function M.setup()
    -- Auto-completar componentes Livewire
    if vim.fn.has("nvim-0.7") == 1 then
        vim.api.nvim_create_autocmd("FileType", {
            pattern = { "php", "blade" },
            callback = function()
                update_component_cache()
            end,
        })
    end
end

-- Fornecer completions para componentes Livewire
function M.get_completions()
    update_component_cache()

    local completions = {}
    for name, info in pairs(component_cache) do
        table.insert(completions, {
            label = name,
            kind = vim.lsp.protocol.CompletionItemKind.Class,
            detail = "Livewire Component",
            documentation = "Class: " .. info.class_name .. "\nView: " .. info.view_name,
        })
    end

    return completions
end

return M
