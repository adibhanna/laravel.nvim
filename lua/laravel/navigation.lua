local M = {}
local config = require("laravel.config")
local Path = require("plenary.path")
local utils = require("laravel.utils")

-- Cache de traduções
local translation_cache = {}
local available_langs = {}
local cache_timestamp = 0

-- Atualizar cache de idiomas disponíveis
local function update_language_cache()
    local current_time = os.time()
    if current_time - cache_timestamp > config.options.cache_ttl then
        available_langs = {}
        translation_cache = {}

        local lang_path = Path:new(vim.fn.getcwd(), "lang")
        local resources_lang_path = Path:new(vim.fn.getcwd(), "resources/lang")

        -- Verificar ambos os caminhos possíveis
        local paths_to_check = {}
        if lang_path:exists() then
            table.insert(paths_to_check, lang_path)
        end
        if resources_lang_path:exists() then
            table.insert(paths_to_check, resources_lang_path)
        end

        for _, path in ipairs(paths_to_check) do
            -- Listar diretórios de idiomas
            local dirs = vim.fn.globpath(path:absolute(), "*", false, true)
            for _, dir in ipairs(dirs) do
                if vim.fn.isdirectory(dir) == 1 then
                    local lang_code = vim.fn.fnamemodify(dir, ":t")
                    if not vim.tbl_contains(available_langs, lang_code) then
                        table.insert(available_langs, lang_code)
                    end

                    -- Carregar arquivos de tradução
                    local files = vim.fn.globpath(dir, "*.php", false, true)
                    for _, file in ipairs(files) do
                        local file_name = vim.fn.fnamemodify(file, ":t:r")
                        if not translation_cache[file_name] then
                            translation_cache[file_name] = {}
                        end
                        translation_cache[file_name][lang_code] = file
                    end

                    -- Também verificar arquivos JSON
                    local json_file = Path:new(path:absolute(), lang_code .. ".json")
                    if json_file:exists() then
                        if not translation_cache["_json"] then
                            translation_cache["_json"] = {}
                        end
                        translation_cache["_json"][lang_code] = json_file:absolute()
                    end
                end
            end
        end

        cache_timestamp = current_time
    end
end

-- Detectar chave de tradução na linha atual
function M.detect_translation_key()
    local line = vim.api.nvim_get_current_line()
    local patterns = {
        "__%(s*['\"]([^'\"]+)['\"]",
        "trans%(s*['\"]([^'\"]+)['\"]",
        "trans_choice%(s*['\"]([^'\"]+)['\"]",
        "@lang%(s*['\"]([^'\"]+)['\"]",
        "Lang::get%(s*['\"]([^'\"]+)['\"]",
    }

    for _, pattern in ipairs(patterns) do
        local match = line:match(pattern)
        if match then
            return match
        end
    end

    return nil
end

-- Escolher idioma para navegação
function M.choose_language(callback)
    update_language_cache()

    if #available_langs == 0 then
        vim.notify("No translation files found", vim.log.levels.WARN)
        return
    end

    if #available_langs == 1 then
        callback(available_langs[1])
        return
    end

    -- Se configurado um idioma padrão, usar ele
    if config.options.translations.default_lang and
        vim.tbl_contains(available_langs, config.options.translations.default_lang) then
        callback(config.options.translations.default_lang)
        return
    end

    -- Mostrar picker de idiomas
    if config.options.translations.show_picker then
        vim.ui.select(
            available_langs,
            {
                prompt = "Select language:",
                format_item = function(lang)
                    local lang_names = {
                        en = "English",
                        pt = "Português",
                        es = "Español",
                        fr = "Français",
                        de = "Deutsch",
                        it = "Italiano",
                        ja = "日本語",
                        ko = "한국어",
                        zh = "中文",
                        ru = "Русский",
                        ar = "العربية",
                        ["pt-BR"] = "Português (Brasil)",
                        ["en-US"] = "English (US)",
                        ["en-GB"] = "English (UK)",
                    }
                    return lang_names[lang] or lang
                end
            },
            function(choice)
                if choice then
                    -- Salvar escolha temporariamente
                    config.options.translations.default_lang = choice
                    callback(choice)
                end
            end
        )
    else
        -- Usar o primeiro idioma disponível
        callback(available_langs[1])
    end
end

-- Navegar para arquivo de tradução
function M.go_to_translation()
    local key = M.detect_translation_key()
    if not key then
        vim.notify("No translation key detected", vim.log.levels.WARN)
        return
    end

    -- Dividir a chave em arquivo e chave específica
    local parts = vim.split(key, ".", { plain = true })
    local file_name = parts[1]
    local specific_key = table.concat(vim.list_slice(parts, 2), ".")

    M.choose_language(function(lang)
        update_language_cache()

        local file_path = nil

        -- Verificar arquivo PHP
        if translation_cache[file_name] and translation_cache[file_name][lang] then
            file_path = translation_cache[file_name][lang]
        elseif translation_cache["_json"] and translation_cache["_json"][lang] then
            -- Para traduções JSON
            file_path = translation_cache["_json"][lang]
        end

        if file_path then
            vim.cmd("edit " .. file_path)

            -- Tentar encontrar a chave específica no arquivo
            if specific_key and specific_key ~= "" then
                vim.defer_fn(function()
                    local search_pattern = "'" .. specific_key .. "'"
                    vim.fn.search(search_pattern, "w")
                end, 100)
            end
        else
            -- Oferecer criar o arquivo de tradução
            local create = vim.fn.input("Translation file not found for '" .. lang ..
                "'. Create it? (y/N): ")
            if create:lower() == "y" then
                M.create_translation_file(file_name, lang)
            end
        end
    end)
end

-- Criar arquivo de tradução
function M.create_translation_file(file_name, lang)
    local lang_dir = Path:new(vim.fn.getcwd(), "lang", lang)

    -- Criar diretório se não existir
    if not lang_dir:exists() then
        lang_dir:mkdir({ parents = true })
    end

    local file_path = Path:new(lang_dir:absolute(), file_name .. ".php")

    -- Template básico para arquivo de tradução
    local template = {
        "<?php",
        "",
        "return [",
        "    //",
        "];",
    }

    file_path:write(table.concat(template, "\n"), "w")
    vim.cmd("edit " .. file_path:absolute())

    -- Limpar cache
    translation_cache = {}
    cache_timestamp = 0

    vim.notify("Translation file created: " .. file_path:absolute(), vim.log.levels.INFO)
end

-- Listar todas as traduções disponíveis
function M.list_translations()
    update_language_cache()

    local translations = {}
    for file_name, langs in pairs(translation_cache) do
        if file_name ~= "_json" then
            for lang, path in pairs(langs) do
                table.insert(translations, {
                    file = file_name,
                    lang = lang,
                    path = path,
                })
            end
        end
    end

    if #translations == 0 then
        vim.notify("No translations found", vim.log.levels.INFO)
        return
    end

    -- Ordenar por arquivo e idioma
    table.sort(translations, function(a, b)
        if a.file == b.file then
            return a.lang < b.lang
        end
        return a.file < b.file
    end)

    -- Usar telescope se disponível
    local ok, telescope = pcall(require, "telescope")
    if ok then
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        pickers.new({}, {
            prompt_title = "Laravel Translations",
            finder = finders.new_table({
                results = translations,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = entry.file .. " (" .. entry.lang .. ")",
                        ordinal = entry.file .. " " .. entry.lang,
                    }
                end
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    vim.cmd("edit " .. selection.value.path)
                end)
                return true
            end,
        }):find()
    else
        -- Fallback sem telescope
        vim.ui.select(
            vim.tbl_map(function(t) return t.file .. " (" .. t.lang .. ")" end, translations),
            { prompt = "Select Translation:" },
            function(choice, idx)
                if choice and idx then
                    vim.cmd("edit " .. translations[idx].path)
                end
            end
        )
    end
end

-- Setup do módulo
function M.setup()
    -- Comandos adicionais
    vim.api.nvim_create_user_command("LaravelTranslations", M.list_translations, {})
    vim.api.nvim_create_user_command("LaravelSetLang", function(opts)
        config.options.translations.default_lang = opts.args
        vim.notify("Default language set to: " .. opts.args, vim.log.levels.INFO)
    end, { nargs = 1 })
end

-- Fornecer completions para chaves de tradução
function M.get_completions()
    update_language_cache()

    local completions = {}

    -- Usar o idioma padrão ou o primeiro disponível
    local lang = config.options.translations.default_lang or available_langs[1]

    if lang then
        for file_name, langs in pairs(translation_cache) do
            if file_name ~= "_json" and langs[lang] then
                -- Ler o arquivo e extrair chaves
                local file_content = Path:new(langs[lang]):read()
                if file_content then
                    -- Padrão básico para extrair chaves de arrays PHP
                    for key in file_content:gmatch("'([%w_%.]+)'%s*=>") do
                        table.insert(completions, {
                            label = file_name .. "." .. key,
                            kind = vim.lsp.protocol.CompletionItemKind.Value,
                            detail = "Translation (" .. lang .. ")",
                        })
                    end
                end
            end
        end
    end

    return completions
end

return M
