-- Laravel Blade template support
local M = {}



-- Setup Blade file type
local function setup_blade_filetype()
    -- Set up Blade file detection
    vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
        pattern = '*.blade.php',
        callback = function()
            vim.bo.filetype = 'blade'
        end,
    })

    -- Set up syntax for Blade files
    vim.api.nvim_create_autocmd('FileType', {
        pattern = 'blade',
        callback = function()
            -- Set basic PHP-like settings
            vim.bo.commentstring = '{{-- %s --}}'
            vim.bo.comments = 's:{{--,e:--}}'

            -- Set up some basic syntax highlighting
            vim.cmd([[
        syntax clear
        runtime! syntax/html.vim
        runtime! syntax/php.vim

        " Blade directives
        syntax match bladeDirective /@\w\+/
        syntax region bladeEcho start=/{{/ end=/}}/ contains=phpRegion
        syntax region bladeEchoRaw start=/{!!/ end=/!!}/ contains=phpRegion
        syntax region bladeComment start=/{{--/ end=/--}}/

        " Highlight groups
        highlight link bladeDirective Special
        highlight link bladeEcho Identifier
        highlight link bladeEchoRaw Identifier
        highlight link bladeComment Comment
      ]])
        end,
    })
end



-- Setup Blade indentation
local function setup_blade_indentation()
    vim.api.nvim_create_autocmd('FileType', {
        pattern = 'blade',
        callback = function()
            -- Set indentation rules similar to HTML/PHP
            vim.bo.shiftwidth = 4
            vim.bo.tabstop = 4
            vim.bo.softtabstop = 4
            vim.bo.expandtab = true
            vim.bo.autoindent = true
            vim.bo.smartindent = true
        end,
    })
end

-- Find view files
function M.find_views()
    local root = _G.laravel_nvim.project_root
    if not root then return {} end

    local views_path = root .. '/resources/views'
    if vim.fn.isdirectory(views_path) == 0 then
        return {}
    end

    local views = {}
    local function scan_directory(dir, prefix)
        prefix = prefix or ''
        local items = vim.fn.readdir(dir) or {}

        for _, item in ipairs(items) do
            local full_path = dir .. '/' .. item
            local view_name = prefix .. (prefix ~= '' and '.' or '') .. item

            if vim.fn.isdirectory(full_path) == 1 then
                -- Recursively scan subdirectories (results will be added to 'views' directly)
                scan_directory(full_path, view_name)
            elseif item:match('%.blade%.php$') then
                -- Remove .blade.php extension for view name
                view_name = view_name:gsub('%.blade%.php$', '')
                views[#views + 1] = {
                    name = view_name,
                    path = full_path,
                }
            end
        end
    end

    scan_directory(views_path)
    return views
end

-- Get view name from current buffer
function M.get_current_view_name()
    local current_file = vim.fn.expand('%:p')
    local root = _G.laravel_nvim.project_root

    if not root or not current_file:match('%.blade%.php$') then
        return nil
    end

    local views_path = root .. '/resources/views/'
    if not current_file:find(views_path, 1, true) then
        return nil
    end

    -- Extract view name
    local relative_path = current_file:sub(#views_path + 1)
    local view_name = relative_path:gsub('%.blade%.php$', ''):gsub('/', '.')

    return view_name
end

-- Navigate to view
function M.goto_view(view_name)
    if not view_name or view_name == '' then
        -- Show view picker
        local views = M.find_views()
        if #views == 0 then
            vim.notify('No Blade views found', vim.log.levels.WARN)
            return
        end

        local items = {}
        for _, view in ipairs(views) do
            items[#items + 1] = view.name
        end

        require('laravel.ui').select(items, {
            prompt = 'Select view:',
            kind = 'blade_view',
        }, function(choice)
            if choice then
                for _, view in ipairs(views) do
                    if view.name == choice then
                        vim.cmd('edit ' .. view.path)
                        break
                    end
                end
            end
        end)
    else
        -- Convert dot notation to file path
        local root = _G.laravel_nvim.project_root
        if not root then return end

        -- 1. Try Blade view file (traditional Laravel views)
        local view_rel = view_name:gsub('%.', '/')
        local blade_path = root .. '/resources/views/' .. view_rel .. '.blade.php'
        if vim.fn.filereadable(blade_path) == 1 then
            vim.cmd('edit ' .. blade_path)
            return
        end

        -- 1b. Try Livewire Volt pages directory
        local volt_path = root .. '/resources/views/pages/' .. view_rel .. '.blade.php'
        if vim.fn.filereadable(volt_path) == 1 then
            vim.cmd('edit ' .. volt_path)
            return
        end

        -- 1c. Try Livewire components directory
        local livewire_path = root .. '/resources/views/livewire/' .. view_rel .. '.blade.php'
        if vim.fn.filereadable(livewire_path) == 1 then
            vim.cmd('edit ' .. livewire_path)
            return
        end

        -- 2. Try Inertia page component (commonly stored in resources/js/Pages)
        --    Support various frontend stacks (.vue, .svelte, .tsx, .jsx, .ts, .js)
        local inertia_dirs = {
            root .. '/resources/js/Pages/', -- common default (Laravel starter kits)
            root .. '/resources/js/pages/', -- lowercase variant
        }

        local component_paths = {}
        for _, dir in ipairs(inertia_dirs) do
            component_paths[#component_paths + 1] = dir .. view_name:gsub('%.', '/')
        end

        local exts = { '.vue', '.svelte', '.tsx', '.jsx', '.ts', '.js' }
        for _, stub in ipairs(component_paths) do
            for _, ext in ipairs(exts) do
                local candidate = stub .. ext
                if vim.fn.filereadable(candidate) == 1 then
                    vim.cmd('edit ' .. candidate)
                    return
                end
            end
        end

        -- 3. As a fallback, try capitalized path variants (Inertia + React conventions)
        --    E.g., "dashboard" -> "Dashboard.vue" or nested paths "admin/dashboard" -> "Admin/Dashboard.vue"
        local function capitalize_path(path)
            local parts = {}
            for part in path:gmatch('[^/]+') do
                parts[#parts + 1] = part:gsub('^%l', string.upper)
            end
            return table.concat(parts, '/')
        end

        for _, inertia_base in ipairs(inertia_dirs) do
            local capitalized_stub = inertia_base .. capitalize_path(view_name:gsub('%.', '/'))
            for _, ext in ipairs(exts) do
                local candidate = capitalized_stub .. ext
                if vim.fn.filereadable(candidate) == 1 then
                    vim.cmd('edit ' .. candidate)
                    return
                end
            end
        end

        -- No view found - prompt user to create it
        M.prompt_create_view(view_name)
    end
end

-- Prompt user to create a missing view
function M.prompt_create_view(view_name)
    local root = _G.laravel_nvim.project_root
    if not root then return end

    -- Determine the most likely file path and type
    local suggested_paths = M.get_suggested_view_paths(view_name)

    if #suggested_paths == 0 then
        vim.notify('Could not determine where to create view: ' .. view_name, vim.log.levels.ERROR)
        return
    end

    -- If only one suggestion, ask directly
    if #suggested_paths == 1 then
        local path_info = suggested_paths[1]
        vim.ui.input({
            prompt = string.format('Create %s view "%s"? (y/N): ', path_info.type, path_info.display_path),
            default = 'n'
        }, function(input)
            if input and (input:lower() == 'y' or input:lower() == 'yes') then
                M.create_view(path_info.full_path, path_info.type, view_name)
            end
        end)
    else
        -- Multiple suggestions - let user choose
        local items = {}
        for _, path_info in ipairs(suggested_paths) do
            items[#items + 1] = string.format('%s (%s)', path_info.display_path, path_info.type)
        end

        require('laravel.ui').select(items, {
            prompt = 'Create view "' .. view_name .. '" as:',
            kind = 'create_view',
        }, function(choice)
            if choice then
                for i, item in ipairs(items) do
                    if item == choice then
                        local path_info = suggested_paths[i]
                        M.create_view(path_info.full_path, path_info.type, view_name)
                        break
                    end
                end
            end
        end)
    end
end

-- Get suggested paths for creating a view
function M.get_suggested_view_paths(view_name)
    local root = _G.laravel_nvim.project_root
    if not root then return {} end

    local suggestions = {}

    -- 1. Blade template
    local blade_path = root .. '/resources/views/' .. view_name:gsub('%.', '/') .. '.blade.php'
    local blade_display = 'resources/views/' .. view_name:gsub('%.', '/') .. '.blade.php'
    suggestions[#suggestions + 1] = {
        full_path = blade_path,
        display_path = blade_display,
        type = 'Blade'
    }

    -- 2. Inertia components - detect which frontend stack is likely being used
    local frontend_info = M.detect_frontend_stack(root)
    if frontend_info then
        local inertia_path = frontend_info.base_dir .. view_name:gsub('%.', '/') .. frontend_info.extension
        local inertia_display = inertia_path:gsub(root .. '/', '')
        suggestions[#suggestions + 1] = {
            full_path = inertia_path,
            display_path = inertia_display,
            type = frontend_info.type
        }

        -- Also suggest capitalized version for React/Vue conventions
        local function capitalize_path(path)
            local parts = {}
            for part in path:gmatch('[^/]+') do
                parts[#parts + 1] = part:gsub('^%l', string.upper)
            end
            return table.concat(parts, '/')
        end

        local capitalized_path = frontend_info.base_dir ..
            capitalize_path(view_name:gsub('%.', '/')) .. frontend_info.extension
        local capitalized_display = capitalized_path:gsub(root .. '/', '')
        suggestions[#suggestions + 1] = {
            full_path = capitalized_path,
            display_path = capitalized_display,
            type = frontend_info.type .. ' (Capitalized)'
        }
    end

    return suggestions
end

-- Detect the frontend stack being used
function M.detect_frontend_stack(root)
    -- Safely check if vim functions are available
    if not vim or not vim.fn then
        return nil
    end

    -- Check for common frontend directories and package.json
    local package_json = root .. '/package.json'
    if vim.fn.filereadable(package_json) == 1 then
        local content = vim.fn.readfile(package_json)
        local package_str = table.concat(content, '\n')

        -- Check for React/TypeScript
        if package_str:match('"react"') or package_str:match('"@types/react"') then
            if package_str:match('"typescript"') or vim.fn.filereadable(root .. '/tsconfig.json') == 1 then
                return {
                    base_dir = root .. '/resources/js/Pages/',
                    extension = '.tsx',
                    type = 'React TypeScript'
                }
            else
                return {
                    base_dir = root .. '/resources/js/Pages/',
                    extension = '.jsx',
                    type = 'React'
                }
            end
        end

        -- Check for Vue
        if package_str:match('"vue"') then
            return {
                base_dir = root .. '/resources/js/Pages/',
                extension = '.vue',
                type = 'Vue'
            }
        end

        -- Check for Svelte
        if package_str:match('"svelte"') then
            return {
                base_dir = root .. '/resources/js/Pages/',
                extension = '.svelte',
                type = 'Svelte'
            }
        end
    end

    -- Check if Pages directory exists and what files are in it
    local pages_dir = root .. '/resources/js/Pages'
    if vim.fn.isdirectory(pages_dir) == 1 then
        local files = vim.fn.readdir(pages_dir) or {}
        for _, file in ipairs(files) do
            if file:match('%.tsx$') then
                return { base_dir = pages_dir .. '/', extension = '.tsx', type = 'React TypeScript' }
            elseif file:match('%.jsx$') then
                return { base_dir = pages_dir .. '/', extension = '.jsx', type = 'React' }
            elseif file:match('%.vue$') then
                return { base_dir = pages_dir .. '/', extension = '.vue', type = 'Vue' }
            elseif file:match('%.svelte$') then
                return { base_dir = pages_dir .. '/', extension = '.svelte', type = 'Svelte' }
            end
        end
    end

    return nil
end

-- Create a view file
function M.create_view(file_path, view_type, view_name)
    -- Ensure directory exists
    local dir = vim.fn.fnamemodify(file_path, ':h')
    if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, 'p')
    end

    -- Generate appropriate template content
    local content = M.generate_view_template(view_type, view_name)

    -- Write file
    vim.fn.writefile(content, file_path)

    -- Open the file
    vim.cmd('edit ' .. file_path)

    vim.notify('Created ' .. view_type .. ' view: ' .. file_path:gsub(_G.laravel_nvim.project_root .. '/', ''),
        vim.log.levels.INFO)
end

-- Generate template content based on view type
function M.generate_view_template(view_type, view_name)
    -- Return empty content - user prefers to start with blank files
    return {}
end

-- Setup function
function M.setup()
    setup_blade_filetype()
    setup_blade_indentation()
end

return M
