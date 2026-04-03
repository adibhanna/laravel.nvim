# Laravel.nvim

A comprehensive Laravel development plugin for Neovim, inspired by Laravel Idea for PhpStorm. This plugin provides intelligent navigation, autocompletion, and development tools specifically designed for Laravel projects.

## Supported Laravel Versions

Laravel 10, 11, and 12 are fully supported. If you encounter any issues, please open a GitHub issue.

## ✨ Features

### 🧭 Smart Navigation

- **Go to Definition (`gd`)**: Navigate to Laravel resources with intelligent context awareness
  - **Treesitter-powered parsing**: Uses Neovim's treesitter for accurate AST-based code analysis
  - **Intelligent fallback**: Gracefully falls back to regex patterns when treesitter is unavailable
  - **Multi-line support**: Handles complex chained method calls and multi-line function definitions
  - **40+ Laravel function patterns**: Comprehensive support for Laravel helpers and facades
  
  **Supported navigation targets:**
  - Routes: `route('dashboard')` → routes/web.php
  - Views: `view('users.index')` → resources/views/users/index.blade.php
  - Inertia: `Inertia::render('Dashboard')` → resources/js/Pages/Dashboard.tsx
  - Config: `config('app.name')` → config/app.php
  - Translations: `__('auth.failed')` → lang/en/auth.php
  - Environment variables: `env('APP_NAME')` → .env file
  - Controllers: `UserController::class` → app/Http/Controllers/UserController.php
  - Controller methods in route groups: `Route::controller(Ctrl::class)->group(...)` → controller method
  - Static method calls: `Route::get()`, `Inertia::render()`, `Config::get()`
  - Method chaining: `->name()`, `->middleware()`, `->where()`
  - Laravel globals: `auth()`, `request()`, `session()`, etc.

### 🔍 Intelligent Autocompletion

- **Route names**: Auto-complete from your route definitions
- **View names**: Complete Blade templates and Inertia components
- **Config keys**: Complete configuration keys from config files
- **Translation keys**: Complete translation keys from language files
- **Environment variables**: Complete from .env files
- **Enhanced IDE Helper completions** (when installed):
  - **Facade methods**: `DB::table()`, `Cache::get()`, `Auth::user()`
  - **Container bindings**: `app('service')`, `resolve('binding')`
  - **Fluent migration methods**: `$table->string()`, `$table->nullable()`
- **30-second caching** for optimal performance

### 📁 Automatic File Creation

- **Missing view prompt**: When navigating to non-existent views, get prompted to create them
- **Smart templates**: Detects your frontend stack (React, Vue, Svelte) and creates appropriate files
- **Directory creation**: Automatically creates necessary directory structures

### 🎯 Laravel-Specific Tools

- **Artisan integration**: Run Artisan commands with autocompletion
- **Composer integration**: Run Composer commands with interactive package management
- **Laravel Sail support**: Full Docker development environment integration
- **Route visualization**: View and navigate your application routes
- **Migration helpers**: Navigate and manage database migrations
- **Model navigation**: Quick access to Eloquent models
- **Schema diagrams**: Visualize your database structure
- **Architecture diagrams**: See your application structure

### Laravel Dump Viewer

The dump viewer captures all your application's `dump()` and `dd()` calls and displays them in a beautifully formatted popup window.

![Laravel Dump Viewer](/assets/images/dumpviewer.png)

#### Features

- **Automatic capture**: All `dump()` and `dd()` calls are automatically captured
- **Real-time updates**: New dumps appear instantly in the viewer
- **Beautiful formatting**: Syntax highlighting and proper indentation
- **File location tracking**: See exactly where each dump originated
- **Timestamp display**: Know when each dump was executed
- **Auto-scroll**: Automatically scroll to the latest dumps
- **Search**: Easily find specific dumps

#### Usage

1. **Enable dump capture:**
   ```vim
   :LaravelDumpsEnable
   ```

2. **Open the dump viewer:**
   ```vim
   :LaravelDumps
   ```
   Or use the keymap: `<leader>Ld`

3. **Use dump() in your Laravel code:**
   ```php
   Route::get('/test', function () {
       dump('Hello from Laravel!');
       dump(['key' => 'value', 'array' => [1, 2, 3]]);
       dump(User::first());
       
       return view('welcome');
   });
   ```

4. **View dumps in real-time** in the popup window

#### Commands

- `:LaravelDumps` - Open dump viewer
- `:LaravelDumpsInstall` - Install service provider (setup only)
- `:LaravelDumpsEnable` - Install service provider and enable dump capture
- `:LaravelDumpsDisable` - Disable dump capture  
- `:LaravelDumpsToggle` - Toggle dump capture
- `:LaravelDumpsClear` - Clear all captured dumps

#### Keymaps

All keymaps use the `<leader>L` prefix (where `<leader>` is typically `\` or `,`):

- `<leader>Ld` - Open dump viewer
- `<leader>LDi` - Install dump service provider
- `<leader>LDe` - Install and enable dump capture
- `<leader>LDd` - Disable dump capture
- `<leader>LDt` - Toggle dump capture
- `<leader>LDc` - Clear dumps

#### Dump Viewer Window Controls

When the dump viewer is open:

- `q` or `<Esc>` - Close window
- `c` - Clear all dumps
- `s` - Toggle auto-scroll
- `r` - Refresh content

#### Setup

**🛠️ Manual setup required for first-time use**

To get started with the dump viewer, you need to install the Laravel service provider:

**Option 1: Install and enable in one step**
```vim
:LaravelDumpsEnable
```

**Option 2: Install first, enable later**
```vim
:LaravelDumpsInstall   " Just creates the service provider
:LaravelDumpsEnable    " Enable dump capture when ready
```

When you install, the plugin will:

1. **🚀 Create** `app/Providers/NvimDumpServiceProvider.php`
2. **🔧 Auto-register** the service provider in your Laravel application:
   - **Laravel 11+ (current)**: Adds to `bootstrap/app.php` using `withProviders()`  
   - **Laravel 10 (legacy)**: Adds to `config/app.php` in the `providers` array
3. **✅ Ready to go!** Start using `dump()` calls

#### Troubleshooting Setup

**🔍 Not seeing dumps? Check your Laravel configuration:**

1. **Verify service provider exists:**
   ```bash
   ls app/Providers/NvimDumpServiceProvider.php
   ```

2. **Check if it's registered in your Laravel app:**
   
   **Laravel 12/11** - Look in `bootstrap/app.php`:
   ```php
   ->withProviders([
       App\Providers\NvimDumpServiceProvider::class,  // ← Should be here
   ])
   ```
   
   **Laravel 10** - Look in `config/app.php`:
   ```php
   'providers' => [
       // ... other providers ...
       App\Providers\NvimDumpServiceProvider::class,  // ← Should be here
   ],
   ```

3. **Clear Laravel caches:**
   ```bash
   php artisan config:cache
   ```

4. **Test with a simple dump:**
   ```php
   // Add to routes/web.php
   Route::get('/test-dumps', function () {
       dump('Hello from Laravel!');
       return 'Check your dump viewer!';
   });
   ```

**Manual Registration (if auto-setup fails):**

If the automatic setup doesn't work, you can manually register the service provider:

<details>
<summary><strong>Laravel 12/11 (bootstrap/app.php)</strong></summary>

**If your `bootstrap/app.php` has an empty `->withProviders()`:**
```php
// Change this:
->withProviders()

// To this:
->withProviders([
    App\Providers\NvimDumpServiceProvider::class,
])
```

**Complete example:**
```php
<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withProviders([
        App\Providers\NvimDumpServiceProvider::class,  // ← Add this line
    ])
    ->withMiddleware(function (Middleware $middleware) {
        //
    })
    ->withExceptions(function (Exceptions $exceptions) {
        //
    })->create();
```
</details>

<details>
<summary><strong>Laravel 10 (config/app.php)</strong></summary>

```php
'providers' => [
    // ... other providers ...
    
    App\Providers\NvimDumpServiceProvider::class,  // ← Add this line
],
```
</details>

> **💡 Pro tip**: The service provider only runs in `local` environment, so it won't affect production!

#### How It Works

The dump viewer works by:

1. **Installing a Laravel Service Provider** that captures `dump()` output
2. **Logging dumps** to `storage/logs/nvim-dumps.log` with timestamps and file locations
3. **Watching the log file** in real-time using Neovim's job system
4. **Displaying dumps** in a beautiful floating window with syntax highlighting

The service provider automatically integrates with Laravel's VarDumper component to capture all dump output without affecting your application's normal behavior.

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "adibhanna/laravel.nvim",
    dependencies = {
        "MunifTanjim/nui.nvim",
        "nvim-lua/plenary.nvim",
    },
    keys = {
        { "<leader>la", ":Artisan<cr>", desc = "Laravel Artisan" },
        { "<leader>lc", ":Composer<cr>", desc = "Composer" },
        { "<leader>lr", ":LaravelRoute<cr>", desc = "Laravel Routes" },
        { "<leader>lm", ":LaravelMake<cr>", desc = "Laravel Make" },
    },
    config = function()
        require("laravel").setup()
    end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "adibhanna/laravel.nvim",
    requires = {
        "MunifTanjim/nui.nvim",
        "nvim-lua/plenary.nvim",
    },
    config = function()
        require("laravel").setup()
    end
}
```

## 📋 Requirements

### Treesitter Support (Recommended)

For optimal navigation accuracy, this plugin leverages **Neovim's treesitter** for intelligent PHP code parsing:

- **Treesitter PHP parser**: Install via `:TSInstall php` for best navigation experience
- **Automatic fallback**: Plugin gracefully falls back to regex parsing if treesitter is unavailable
- **Enhanced accuracy**: Treesitter provides AST-based parsing for precise function call detection
- **Multi-line support**: Handles complex Laravel patterns across multiple lines

**Quick setup:**
```vim
" Install PHP treesitter parser
:TSInstall php

" Verify installation
:TSInstallInfo php
```

> **Note**: While treesitter is highly recommended for the best experience, the plugin will work without it using regex-based parsing as a fallback.

## ⚙️ Configuration

### Basic Setup

```lua
require("laravel").setup({
    notifications = true, -- Enable/disable Laravel.nvim notifications (default: true)
    debug = false,        -- Enable/disable debug error notifications (default: false)
    keymaps = true,       -- Enable/disable Laravel.nvim keymaps (default: true)
    sail = {
        enabled = true,           -- Enable/disable Laravel Sail integration (default: true)
        auto_detect = true,       -- Auto-detect Sail usage in project (default: true)
    },
})
```

### Configuration Options

| Option             | Type      | Default | Description                                              |
| ------------------ | --------- | ------- | -------------------------------------------------------- |
| `notifications`    | `boolean` | `true`  | Enable/disable Laravel project detection notifications   |
| `debug`            | `boolean` | `false` | Enable/disable debug error notifications for completions |
| `keymaps`          | `boolean` | `true`  | Enable/disable Laravel.nvim default keymaps              |
| `sail.enabled`     | `boolean` | `true`  | Enable/disable Laravel Sail integration                  |
| `sail.auto_detect` | `boolean` | `true`  | Auto-detect Sail usage and wrap commands                 |

### Examples

**Disable notifications:**

```lua
require("laravel").setup({
    notifications = false, -- No notifications when Laravel project is detected
})
```

**Enable debug mode (to see completion errors):**

```lua
require("laravel").setup({
    debug = true, -- Show completion error notifications for debugging
})
```

**Configure Laravel Sail integration:**

```lua
require("laravel").setup({
    sail = {
        enabled = true,           -- Enable Sail integration (default: true)
        auto_detect = true,       -- Auto-detect when to use Sail (default: true)
    },
})
```

When Sail is detected in your project (presence of `docker-compose.yml` and `vendor/bin/sail`), all `Artisan` and `Composer` commands will automatically be wrapped with `./vendor/bin/sail`. For example:

- `:Artisan migrate` becomes `./vendor/bin/sail artisan migrate`
- `:Composer install` becomes `./vendor/bin/sail composer install`

**All Laravel commands (including Sail commands) work globally** - you can run them from any file type (JavaScript, CSS, Markdown, etc.) within a Laravel project, not just PHP files.

**Enable Laravel IDE Helper integration:**

First, install the Laravel IDE Helper package in your Laravel project:

```bash
# In your Laravel project root
composer require --dev barryvdh/laravel-ide-helper
```

Then generate the helper files:

```bash
# Generate all IDE helper files
php artisan ide-helper:generate
php artisan ide-helper:models --write
php artisan ide-helper:meta
```

Or use the Neovim commands after opening your Laravel project:

```vim
" Install Laravel IDE Helper (if not already installed)
:LaravelInstallIdeHelper

" Check IDE Helper status and optionally generate files
:LaravelIdeHelperCheck

" Or directly generate all IDE helper files
:LaravelIdeHelper all

" Remove only the generated files (keep package installed)
:LaravelIdeHelperClean

" To completely remove IDE Helper (package + files)
:LaravelRemoveIdeHelper
```

The plugin will automatically detect when IDE Helper is installed and provide enhanced completions!

> **Note**: The plugin will no longer show automatic prompts on startup. Use `:LaravelIdeHelperCheck` to manually check if files need to be generated.

**Disable default keymaps (to create custom ones):**

```lua
require("laravel").setup({
    keymaps = false, -- Disable all default keymaps
})

-- Then create your own custom keymaps
vim.keymap.set('n', '<leader>a', ':Artisan<CR>')
vim.keymap.set('n', '<leader>c', ':Composer<CR>')
vim.keymap.set('n', '<leader>gc', function()
    require('laravel.navigate').goto_controller()
end)
```

### Completion Engine Integration

#### For [blink.nvim](https://github.com/saghen/blink.nvim) users:

```lua
{
    "saghen/blink.nvim",
    opts = {
        sources = {
            default = { "laravel", "lsp", "path", "snippets", "buffer" },
            providers = {
                laravel = {
                    name = "laravel",
                    module = "laravel.blink_source",
                },
            },
        },
    },
}
```

#### For [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) users:

```lua
require('cmp').setup({
    sources = cmp.config.sources({
        { name = 'laravel' },
        { name = 'nvim_lsp' },
        { name = 'buffer' },
    })
})
```

## 🚀 Usage Examples

### Navigation with `gd` or `:LaravelGoto`

#### Route Navigation

```php
// In your controller
Route::get('/dashboard', function () {
    return view('dashboard'); // Press 'gd' or run :LaravelGoto on 'dashboard'
});

// Press 'gd' or run :LaravelGoto on route name to jump to route definition
return route('dashboard'); // → routes/web.php
```

#### View Navigation

```php
// Blade templates
return view('users.index'); // → resources/views/users/index.blade.php
return view('auth.login'); // → resources/views/auth/login.blade.php

// Inertia components
return Inertia::render('Dashboard'); // → resources/js/Pages/Dashboard.tsx
return Inertia::render('users/show'); // → resources/js/Pages/users/show.tsx
```

#### Configuration Navigation

```php
// Navigate to config files
$name = config('app.name'); // → config/app.php (to 'name' key)
$driver = config('database.default'); // → config/database.php
```

#### Translation Navigation

```php
// Navigate to language files
$message = __('auth.failed'); // → lang/en/auth.php
$welcome = trans('messages.welcome'); // → lang/en/messages.php
```

#### Environment Variable Navigation

```php
// Navigate to .env file
$name = env('APP_NAME'); // → .env file (to APP_NAME line)
$debug = env('APP_DEBUG'); // → .env file (to APP_DEBUG line)
```

#### Controller Navigation

```php
// Navigate to controller classes
Route::get('/users', UserController::class); // → app/Http/Controllers/UserController.php

// Navigate to controller methods in Route::controller() groups
Route::controller(ImportController::class)->group(function () {
    Route::get('/import', 'index');   // Press 'gd' on 'index' → ImportController::index()
    Route::post('/import', 'submit'); // Press 'gd' on 'submit' → ImportController::submit()
});
```

### Autocompletion Examples

#### Route Completion

```php
// Type 'route(' and get completions for:
route('dashboard')     // ← Auto-completed from routes/web.php
route('users.index')   // ← From named routes
route('api.users.show') // ← API routes included
```

#### View Completion

```php
// Type 'view(' and get completions for:
view('dashboard')        // ← From resources/views/dashboard.blade.php
view('users.index')      // ← From resources/views/users/index.blade.php
view('auth.login')       // ← Nested directories supported

// Inertia completion
Inertia::render('Dashboard')    // ← From resources/js/Pages/Dashboard.tsx
Inertia::render('users/Show')   // ← Nested components
```

#### Config Completion

```php
// Type 'config(' and get completions for:
config('app.name')           // ← From config/app.php
config('database.default')   // ← From config/database.php
config('mail.mailers.smtp')  // ← Nested keys supported
```

#### Translation Completion

```php
// Type '__(' and get completions for:
__('auth.failed')        // ← From lang/en/auth.php
__('validation.required') // ← From lang/en/validation.php
trans('messages.welcome') // ← Custom translation files
```

#### Environment Variable Completion

```php
// Type 'env(' and get completions for:
env('APP_NAME')          // ← From .env file
env('DB_CONNECTION')     // ← Database configuration
env('MAIL_MAILER')       // ← Mail configuration
```

#### Laravel IDE Helper Integration

With [barryvdh/laravel-ide-helper](https://github.com/barryvdh/laravel-ide-helper) installed, you get enhanced completions for:

##### Facade Method Completion

```php
// Type 'DB::' and get completions for:
DB::table('users')       // ← Database methods
DB::connection()         // ← Connection methods
DB::transaction()        // ← Transaction methods

// Other facades work too:
Cache::get()             // ← Cache methods
Auth::user()             // ← Authentication methods
Storage::disk()          // ← Storage methods
```

##### Container Binding Completion

```php
// Type 'app(' and get completions for:
app('auth')              // ← From container bindings
app('cache')             // ← Service container
app('config')            // ← Configuration service
resolve('custom.service') // ← Custom bindings
```

##### Fluent Migration Methods

```php
Schema::create('users', function (Blueprint $table) {
    $table->id();            // ← Auto-completion after $table->
    $table->string('name');  // ← Column types
    $table->nullable();      // ← Column modifiers
    $table->index();         // ← Index methods
});
```

> **Note**: To enable IDE Helper completions, install the package:
>
> ```bash
> composer require --dev barryvdh/laravel-ide-helper
> ```
>
> Then run `:LaravelIdeHelper all` to generate the helper files.

### Composer Management Examples

#### Interactive Package Installation

```vim
:ComposerRequire
" ↓ Plugin prompts for package name
" Package name: laravel/horizon
" ↓ Plugin prompts for version (optional)
" Version constraint (optional): ^5.0
" ↓ Plugin prompts for dev dependency
" Install as dev dependency? (y/N): n
" ↓ Runs: composer require laravel/horizon:^5.0
```

#### Interactive Package Removal

```vim
:ComposerRemove
" ↓ Plugin shows fuzzy finder with installed packages
" Select package to remove:
" > laravel/horizon
"   phpunit/phpunit
"   spatie/laravel-ray
" ↓ Runs: composer remove laravel/horizon
```

#### Direct Composer Commands

```vim
:Composer install              " Install dependencies
:Composer update               " Update all packages
:Composer dump-autoload        " Regenerate autoloader
:Composer show                 " List installed packages
:Composer outdated             " Show outdated packages
:Composer validate             " Validate composer.json
```

#### Dependencies Visualization

```vim
:ComposerDependencies
" ↓ Opens buffer showing dependency tree:
" laravel/framework v10.0.0
" ├── doctrine/inflector (^2.0)
" ├── dragonmantank/cron-expression (^3.0)
" ├── egulias/email-validator (^3.0)
" └── ...
```

### File Creation Examples

When you navigate to a non-existent view, you'll be prompted to create it:

```php
// Navigate to non-existent view
return Inertia::render('onboarding/welcome');
// ↓ Plugin detects missing file and prompts:
// "Create React TypeScript view onboarding/welcome? (y/N)"
```

The plugin will:

1. **Detect your frontend stack** (React, Vue, Svelte, TypeScript)
2. **Suggest multiple options**:
   - `resources/views/onboarding/welcome.blade.php` (Blade)
   - `resources/js/Pages/onboarding/welcome.tsx` (React TypeScript)
   - `resources/js/Pages/Onboarding/Welcome.tsx` (Capitalized)
3. **Create empty files** with proper extensions
4. **Create directories** if they don't exist

## 📋 Commands

### Core Commands

| Command          | Description                     | Example                                   |
| ---------------- | ------------------------------- | ----------------------------------------- |
| `:Artisan`       | Run Laravel Artisan commands    | `:Artisan make:controller UserController` |
| `:Composer`      | Run Composer commands           | `:Composer install`                       |
| `:LaravelMake`   | Interactive make command picker | `:LaravelMake`                            |
| `:LaravelRoute`  | Show all application routes     | `:LaravelRoute`                           |
| `:LaravelStatus` | Check plugin status             | `:LaravelStatus`                          |

### Composer Commands

| Command                  | Description                    | Example                            |
| ------------------------ | ------------------------------ | ---------------------------------- |
| `:Composer [command]`    | Run any Composer command       | `:Composer update`                 |
| `:ComposerRequire [pkg]` | Interactive package require    | `:ComposerRequire laravel/horizon` |
| `:ComposerRemove [pkg]`  | Interactive package removal    | `:ComposerRemove phpunit/phpunit`  |
| `:ComposerDependencies`  | Show project dependencies tree | `:ComposerDependencies`            |

### Laravel Sail Commands

| Command           | Description                  | Example                |
| ----------------- | ---------------------------- | ---------------------- |
| `:Sail [command]` | Run any Sail command         | `:Sail php --version`  |
| `:SailUp`         | Start Sail containers        | `:SailUp -d`           |
| `:SailDown`       | Stop Sail containers         | `:SailDown`            |
| `:SailRestart`    | Restart Sail containers      | `:SailRestart`         |
| `:SailTest`       | Run tests through Sail       | `:SailTest --parallel` |
| `:SailShare`      | Share application via tunnel | `:SailShare`           |
| `:SailShell`      | Open shell in container      | `:SailShell`           |
