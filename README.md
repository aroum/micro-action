# action plugin for micro editor

The `action` plugin allows you to save and execute commands (runners, debuggers, formatters) depending on the active buffer's filetype or absolute path. It supports interactive selection via FZF, customizable parameters per action, file placeholders, silent background execution, and running commands in an embedded terminal split.

![banner](pisc/banner.png)

---

## Key Features

### 1. Context-Aware Runner Configurations
* **Filetype Actions:** Define a list of commands specific to filetypes (e.g., run Python, build Go, lint JavaScript) under `"action-filetypes"`.
* **Per-File Overrides:** Define file-specific overrides or extensions under `"action-files"` based on absolute path matching or wildcards (glob patterns).

### 2. Flexible Shell Execution Modes
* **Interactive Terminal Split:** Run commands in an embedded terminal emulator split horizontally at the bottom (`runInBuiltinTerm`), keeping you in the editor context.
* **Silent Background Execution:** Execute tasks silently in the background (`runSilent`). If a command fails, the error output is shown on the InfoBar; if it succeeds, a notification is displayed.
* **Standard Interactive Shell:** Run interactive tools directly in the system shell (default fallback).

### 3. Automated Editor Workflows
* **Save Before Run:** Automatically saves the active buffer before running the command (`saveBeforeRun`), ensuring your latest changes are always built or executed.
* **Reload After Run:** Automatically reloads the buffer from disk after the command exits (`reloadAfterRun`). This is perfect for formatters/linter auto-fixes (e.g., `ruff`, `prettier`, `goimports`).
* **Trigger on Save:** Automatically executes actions when saving the buffer (`runOnSave`).

### 4. Dynamic Path Placeholders
Use the following placeholders inside command strings for dynamic path substitution:
* `{file}`: Absolute path to the current file (e.g., `/home/user/project/main.py`).
* `{stem}`: Filename without its extension (e.g., `main`).
* `{dir}`: Directory containing the current file (e.g., `/home/user/project`).

### 5. Smart "Rerun Last" Target
* The `actionlast` command remembers the last selected command to rerun it instantly (e.g., bound to `F5`). Direct runs via hotkey bindings or command lines do not update this rerun target, allowing you to rerun your primary task while running other actions manually.

### 6. FZF Session Persistence
* **Stay Open:** Set the global option `actionFzfStay` to `true` to keep the FZF menu open after running a command, allowing you to execute multiple commands in sequence.

## Installation

Add the repository `repo.json` link to your `settings.json` file:

```json
"pluginrepos": [
    "https://raw.githubusercontent.com/aroum/micro-action/main/repo.json"
]
```

Then install the plugin by running:

```bash
> plugin install action
```

To view the help page inside the editor, run:

```bash
> help action
```

### Dependencies

This plugin requires or integrates with the following tools:

* **`fzf`** (Mandatory): Required for selecting and searching configured actions.

## Commands & Keybindings

* **`actionpick`**
  Open the FZF selection menu containing all actions configured for the current buffer. Choosing an action here runs it and saves it as the rerun target for `actionlast`.
  
* **`actionlast`**
  Re-run the last action selected from the FZF menu. When triggered, it prints what is running to the InfoBar. If no action has been selected yet, it runs the first alphabetically.

* **`actionrun <action-name>`**
  Run a specific action directly by name (e.g., from the command line or from custom keybindings) without updating the `actionlast` target.

### Example Keybindings (`bindings.json`)

```json
{
    "F5": "command:actionlast",
    "Ctrl-F5": "command:actionpick",
    "Alt-x": "command:actionrun \"format (ruff)\""
}
```

## Settings 

All parameters for the `action` plugin can be configured inside your main `settings.json` file.

### Global Options

* **`actionFzfStay`** (boolean, default: `false`): Keep the FZF window open after running a command so you can execute multiple commands sequentially.
* **`actionRunInBuiltinTerm`** (boolean, default: `false`): Default fallback value for the `runInBuiltinTerm` setting of actions if not overridden by the action itself.
* **`fzfcmd`** (string, default: `"fzf"`): Custom command or path to run FZF.

### Action Configuration Parameters

Each action configured under `"action-filetypes"` or `"action-files"` is defined as an object with the following properties:

* **`cmd`** (string, required): The shell command to execute. Supports `{file}`, `{stem}`, and `{dir}` placeholders.
* **`saveBeforeRun`** (boolean, default: `true`): Saves the active buffer before running the command.
* **`reloadAfterRun`** (boolean, default: `false`): Reloads the buffer from disk after the command exits.
* **`runInBuiltinTerm`** (boolean, default: `false`): Runs the command inside an embedded terminal emulator split horizontally at the bottom. If not set, falls back to the global option `actionRunInBuiltinTerm`.
* **`runSilent`** (boolean, default: `false`): Runs the command in the background. If the command succeeds, a success message is shown. If it fails, the error output is shown.
* **`runOnSave`** (boolean, default: `false`): Automatically triggers this action whenever you save the buffer.

### Example Configuration (`settings.json`)

```json
{
    "actionFzfStay": false,
    "actionRunInBuiltinTerm": false,
    "action-filetypes": {
        "python": {
            "run": {
                "cmd": "python3 {file}",
                "saveBeforeRun": true
            },
            "format (ruff)": {
                "cmd": "ruff format {file}",
                "saveBeforeRun": true,
                "reloadAfterRun": true,
                "runSilent": true
            },
            "lint": {
                "cmd": "ruff check {file}",
                "runSilent": true
            }
        },
        "go": {
            "run": {
                "cmd": "go run {file}",
                "runInBuiltinTerm": true
            },
            "build": {
                "cmd": "go build -v",
                "runInBuiltinTerm": true
            }
        }
    },
    "action-files": {
        "/home/user/project/config.toml": {
            "mode": "extend",
            "actions": {
                "reload app": {
                    "cmd": "systemctl --user restart myapp",
                    "saveBeforeRun": true,
                    "runSilent": true
                }
            }
        }
    }
}
```

* **`mode`**: `"extend"` (merges/overwrites matching keys) or `"override"` (ignores all filetype actions, using only these file-specific actions).
