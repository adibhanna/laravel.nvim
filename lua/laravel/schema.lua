-- Laravel schema analysis and diagram generation
local ui = require('laravel.ui')

local M = {}

-- Get project root directory
local function get_project_root()
    local current_dir = vim.fn.getcwd()
    local artisan_file = current_dir .. '/artisan'

    if vim.fn.filereadable(artisan_file) == 1 then
        return current_dir
    end

    -- Try to find Laravel root by looking for artisan file
    local root = vim.fn.findfile('artisan', vim.fn.expand('%:p:h') .. ';')
    if root and root ~= '' then
        return vim.fn.fnamemodify(root, ':h')
    end

    return nil
end

-- Find all migration files
function M.find_migrations()
    local root = get_project_root()
    if not root then
        return {}
    end

    local migrations_dir = root .. '/database/migrations'
    if vim.fn.isdirectory(migrations_dir) == 0 then
        return {}
    end

    local migrations = {}
    local files = vim.fn.glob(migrations_dir .. '/*.php', false, true)

    for _, file in ipairs(files) do
        local name = vim.fn.fnamemodify(file, ':t:r') -- filename without extension
        -- Extract timestamp and migration name
        local timestamp, migration_name = name:match('^(%d+_%d+_%d+_%d+)_(.+)$')

        table.insert(migrations, {
            name = migration_name or name,
            full_name = name,
            timestamp = timestamp,
            path = file
        })
    end

    -- Sort by timestamp
    table.sort(migrations, function(a, b)
        return (a.timestamp or '') < (b.timestamp or '')
    end)

    return migrations
end

-- Parse a single migration file to extract schema information
function M.parse_migration(file_path)
    local content = vim.fn.readfile(file_path)
    local schema_info = {
        tables = {},
        operations = {}
    }

    local current_table = nil
    local in_schema_block = false

    for _, line in ipairs(content) do
        -- Remove leading/trailing whitespace
        line = line:match('^%s*(.-)%s*$') or line

        -- Detect Schema::create or Schema::table calls
        local success_create, create_match = pcall(function()
            return line:match("Schema::create%s*%(%s*['\"]([^'\"]+)['\"]")
        end)
        local success_table, table_match = pcall(function()
            return line:match("Schema::table%s*%(%s*['\"]([^'\"]+)['\"]")
        end)

        if success_create and create_match then
            current_table = create_match
            in_schema_block = true
            schema_info.tables[current_table] = {
                columns = {},
                indexes = {},
                foreign_keys = {}
            }
            table.insert(schema_info.operations, {
                type = 'create',
                table = current_table
            })
        elseif success_table and table_match then
            current_table = table_match
            in_schema_block = true
            if not schema_info.tables[current_table] then
                schema_info.tables[current_table] = {
                    columns = {},
                    indexes = {},
                    foreign_keys = {}
                }
            end
            table.insert(schema_info.operations, {
                type = 'modify',
                table = current_table
            })
        end

        -- Parse column definitions when inside a schema block
        if in_schema_block and current_table then
            -- Parse various column types
            local column_patterns = {
                {
                    pattern = "%$table%->id%s*%(%s*%)",
                    type = 'id',
                    name = function()
                        return 'id'
                    end
                },
                {
                    pattern = "%$table%->id%s*%(%s*['\"]([^'\"]+)['\"]%s*%)",
                    type = 'id'
                },
                { pattern = "%$table%->string%s*%(%s*['\"]([^'\"]+)['\"]",     type = 'string' },
                { pattern = "%$table%->text%s*%(%s*['\"]([^'\"]+)['\"]",       type = 'text' },
                { pattern = "%$table%->integer%s*%(%s*['\"]([^'\"]+)['\"]",    type = 'integer' },
                { pattern = "%$table%->bigInteger%s*%(%s*['\"]([^'\"]+)['\"]", type = 'bigInteger' },
                { pattern = "%$table%->boolean%s*%(%s*['\"]([^'\"]+)['\"]",    type = 'boolean' },
                { pattern = "%$table%->timestamp%s*%(%s*['\"]([^'\"]+)['\"]",  type = 'timestamp' },
                {
                    pattern = "%$table%->timestamps%s*%(%s*%)",
                    type = 'timestamps',
                    name = function()
                        return
                        'created_at,updated_at'
                    end
                },
                {
                    pattern = "%$table%->softDeletes%s*%(%s*%)",
                    type = 'softDeletes',
                    name = function()
                        return
                        'deleted_at'
                    end
                },
                { pattern = "%$table%->json%s*%(%s*['\"]([^'\"]+)['\"]",     type = 'json' },
                { pattern = "%$table%->decimal%s*%(%s*['\"]([^'\"]+)['\"]",  type = 'decimal' },
                { pattern = "%$table%->date%s*%(%s*['\"]([^'\"]+)['\"]",     type = 'date' },
                { pattern = "%$table%->datetime%s*%(%s*['\"]([^'\"]+)['\"]", type = 'datetime' },
                { pattern = "%$table%->enum%s*%(%s*['\"]([^'\"]+)['\"]",         type = 'enum' },
                { pattern = "%$table%->uuid%s*%(%s*['\"]([^'\"]+)['\"]",         type = 'uuid' },
                { pattern = "%$table%->ulid%s*%(%s*['\"]([^'\"]+)['\"]",         type = 'ulid' },
                { pattern = "%$table%->foreignId%s*%(%s*['\"]([^'\"]+)['\"]",    type = 'foreignId' },
                { pattern = "%$table%->foreignUlid%s*%(%s*['\"]([^'\"]+)['\"]",  type = 'foreignUlid' },
                { pattern = "%$table%->foreignUuid%s*%(%s*['\"]([^'\"]+)['\"]",  type = 'foreignUuid' },
                { pattern = "%$table%->float%s*%(%s*['\"]([^'\"]+)['\"]",        type = 'float' },
                { pattern = "%$table%->double%s*%(%s*['\"]([^'\"]+)['\"]",       type = 'double' },
                { pattern = "%$table%->binary%s*%(%s*['\"]([^'\"]+)['\"]",       type = 'binary' },
                { pattern = "%$table%->char%s*%(%s*['\"]([^'\"]+)['\"]",         type = 'char' },
                { pattern = "%$table%->mediumText%s*%(%s*['\"]([^'\"]+)['\"]",   type = 'mediumText' },
                { pattern = "%$table%->longText%s*%(%s*['\"]([^'\"]+)['\"]",     type = 'longText' },
                { pattern = "%$table%->tinyInteger%s*%(%s*['\"]([^'\"]+)['\"]",  type = 'tinyInteger' },
                { pattern = "%$table%->smallInteger%s*%(%s*['\"]([^'\"]+)['\"]", type = 'smallInteger' },
                { pattern = "%$table%->mediumInteger%s*%(%s*['\"]([^'\"]+)['\"]", type = 'mediumInteger' },
                { pattern = "%$table%->unsignedBigInteger%s*%(%s*['\"]([^'\"]+)['\"]", type = 'unsignedBigInteger' },
                { pattern = "%$table%->ipAddress%s*%(%s*['\"]([^'\"]+)['\"]",    type = 'ipAddress' },
                { pattern = "%$table%->macAddress%s*%(%s*['\"]([^'\"]+)['\"]",   type = 'macAddress' },
                { pattern = "%$table%->year%s*%(%s*['\"]([^'\"]+)['\"]",         type = 'year' },
                { pattern = "%$table%->time%s*%(%s*['\"]([^'\"]+)['\"]",         type = 'time' },
                { pattern = "%$table%->jsonb%s*%(%s*['\"]([^'\"]+)['\"]",        type = 'jsonb' },
                {
                    pattern = "%$table%->rememberToken%s*%(%s*%)",
                    type = 'string',
                    name = function() return 'remember_token' end
                },
                {
                    pattern = "%$table%->nullableTimestamps%s*%(%s*%)",
                    type = 'timestamps',
                    name = function() return 'created_at,updated_at' end
                },
                {
                    pattern = "%$table%->morphs%s*%(%s*['\"]([^'\"]+)['\"]",
                    type = 'morphs',
                    name = function(match) return match .. '_type,' .. match .. '_id' end
                },
                {
                    pattern = "%$table%->ulidMorphs%s*%(%s*['\"]([^'\"]+)['\"]",
                    type = 'ulidMorphs',
                    name = function(match) return match .. '_type,' .. match .. '_id' end
                },
                {
                    pattern = "%$table%->uuidMorphs%s*%(%s*['\"]([^'\"]+)['\"]",
                    type = 'uuidMorphs',
                    name = function(match) return match .. '_type,' .. match .. '_id' end
                },
            }

            for _, col_pattern in ipairs(column_patterns) do
                local success, match = pcall(function()
                    return line:match(col_pattern.pattern)
                end)

                if success and match then
                    local column_name = col_pattern.name and col_pattern.name(match) or match
                    if column_name then
                        -- Handle multiple columns (like timestamps)
                        for name in column_name:gmatch('[^,]+') do
                            name = name:match('^%s*(.-)%s*$') -- trim
                            table.insert(schema_info.tables[current_table].columns, {
                                name = name,
                                type = col_pattern.type
                            })
                        end
                    end
                    break
                elseif not success then
                    -- Skip invalid patterns silently
                end
            end

            -- Parse foreign key constraints
            -- Look for $table->foreign('column')->references('id')->on('table')
            local success_local, local_key = pcall(function()
                return line:match("%$table%->foreign%s*%(%s*['\"]([^'\"]+)['\"]")
            end)

            if success_local and local_key then
                local success_foreign, foreign_key = pcall(function()
                    return line:match("%->references%s*%(%s*['\"]([^'\"]+)['\"]")
                end)
                local success_table, foreign_table = pcall(function()
                    return line:match("%->on%s*%(%s*['\"]([^'\"]+)['\"]")
                end)

                if success_foreign and success_table and foreign_key and foreign_table then
                    table.insert(schema_info.tables[current_table].foreign_keys, {
                        local_key = local_key,
                        foreign_table = foreign_table,
                        foreign_key = foreign_key
                    })
                end
            end

            -- Detect end of schema block
            local success_end = pcall(function()
                return line:match('});')
            end)
            if success_end and line:match('});') then
                in_schema_block = false
                current_table = nil
            end
        end
    end

    return schema_info
end

-- Generate Mermaid ER diagram from schema information
function M.generate_mermaid_diagram(all_schema_info)
    local lines = {}
    table.insert(lines, 'erDiagram')

    -- Collect all tables and their columns
    local all_tables = {}
    for _, schema in ipairs(all_schema_info) do
        for table_name, table_info in pairs(schema.tables) do
            if not all_tables[table_name] then
                all_tables[table_name] = {
                    columns = {},
                    foreign_keys = {}
                }
            end

            -- Merge columns (avoid duplicates)
            local existing_columns = {}
            for _, col in ipairs(all_tables[table_name].columns) do
                existing_columns[col.name] = true
            end

            for _, col in ipairs(table_info.columns) do
                if not existing_columns[col.name] then
                    table.insert(all_tables[table_name].columns, col)
                    existing_columns[col.name] = true
                end
            end

            -- Merge foreign keys
            for _, fk in ipairs(table_info.foreign_keys) do
                table.insert(all_tables[table_name].foreign_keys, fk)
            end
        end
    end

    -- Define tables with columns
    for table_name, table_info in pairs(all_tables) do
        if #table_info.columns > 0 then
            table.insert(lines, '    ' .. table_name .. ' {')

            for _, column in ipairs(table_info.columns) do
                local type_mapping = {
                    id = 'int',
                    string = 'varchar',
                    text = 'text',
                    mediumText = 'text',
                    longText = 'text',
                    char = 'char',
                    integer = 'int',
                    tinyInteger = 'tinyint',
                    smallInteger = 'smallint',
                    mediumInteger = 'mediumint',
                    bigInteger = 'bigint',
                    unsignedBigInteger = 'bigint',
                    boolean = 'boolean',
                    timestamp = 'timestamp',
                    timestamps = 'timestamp',
                    softDeletes = 'timestamp',
                    json = 'json',
                    jsonb = 'jsonb',
                    decimal = 'decimal',
                    float = 'float',
                    double = 'double',
                    date = 'date',
                    datetime = 'datetime',
                    time = 'time',
                    year = 'year',
                    enum = 'enum',
                    binary = 'binary',
                    uuid = 'uuid',
                    ulid = 'ulid',
                    foreignId = 'bigint',
                    foreignUlid = 'ulid',
                    foreignUuid = 'uuid',
                    ipAddress = 'varchar',
                    macAddress = 'varchar',
                    morphs = 'varchar',
                    ulidMorphs = 'ulid',
                    uuidMorphs = 'uuid',
                }

                local mermaid_type = type_mapping[column.type] or column.type
                local key_indicator = ''

                -- Mark primary keys
                if column.name == 'id' or column.type == 'id' then
                    key_indicator = ' PK'
                end

                table.insert(lines, '        ' .. mermaid_type .. ' ' .. column.name .. key_indicator)
            end

            table.insert(lines, '    }')
        end
    end

    -- Add empty line before relationships
    table.insert(lines, '')

    -- Define relationships
    for table_name, table_info in pairs(all_tables) do
        for _, fk in ipairs(table_info.foreign_keys) do
            -- Create relationship: foreign_table ||--o{ local_table : "relationship"
            table.insert(lines, '    ' .. fk.foreign_table .. ' ||--o{ ' .. table_name .. ' : "' .. fk.local_key .. '"')
        end
    end

    return table.concat(lines, '\n')
end

-- Analyze all migrations and generate schema diagram
function M.analyze_schema()
    local migrations = M.find_migrations()

    if #migrations == 0 then
        ui.warn('No migration files found')
        return
    end

    ui.info('Analyzing ' .. #migrations .. ' migration files...')

    local all_schema_info = {}

    for _, migration in ipairs(migrations) do
        local schema_info = M.parse_migration(migration.path)
        table.insert(all_schema_info, schema_info)
    end

    return all_schema_info
end

-- Show schema diagram in terminal or export to file
function M.show_schema_diagram(export_to_file)
    local all_schema_info = M.analyze_schema()
    if not all_schema_info then
        return
    end

    local mermaid_diagram = M.generate_mermaid_diagram(all_schema_info)

    if export_to_file then
        -- Export to mermaid file
        local root = get_project_root()
        if not root then
            ui.error('Not in a Laravel project')
            return
        end

        local export_path = root .. '/database-schema.mmd'
        vim.fn.writefile(vim.split(mermaid_diagram, '\n'), export_path)
        ui.info('Schema diagram exported to: ' .. export_path)

        -- Ask if user wants to open the file
        ui.select({ 'Yes', 'No' }, {
            prompt = 'Open exported diagram file?',
        }, function(choice)
            if choice == 'Yes' then
                vim.cmd('edit ' .. export_path)
            end
        end)
    else
        -- Show in terminal using create_diagram function
        local success, err = pcall(function()
            return create_diagram({
                content = mermaid_diagram
            })
        end)

        if not success then
            -- Fallback: open in a new buffer
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(mermaid_diagram, '\n'))
            vim.api.nvim_buf_set_option(buf, 'filetype', 'mermaid')
            vim.api.nvim_buf_set_name(buf, 'Laravel Database Schema')
            vim.cmd('split')
            vim.api.nvim_set_current_buf(buf)
            ui.info('Schema diagram displayed in buffer')
        end
    end
end

return M
