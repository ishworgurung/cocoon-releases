# 🔧 Troubleshooting

Find the message you got, then follow the fix. **Start with `cocoon --doctor`**: it tests the host-side causes below and prints a `fix:` for each one.

- [🚪 It won't start](#-it-wont-start): `/dev/kvm`, folder, live mode, tools, disk
- [📥 First run](#-first-run): downloads and checksums
- [🔌 Ports and attach](#-ports-and-attach)
- [🌐 Inside the VM](#-inside-the-vm): 403s, read-only root, logins
- [🧯 Stuck or odd](#-stuck-or-odd)

---

## 🚪 It won't start

### ❌ `cannot open /dev/kvm: Permission denied (os error 13)`

```
alice@isg:~$ ./cocoon
cocoon: cannot open /dev/kvm: Permission denied (os error 13)
  fix: sudo usermod -aG kvm $USER, then log in again (the group may be called differently: ls -l /dev/kvm)
  `cocoon --doctor` checks the rest of this host
```

Your user isn't allowed to use KVM. Add yourself to the group that owns the device:

```sh
ls -l /dev/kvm                # who owns it? usually: crw-rw---- root kvm
sudo usermod -aG kvm $USER    # use the group name you saw above, if it isn't kvm
```

Then **log out and back in** (a new terminal is not enough), or run `newgrp kvm` in the current one. Check with `id`: it must list `kvm`.

### ❌ `/dev/kvm does not exist`

The machine has no KVM, and a VM can't start without it.

- **On your own computer:** turn on virtualization (Intel VT-x / AMD-V) in the BIOS or UEFI, then `sudo modprobe kvm_intel` (or `kvm_amd`). `lscpu | grep -i virtualization` shows whether the CPU has it.
- **Inside a virtual machine:** the host must enable *nested virtualization* for it. Most cloud VMs and CI runners don't: use a bare-metal instance, or a machine that does.
- **Not Linux, or not x86_64?** cocoon needs Linux on x86_64 (arm64 is not released yet).

### ❌ `/dev/kvm answered -1, not API 12`

Something is at `/dev/kvm` but it isn't a working KVM. Update the kernel, and check `ls -l /dev/kvm` shows a character device (`crw-…`).

### ❌ `not copying /home/alice onto /workspace by default…`

```
alice@isg:~$ ./cocoon
cocoon: not copying /home/alice onto /workspace by default: run cocoon in a project folder, or name one with -W DIR (COCOON_WORKSPACE= for an empty /workspace)
```

You ran it from your home directory (or `/`). That is refused on purpose: it would give the agent everything you own.

> 🔀 **Did you pass `-W`?** `cocoon -c -W code` gives this same error. **cocoon's own switches (`-W`, `-P`) must come first**: the first thing cocoon
> doesn't recognise (here `-c`) starts Claude Code's part, so a later `-W code` went to Claude and cocoon used your current directory.
> Write it as `cocoon -W code -c`. Newer versions stop with `you typed: … / write it as: …` and show the corrected command.

Either:

```sh
cd ~/code/my-project && cocoon          # run it in a project folder
cocoon -W ~/code/my-project             # or name one
COCOON_WORKSPACE= cocoon                # or start with an empty /workspace
```

### ❌ `live mode cannot set up virtiofsd's sandbox here: Permission denied (os error 13)`

Live mode shares your folder through a helper that needs an unprivileged *user namespace* it can mount in. **Ubuntu 24.04 and later** let programs create one but then refuse the mount. Two ways out:

```sh
# Option A: allow it (machine-wide; persists across reboots)
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/60-cocoon-userns.conf

# Option B: use copy mode, which needs none of this: set  mode = "copy"  in ~/.config/cocoon/cocoon.toml
```

On Debian: `sudo sysctl kernel.unprivileged_userns_clone=1`. If it says `No space left on device (os error 28)`, `user.max_user_namespaces` is `0`: raise it.

### ❌ `mkfs.ext4 is not on PATH` / `debugfs is not on PATH`

Install e2fsprogs:

```sh
sudo apt install e2fsprogs      # Debian, Ubuntu
sudo dnf install e2fsprogs      # Fedora
sudo pacman -S e2fsprogs        # Arch
```

### ❌ `disk space  3.9 GB free for sessions`

`--doctor` wants about 4 GB free where cocoon keeps its sessions (`~/.cache/cocoon`). Free some space, or put cocoon's files on a bigger disk with `COCOON_HOME=/path/short`. A VM's scratch disk is 8 GiB *sparse* (only what is written takes space); lower it with `scratch_mib` in the config.

### ❌ `…: too long for a Unix socket; use a shorter COCOON_HOME`

Sockets live in the session directory, and Unix socket paths are limited to 107 bytes. Use a short location: `COCOON_HOME=~/.cc cocoon`.

### ❌ `[vm] has unknown keys …` / `[network] allow: … is not "host" or "host:port"`

A mistake in `~/.config/cocoon/cocoon.toml`. The message names the key; fix it. Or delete the file, and cocoon writes the defaults again on the next run.

---

## 📥 First run

### 🐢 It's slow, or looks stuck on `📦 unpacking…` / `📥 downloading Claude Code…`

The first run unpacks a ~1.3 GB VM image (sparse on disk) and downloads Claude Code (~146 MB) from npm. About 10 seconds on a fast connection, longer on a slow one. It only happens once.

### ❌ `Claude Code … does not match its pinned SHA-512`

cocoon refused a Claude Code download that isn't the exact file this binary was built to expect. **Don't work around it.** Try again (a proxy or captive portal may have served a different page); if it persists, report it.

### ❌ The download fails

The first run needs to reach `registry.npmjs.org`. Behind a corporate proxy, set `HTTPS_PROXY` for the run. Check you're online: `curl -I https://registry.npmjs.org/`.

---

## 🔌 Ports and attach

### ❌ `listening on 127.0.0.1:3000 (in use?)`

Something on your machine already uses that port. Pick another host port: `cocoon -P 8080:3000`.

### ❌ `no running cocoon VM in …`

`cocoon --attach` needs a VM that is running. Start one in another terminal first. It looks in the same place as the VM was started with: if you used `COCOON_HOME`, set it for `--attach` too.

### ❌ `the VM refused the connection`

The VM is not ready to take connections yet. Wait until the boot screen has finished and Claude Code (or the shell) is up, then try again.

---

## 🌐 Inside the VM

### 🚫 `403` or `Received HTTP code 403 from proxy after CONNECT`

The site isn't on the allowlist. That is the sandbox working. Check the proxy log at the end of the session (or `/tmp/cc-lab-*.log`), then add the host to `allow` in the config. See [what the VM can reach](USAGE.md#-what-the-vm-can-reach).

### 🔒 `apk add: Unable to open log: Read-only file system`

The VM's root is read-only by design. Use user-level installs (`pip install --user`, `npm install`, `cargo install`): they work and vanish at exit. The image already has bash, git, gh, ssh, ripgrep, fd, jq, vim, Python, Node, gcc/g++, make and headless Chromium.

### 💳 `Credit balance too low`, or the header says `API Usage Billing`

You have an Anthropic **API key** saved, and API billing is separate from a Claude subscription. Remove it with `cocoon --api-key` (empty answer), then log in with `/login` or `cocoon --oauth-token`. See [logging in](USAGE.md#-logging-in).

### 🔑 Asked to log in every time

Check `[claude] persist` is `true` in the config. A login made with `/login` is only kept if it is. Saved API keys and tokens (`cocoon --api-key`, `--oauth-token`) are kept either way.

### 🐢 My project is slow in live mode

Small files over the shared folder are 3–10× slower than on a disk, especially `node_modules` and build output. Use `mode = "copy"`, or keep those directories out of the shared folder.

---

## 🧯 Stuck or odd

### 🧊 It hangs after pressing Ctrl-D twice on the login screen

A known issue: Claude Code's exit doesn't finish there. From **another terminal**, stop cocoon; it cleans up after itself:

```sh
pkill -TERM -x cocoon
```

### 🧹 Did a crashed session leave anything behind?

Look in `~/.cache/cocoon/sessions/`. A directory there with no running VM is safe to delete: `rm -rf ~/.cache/cocoon/sessions/cc-lab-XXXXXX`. A `seed.ext4` inside it may contain your credentials, so remove it rather than leave it.

### 🖥️ The screen is garbled after quitting

Run `reset`. Resizing the window while the VM runs is supported; the VM's console follows it.

### 📋 Still stuck?

Run `cocoon --doctor` and keep the session log (`/tmp/cc-lab-XXXXXX.log`; it has no credentials). Open an issue in this repository with both.
