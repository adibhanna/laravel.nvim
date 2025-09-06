local M = {}
local Path = require("plenary.path")

-- Executar comando Artisan
function M.run()
    local cmd = vim.fn.input("Artisan command: ", "php artisan ")
    if cmd == "" then
        return
    end

    -- Executar comando
    vim.cmd("!" .. cmd)
end

-- Interface interativa para comandos make
function M.make_interactive()
    local make_commands = {
        { label = "controller",   cmd = "make:controller" },
        { label = "model",        cmd = "make:model" },
        { label = "migration",    cmd = "make:migration" },
        { label = "seeder",       cmd = "make:seeder" },
        { label = "factory",      cmd = "make:factory" },
        { label = "middleware",   cmd = "make:middleware" },
        { label = "request",      cmd = "make:request" },
        { label = "resource",     cmd = "make:resource" },
        { label = "test",         cmd = "make:test" },
        { label = "command",      cmd = "make:command" },
        { label = "event",        cmd = "make:event" },
        { label = "listener",     cmd = "make:listener" },
        { label = "mail",         cmd = "make:mail" },
        { label = "notification", cmd = "make:notification" },
        { label = "policy",       cmd = "make:policy" },
        { label = "provider",     cmd = "make:provider" },
        { label = "rule",         cmd = "make:rule" },
        { label = "livewire",     cmd = "make:livewire" },
    }

    vim.ui.select(
        vim.tbl_map(function(item) return item.label end, make_commands),
        { prompt = "Select make command:" },
        function(choice, idx)
            if choice and idx then
                local selected = make_commands[idx]
                local name = vim.fn.input(selected.label .. " name: ")
                if name ~= "" then
                    local cmd = "php artisan " .. selected.cmd .. " " .. name
                    local result = vim.fn.system(cmd)

                    if vim.v.shell_error == 0 then
                        vim.notify(selected.label .. " '" .. name .. "' created successfully", vim.log.levels.INFO)
                    else
                        vim.notify("Failed to create " .. selected.label .. ": " .. result, vim.log.levels.ERROR)
                    end
                end
            end
        end
    )
end

-- Setup do módulo
function M.setup()
    -- Nada específico por enquanto
end

return M
