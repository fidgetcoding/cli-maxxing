# cli-maxxing: the essence

**What it is.** One command that sets up a working Claude Code machine: Git, Node, Claude Code, shell aliases, a better terminal, dev tools, multi-agent orchestration, productivity connections, a security check and a status line. Eight steps plus a final one, and every step's safe to run twice.

**Who it's for.** People who want to work with AI tools in a terminal and have never set one up, plus people who have and don't want to spend a weekend on it again. You need a paid Claude plan to get anything out of it, and the installer tells you that before anything else.

**Why it exists.** Getting this stack running end to end on a clean machine took me a lot of trial and error. I'm no expert, and the README opens by saying so: this was fidgetcoded.

**What's different.**

- It's been tested on the people it's for. My mom's fresh Mac found two bugs that would've hit every new macOS user. A friend's Mac found a third set the installer's own checks were blind to.
- A robot now does that test on every change. CI runs the real one-liner as a brand new account, twice, on throwaway machines, then checks the result from a clean login shell.
- It checks before it changes anything. Preflight gives an account with no sudo a clear partial install or a clear stop. It also stops on old macOS and on networks that block the hosts it needs.
- It recovers. Each step downloads all the way before it runs, a failed step gets reported instead of marked done, and a rerun keeps your existing Ghostty config, status line and Telegram settings.
- Older Linux gets handled, too. On Ubuntu 22.04, which has no Python new enough for hyperresearch, that one optional tool gets skipped with a message and the rest of the install finishes.
- Releases are pinned. Skills and MCP servers install at a specific commit, version and SHA-256, and a daily CI job checks that every pin still resolves. Updates are something you run yourself.
- It's opinionated about what's optional: Steps 1 to 4, 8 and Final run automatically, while Steps 5, 6 and 7 are yours to run because they need your accounts.

**How to try it.** In a normal terminal, not as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/install.sh)
```

About 20 minutes. Then open a new terminal and run `claude --version`.

**What works today.** You can read all of this on the repo's Actions tab. As of `fd3998f` (November 4, 2026):

- The fresh-machine install passes on Ubuntu 24.04, Ubuntu 22.04, Debian 12, Fedora 41 and macOS 15 (zsh and bash), plus a standard non-admin macOS account and Linux with no sudo. macOS 14 passed in the last weekly run, on November 2.
- 39 of 39 preflight checks and 35 of 35 offline maintenance tests pass, on Linux and on macOS.
- The daily pin check passes.
- 28 shell scripts, 0 ShellCheck warnings.
- Real installs on record: my mom's Mac (2026-04-17) and a friend's M4 Max (2026-07-24).
