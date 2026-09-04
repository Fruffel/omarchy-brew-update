# Homebrew update

Bar widget for Omarchy Quattro that checks Homebrew for outdated packages,
upgrades them in one click, and runs a quiet upgrade when the desktop starts.

Homebrew is invoked as your user against a writable linuxbrew prefix. After
setup, no sudo password is required.

## Install

```sh
omarchy plugin add https://github.com/Fruffel/omarchy-brew-update.git --enable
~/.config/omarchy/plugins/fruffel.brew-update/scripts/setup
```

## Usage

- The beer icon stays in the bar. A count appears next to it when packages are outdated.
- Left click opens the package list. **Update all** upgrades headlessly in
  the background and notifies when done (button shows a spinner meanwhile).
- Middle click upgrades immediately.
- Right click refreshes the list.
- Super menu → **Update → Homebrew** also launches the upgrader.

A post-boot hook upgrades packages quietly after the desktop starts and only
notifies when something actually changed.

## Configure

Values live on the bar entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
| --- | --- | --- |
| `pollMinutes` | `30` | How often to run `brew update` + `brew outdated` |
| `upgradeOnStart` | `true` | Quiet upgrade ~45s after the shell starts |
| `showWhenCurrent` | `true` | Keep the icon visible when everything is current |
| `includeCasks` | `true` | Include Homebrew casks |
| `greedyCasks` | `false` | Also upgrade auto-updating casks |
| `notifications` | `false` | Send desktop notifications (`omarchy bar set fruffel.brew-update notifications true` to opt in) |

```sh
omarchy bar set fruffel.brew-update pollMinutes 15
omarchy bar move fruffel.brew-update --section center --after omarchy.clock
```

## Setup / no sudo

Linuxbrew only needs write access to its prefix (`/home/linuxbrew/.linuxbrew`
on this machine). The setup script checks that and installs the post-boot hook.

If the prefix is owned by root, run this **once** in a terminal:

```sh
sudo chown -R "$(whoami):" "$(brew --prefix)"
~/.config/omarchy/plugins/fruffel.brew-update/scripts/setup
```

Background jobs set `SUDO_ASKPASS` to a helper that fails immediately, so a
stray `sudo` cannot hang the bar waiting for a password.

## Remove

```sh
omarchy plugin disable fruffel.brew-update
rm -f ~/.config/omarchy/hooks/post-boot.d/brew-update
```
