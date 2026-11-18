# 🦋 cocoon

**Claude Code in a microVM.** cocoon runs [Claude Code](https://www.anthropic.com/claude-code)
inside a small virtual machine on your own Linux box, so the agent gets a real
kernel, real tools and a project folder, and **nothing else**:

- 🔒 **Rootless.** No `sudo`, no root daemon, nothing installed system-wide.
- 🚫🌐 **No network card in the VM.** Its only way out is a proxy on your host that allows
  only the sites you list (GitHub, npm, PyPI, crates.io and Anthropic out of the box) and logs every attempt.
- 📁 **Your folder, your choice.** The agent works on your project directly (*live* mode), or on a
  throwaway copy that you review before anything touches the original (*copy* mode).
- 🧰 **A real dev box inside:** bash, git, gh, ssh, ripgrep, fd, jq, vim, Python, Node, gcc, make, headless Chromium.

> This repository holds the **prebuilt binaries and the user guide**. The source is not published here.

## ✅ What you need

| | |
| --- | --- |
| 🐧 **Linux on x86_64** | arm64 is not released yet |
| ⚙️ **KVM** | read and write access to `/dev/kvm` (usually: be in the `kvm` group) |
| 🧱 **e2fsprogs** | `mkfs.ext4` and `debugfs` (installed on nearly every distribution) |
| 💾 **~4 GB free disk** | for the first run; sessions use more while they run |
| 🧠 **~4 GB free memory** | per session (adjustable) |
| 🌐 **Internet on the first run** | to fetch Claude Code from npm (checked against a pinned SHA-512) |
| 🔑 **A Claude login** | a subscription (Pro, Max, Team, Enterprise) or an Anthropic API key |

You do **not** need root, Docker or any package other than e2fsprogs.

## 📦 Install

**One line** (downloads the binary, checks its SHA-256, puts it in `~/.local/bin`; it never edits your shell profile):

```sh
curl -fsSL https://raw.githubusercontent.com/ishworgurung/cocoon-releases/main/install.sh | bash
```

Prefer to read it first? [install.sh](install.sh) is short. Or do it by hand:

```sh
B=https://github.com/ishworgurung/cocoon-releases/releases/latest/download   # or .../releases/download/vX.Y.Z for a specific version
curl -fsSLO $B/cocoon-x86_64
curl -fsSLO $B/SHA256SUMS
sha256sum -c SHA256SUMS                  # must say: cocoon-x86_64: OK
install -m 755 cocoon-x86_64 ~/.local/bin/cocoon
```

If `~/.local/bin` is not on your `PATH`, the installer prints the exact line to add and which file it belongs in.

## 🩺 Step 1: check your machine

```sh
cocoon --doctor
```

```
🩺 cocoon doctor
   ✅ kvm              /dev/kvm opens and answers (API 12)
   ✅ mkfs.ext4        mke2fs 1.47.2
   ✅ debugfs          debugfs 1.47.2
   ✅ user namespaces  an unprivileged user and mount namespace can be made and mounted in (live mode)
   ✅ VM pieces        compiled into this binary
   ✅ claude code      not downloaded yet: the first session fetches it from npm, checked against its pinned SHA-512
   ✅ config           ~/.config/cocoon/cocoon.toml does not exist yet; the first run writes the default
   ✅ disk space       120.0 GB free for sessions
   ✅ session log      /tmp is writable

   all 9 checks passed
```

Every ❌ comes with a `fix:` line. The most common one on a fresh machine:

```
❌ kvm   cannot open /dev/kvm: Permission denied (os error 13)
   fix: sudo usermod -aG kvm $USER, then log in again
```

Run that, **log out and back in** (or `newgrp kvm`), and check `id` lists `kvm`.
More in the [troubleshooting guide](docs/TROUBLESHOOTING.md).

## 🔑 Step 2: log in once

Pick one:

```sh
cocoon --oauth-token     # 🎫 Claude subscription: paste the token `claude setup-token` printed
cocoon --api-key         # 🗝️ Anthropic API key (pay per use)
```

or just start `cocoon` and type `/login` inside. Your login is kept between sessions
(readable only by you). Details, and the one trap about subscriptions vs API credit, are in the [usage guide](docs/USAGE.md#-logging-in).

## 🚀 Step 3: run it

```sh
cd ~/code/my-project
cocoon
```

The first run takes about 10 seconds: it writes a default config, unpacks the VM, and downloads Claude Code.
After that a VM boots in well under a second. You'll see the session summary, a 5-second boot menu
(**Enter** boots at once, `↑`/`↓` pick *Claude Code* or *Shell*), and then Claude Code is running in `/workspace`,
which is your project folder.

> ⚠️ **By default the agent edits your folder itself**, and an `rm -rf` is real. Use it on a folder under
> version control, or switch to [copy mode](docs/USAGE.md#-live-or-copy-your-folder-or-a-throwaway-copy).

Quit with `/exit` (or `exit` in the shell). The VM stops and cleans up after itself.

### 😮 "not copying /home/alice onto /workspace"

Running `cocoon` straight from your home directory (or `/`) stops on purpose, so the agent isn't handed everything you own by accident:

```
alice@isg:~$ ./cocoon
cocoon: not copying /home/alice onto /workspace by default: run cocoon in a project folder, or name one with -W DIR (COCOON_WORKSPACE= for an empty /workspace)
```

Fix: `cd` into a project folder first, or name one: `cocoon -W ~/code/my-project`.
Want a scratch VM with an empty `/workspace` instead? `COCOON_WORKSPACE= cocoon`.

## 🧭 Cheat sheet

| I want to… | Run |
| --- | --- |
| 🤖 Claude Code on this folder | `cocoon` |
| ↩️ continue the last conversation here | `cocoon -c` |
| 💬 one-shot prompt | `cocoon -p "fix the failing tests"` |
| 🐚 a shell in the VM instead | `cocoon shell` |
| 📁 another folder | `cocoon -W ~/code/other` (cocoon's `-W`/`-P` go **first**: `cocoon -W ~/code/other -c`) |
| 🌐 open a dev server from the VM in my browser | `cocoon -P 3000` → `http://127.0.0.1:3000` |
| 🔌 a second terminal into the running VM | `cocoon --attach` |
| 🩺 check this machine | `cocoon --doctor` |
| 🆘 help | `cocoon -h` |

Everything cocoon doesn't recognise goes straight to Claude Code, so `cocoon --model opus`, `cocoon -w`
and `cocoon -- --help` work as you'd expect. The full guide: [docs/USAGE.md](docs/USAGE.md).

## 🛡️ Verify what you downloaded

Every release has `SHA256SUMS`:

```sh
sha256sum -c SHA256SUMS --ignore-missing
```

Claude Code itself is proprietary and **not** inside the binary: cocoon downloads it from npm on the
first run and refuses to use it unless it matches the checksum the binary was built with.

## 🗑️ Uninstall

```sh
rm ~/.local/bin/cocoon
rm -rf ~/.cache/cocoon ~/.config/cocoon ~/.local/share/cocoon   # the VM, your settings and saved logins
```

## 📚 Guides

- 📖 [Usage guide](docs/USAGE.md): everything you can do, the config file, environment variables
- 🔧 [Troubleshooting](docs/TROUBLESHOOTING.md): the error you just hit, and its fix
