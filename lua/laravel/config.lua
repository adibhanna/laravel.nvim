local M = {}

M.options = {
    notifications = true,
    livewire = {
        component_path = "app/Livewire",
        view_path = "resources/views/livewire",
        namespace = "App\\Livewire",
    },
    translations = {
        default_lang = nil, -- Auto-detect or prompt
        show_picker = true, -- Show language picker when multiple translations exist
    },
    cache_ttl = 30,         -- Cache time in seconds
}

M.setup = function(opts)
    M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
