-- Laravel navigation utilities
local M = {}

local ui = require('laravel.ui')

-- Treesitter utilities for Laravel navigation
local ts_utils = {}

-- Check if treesitter is available and get parser
function ts_utils.get_parser()
    -- Try Neovim's built-in treesitter API first (0.9+)
    local ok, parser = pcall(vim.treesitter.get_parser, 0)
    if ok and parser then
        return parser, nil
    end

    -- Fallback: try nvim-treesitter plugin
    local has_ts, ts = pcall(require, 'nvim-treesitter.parsers')
    if not has_ts then
        return nil
    end

    local filetype = vim.bo.filetype
    if not ts.has_parser(filetype) then
        return nil
    end

    parser = ts.get_parser()
    if not parser then
        return nil
    end

    return parser, ts
end

-- Get the treesitter query for Laravel function calls
function ts_utils.get_laravel_query()
    -- Check if we have treesitter query support
    if not vim.treesitter.query or not vim.treesitter.query.parse then
        return nil
    end

    local query_string = [[
        ; Simple function calls - match any function with string arguments
        (function_call_expression
          (name) @function_name
          (arguments
            (argument
              (string) @string_arg
            )
          )
        ) @function_call

        ; Function calls with multiple arguments - capture all strings
        (function_call_expression
          (name) @function_name
          (arguments
            (argument
              (string) @string_arg
            )
            (argument
              (string) @string_arg_2
            )+
          )
        ) @function_call_multi

        ; Static method calls (Class::method)
        (scoped_call_expression
          (name) @scope_name
          (name) @method_name
          (arguments
            (argument
              (string) @string_arg
            )
          )
        ) @method_call

        ; Static method calls with multiple arguments
        (scoped_call_expression
          (name) @scope_name
          (name) @method_name
          (arguments
            (argument
              (string) @string_arg
            )
            (argument
              (string) @string_arg_2
            )+
          )
        ) @method_call_multi

        ; Member/method calls
        (member_call_expression
          (name) @method_name
          (arguments
            (argument
              (string) @string_arg
            )
          )
        ) @member_call

        ; Capture any string with content
        (string
          (string_content) @string_content
        ) @string_node
    ]]

    local ok, query = pcall(vim.treesitter.query.parse, 'php', query_string)
    if not ok then
        -- Try to create a minimal working query to test basic functionality
        local minimal_ok, minimal_query = pcall(vim.treesitter.query.parse, 'php', '(name) @any_name')
        if minimal_ok then
            return minimal_query
        end
        return nil
    end
    return query
end

-- Extract Laravel function call information using direct AST traversal (no queries)
function ts_utils.get_laravel_call_at_cursor()
    local parser, ts = ts_utils.get_parser()
    if not parser then
        return nil
    end

    local ok, tree = pcall(function()
        return parser:parse()[1]
    end)
    if not ok or not tree then
        return nil
    end

    local root = tree:root()
    if not root then
        return nil
    end

    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
    cursor_row = cursor_row - 1 -- Convert to 0-based

    -- Find the node at cursor position and traverse up to find Laravel function calls
    local cursor_node = root:descendant_for_range(cursor_row, cursor_col, cursor_row, cursor_col)
    if not cursor_node then
        return nil
    end

    -- First strategy: Look for the most specific Laravel call that contains the cursor
    local best_call_info = nil
    local best_distance = math.huge

    -- Traverse up the tree to find function calls that contain the cursor
    local current_node = cursor_node
    local search_depth = 0

    while current_node and search_depth < 10 do
        local call_info = ts_utils.extract_laravel_call_from_node(current_node)
        if call_info then
            -- Check if this call actually contains the cursor position
            if ts_utils.node_contains_cursor(current_node, cursor_row, cursor_col) then
                -- Calculate how close this node is to the cursor (smaller nodes = closer)
                local ok_range, start_row, start_col, end_row, end_col = pcall(function()
                    return current_node:range()
                end)

                if ok_range then
                    local node_size = (end_row - start_row) * 1000 + (end_col - start_col)
                    -- Prefer smaller nodes (more specific) and closer to cursor
                    local distance = node_size + search_depth

                    if distance < best_distance then
                        best_distance = distance
                        best_call_info = call_info
                    end
                end
            end
        end

        current_node = current_node:parent()
        search_depth = search_depth + 1
    end

    -- Return the most specific Laravel call that contains the cursor
    if best_call_info then
        return best_call_info
    end

    -- Fallback: Search current line only if no containing call found
    local line_node = root:descendant_for_range(cursor_row, 0, cursor_row, 1000)
    if line_node then
        return ts_utils.search_laravel_calls_in_node_with_cursor_check(line_node, cursor_row, cursor_col)
    end

    return nil
end

-- Extract Laravel call info from a single node using direct AST traversal
function ts_utils.extract_laravel_call_from_node(node)
    if not node then
        return nil
    end

    -- Check if this is a function call expression
    if node:type() == 'function_call_expression' then
        return ts_utils.parse_function_call_node(node)
    end

    -- Check if this is a scoped call expression (Class::method)
    if node:type() == 'scoped_call_expression' then
        return ts_utils.parse_scoped_call_node(node)
    end

    -- Check if this is a member call expression ($obj->method)
    if node:type() == 'member_call_expression' then
        return ts_utils.parse_member_call_node(node)
    end

    -- Check if this is a controller class reference (ControllerName::class)
    if node:type() == 'class_constant_access_expression' then
        return ts_utils.parse_controller_class_node(node)
    end

    -- Check if this is just a name node that might be a controller
    if node:type() == 'name' then
        return ts_utils.parse_controller_name_node(node)
    end

    return nil
end

-- Search for Laravel function calls within a node
function ts_utils.search_laravel_calls_in_node(node)
    if not node then
        return nil
    end

    -- First check the node itself
    local call_info = ts_utils.extract_laravel_call_from_node(node)
    if call_info then
        return call_info
    end

    -- Recursively search children
    for i = 0, node:child_count() - 1 do
        local child = node:child(i)
        if child then
            local child_call_info = ts_utils.search_laravel_calls_in_node(child)
            if child_call_info then
                return child_call_info
            end
        end
    end

    return nil
end

-- Search for Laravel function calls within a node, prioritizing ones that contain the cursor
function ts_utils.search_laravel_calls_in_node_with_cursor_check(node, cursor_row, cursor_col)
    if not node then
        return nil
    end

    local best_call_info = nil
    local best_distance = math.huge

    -- Recursively search all Laravel calls in this node and its children
    local function find_all_calls(search_node, depth)
        if depth > 10 then
            return
        end

        local call_info = ts_utils.extract_laravel_call_from_node(search_node)
        if call_info then
            -- Check if this call contains the cursor
            if ts_utils.node_contains_cursor(search_node, cursor_row, cursor_col) then
                local ok_range, start_row, start_col, end_row, end_col = pcall(function()
                    return search_node:range()
                end)

                if ok_range then
                    local node_size = (end_row - start_row) * 1000 + (end_col - start_col)
                    local distance = node_size + depth

                    if distance < best_distance then
                        best_distance = distance
                        best_call_info = call_info
                    end
                end
            end
        end

        -- Recursively search children
        for i = 0, search_node:child_count() - 1 do
            local child = search_node:child(i)
            if child then
                find_all_calls(child, depth + 1)
            end
        end
    end

    find_all_calls(node, 0)
    return best_call_info
end

-- Parse a function_call_expression node (e.g., config('app.name'))
function ts_utils.parse_function_call_node(node)
    if node:child_count() < 2 then
        return nil
    end

    -- Child[0] should be the function name
    local name_node = node:child(0)
    if not name_node or name_node:type() ~= 'name' then
        return nil
    end

    local ok_name, function_name = pcall(vim.treesitter.get_node_text, name_node, 0)
    if not ok_name or not function_name then
        return nil
    end

    -- Child[1] should be the arguments
    local args_node = node:child(1)
    if not args_node or args_node:type() ~= 'arguments' then
        return nil
    end

    local string_args = ts_utils.extract_string_arguments(args_node)
    if #string_args == 0 then
        return nil
    end

    return ts_utils.create_laravel_call_info(function_name, nil, nil, string_args, 'function')
end

-- Parse a scoped_call_expression node (e.g., Route::get())
function ts_utils.parse_scoped_call_node(node)
    if node:child_count() < 3 then
        return nil
    end

    -- Find scope name and method name
    local scope_name = nil
    local method_name = nil
    local args_node = nil

    for i = 0, node:child_count() - 1 do
        local child = node:child(i)
        if child then
            if child:type() == 'name' then
                if not scope_name then
                    scope_name = ts_utils.get_node_text_safe(child)
                elseif not method_name then
                    method_name = ts_utils.get_node_text_safe(child)
                end
            elseif child:type() == 'arguments' then
                args_node = child
            end
        end
    end

    if not scope_name or not method_name or not args_node then
        return nil
    end

    local string_args = ts_utils.extract_string_arguments(args_node)
    if #string_args == 0 then
        return nil
    end

    return ts_utils.create_laravel_call_info(method_name, scope_name, method_name, string_args, 'scoped')
end

-- Parse a member_call_expression node (e.g., $route->name())
function ts_utils.parse_member_call_node(node)
    if node:child_count() < 3 then
        return nil
    end

    -- Find method name and arguments
    local method_name = nil
    local args_node = nil

    for i = 0, node:child_count() - 1 do
        local child = node:child(i)
        if child then
            if child:type() == 'name' then
                method_name = ts_utils.get_node_text_safe(child)
            elseif child:type() == 'arguments' then
                args_node = child
            end
        end
    end

    if not method_name or not args_node then
        return nil
    end

    local string_args = ts_utils.extract_string_arguments(args_node)
    if #string_args == 0 then
        return nil
    end

    return ts_utils.create_laravel_call_info(method_name, nil, method_name, string_args, 'method')
end

-- Parse a controller class reference (e.g., CompanyProfileController::class)
function ts_utils.parse_controller_class_node(node)
    if node:child_count() < 2 then
        return nil
    end

    -- Look for ControllerName::class pattern
    local class_name = nil
    local constant_name = nil

    for i = 0, node:child_count() - 1 do
        local child = node:child(i)
        if child and child:type() == 'name' then
            if not class_name then
                class_name = ts_utils.get_node_text_safe(child)
            else
                constant_name = ts_utils.get_node_text_safe(child)
            end
        end
    end

    -- Check if this is a Controller::class pattern
    if class_name and constant_name == 'class' and class_name:match('Controller$') then
        return {
            func = 'controller',
            partial = class_name,
            call_type = 'class_reference',
            function_name = nil,
            scope_name = class_name,
            method_name = nil,
            all_args = { class_name }
        }
    end

    return nil
end

-- Parse a controller name node (e.g., just "CompanyProfileController")
function ts_utils.parse_controller_name_node(node)
    local name = ts_utils.get_node_text_safe(node)

    -- Check if this looks like a controller name
    if name and name:match('Controller$') then
        -- Verify it's in a route context by checking parent nodes
        local parent = node:parent()
        local depth = 0
        while parent and depth < 5 do
            local parent_text = ts_utils.get_node_text_safe(parent)
            if parent_text and parent_text:match('Route::') then
                return {
                    func = 'controller',
                    partial = name,
                    call_type = 'controller_name',
                    function_name = nil,
                    scope_name = name,
                    method_name = nil,
                    all_args = { name }
                }
            end
            parent = parent:parent()
            depth = depth + 1
        end
    end

    return nil
end

-- Extract string arguments from an arguments node
function ts_utils.extract_string_arguments(args_node)
    local string_args = {}

    for i = 0, args_node:child_count() - 1 do
        local child = args_node:child(i)
        if child and child:type() == 'argument' then
            -- Look for string inside argument
            for j = 0, child:child_count() - 1 do
                local arg_child = child:child(j)
                if arg_child and arg_child:type() == 'string' then
                    -- Extract string content
                    local string_content = ts_utils.extract_string_content(arg_child)
                    if string_content then
                        table.insert(string_args, string_content)
                    end
                    break
                end
            end
        end
    end

    return string_args
end

-- Extract string content from a string node
function ts_utils.extract_string_content(string_node)
    for i = 0, string_node:child_count() - 1 do
        local child = string_node:child(i)
        if child and child:type() == 'string_content' then
            return ts_utils.get_node_text_safe(child)
        end
    end

    -- Fallback: get the full string and remove quotes
    local full_text = ts_utils.get_node_text_safe(string_node)
    if full_text then
        -- Remove surrounding quotes
        local clean_text = full_text:match('^[\'"](.*)[\'"]$')
        return clean_text or full_text
    end

    return nil
end

-- Safely get node text
function ts_utils.get_node_text_safe(node)
    if not node then
        return nil
    end

    local ok, text = pcall(vim.treesitter.get_node_text, node, 0)
    return ok and text or nil
end

-- Create Laravel call info from parsed components
function ts_utils.create_laravel_call_info(function_name, scope_name, method_name, string_args, call_type)
    if not function_name or #string_args == 0 then
        return nil
    end

    -- Map Laravel functions to navigation types
    local laravel_functions = {
        -- Navigation helpers
        route = 'route',
        view = 'view',
        config = 'config',
        __ = 'trans',
        trans = 'trans',
        env = 'env',

        -- Asset helpers
        asset = 'asset',
        secure_asset = 'asset',
        mix = 'asset',

        -- URL helpers
        action = 'route',
        to_route = 'route',
        url = 'url',
        secure_url = 'url',

        -- Path helpers
        app_path = 'path',
        base_path = 'path',
        config_path = 'path',
        database_path = 'path',
        lang_path = 'path',
        public_path = 'path',
        resource_path = 'path',
        storage_path = 'path',

        -- Inertia
        inertia = 'view',

        -- Other Laravel helpers
        policy = 'policy',
        broadcast = 'broadcast',
        event = 'event',
        collect = 'collect',
        cache = 'cache',
        session = 'session',
        request = 'request',
        response = 'response',
        redirect = 'redirect',
        back = 'redirect',
        abort = 'abort',
        logger = 'logger',

        -- Method calls
        name = 'route_name', -- for ->name() calls
        render = 'view',     -- for Inertia::render()
        middleware = 'middleware',
        where = 'route_constraint',
    }

    -- Scoped calls where the second string arg is a view/component name
    local scoped_view_methods = {
        ['route:inertia'] = true,
        ['route:view'] = true,
        ['volt:route'] = true,
    }

    local func_type = nil
    local target_string = nil

    -- Handle function calls
    if call_type == 'function' then
        func_type = laravel_functions[function_name]
        target_string = string_args[1]

        -- Handle scoped/static method calls
    elseif call_type == 'scoped' and scope_name and method_name then
        local scope_lower = scope_name:lower()
        local method_lower = method_name:lower()
        local scoped_key = scope_lower .. ':' .. method_lower

        -- Scoped calls where second arg is a view name
        if scoped_view_methods[scoped_key] and #string_args >= 2 then
            func_type = 'view'
            target_string = string_args[2]

            -- Route static methods
        elseif scope_lower == 'route' then
            if method_lower == 'controller' and #string_args >= 1 then
                -- Route::controller(SomeController::class) - navigate to controller
                func_type = 'controller'
                target_string = string_args[1]
            elseif method_lower:match('^(get|post|put|patch|delete|options|head|any|match|redirect|resource|apiresource)$') then
                -- Check if second arg is a controller method name (used in Route::controller() groups)
                -- Method names are lowercase identifiers without dots or slashes
                if #string_args >= 2 and string_args[2]:match('^[%l_][%w_]*$') then
                    func_type = 'controller_method'
                    target_string = string_args[2]
                else
                    func_type = 'route'
                    target_string = string_args[1] -- First argument is usually the URI
                end
            end

            -- Inertia static methods
        elseif scope_lower == 'inertia' and method_lower == 'render' then
            func_type = 'view'
            target_string = string_args[1]

            -- Config facade
        elseif scope_lower == 'config' and method_lower == 'get' then
            func_type = 'config'
            target_string = string_args[1]

            -- View facade
        elseif scope_lower == 'view' and method_lower == 'make' then
            func_type = 'view'
            target_string = string_args[1]

            -- Other facades
        elseif laravel_functions[method_lower] then
            func_type = laravel_functions[method_lower]
            target_string = string_args[1]
        end

        -- Handle method calls (instance or chained)
    elseif call_type == 'method' and method_name then
        local method_lower = method_name:lower()

        if method_lower == 'name' then
            func_type = 'route_name'
            target_string = string_args[1]
        elseif method_lower == 'view' then
            func_type = 'view'
            target_string = string_args[1]
        elseif laravel_functions[method_lower] then
            func_type = laravel_functions[method_lower]
            target_string = string_args[1]
        end
    end

    if func_type and target_string then
        return {
            func = func_type,
            partial = target_string,
            call_type = call_type,
            function_name = function_name,
            scope_name = scope_name,
            method_name = method_name,
            all_args = string_args
        }
    end

    return nil
end

-- Find the controller class from a Route::controller() group by walking up the AST
function ts_utils.find_controller_from_group(node)
    if not node then
        return nil
    end

    local current = node:parent()
    local depth = 0

    while current and depth < 20 do
        -- Look for member_call_expression or scoped_call_expression containing "controller"
        local node_text = ts_utils.get_node_text_safe(current)
        if node_text then
            -- Check for Route::controller(SomeController::class) pattern
            local controller = node_text:match('Route%s*::%s*controller%s*%(([%w_]+)%s*::%s*class%)')
            if controller then
                return controller
            end
            -- Also check for ->controller(SomeController::class) chained pattern
            controller = node_text:match('->%s*controller%s*%(([%w_]+)%s*::%s*class%)')
            if controller then
                return controller
            end
        end

        current = current:parent()
        depth = depth + 1
    end

    return nil
end

-- Check if a node contains the cursor position
function ts_utils.node_contains_cursor(node, cursor_row, cursor_col)
    if not node then
        return false
    end

    local ok, start_row, start_col, end_row, end_col = pcall(function()
        return node:range()
    end)

    if not ok then
        return false
    end

    return cursor_row >= start_row and cursor_row <= end_row and
        (cursor_row > start_row or cursor_col >= start_col) and
        (cursor_row < end_row or cursor_col <= end_col)
end

-- Debug version of extract_call_info that shows step-by-step process
function ts_utils.extract_call_info_debug(match, query)
    local debug_steps = {}
    local function_name = nil
    local scope_name = nil
    local method_name = nil
    local string_args = {}
    local call_type = nil

    table.insert(debug_steps, 'Extract Call Info Debug:')
    table.insert(debug_steps, '========================')

    for id, node in pairs(match) do
        if node == nil then
            table.insert(debug_steps, 'Skipping nil node')
            goto continue
        end

        local capture_name = query.captures[id]
        if not capture_name then
            table.insert(debug_steps, 'No capture name for node')
            goto continue
        end

        local ok, text = pcall(vim.treesitter.get_node_text, node, 0)
        if not ok or not text then
            table.insert(debug_steps, 'Failed to get text for capture: ' .. capture_name)
            goto continue
        end

        table.insert(debug_steps, 'Processing: ' .. capture_name .. ' = "' .. text .. '"')

        if capture_name == 'function_name' then
            function_name = text
            call_type = 'function'
            table.insert(debug_steps, '  → Set function_name = ' .. text)
        elseif capture_name == 'scope_name' then
            scope_name = text
            call_type = 'scoped'
            table.insert(debug_steps, '  → Set scope_name = ' .. text)
        elseif capture_name == 'method_name' then
            method_name = text
            if call_type ~= 'scoped' then
                call_type = 'method'
            end
            table.insert(debug_steps, '  → Set method_name = ' .. text)
        elseif capture_name == 'string_arg' or capture_name == 'string_arg_2' then
            local clean_string = text
            clean_string = clean_string:match('^[\'"](.*)[\'"]$') or clean_string
            clean_string = clean_string:match('^"(.*)"$') or clean_string
            clean_string = clean_string:match("^'(.*)'$") or clean_string
            table.insert(string_args, clean_string)
            table.insert(debug_steps, '  → Added string arg: "' .. clean_string .. '"')
        elseif capture_name == 'string_content' then
            table.insert(string_args, text)
            table.insert(debug_steps, '  → Added string content: "' .. text .. '"')
        end

        ::continue::
    end

    table.insert(debug_steps, '')
    table.insert(debug_steps, 'Results:')
    table.insert(debug_steps, '--------')
    table.insert(debug_steps, 'call_type: ' .. (call_type or 'nil'))
    table.insert(debug_steps, 'function_name: ' .. (function_name or 'nil'))
    table.insert(debug_steps, 'scope_name: ' .. (scope_name or 'nil'))
    table.insert(debug_steps, 'method_name: ' .. (method_name or 'nil'))
    table.insert(debug_steps, 'string_args: ' .. table.concat(string_args, ', '))

    return debug_steps, {
        call_type = call_type,
        function_name = function_name,
        scope_name = scope_name,
        method_name = method_name,
        string_args = string_args
    }
end

-- Extract call information from treesitter match
function ts_utils.extract_call_info(match, query)
    local function_name = nil
    local scope_name = nil
    local method_name = nil
    local string_args = {}
    local call_type = nil

    for id, node in pairs(match) do
        -- Skip nil nodes
        if node == nil then
            goto continue
        end

        local capture_name = query.captures[id]
        if not capture_name then
            goto continue
        end

        -- Safely get node text
        local ok, text = pcall(vim.treesitter.get_node_text, node, 0)
        if not ok or not text then
            goto continue
        end

        if capture_name == 'function_name' then
            function_name = text
            call_type = 'function'
        elseif capture_name == 'scope_name' then
            scope_name = text
            call_type = 'scoped'
        elseif capture_name == 'method_name' then
            method_name = text
            if call_type ~= 'scoped' then
                call_type = 'method'
            end
        elseif capture_name == 'string_arg' or capture_name == 'string_arg_2' then
            -- Remove quotes from string (handle both single and double quotes)
            local clean_string = text
            -- Remove outer quotes if present
            clean_string = clean_string:match('^[\'"](.*)[\'"]$') or clean_string
            -- Handle double quotes with potential escape sequences
            clean_string = clean_string:match('^"(.*)"$') or clean_string
            -- Handle single quotes
            clean_string = clean_string:match("^'(.*)'$") or clean_string

            table.insert(string_args, clean_string)
        elseif capture_name == 'string_content' then
            -- Direct string content without quotes (PHP grammar structure)
            table.insert(string_args, text)
        end

        ::continue::
    end

    -- Determine the Laravel function type and return structured info
    local laravel_functions = {
        -- Navigation helpers
        route = 'route',
        view = 'view',
        config = 'config',
        __ = 'trans',
        trans = 'trans',
        env = 'env',

        -- Asset helpers
        asset = 'asset',
        secure_asset = 'asset',
        mix = 'asset',

        -- URL helpers
        action = 'route',
        to_route = 'route',
        url = 'url',
        secure_url = 'url',

        -- Path helpers
        app_path = 'path',
        base_path = 'path',
        config_path = 'path',
        database_path = 'path',
        lang_path = 'path',
        public_path = 'path',
        resource_path = 'path',
        storage_path = 'path',

        -- Inertia
        inertia = 'view',

        -- Other Laravel helpers
        policy = 'policy',
        broadcast = 'broadcast',
        event = 'event',
        collect = 'collect',
        cache = 'cache',
        session = 'session',
        request = 'request',
        response = 'response',
        redirect = 'redirect',
        back = 'redirect',
        abort = 'abort',
        logger = 'logger',

        -- Method calls
        name = 'route_name', -- for ->name() calls
        render = 'view',     -- for Inertia::render()
        middleware = 'middleware',
        where = 'route_constraint',
    }

    local func_type = nil
    local target_string = nil

    -- Scoped calls where the second string arg is a view/component name
    local scoped_view_methods = {
        ['route:inertia'] = true,
        ['route:view'] = true,
        ['volt:route'] = true,
    }

    -- Handle function calls
    if call_type == 'function' and function_name then
        func_type = laravel_functions[function_name]
        target_string = string_args[1]

        -- Handle scoped/static method calls
    elseif call_type == 'scoped' and scope_name and method_name then
        local scope_lower = scope_name:lower()
        local method_lower = method_name:lower()
        local scoped_key = scope_lower .. ':' .. method_lower

        -- Scoped calls where second arg is a view name
        if scoped_view_methods[scoped_key] and #string_args >= 2 then
            func_type = 'view'
            target_string = string_args[2]

            -- Route static methods
        elseif scope_lower == 'route' then
            if method_lower == 'controller' and #string_args >= 1 then
                func_type = 'controller'
                target_string = string_args[1]
            elseif method_lower:match('^(get|post|put|patch|delete|options|head|any|match|redirect|resource|apiresource)$') then
                if #string_args >= 2 and string_args[2]:match('^[%l_][%w_]*$') then
                    func_type = 'controller_method'
                    target_string = string_args[2]
                else
                    func_type = 'route'
                    target_string = string_args[1]
                end
            end

            -- Inertia static methods
        elseif scope_lower == 'inertia' and method_lower == 'render' then
            func_type = 'view'
            target_string = string_args[1]

            -- Config facade
        elseif scope_lower == 'config' and method_lower == 'get' then
            func_type = 'config'
            target_string = string_args[1]

            -- View facade
        elseif scope_lower == 'view' and method_lower == 'make' then
            func_type = 'view'
            target_string = string_args[1]

            -- Other facades
        elseif laravel_functions[method_lower] then
            func_type = laravel_functions[method_lower]
            target_string = string_args[1]
        end

        -- Handle method calls (instance or chained)
    elseif call_type == 'method' and method_name then
        local method_lower = method_name:lower()

        if method_lower == 'name' then
            func_type = 'route_name'
            target_string = string_args[1]
        elseif method_lower == 'view' then
            func_type = 'view'
            target_string = string_args[1]
        elseif laravel_functions[method_lower] then
            func_type = laravel_functions[method_lower]
            target_string = string_args[1]
        end
    end

    if func_type and target_string then
        return {
            func = func_type,
            partial = target_string,
            call_type = call_type,
            function_name = function_name,
            scope_name = scope_name,
            method_name = method_name,
            all_args = string_args
        }
    end

    -- Debug: If we couldn't extract info, at least log what we found
    -- This helps debug why extraction is failing
    if call_type and (function_name or method_name) and #string_args > 0 then
        -- We found something but it wasn't recognized as a Laravel function
        -- This could help identify missing patterns
    end

    return nil
end

-- Direct AST-based Laravel context detection
function ts_utils.is_laravel_context_ts()
    local ok, call_info = pcall(ts_utils.get_laravel_call_at_cursor)
    if not ok then
        return false
    end
    return call_info ~= nil
end

-- Enhanced Laravel string navigation using treesitter
function ts_utils.goto_laravel_string_ts()
    local ok, call_info = pcall(ts_utils.get_laravel_call_at_cursor)
    if not ok or not call_info then
        return false
    end

    -- Navigate based on the detected context
    if call_info.func == 'route' or call_info.func == 'route_name' then
        M.goto_route_definition(call_info.partial)
    elseif call_info.func == 'view' then
        M.goto_view(call_info.partial)
    elseif call_info.func == 'config' then
        M.goto_config(call_info.partial)
    elseif call_info.func == 'trans' then
        M.goto_translation(call_info.partial)
    elseif call_info.func == 'env' then
        M.goto_env(call_info.partial)
    elseif call_info.func == 'asset' then
        M.goto_asset(call_info.partial)
    elseif call_info.func == 'controller' then
        M.goto_controller(call_info.partial)
    elseif call_info.func == 'controller_method' then
        M.goto_controller_method(call_info.partial)
    elseif call_info.func == 'path' then
        -- Handle Laravel path helpers - could navigate to directories
        return false -- Not implemented yet
    elseif call_info.func == 'url' then
        -- Handle URL helpers - could show URL info
        return false -- Not implemented yet
    elseif call_info.func == 'policy' then
        -- Could navigate to policy files
        M.goto_policy(call_info.partial)
    elseif call_info.func == 'middleware' then
        -- Could navigate to middleware files
        M.goto_middleware(call_info.partial)
    elseif call_info.func == 'event' then
        -- Could navigate to event files
        M.goto_event(call_info.partial)
    else
        -- Unknown Laravel function
        return false
    end

    return true
end

-- Navigate to policy file
function M.goto_policy(policy_name)
    if not policy_name or policy_name == '' then
        ui.warn('No policy name provided')
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    local policy_path = root .. '/app/Policies/' .. policy_name .. 'Policy.php'
    if vim.fn.filereadable(policy_path) == 1 then
        vim.cmd('edit ' .. policy_path)
    else
        ui.warn('Policy file not found: ' .. policy_name .. 'Policy.php')
    end
end

-- Navigate to middleware file
function M.goto_middleware(middleware_name)
    if not middleware_name or middleware_name == '' then
        ui.warn('No middleware name provided')
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    local middleware_path = root .. '/app/Http/Middleware/' .. middleware_name .. '.php'
    if vim.fn.filereadable(middleware_path) == 1 then
        vim.cmd('edit ' .. middleware_path)
    else
        ui.warn('Middleware file not found: ' .. middleware_name .. '.php')
    end
end

-- Navigate to event file
function M.goto_event(event_name)
    if not event_name or event_name == '' then
        ui.warn('No event name provided')
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    local event_path = root .. '/app/Events/' .. event_name .. '.php'
    if vim.fn.filereadable(event_path) == 1 then
        vim.cmd('edit ' .. event_path)
    else
        ui.warn('Event file not found: ' .. event_name .. '.php')
    end
end

-- Get Laravel project root
local function get_project_root()
    return _G.laravel_nvim.project_root
end

-- Find controllers
function M.find_controllers()
    local root = get_project_root()
    if not root then return {} end

    local controllers_path = root .. '/app/Http/Controllers'
    if vim.fn.isdirectory(controllers_path) == 0 then
        return {}
    end

    local controllers = {}
    local function scan_directory(dir, namespace)
        namespace = namespace or 'App\\Http\\Controllers'

        -- Check if directory exists
        if vim.fn.isdirectory(dir) ~= 1 then
            return
        end

        local items = vim.fn.readdir(dir)
        if not items then
            return
        end

        for _, item in ipairs(items) do
            local full_path = dir .. '/' .. item

            if vim.fn.isdirectory(full_path) == 1 then
                -- Recursively scan subdirectories
                scan_directory(full_path, namespace .. '\\' .. item)
            elseif item:match('%.php$') and item:match('Controller%.php$') then
                local class_name = item:gsub('%.php$', '')
                controllers[#controllers + 1] = {
                    name = class_name,
                    namespace = namespace .. '\\' .. class_name,
                    path = full_path,
                }
            end
        end
    end

    scan_directory(controllers_path)
    return controllers
end

-- Find models
function M.find_models()
    local root = get_project_root()
    if not root then return {} end

    local models_path = root .. '/app/Models'
    local app_path = root .. '/app'

    local models = {}
    local seen_names = {} -- Track seen model names to prevent duplicates

    local function scan_directory(dir, namespace, is_models_dir)
        namespace = namespace or 'App'

        -- Check if directory exists
        if vim.fn.isdirectory(dir) ~= 1 then
            return
        end

        local items = vim.fn.readdir(dir)
        if not items then
            return
        end

        for _, item in ipairs(items) do
            local full_path = dir .. '/' .. item

            if vim.fn.isdirectory(full_path) == 1 then
                if item == 'Models' then
                    -- Scan Models directory
                    scan_directory(full_path, namespace .. '\\Models', true)
                elseif not item:match('^[A-Z]') and not is_models_dir then
                    -- Skip non-capitalized directories in app root (like Http, Console, etc.)
                    -- unless we're already in Models directory
                else
                    -- Recursively scan subdirectories
                    scan_directory(full_path, namespace .. '\\' .. item, is_models_dir)
                end
            elseif item:match('%.php$') then
                local class_name = item:gsub('%.php$', '')

                -- Skip if we've already seen this model name
                if seen_names[class_name] then
                    goto continue
                end

                -- Check if this looks like a model
                local is_model = false
                if is_models_dir then
                    is_model = true
                elseif dir == app_path then
                    -- Check if it's a model in the app root (Laravel < 8 style)
                    local content = vim.fn.readfile(full_path, '', 10) -- Read first 10 lines
                    for _, line in ipairs(content) do
                        if line:match('extends.*Model') or line:match('use.*Model') then
                            is_model = true
                            break
                        end
                    end
                end

                if is_model then
                    seen_names[class_name] = true
                    models[#models + 1] = {
                        name = class_name,
                        namespace = namespace .. '\\' .. class_name,
                        path = full_path,
                    }
                end

                ::continue::
            end
        end
    end

    -- First scan Models directory (Laravel 8+) - prioritize this
    if vim.fn.isdirectory(models_path) == 1 then
        scan_directory(models_path, 'App\\Models', true)
    end

    -- Only scan app root for models (Laravel < 8) if Models directory doesn't exist
    if vim.fn.isdirectory(models_path) == 0 then
        scan_directory(app_path, 'App', false)
    end

    return models
end

-- Navigate to controller
function M.goto_controller(controller_name)
    if not controller_name or controller_name == '' then
        -- Show controller picker
        local controllers = M.find_controllers()
        if #controllers == 0 then
            ui.warn('No controllers found')
            return
        end

        local items = {}
        for _, controller in ipairs(controllers) do
            items[#items + 1] = controller.name
        end

        ui.select(items, {
            prompt = 'Select controller:',
            kind = 'laravel_controller',
        }, function(choice)
            if choice then
                for _, controller in ipairs(controllers) do
                    if controller.name == choice then
                        vim.cmd('edit ' .. controller.path)
                        break
                    end
                end
            end
        end)
    else
        -- Find specific controller
        local controllers = M.find_controllers()
        local found_controller = nil

        for _, controller in ipairs(controllers) do
            if controller.name:lower():match(controller_name:lower()) then
                found_controller = controller
                break
            end
        end

        if found_controller then
            vim.cmd('edit ' .. found_controller.path)
        else
            ui.error('Controller not found: ' .. controller_name)
        end
    end
end

-- Navigate to controller method (used in Route::controller() groups)
-- Finds the controller from the route group context and jumps to the method
function M.goto_controller_method(method_name)
    if not method_name or method_name == '' then
        ui.warn('No method name provided')
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    -- Try to find the controller from the surrounding Route::controller() call
    -- by scanning the current buffer upward from cursor position
    local controller_name = nil
    local current_line = vim.fn.line('.')
    local lines = vim.api.nvim_buf_get_lines(0, 0, current_line, false)

    -- Search backward for Route::controller(SomeController::class)
    for i = #lines, 1, -1 do
        local match = lines[i]:match('Route%s*::%s*controller%s*%(([%w_\\]+)%s*::%s*class%)')
        if match then
            -- Extract just the class name (without namespace)
            controller_name = match:match('([%w_]+)$')
            break
        end
        -- Also check for ->controller(SomeController::class) chained pattern
        match = lines[i]:match('->%s*controller%s*%(([%w_\\]+)%s*::%s*class%)')
        if match then
            controller_name = match:match('([%w_]+)$')
            break
        end
    end

    if not controller_name then
        -- Fallback: try treesitter to find controller in parent scope
        local parser_ok, _ = pcall(ts_utils.get_parser)
        if parser_ok then
            local ok, tree = pcall(function()
                local parser = ts_utils.get_parser()
                return parser and parser:parse()[1]
            end)
            if ok and tree then
                local tree_root = tree:root()
                local cursor_row = vim.fn.line('.') - 1
                local cursor_col = vim.fn.col('.') - 1
                local cursor_node = tree_root:descendant_for_range(cursor_row, cursor_col, cursor_row, cursor_col)
                if cursor_node then
                    controller_name = ts_utils.find_controller_from_group(cursor_node)
                end
            end
        end
    end

    if not controller_name then
        ui.warn('Could not find controller for method: ' .. method_name .. '. Not inside a Route::controller() group?')
        return
    end

    -- Find the controller file
    local controllers = M.find_controllers()
    local found_controller = nil

    for _, controller in ipairs(controllers) do
        if controller.name == controller_name or controller.name:lower() == controller_name:lower() then
            found_controller = controller
            break
        end
    end

    if not found_controller then
        ui.error('Controller not found: ' .. controller_name)
        return
    end

    -- Open controller file and navigate to the method
    vim.cmd('edit ' .. found_controller.path)

    -- Search for the method definition
    local method_pattern = 'function%s+' .. vim.pesc(method_name) .. '%s*%('
    local search_result = vim.fn.search(method_pattern, 'w')
    if search_result > 0 then
        vim.cmd('normal! zz')
    else
        ui.warn('Method "' .. method_name .. '" not found in ' .. controller_name)
    end
end

-- Navigate to model
function M.goto_model(model_name)
    if not model_name or model_name == '' then
        -- Show model picker
        local models = M.find_models()
        if #models == 0 then
            ui.warn('No models found')
            return
        end

        local items = {}
        for _, model in ipairs(models) do
            items[#items + 1] = model.name
        end

        ui.select(items, {
            prompt = 'Select model:',
            kind = 'laravel_model',
        }, function(choice)
            if choice then
                for _, model in ipairs(models) do
                    if model.name == choice then
                        vim.cmd('edit ' .. model.path)
                        break
                    end
                end
            end
        end)
    else
        -- Find specific model
        local models = M.find_models()
        local found_model = nil

        for _, model in ipairs(models) do
            if model.name:lower():match(model_name:lower()) then
                found_model = model
                break
            end
        end

        if found_model then
            vim.cmd('edit ' .. found_model.path)
        else
            ui.error('Model not found: ' .. model_name)
        end
    end
end

-- Navigate to view
function M.goto_view(view_name)
    require('laravel.blade').goto_view(view_name)
end

-- Find route files
function M.find_route_files()
    local root = get_project_root()
    if not root then
        return {}
    end

    local routes_dir = root .. '/routes'
    if vim.fn.isdirectory(routes_dir) == 0 then
        return {}
    end

    local route_files = {}
    local files = vim.fn.glob(routes_dir .. '/*.php', false, true)

    for _, file in ipairs(files) do
        local name = vim.fn.fnamemodify(file, ':t:r') -- filename without extension
        table.insert(route_files, {
            name = name,
            path = file,
            relative_path = 'routes/' .. name .. '.php'
        })
    end

    -- Sort by name
    table.sort(route_files, function(a, b)
        return a.name < b.name
    end)

    return route_files
end

-- Navigate to route file
function M.goto_route_file(route_name)
    if not route_name or route_name == '' then
        -- Show route file picker
        local route_files = M.find_route_files()
        if #route_files == 0 then
            ui.warn('No route files found')
            return
        end

        local items = {}
        for _, route_file in ipairs(route_files) do
            items[#items + 1] = route_file.name
        end

        ui.select(items, {
            prompt = 'Select route file:',
            kind = 'laravel_route_file',
        }, function(choice)
            if choice then
                for _, route_file in ipairs(route_files) do
                    if route_file.name == choice then
                        vim.cmd('edit ' .. route_file.path)
                        break
                    end
                end
            end
        end)
    else
        -- Find specific route file
        local route_files = M.find_route_files()
        local found_route = nil

        for _, route_file in ipairs(route_files) do
            if route_file.name:lower():match(route_name:lower()) then
                found_route = route_file
                break
            end
        end

        if found_route then
            vim.cmd('edit ' .. found_route.path)
        else
            ui.error('Route file not found: ' .. route_name)
        end
    end
end

-- Check if current context is Laravel-specific and should use Laravel navigation
function M.is_laravel_navigation_context()
    -- Try treesitter first if available - this is now the primary method
    if ts_utils.is_laravel_context_ts() then
        return true
    end

    -- Minimal regex fallback - only for very basic cases when treesitter fails
    local line = vim.fn.getline('.')

    -- Only check for the most obvious Laravel patterns as fallback
    local basic_patterns = {
        'route%s*%(',
        'view%s*%(',
        'Route%s*::%s*',
        'Inertia%s*::%s*render%s*%(',
    }

    for _, pattern in ipairs(basic_patterns) do
        if line:match(pattern) then
            return true
        end
    end

    return false
end

-- Helper: Get joined lines around the cursor for multi-line function call extraction
local function get_surrounding_lines_joined(window, num_lines)
    window = window or 0
    num_lines = num_lines or 3
    local curr_line = vim.fn.line('.')
    local start_line = math.max(1, curr_line - num_lines)
    local end_line = curr_line + num_lines
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), start_line - 1, end_line, false)
    return table.concat(lines, ' ')
end

-- Enhanced Laravel string navigation - detects context and navigates to appropriate file
function M.goto_laravel_string()
    -- PRIMARY: Try treesitter navigation (this should handle 90%+ of cases)
    if ts_utils.goto_laravel_string_ts() then
        return true
    end

    -- MINIMAL FALLBACK: Only try regex for the most basic patterns
    local line = vim.fn.getline('.')
    local col = vim.fn.col('.')

    -- Only handle the most obvious regex patterns as absolute fallback
    -- Order matters: more specific patterns first
    local basic_extractions = {
        -- Route::view('/uri', 'view.name') - extract the VIEW (second arg)
        { pattern = "Route::view%s*%(%s*['\"][^'\"]*['\"]%s*,%s*['\"]([^'\"]+)['\"]",    func = 'view' },
        { pattern = "Route::inertia%s*%(%s*['\"][^'\"]*['\"]%s*,%s*['\"]([^'\"]+)['\"]", func = 'view' },
        { pattern = "Inertia::render%s*%(%s*['\"]([^'\"]+)['\"]",                        func = 'view' },
        { pattern = "route%s*%(%s*['\"]([^'\"]+)['\"]",                                  func = 'route' },
        -- Generic view() helper - must NOT match Route::view()
        { pattern = "[^:]view%s*%(%s*['\"]([^'\"]+)['\"]",                               func = 'view' },
        { pattern = "^view%s*%(%s*['\"]([^'\"]+)['\"]",                                  func = 'view' },
    }

    for _, extraction in ipairs(basic_extractions) do
        local match = line:match(extraction.pattern)
        if match then
            if extraction.func == 'route' then
                M.goto_route_definition(match)
            elseif extraction.func == 'view' then
                M.goto_view(match)
            end
            return true
        end
    end

    -- If we get here, neither treesitter nor basic regex worked
    ui.warn('No Laravel navigation pattern detected at cursor position')
    return false
end

-- Legacy regex-based navigation (kept for compatibility but minimized)
function M.goto_laravel_string_regex_legacy()
    -- This function is now deprecated in favor of treesitter-based navigation
    -- It's kept only for extreme edge cases or if treesitter is unavailable
    ui.warn('Using legacy regex navigation - treesitter method failed')
    return false
end

-- Collect all route files in the routes/ directory
local function get_all_route_files(root)
    local routes_dir = root .. '/routes'
    if vim.fn.isdirectory(routes_dir) == 0 then
        return {}
    end

    local files = vim.fn.glob(routes_dir .. '/**/*.php', false, true)
    if not files or #files == 0 then
        return {}
    end

    return files
end

-- Navigate to route definition by name
function M.goto_route_definition(route_name)
    if not route_name or route_name == '' then
        ui.warn('No route name provided')
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    local route_files = get_all_route_files(root)

    local found = false
    for _, route_file in ipairs(route_files) do
        if vim.fn.filereadable(route_file) == 1 then
            local lines = vim.fn.readfile(route_file)
            local name_pattern = '->name%s*%(%s*[\'"]' .. vim.pesc(route_name) .. '[\'"]'

            -- First try: Look for exact ->name() matches on a single line
            for i = 1, #lines do
                if lines[i]:match(name_pattern) then
                    vim.cmd('edit ' .. route_file)
                    vim.fn.cursor(i, 1)
                    vim.cmd('normal! zz')
                    found = true
                    break
                end
            end

            -- Second try: Join lines in windows of 5 to catch multi-line route definitions
            if not found then
                local window = 5
                for i = 1, #lines do
                    local chunk = {}
                    local chunk_lines = {}
                    for j = 0, window - 1 do
                        if lines[i + j] then
                            table.insert(chunk, lines[i + j])
                            table.insert(chunk_lines, i + j)
                        end
                    end
                    local joined = table.concat(chunk, ' ')

                    if joined:match(name_pattern) then
                        -- Find which specific line in the chunk contains the name
                        local target_line = i
                        for _, line_num in ipairs(chunk_lines) do
                            if lines[line_num]:match('->name') then
                                target_line = line_num
                                break
                            end
                        end

                        vim.cmd('edit ' .. route_file)
                        vim.fn.cursor(target_line, 1)
                        vim.cmd('normal! zz')
                        found = true
                        break
                    end
                end
            end

            -- Third try: Handle group name prefixes (e.g., Route::name('prefix.')->group(...))
            -- Search for the route name suffix inside a named group
            if not found and route_name:find('%.') then
                local parts = {}
                for part in route_name:gmatch('[^%.]+') do
                    table.insert(parts, part)
                end

                if #parts >= 2 then
                    local suffix = parts[#parts]
                    local suffix_pattern = '->name%s*%(%s*[\'"]' .. vim.pesc(suffix) .. '[\'"]'

                    for i = 1, #lines do
                        if lines[i]:match(suffix_pattern) then
                            -- Verify we're inside a named group with the right prefix
                            local prefix = table.concat(parts, '.', 1, #parts - 1) .. '.'
                            for j = math.max(1, i - 20), i - 1 do
                                local group_pattern = 'name%s*%(%s*[\'"]' .. vim.pesc(prefix) .. '[\'"]'
                                if lines[j]:match(group_pattern) then
                                    vim.cmd('edit ' .. route_file)
                                    vim.fn.cursor(i, 1)
                                    vim.cmd('normal! zz')
                                    found = true
                                    break
                                end
                            end
                            if found then break end
                        end
                    end
                end
            end

            if found then break end
        end
    end

    if not found then
        ui.warn('Route not found: ' .. route_name)
    end
end

-- Navigate to config file
function M.goto_config(config_key)
    if not config_key or config_key == '' then
        ui.warn('No config key provided')
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    -- Extract the config file from the key (e.g., 'app.name' -> 'app')
    local config_file = config_key:match('^([^%.]+)')
    if not config_file then
        config_file = config_key
    end

    local config_path = root .. '/config/' .. config_file .. '.php'

    if vim.fn.filereadable(config_path) == 1 then
        vim.cmd('edit ' .. config_path)

        -- Try to find the specific key
        if config_key:find('%.') then
            local key_parts = {}
            for part in config_key:gmatch('[^%.]+') do
                table.insert(key_parts, part)
            end

            -- Skip the first part (file name) and search for the nested key
            if #key_parts > 1 then
                local search_key = key_parts[2]
                vim.fn.search("'" .. search_key .. "'\\|\"" .. search_key .. "\"", 'w')
            end
        end

        vim.cmd('normal! zz')
    else
        ui.warn('Config file not found: ' .. config_file .. '.php')
    end
end

-- Navigate to translation file
function M.goto_translation(trans_key)
    if not trans_key or trans_key == '' then
        ui.warn('No translation key provided')
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    -- Extract the translation file from the key (e.g., 'auth.failed' -> 'auth')
    local trans_file = trans_key:match('^([^%.]+)')
    if not trans_file then
        trans_file = trans_key
    end

    -- Try different language directories
    local lang_dirs = { root .. '/lang/en', root .. '/resources/lang/en' }

    for _, lang_dir in ipairs(lang_dirs) do
        local trans_path = lang_dir .. '/' .. trans_file .. '.php'

        if vim.fn.filereadable(trans_path) == 1 then
            vim.cmd('edit ' .. trans_path)

            -- Try to find the specific key
            if trans_key:find('%.') then
                local key_parts = {}
                for part in trans_key:gmatch('[^%.]+') do
                    table.insert(key_parts, part)
                end

                -- Skip the first part (file name) and search for the nested key
                if #key_parts > 1 then
                    local search_key = key_parts[2]
                    vim.fn.search("'" .. search_key .. "'\\|\"" .. search_key .. "\"", 'w')
                end
            end

            vim.cmd('normal! zz')
            return
        end
    end

    ui.warn('Translation file not found: ' .. trans_file .. '.php')
end

-- Navigate to environment variable in .env file
function M.goto_env(env_key)
    if not env_key or env_key == '' then
        ui.warn('No environment variable provided')
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    -- Try different .env files
    local env_files = {
        root .. '/.env',
        root .. '/.env.example',
        root .. '/.env.local',
        root .. '/.env.production',
        root .. '/.env.staging',
        root .. '/.env.testing',
    }

    for _, env_file in ipairs(env_files) do
        if vim.fn.filereadable(env_file) == 1 then
            local lines = vim.fn.readfile(env_file)
            for i, line in ipairs(lines) do
                -- Look for the environment variable
                if line:match('^' .. vim.pesc(env_key) .. '%s*=') then
                    vim.cmd('edit ' .. env_file)
                    vim.fn.cursor(i, 1)
                    vim.cmd('normal! zz')
                    return
                end
            end
        end
    end

    -- If not found, open the main .env file anyway
    local main_env = root .. '/.env'
    if vim.fn.filereadable(main_env) == 1 then
        vim.cmd('edit ' .. main_env)
        ui.warn('Environment variable "' .. env_key .. '" not found, but opened .env file')
    else
        ui.warn('No .env file found in project root')
    end
end

-- Navigate to asset file
function M.goto_asset(asset_path)
    if not asset_path or asset_path == '' then
        ui.warn('No asset path provided')
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    -- Try different asset locations
    local asset_locations = {
        root .. '/public/' .. asset_path,
        root .. '/resources/js/' .. asset_path,
        root .. '/resources/css/' .. asset_path,
        root .. '/resources/sass/' .. asset_path,
        root .. '/resources/assets/' .. asset_path,
    }

    for _, asset_file in ipairs(asset_locations) do
        if vim.fn.filereadable(asset_file) == 1 then
            vim.cmd('edit ' .. asset_file)
            return
        end
    end

    ui.warn('Asset file not found: ' .. asset_path)
end

-- Enhanced debug function to show treesitter parse information and all matches
function M.debug_treesitter_context()
    local parser, ts = ts_utils.get_parser()
    if not parser then
        ui.error('Treesitter not available')
        return
    end

    local ok, tree = pcall(function() return parser:parse()[1] end)
    if not ok or not tree then
        ui.error('Failed to parse tree')
        return
    end

    local root = tree:root()
    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
    cursor_row = cursor_row - 1

    local debug_info = {
        'Treesitter Debug Information:',
        '============================',
        'Cursor Position: Row ' .. cursor_row .. ', Col ' .. cursor_col,
        'Filetype: ' .. vim.bo.filetype,
        '',
        'Query Creation Status:',
        '--------------------'
    }

    local query = ts_utils.get_laravel_query()
    if not query then
        table.insert(debug_info, 'Failed to create main Laravel query')
    else
        table.insert(debug_info, 'Main Laravel query created successfully')
    end

    table.insert(debug_info, '')
    table.insert(debug_info, 'Raw AST at Cursor:')
    table.insert(debug_info, '-----------------')

    -- Show the actual AST nodes at cursor position
    local cursor_node = root:descendant_for_range(cursor_row, cursor_col, cursor_row, cursor_col)
    if cursor_node then
        local depth = 0
        local current = cursor_node
        while current and depth < 8 do
            local node_type = current:type()
            local node_text = ''
            local ok_text, text = pcall(vim.treesitter.get_node_text, current, 0)
            if ok_text and text then
                node_text = text:gsub('\n', '\\n'):sub(1, 50)
                if #text > 50 then node_text = node_text .. '...' end
            end

            local indent = string.rep('  ', depth)
            table.insert(debug_info, indent .. '- ' .. node_type .. ': "' .. node_text .. '"')

            current = current:parent()
            depth = depth + 1
        end
    else
        table.insert(debug_info, 'No node found at cursor position')
    end

    table.insert(debug_info, '')
    table.insert(debug_info, 'All Laravel Matches Found:')
    table.insert(debug_info, '-------------------------')

    -- Find all Laravel patterns in the current function/scope
    local current_function_node = root:descendant_for_range(cursor_row, 0, cursor_row, 1000)
    local all_matches = {}

    -- Debug: Show what node we're searching in
    if current_function_node then
        table.insert(debug_info, 'Search Node Type: ' .. current_function_node:type())
        local ok_text, search_text = pcall(vim.treesitter.get_node_text, current_function_node, 0)
        if ok_text and search_text then
            local preview = search_text:gsub('\n', '\\n'):sub(1, 100)
            if #search_text > 100 then preview = preview .. '...' end
            table.insert(debug_info, 'Search Node Text: "' .. preview .. '"')
        end

        -- Test with ultra basic queries
        local simple_query_string = [[
            (name) @any_name
        ]]

        local simple_ok, simple_query = pcall(vim.treesitter.query.parse, 'php', simple_query_string)
        if simple_ok and simple_query then
            table.insert(debug_info, 'Simple query created successfully')
            table.insert(debug_info, '')
            table.insert(debug_info, 'Simple Function Calls Found:')
            table.insert(debug_info, '----------------------------')

            local simple_iter_ok, simple_iter = pcall(simple_query.iter_matches, simple_query, current_function_node, 0)
            if simple_iter_ok and simple_iter then
                local simple_captures = {}
                for _, match, _ in simple_iter do
                    for id, node in pairs(match) do
                        if node then
                            local capture_name = simple_query.captures[id]
                            local ok_text, text = pcall(vim.treesitter.get_node_text, node, 0)
                            if ok_text and text then
                                if not simple_captures[capture_name] then
                                    simple_captures[capture_name] = {}
                                end
                                table.insert(simple_captures[capture_name], text)
                            end
                        end
                    end
                end

                -- Show summary of what we captured
                if next(simple_captures) then
                    for capture_name, texts in pairs(simple_captures) do
                        table.insert(debug_info, '  ' .. capture_name .. ': ' .. #texts .. ' matches')
                        for i, text in ipairs(texts) do
                            if i <= 3 then -- Show first 3 matches
                                local preview = text:gsub('\n', '\\n'):sub(1, 40)
                                if #text > 40 then preview = preview .. '...' end
                                table.insert(debug_info, '    [' .. i .. '] "' .. preview .. '"')
                            elseif i == 4 then
                                table.insert(debug_info, '    ... and ' .. (#texts - 3) .. ' more')
                                break
                            end
                        end
                    end
                else
                    table.insert(debug_info, '  No captures found')
                end
            else
                table.insert(debug_info, '  Error iterating simple query')
            end
        else
            table.insert(debug_info, '  Error creating simple query')
        end

        table.insert(debug_info, '')
        table.insert(debug_info, 'AST Node Analysis:')
        table.insert(debug_info, '------------------')

        -- Let's manually find function calls in the AST and test queries on them
        local found_function_calls = {}
        local function find_function_calls(node, depth)
            if depth > 10 then return end

            if node:type() == 'function_call_expression' then
                table.insert(debug_info, 'Found function_call_expression at depth ' .. depth .. ':')
                table.insert(found_function_calls, node) -- Store for testing
                local child_count = node:child_count()
                for i = 0, child_count - 1 do
                    local child = node:child(i)
                    if child then
                        local child_type = child:type()
                        local child_ok, child_text = pcall(vim.treesitter.get_node_text, child, 0)
                        if child_ok and child_text then
                            local preview = child_text:gsub('\n', '\\n'):sub(1, 50)
                            if #child_text > 50 then preview = preview .. '...' end
                            table.insert(debug_info, '  Child[' .. i .. '] ' .. child_type .. ': "' .. preview .. '"')

                            -- If this child is the function name, let's see its structure
                            if child_type == 'name' then
                                table.insert(debug_info, '    ^ This is the function name!')
                            elseif child_type == 'arguments' then
                                table.insert(debug_info, '    ^ These are the arguments, exploring...')
                                local arg_count = child:child_count()
                                for j = 0, arg_count - 1 do
                                    local arg_child = child:child(j)
                                    if arg_child then
                                        local arg_type = arg_child:type()
                                        local arg_ok, arg_text = pcall(vim.treesitter.get_node_text, arg_child, 0)
                                        if arg_ok and arg_text then
                                            table.insert(debug_info,
                                                '      Arg[' .. j .. '] ' .. arg_type .. ': "' .. arg_text .. '"')
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Recursively search children
            for i = 0, node:child_count() - 1 do
                local child = node:child(i)
                if child then
                    find_function_calls(child, depth + 1)
                end
            end
        end

        if current_function_node then
            find_function_calls(current_function_node, 0)
        end

        -- Test query directly on found function calls
        if #found_function_calls > 0 and simple_query then
            table.insert(debug_info, '')
            table.insert(debug_info, 'Direct Query Test on Function Call:')
            table.insert(debug_info, '-----------------------------------')

            local function_call_node = found_function_calls[1]
            local direct_iter_ok, direct_iter = pcall(simple_query.iter_matches, simple_query, function_call_node, 0)
            if direct_iter_ok and direct_iter then
                local direct_captures = {}
                for _, match, _ in direct_iter do
                    for id, node in pairs(match) do
                        if node then
                            local capture_name = simple_query.captures[id]
                            local ok_text, text = pcall(vim.treesitter.get_node_text, node, 0)
                            if ok_text and text then
                                if not direct_captures[capture_name] then
                                    direct_captures[capture_name] = {}
                                end
                                table.insert(direct_captures[capture_name], text)
                            end
                        end
                    end
                end

                if next(direct_captures) then
                    for capture_name, texts in pairs(direct_captures) do
                        table.insert(debug_info, '  ' .. capture_name .. ': ' .. table.concat(texts, ', '))
                    end
                else
                    table.insert(debug_info, '  No direct captures found either')
                end
            else
                table.insert(debug_info, '  Error in direct query iteration')
            end
        end

        table.insert(debug_info, '')
        table.insert(debug_info, 'Laravel Query Results:')
        table.insert(debug_info, '--------------------')

        if not query then
            table.insert(debug_info, 'Skipping - no Laravel query available')
        else
            local iter_ok, iter = pcall(query.iter_matches, query, current_function_node, 0)
            if iter_ok and iter then
                local match_count = 0
                for _, match, _ in iter do
                    match_count = match_count + 1
                    table.insert(debug_info, 'Raw Match #' .. match_count .. ':')

                    -- Show raw match info
                    for id, node in pairs(match) do
                        if node then
                            local capture_name = query.captures[id]
                            local ok_text, text = pcall(vim.treesitter.get_node_text, node, 0)
                            if ok_text and text then
                                local node_type = node:type()
                                table.insert(debug_info,
                                    '  ' .. (capture_name or 'unknown') .. ' (' .. node_type .. '): "' .. text .. '"')
                            end
                        end
                    end

                    local debug_steps, extraction_data = ts_utils.extract_call_info_debug(match, query)

                    -- Add detailed extraction steps to debug output
                    for _, step in ipairs(debug_steps) do
                        table.insert(debug_info, '  ' .. step)
                    end

                    local call_info = ts_utils.extract_call_info(match, query)
                    table.insert(debug_info, '  Final extract result: ' .. (call_info and 'SUCCESS' or 'FAILED'))
                    if call_info then
                        local match_details = {
                            count = match_count,
                            call_info = call_info,
                            ranges = {}
                        }

                        -- Get node ranges for this match
                        for _, match_node in pairs(match) do
                            if match_node then
                                local ok_range, start_row, start_col, end_row, end_col = pcall(function()
                                    return match_node:range()
                                end)
                                if ok_range then
                                    table.insert(match_details.ranges, {
                                        start_row = start_row,
                                        start_col = start_col,
                                        end_row = end_row,
                                        end_col = end_col,
                                        contains_cursor = start_row <= cursor_row and cursor_row <= end_row and
                                            (start_row < cursor_row or start_col <= cursor_col) and
                                            (end_row > cursor_row or end_col >= cursor_col)
                                    })
                                end
                            end
                        end

                        table.insert(all_matches, match_details)
                    else
                        table.insert(debug_info, '  Failed to extract call info from this match')
                    end
                end

                if match_count == 0 then
                    table.insert(debug_info, 'No Laravel matches found with main query')
                end
            else
                table.insert(debug_info, 'Error iterating Laravel query: ' .. tostring(iter))
            end
        end
    else
        table.insert(debug_info, 'No search node found for current line')
    end

    -- Show parsed match summaries
    if #all_matches > 0 then
        table.insert(debug_info, '')
        table.insert(debug_info, 'Parsed Matches Summary:')
        table.insert(debug_info, '======================')
        for _, match in ipairs(all_matches) do
            table.insert(debug_info, 'Match #' .. match.count .. ':')
            table.insert(debug_info, '  Function: ' .. (match.call_info.func or 'nil'))
            table.insert(debug_info, '  Target: ' .. (match.call_info.partial or 'nil'))
            table.insert(debug_info, '  Type: ' .. (match.call_info.call_type or 'nil'))

            for i, range in ipairs(match.ranges) do
                local range_str = string.format('  Range %d: [%d,%d] to [%d,%d]',
                    i, range.start_row, range.start_col, range.end_row, range.end_col)
                if range.contains_cursor then
                    range_str = range_str .. ' ← CONTAINS CURSOR'
                end
                table.insert(debug_info, range_str)
            end
        end
    end

    -- Show what was actually selected
    table.insert(debug_info, '')
    table.insert(debug_info, 'Selected Match:')
    table.insert(debug_info, '==============')

    local ok, call_info = pcall(ts_utils.get_laravel_call_at_cursor)
    if ok and call_info then
        table.insert(debug_info, 'Function Type: ' .. (call_info.func or 'nil'))
        table.insert(debug_info, 'Target String: ' .. (call_info.partial or 'nil'))
        table.insert(debug_info, 'Call Type: ' .. (call_info.call_type or 'nil'))
        table.insert(debug_info, 'Function Name: ' .. (call_info.function_name or 'nil'))
        table.insert(debug_info, 'Scope Name: ' .. (call_info.scope_name or 'nil'))
        table.insert(debug_info, 'Method Name: ' .. (call_info.method_name or 'nil'))
        table.insert(debug_info, 'All Arguments: ' .. table.concat(call_info.all_args or {}, ', '))
    else
        table.insert(debug_info, 'No match selected or error occurred')
    end

    ui.show_float(debug_info, { title = 'Enhanced Treesitter Debug' })
end

-- Test treesitter vs regex parsing
function M.compare_parsing_methods()
    local ts_ok, ts_context = pcall(ts_utils.get_laravel_call_at_cursor)
    local regex_works = false

    -- Get regex result without treesitter interference
    local original_is_laravel_context_ts = ts_utils.is_laravel_context_ts
    ts_utils.is_laravel_context_ts = function() return false end
    regex_works = M.is_laravel_navigation_context()
    ts_utils.is_laravel_context_ts = original_is_laravel_context_ts

    local comparison = {
        'Laravel Navigation Parsing Comparison:',
        '=====================================',
        '',
        'Treesitter Result:',
        ts_ok and ts_context and ('  Function: ' .. (ts_context.func or 'nil')) or '  No match found or error',
        ts_ok and ts_context and ('  Target: ' .. (ts_context.partial or 'nil')) or '',
        ts_ok and ts_context and ('  Call Type: ' .. (ts_context.call_type or 'nil')) or '',
        not ts_ok and ('  Error: ' .. tostring(ts_context)) or '',
        '',
        'Regex Result:',
        regex_works and '  Match found' or '  No match found',
        '',
        'Recommendation:',
        ts_ok and ts_context and '  Use treesitter navigation' or
        (regex_works and '  Use regex fallback' or '  No navigation available'),
    }

    ui.show_float(comparison, { title = 'Parsing Methods Comparison' })
end

-- Navigate to Laravel global function documentation or definition
function M.goto_laravel_global(global_func)
    if not global_func or global_func == '' then
        ui.warn('No global function provided')
        return
    end

    -- Map of Laravel global functions to their documentation or relevant files
    local global_mappings = {
        auth = { type = 'provider', path = '/config/auth.php', desc = 'Authentication configuration' },
        request = { type = 'docs', desc = 'Request helper - provides access to current HTTP request' },
        session = { type = 'provider', path = '/config/session.php', desc = 'Session configuration' },
        cache = { type = 'provider', path = '/config/cache.php', desc = 'Cache configuration' },
        cookie = { type = 'provider', path = '/config/session.php', desc = 'Cookie configuration in session config' },
        response = { type = 'docs', desc = 'Response helper - creates HTTP responses' },
        redirect = { type = 'docs', desc = 'Redirect helper - creates redirect responses' },
        back = { type = 'docs', desc = 'Back helper - redirects to previous page' },
        old = { type = 'docs', desc = 'Old input helper - retrieves old form input' },
        asset = { type = 'docs', desc = 'Asset helper - generates URLs for assets' },
        url = { type = 'docs', desc = 'URL helper - generates URLs' },
        secure_url = { type = 'docs', desc = 'Secure URL helper - generates HTTPS URLs' },
        action = { type = 'docs', desc = 'Action helper - generates URLs for controller actions' },
        mix = { type = 'file', path = '/webpack.mix.js', desc = 'Laravel Mix configuration' },
        app = { type = 'provider', path = '/config/app.php', desc = 'Application configuration' },
        env = { type = 'file', path = '/.env', desc = 'Environment configuration' },
        config = { type = 'provider', path = '/config', desc = 'Configuration files' },
        dd = { type = 'docs', desc = 'Dump and die helper' },
        dump = { type = 'docs', desc = 'Dump helper' },
        logger = { type = 'provider', path = '/config/logging.php', desc = 'Logging configuration' },
        validator = { type = 'provider', path = '/config/validation.php', desc = 'Validation configuration' },
        abort = { type = 'docs', desc = 'Abort helper - throws HTTP exceptions' },
    }

    local mapping = global_mappings[global_func]
    if not mapping then
        return
    end

    local root = get_project_root()
    if not root then
        ui.error('Not in a Laravel project')
        return
    end

    if mapping.type == 'file' or mapping.type == 'provider' then
        local file_path = root .. mapping.path

        if mapping.type == 'provider' and mapping.path == '/config' then
            -- Open config directory
            vim.cmd('edit ' .. file_path)
        elseif vim.fn.filereadable(file_path) == 1 then
            vim.cmd('edit ' .. file_path)
        elseif vim.fn.isdirectory(file_path) == 1 then
            vim.cmd('edit ' .. file_path)
        else
            ui.warn('File not found: ' .. file_path)
        end
    end
end

return M
