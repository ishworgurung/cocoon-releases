# 📖 cocoon usage guide

Everything you can do with `cocoon`, in the order you'll want it. New here? Start with the [README](../README.md).

- [🧭 The commands](#-the-commands)
- [🔑 Logging in](#-logging-in)
- [📁 Live or copy: your folder or a throwaway copy](#-live-or-copy-your-folder-or-a-throwaway-copy)
- [🌐 What the VM can reach](#-what-the-vm-can-reach)
- [🔌 Ports and a second terminal](#-ports-and-a-second-terminal)
- [⚙️ The config file](#️-the-config-file)
- [🌱 Environment variables](#-environment-variables)
- [🗂️ Where cocoon keeps things](#️-where-cocoon-keeps-things)
- [📜 After a session: the log](#-after-a-session-the-log)

## 🧭 The commands

```text
cocoon [-W DIR] [-P PORT]... [CLAUDE ARGS...]   Claude Code in a VM
cocoon [-W DIR] [-P PORT]... shell              a shell in a VM instead
cocoon -a|--attach [NAME]                       another shell in a running VM
cocoon --doctor                                 check this host for what cocoon needs
cocoon --api-key                                save an Anthropic API key for every session
cocoon --oauth-token                            save a Claude subscription token (claude setup-token)
cocoon -h|--help
```

| Switch | What it does |
| --- | --- |
| `-W`, `--workspace DIR` | the folder that becomes `/workspace`. Default: `$COCOON_WORKSPACE`, else the **current directory**. Never your home directory or `/` unless you name it |
| `-P`, `--port PORT` | reach the VM's `localhost:PORT` at your `127.0.0.1:PORT`. `-P 8080:3000` uses host port 8080. Repeat for more |
| `-a`, `--attach [NAME]` | a new login shell in a **running** VM: the newest, or the one whose session name contains `NAME`. `exit` detaches |
| `shell` | a login shell instead of Claude Code. Run `claude` there yourself |
| `--doctor` | checks KVM, e2fsprogs, user namespaces, config and disk space, and says how to fix each failure. Exit status 1 if anything fails |
| anything else | goes to Claude Code: `-c`, `-p "..."`, `-w`, `--model ...`. After `--`, *everything* does (`cocoon -- --help` shows Claude's help) |

> ⚠️ **cocoon's own switches (`-W`, `-P`) must come FIRST**, before anything meant for Claude: `cocoon -W ~/code/api -c`, **not** `cocoon -c -W ~/code/api`.
> They use **capitals** where Claude uses the letter, so Claude's `-w` and `-p` still reach Claude. After `--`, everything goes to Claude.
> `cocoon --version` shows *Claude Code's* version.

### The boot menu

On a terminal, cocoon shows a short menu before starting: **Claude Code** or **Shell**. It boots the highlighted
entry after 5 seconds. `Enter` boots now, `↑`/`↓` (or `j`/`k`, `1`/`2`) choose, any key stops the countdown, `q` or `Ctrl-C` cancels.
Skip it with `COCOON_MENU_SECONDS=0`. Without a terminal (a script, a pipe) there is no menu and no wait.

### Everyday examples

```sh
cd ~/code/api && cocoon                       # 🤖 Claude Code on this project
cocoon -c                                     # ↩️ continue this folder's last conversation
cocoon -p "explain the build, then fix it"    # 💬 one-shot, then the VM stops
cocoon shell                                  # 🐚 poke around yourself
cocoon -P 3000                                # 🌐 dev server on :3000 in the VM → http://127.0.0.1:3000
cocoon -W ~/code/other --model opus           # 📁 another folder, a Claude option
```

Resizing your terminal resizes the VM's console too, so full-screen Claude Code redraws correctly.

## 🔑 Logging in

Claude Code in the VM needs a login, and you only do it once. Pick the row that matches how you pay for Claude:

| You have | Do this, once | What is saved |
| --- | --- | --- |
| A **Claude subscription** (Pro, Max, Team, Enterprise) and a browser | Start `cocoon`, run `/login` inside, open the link it prints | Claude Code's own login, in `~/.local/share/cocoon/` |
| A **Claude subscription**, no browser on this machine | On any machine with Claude Code run `claude setup-token`; here run `cocoon --oauth-token` and paste the token | `~/.config/cocoon/oauth-token` (mode 0600) |
| An **Anthropic API key** (Console, pay per use) | `cocoon --api-key` and paste the key | `~/.config/cocoon/api-key` (mode 0600) |

⚠️ **A paid claude.ai plan is not API credit.** An API key (`sk-ant-api…`) bills your *API* account, which has its own prepaid
balance and never uses your Pro, Max, Team or Enterprise plan. If you pay for claude.ai and Claude Code's header says
`API Usage Billing`, or you see `Credit balance too low`, you are using an API key: remove it with `cocoon --api-key`
(answer with an empty line) and log in with `/login` or `cocoon --oauth-token` instead. **A saved API key takes priority** over a subscription login.

- `--api-key` and `--oauth-token` read the secret without echoing it (or from a pipe: `pass show anthropic | cocoon --api-key`). Run again to replace; an empty answer removes it.
- **For one run only**, set `COCOON_ANTHROPIC_API_KEY` or `COCOON_CLAUDE_CODE_OAUTH_TOKEN` in your shell. An `ANTHROPIC_API_KEY` already in your shell is **ignored**, so a key you use for something else never leaks in.
- The secrets are **not encrypted** on disk; they are protected by file mode, like `~/.ssh` keys. They reach the VM on a throwaway disk that is deleted at exit, never on a command line.
- The boot screen's `🔑 login` line says which logins this session has.

cocoon also keeps Claude Code's settings and each folder's conversations between sessions (so `cocoon -c` works), in `~/.local/share/cocoon/`. Turn that off with `[claude] persist = false`.

## 📁 Live or copy: your folder or a throwaway copy

`[workspace] mode` in the config decides how the project reaches the VM.

| | **live** (default) | **copy** |
| --- | --- | --- |
| The agent works on | **your folder itself** | a copy on a disk of its own |
| Your edits and the agent's | each sees the other's at once | independent |
| A mistake (`rm -rf`) | **real** | harmless until you apply it |
| Speed on many small files | slower (3–10× on `node_modules`) | native disk speed |
| At exit | nothing to do: changes are already there | cocoon lists what changed and asks |

### 🪞 Copy mode, step by step

Set `mode = "copy"` in `~/.config/cocoon/cocoon.toml`. When the VM stops cleanly, cocoon reads the copy back and compares three versions
of every file: how your folder **began**, how it is **now**, and what the agent left:

```
  workspace changes: 1 added, 1 changed, 1 deleted
    + added.txt
    ~ edit.txt
    - gone.txt
  apply these to /home/alice/code/api? [y/N]
```

- `+` added, `~` changed, `-` deleted, `!` a **conflict**: you and the agent both changed it, so it is left alone.
- **Files you edited meanwhile are never reverted.**
- A symlink the agent made that points outside the folder is flagged with `⚠`.
- **y** applies the changes. **N**, no terminal, or a conflict keeps the agent's whole `/workspace` in `~/.cache/cocoon/sessions/<id>/result/` for you to inspect.
- A VM that did not shut down cleanly discards the copy. `COCOON_KEEP=1` keeps the disk image.

With `COCOON_WORKSPACE=` (empty) you get an empty `/workspace` of its own, in either mode.

## 🌐 What the VM can reach

The VM has **no network card**. Everything it sends goes through a proxy on your host, which allows only what the config lists and
logs every request. Out of the box:

| Allowed | For |
| --- | --- |
| `api.anthropic.com`, `*.anthropic.com`, `platform.claude.com`, `*.claude.ai` | Claude Code |
| `github.com`, `api.github.com`, `*.github.com`, `*.githubusercontent.com`, `github.com:22` | git (HTTPS and SSH), `gh`, release downloads |
| `registry.npmjs.org` | npm |
| `pypi.org`, `files.pythonhosted.org` | pip |
| `crates.io`, `*.crates.io`, `*.rustup.rs`, `*.rust-lang.org` | cargo and rustup |

Anything else gets a **`403`** and a red line in the session's proxy log. To allow another site, add it to `allow` in the config:

```toml
[network]
allow = [
    "api.anthropic.com",
    # ...the rest of the defaults...
    "example.com",          # "host" means port 443
    "*.example.org",        # every name under it (not example.org itself: list that too)
    "git.example.com:22",   # "host:port"
]
```

`allow_all = true` lets the VM reach **any public address**. Even then, loopback, your LAN, link-local and cloud-metadata
addresses (`169.254.169.254`) stay blocked, because the proxy runs on your host. Widen the list only when you mean to.

The root file system is read-only: `apk add` can't work. User-level installs (`pip install --user`, `npm i`, `cargo install`) go to the
VM's scratch disk and vanish at exit.

## 🔌 Ports and a second terminal

- **`-P 3000`** (or `[ports] forward = [3000]`) makes a server on the VM's `localhost:3000` reachable at your `http://127.0.0.1:3000`.
  Only your own machine can reach it. `-P 8080:3000` maps host port 8080 to VM port 3000. A server bound to `localhost` inside needs no change.
- **`cocoon --attach`** from another terminal opens a **second shell** in the running VM, on its own terminal. With several VMs running it picks the newest;
  `cocoon --attach NAME` picks the one whose session name (`cc-lab-XXXXXX`) contains `NAME`.

## ⚙️ The config file

`~/.config/cocoon/cocoon.toml` is written with the defaults on first run. Another file: `COCOON_CONFIG=PATH`. Mistakes are reported with the
key and the file, before any VM starts.

```toml
[vm]
vcpus = 4          # 1 to 32
memory_mib = 4096  # at least 1024
disk_mib = 4096    # free space on /workspace in copy mode
scratch_mib = 8192 # the VM's /root and /tmp: sparse, discarded every session

[workspace]
mode = "live"      # or "copy"

[claude]
persist = true     # keep /login, settings and conversations between sessions

[ports]
forward = []       # for example [3000, "8080:5173"]

[network]
allow_all = false
allow = [ "api.anthropic.com", "github.com", "registry.npmjs.org" ]   # plus the rest of the defaults
```

Memory is mapped lazily: the host pays only for the pages the VM touches.

## 🌱 Environment variables

| Variable | What it does |
| --- | --- |
| `COCOON_ANTHROPIC_API_KEY` | an Anthropic API key for this run only (beats the saved one) |
| `COCOON_CLAUDE_CODE_OAUTH_TOKEN` | a Claude subscription token for this run only |
| `COCOON_WORKSPACE=DIR` | as `-W DIR`; `COCOON_WORKSPACE=` (empty) gives an empty `/workspace` |
| `COCOON_KEEP=1` | keep the session's work directory, including the copy-mode disk image |
| `COCOON_CONFIG=PATH` | use another config file |
| `COCOON_HOME=DIR` | keep config, cache, sessions and state under one directory (keep the path **short**) |
| `COCOON_MENU_SECONDS=N` | boot menu countdown; `0` skips the menu |
| `COCOON_NO_COLOR=1` (or `NO_COLOR`) | no colours in cocoon's output |

## 🗂️ Where cocoon keeps things

| Path | What is there |
| --- | --- |
| `~/.config/cocoon/cocoon.toml` | the config |
| `~/.config/cocoon/api-key`, `oauth-token` | saved credentials (mode 0600) |
| `~/.local/share/cocoon/` | Claude Code's saved login, settings and each folder's conversations |
| `~/.cache/cocoon/` | the unpacked VM (about 1.3 GB, sparse), Claude Code's disk, and running sessions |
| `/tmp/cc-lab-XXXXXX.log` | each session's log |

Respects `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `XDG_CACHE_HOME`.

## 📜 After a session: the log

Each session ends with the **proxy log** (every destination the VM asked for, refusals in red 🟥) and the **VM's metrics** (disk I/O, CPU time, peak memory, errors).
The same text, without colours, is written to `/tmp/cc-lab-XXXXXX.log` (readable only by you, no credentials), and the path is printed at the end.

## 🆘 Something went wrong?

See the [troubleshooting guide](TROUBLESHOOTING.md): it lists the error messages you may meet on day one and what to do about each.
