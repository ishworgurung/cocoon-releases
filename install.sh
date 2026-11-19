#!/bin/sh
# cocoon installer:
#   curl -fsSL https://raw.githubusercontent.com/ishworgurung/cocoon-releases/main/install.sh | bash
#
# What it does: downloads the cocoon binary for this machine, checks it
# against its published SHA-256, and puts it in ~/.local/bin (or
# $COCOON_INSTALL_DIR). That is all. It does not use sudo, does not edit any
# shell profile, and does not start anything; if the install directory is not
# on your PATH it prints the line to add and which file it belongs in.
#
# Settings (environment):
#   COCOON_INSTALL_DIR   where the binary goes         (default: ~/.local/bin)
#   COCOON_INSTALL_BASE  where the files are served    (default: the latest GitHub release)
#
# Served files: $BASE/cocoon-<arch> and $BASE/cocoon-<arch>.sha256, where
# <arch> is x86_64 or aarch64 and the .sha256 holds `sha256sum` output. Only
# x86_64 is released so far.
#
# POSIX sh only, so it behaves the same under bash, zsh, dash and busybox.
# Everything is inside main(), called on the last line: a download cut short
# halfway through the script then runs nothing at all.

BASE_DEFAULT="https://github.com/ishworgurung/cocoon-releases/releases/latest/download"

main() {
    set -eu

    # Colour only on a terminal; stdout is the pipe when run as above.
    if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
        B=$(printf '\033[1m'); R=$(printf '\033[31m'); Y=$(printf '\033[33m'); N=$(printf '\033[0m')
    else
        B=""; R=""; Y=""; N=""
    fi
    say()  { printf '%s\n' "$*" >&2; }
    step() { printf '%s==>%s %s\n' "$B" "$N" "$*" >&2; }
    warn() { printf '%swarning:%s %s\n' "$Y" "$N" "$*" >&2; }
    die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
    have() { command -v "$1" >/dev/null 2>&1; }

    base=${COCOON_INSTALL_BASE:-$BASE_DEFAULT}
    base=${base%/}
    # The binary runs a VM on your behalf: only fetch it over HTTPS. Plain
    # HTTP is accepted for a server on this machine, for testing.
    case $base in
        https://*) ;;
        http://127.0.0.1*|http://localhost*) ;;
        *) die "COCOON_INSTALL_BASE must be an https:// URL (got $base)" ;;
    esac

    [ "$(uname -s)" = "Linux" ] || die "cocoon runs a Linux microVM with KVM: it supports Linux hosts only (this is $(uname -s))."
    case $(uname -m) in
        x86_64|amd64)  arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) die "no cocoon build for $(uname -m)" ;;
    esac

    [ "$(id -u)" != 0 ] || warn "running as root: cocoon is meant to run as your own user, and installs into root's home here."
    [ -n "${HOME:-}" ] || die "HOME is not set"

    if have curl; then
        fetch()    { curl -fsSL --proto '=https,http' --tlsv1.2 --retry 3 -o "$2" "$1"; }
        fetch_big() {
            if [ -t 2 ]; then curl -fL --proto '=https,http' --tlsv1.2 --retry 3 -# -o "$2" "$1"
            else curl -fsSL --proto '=https,http' --tlsv1.2 --retry 3 -o "$2" "$1"; fi
        }
    elif have wget; then
        fetch()     { wget -q -O "$2" "$1"; }
        fetch_big() { wget -q -O "$2" "$1"; }
    else
        die "need curl or wget"
    fi
    if have sha256sum; then
        sha() { sha256sum "$1" | cut -d ' ' -f 1; }
    elif have shasum; then
        sha() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
    else
        die "need sha256sum (coreutils) or shasum to check the download"
    fi

    dir=${COCOON_INSTALL_DIR:-$HOME/.local/bin}
    case $dir in "~"*) dir=$HOME${dir#"~"} ;; esac
    name=cocoon-$arch
    dest=$dir/cocoon

    step "Installing cocoon ($arch) into $dir"
    mkdir -p "$dir" || die "cannot create $dir"
    [ -w "$dir" ] || die "$dir is not writable by you; set COCOON_INSTALL_DIR to a directory that is"

    # The download goes into a private directory next to its destination, not
    # into /tmp: /tmp is often a RAM disk smaller than the binary (582 MB), and
    # this way the space check below covers it and installing is a rename.
    # The directory is removed however this ends.
    tmp=$(mktemp -d "$dir/.cocoon-install.XXXXXX") || die "cannot make a temporary directory in $dir"
    trap 'rm -rf "$tmp"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP

    # The binary is about 600 MB; its first run unpacks about 2.3 GB more into
    # the cache (the root image and Claude Code's disk).
    free_kb=$(df -Pk "$dir" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "${free_kb:-}" ] && [ "$free_kb" -lt 800000 ] 2>/dev/null; then
        die "only $((free_kb / 1024)) MiB free in $dir; the download needs about 800 MiB"
    fi
    cache=${XDG_CACHE_HOME:-$HOME/.cache}
    [ -d "$cache" ] || cache=$HOME
    cache_kb=$(df -Pk "$cache" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "${cache_kb:-}" ] && [ "$cache_kb" -lt 3000000 ] 2>/dev/null; then
        warn "only $((cache_kb / 1024)) MiB free for $cache; cocoon's first run unpacks about 2.3 GiB there"
    fi

    step "Downloading $name"
    fetch "$base/$name.sha256" "$tmp/sum" || die "cannot fetch $base/$name.sha256 (no $arch build published yet?)"
    want=$(cut -d ' ' -f 1 "$tmp/sum" | head -n 1)
    case $want in
        *[!0-9a-f]*|"") die "$name.sha256 does not hold a SHA-256" ;;
    esac
    [ "${#want}" = 64 ] || die "$name.sha256 does not hold a SHA-256"
    rc=0
    fetch_big "$base/$name" "$tmp/$name" || rc=$?
    case $rc in
        0) ;;
        # curl 23 and wget 3: the download arrived but could not be written.
        23|3) die "cannot write the download into $dir: is the disk full? ($(df -Ph "$dir" | awk 'NR==2 {print $4}') free)" ;;
        *) die "cannot fetch $base/$name" ;;
    esac

    step "Checking the SHA-256"
    got=$(sha "$tmp/$name")
    [ "$got" = "$want" ] || die "the download does not match its checksum (expected $want, got $got); nothing was installed"

    # Rename into place, on the same file system: a cocoon already running
    # keeps its old file, and a failure here leaves the previous install untouched.
    chmod 0755 "$tmp/$name"
    mv -f "$tmp/$name" "$dest" || die "cannot write $dest"
    say "    installed $dest"

    path_hint "$dir"
    next_steps "$dest"
}

# Whether $1 is a directory on PATH.
on_path() {
    case ":${PATH:-}:" in *":$1:"*) return 0 ;; esac
    return 1
}

path_hint() {
    dir=$1
    # Another cocoon earlier on PATH would shadow this one.
    other=$(command -v cocoon 2>/dev/null || true)
    if [ -n "$other" ] && [ "$other" != "$dir/cocoon" ]; then
        warn "another cocoon is first on your PATH: $other"
    fi
    if on_path "$dir"; then
        return 0
    fi
    # The login shell, not the shell running this script: piped to bash, that is always bash.
    shell=$(basename "${SHELL:-sh}")
    case $shell in
        zsh)
            rc=${ZDOTDIR:-$HOME}/.zshrc
            line="export PATH=\"$dir:\$PATH\""
            ;;
        bash)
            # Login shells read .bash_profile (or .profile) first; most terminals start interactive ones.
            rc=$HOME/.bashrc
            line="export PATH=\"$dir:\$PATH\""
            ;;
        fish)
            rc=$HOME/.config/fish/config.fish
            line="fish_add_path $dir"
            ;;
        *)
            rc=$HOME/.profile
            line="export PATH=\"$dir:\$PATH\""
            ;;
    esac
    # Show $HOME rather than a literal path when the directory is under it.
    case $dir in "$HOME"/*) line=$(printf '%s' "$line" | sed "s|$HOME|\$HOME|") ;; esac
    printf '\n%s is not on your PATH.%s\n' "$B$dir" "$N" >&2
    say "To use cocoon, add this line to $rc (I did not change it):"
    printf '\n    %s\n\n' "$line" >&2
    say "then open a new terminal, or run it once in this one."
    if [ "$shell" = bash ] && [ ! -e "$HOME/.bashrc" ]; then
        say "(there is no ~/.bashrc yet; ~/.bash_profile or ~/.profile works too)"
    fi
}

next_steps() {
    dest=$1
    printf '\n' >&2
    step "Checking this machine"
    # --doctor lists what is missing (KVM access, e2fsprogs, ...) and how to fix it.
    # A build without it would pass the word on to Claude Code, so ask first.
    if "$dest" --help 2>&1 | grep -q -- '--doctor'; then
        if ! "$dest" --doctor >&2; then
            warn "cocoon --doctor found problems (above). cocoon is installed; fix them before the first run."
        fi
    else
        say "(this build has no --doctor; /dev/kvm and e2fsprogs are what it needs)"
    fi
    printf '\n%sDone.%s In a project folder:\n\n    cocoon                 Claude Code in a VM\n    cocoon shell           a shell in a VM\n    cocoon --help\n\n' "$B" "$N" >&2
    say "The first run unpacks the VM into ~/.cache/cocoon and downloads Claude Code (checked against a pinned SHA-512)."
    say "To uninstall: rm $dest; rm -rf ~/.cache/cocoon ~/.config/cocoon ~/.local/share/cocoon"
}

main "$@"
