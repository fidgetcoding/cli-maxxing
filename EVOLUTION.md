# cli-maxxing: how it got here

## Short version

It started as a setup script on 2026-03-23 and took 60 commits on day one. It looked solid on my machine, because my machine masked the bugs. Then I ran it on my mom's Mac. Half the install bailed, and the part that worked was invisible to her shell. A 15-agent swarm rewrote the path handling the same day. Five audit passes later, everything was green, and in July a friend's Mac proved green could still mean broken. So on 2026-11-01 I stopped trusting my own machine: CI now runs the real one-liner as a brand new account on five operating systems. Its first run found more bugs. Claude Code swarms did most of the writing throughout, and I decided what to test and what to fix.

## Origin, in my words

From the README: "Getting this stack running end-to-end on a clean machine took a lot of trial and error, and it still might not be perfect."

After the install with my mom: "given the mess ups in her process, we NEED TO UPDATE all the scripts in CLI-MAXXING correctly so that everything happens smooth and perfect moving forward"

And right after: "need to make sure that CLAUDE ALWAYS DOWNLOADS. that is literally the most important part"

## Timeline

| Date | Commit | What happened |
|---|---|---|
| 2026-03-23 | `60bf06e` | First commit: Script 0, a setup installer |
| 2026-03-23 | `d7e333c` | "Fix 3 client-environment bugs for fresh installs", one of 60 commits that day |
| 2026-03-23 | `dc82990` | Windows via PowerShell tried, later dropped |
| 2026-04-16 | `123704b` | Swarm tier system |
| 2026-04-17 | subject: "fix multi-shell + mid-script PATH bugs" | Mom's Mac fixes. 14 files, +1,485, -549 |
| 2026-04-17 | `c70d21c` | Claude-first: subscription gate up front, retries on install |
| 2026-04-20 | `28033a5` | Steps 1 to 4 shellcheck clean |
| 2026-04-21 | `88047d0` | Fifth audit pass lands |
| 2026-07-02 | `d5fc330` | 15-agent audit of the safety check skill |
| 2026-07-24 | `afc4328` | Bash login shell fix from a friend's Mac |
| 2026-08-17 | `cfb973b` | Installed skills de-personalized, PII gate added |
| 2026-11-01 | `3f5463f` | Fresh-machine install test on macOS and Linux |
| 2026-11-01 | `5fdf2ec` | Fixes for what that test found on Linux and macOS |
| 2026-11-01 | `8a868f1` | Preflight: no sudo and locked-down Macs handled up front |
| 2026-11-01 | `69367f0` | Daily check that pinned versions and SHA-256s still resolve |
| 2026-11-01 | `826851f` | The daily job keeps scheduled checks from being switched off |

## Round by round

**Round 1: it works on my machine (03-23 to 04-16).**
Built: a numbered step per concern, each idempotent.
Tested: on my own machine, plus early testers.
Broke: nothing I could see. I use bash on purpose, so my setup hid the shell bugs.
What came next: a real beginner on a real Mac.

**Round 2: my mom's Mac (04-17).**
Tested: the one-liner on her fresh Mac. Step 1 installed Homebrew, Node and Claude Code.
Broke: then the rest bailed with "Homebrew not found" and "Node.js not found". Two bugs stacked:
- The parent script never re-read PATH after Step 1, so every later step ran blind.
- The installer read her account's login shell, bash, and wrote everything to bash's files. Her Terminal opened zsh. Claude had installed and her daily shell couldn't see it.

Fixed: a 15-agent swarm in about 13 minutes. `reload_path()` between steps, all four shell files written on macOS, breadcrumbs for steps that didn't finish. Then a hard gate after Step 1 and 3 retries on the Claude install.
What it made me want next: "does it tell people to sign up for the claude subscription first before anything that they do, that is critical". It does now.

**Round 3: five audit passes (through 04-21).**
Built: nothing new. This was all about trust.
Tested: 15-agent audits, ending at 25 of 25 invariants and 42 of 42 shellcheck.
Broke: pass 5 found credential variables left set after use in Steps 5, 6 and 7, a stale skill checksum soft-failing every install, and `xargs` chewing backslashes in a token trim.
Fixed: unset after use, pure-bash trim, checksum synced. `88047d0`, `6c0b029`.

**Round 4: green and broken (07-24).**
Tested: a friend's M4 Max. The installer reported all green.
Broke: `claude: command not found` in every new terminal. Their account was bash by default, and login bash reads only `~/.bash_profile`. Claude's nvm folder was never saved to any startup file. The worst part: the self-test passed because the installer had fixed its own PATH in-process.
Fixed: `afc4328`. A `.bash_profile` to `.bashrc` bridge, Claude's real path saved, and a self-test run from a clean `env -i` login shell.

**Round 5: clean the payload (08-17).**
Tested: an audit of what the installer actually puts on someone's machine.
Broke: my own private details were in skills that shipped to other people.
Fixed: `cfb973b`, `6c05600`, plus `scripts/check-pii.sh`.

**Round 6: fresh machines, every change (11-01).**
Built: `tests/fresh-install/`, which runs the real one-liner as a brand new account on GitHub-hosted runners, twice, then checks the result from a clean login shell. It never runs on anyone's own machine.
Broke, on its first run: nvm killed Step 1 under `set -u` on bash 4.4 and up. An empty `.bash_profile` hid Claude from every login shell. `tzdata` hung Ubuntu 22.04 on a prompt. Fedora was missing `libatomic` and used a `dnf` group command that dnf5 dropped. Ghostty's snap needs `--classic`. Python 3.13 for hyperresearch was being skipped on every fresh Mac.
Fixed: `5fdf2ec`.
Also built: preflight, which runs before anything is written (`8a868f1`). No sudo gets a clear partial install or a clear stop, and never a password prompt that can't succeed. A daily check reads the pins straight out of the step scripts (`69367f0`), and `tests/pins` breaks each kind of pin to prove the check catches a vendor change. GitHub had already switched off Security Checks for inactivity, so the daily job now keeps scheduled checks on (`826851f`).

**Round 7: failure recovery and statusline cost (11-04).**
I added offline regression tests that exercise the installers with disposable homes,
stub downloads and fake commands. They cover repeated runs, truncated downloads,
missing tools, malformed settings, shell paths with spaces/metacharacters and
untrusted statusline input without installing anything on the development machine.

Fixed: orchestration now downloads each step completely before running it, reports
child failures and clears stale completion markers. Counted errors no longer mark
steps complete. nvm sourcing tolerates unset internal variables, and shell PATH
persistence quotes literal directories. Existing Ghostty, project statusline,
custom global statusline and Telegram access settings survive maintenance. Global
statusline/memory-hook merges validate JSON and use atomic writes with an installer
lock; memory-hook reruns preserve other Stop hooks. The PDF helper cleans up its
temporary files on both success and failure.

The statusline now validates numeric input before shell arithmetic and parses JSON
once instead of six times. Both embedded copies match the template. The Step 5
selection menu reads the MCP inventory once instead of eleven times. The fixture
benchmark compares the old and new statusline with alternating runs; its timings
measure script execution, not end-to-end Claude responsiveness.

Tested locally: 32 offline maintenance tests passed on Bash 3.2 and Bash 5.3. The
same suite is wired into the existing Linux/macOS preflight CI job. Actual package
installation, vendor endpoints and credential-backed MCP integration still need
the throwaway-machine CI checks; I did not run a live install in this pass.

Release CI then caught an Ubuntu 22.04 regression: its intentional hyperresearch
skip (no supported Python) was counted as a failed Step 3. That Linux skip now
warns without blocking completion. Added regressions for the supported skip,
failed Python installation on macOS, and failed hyperresearch installation;
actual installation failures still prevent the completion marker.

## Test log

| Date | Check | Result |
|---|---|---|
| 2026-04-17 | Fresh Mac, my mom's | Failed, then passed after a manual repair and rerun |
| 2026-04-17 | Swarm review of the fix | Shellcheck clean at warning level |
| 2026-04-21 | Fifth pass | 25 of 25 invariants, 42 of 42 shellcheck |
| 2026-07-24 | Friend's M4 Max | All green, actually broken, fixed |
| 2026-11-01 | CI, fresh install at `4a721aa` | Ubuntu 24.04, Ubuntu 22.04, Debian 12, Fedora 41, macOS 15 on zsh and bash |
| 2026-11-01 | CI, same run | Non-admin macOS account, Linux with no sudo and with no git, preflight tests on Linux and macOS |
| 2026-11-01 | CI, pinned versions | Pass |
| 2026-11-01 | shellcheck -S warning, fresh clone | 28 scripts, 0 warnings |

CI can't click the Xcode Command Line Tools dialog, so that part is proven only by the real Macs above.

## Roads not taken

- **Reordering Step 1 to get Claude on earlier.** On a fresh Mac it has to be Command Line Tools, then Homebrew, Git, Node, Claude, because the stock `git` is a stub that pops up a dialog.
- **A plugin marketplace.** Benched on 2026-07-02. Auto-update trades "people drift stale" for "one bad push hits everyone silently". Pinned releases and a manual `update.sh` stayed.
- **Windows.** The README says no, and I don't plan to port it.
- **Installing everything automatically.** Steps 5, 6 and 7 stay manual because they need your accounts and tokens.

## Sources

- Git log of `fidgetcoding/cli-maxxing`. A history rewrite on 2026-04-25 changed older SHAs.
- `CHANGELOG.md`, `README.md`, `scripts/check-pii.sh`, `tests/fresh-install/`, `tests/pins/`, `tests/preflight/`, and the bodies of the commits above.
- CI runs on the repo's Actions tab.
- Private notes from the 2026-04-17 install, the 2026-04-21 fifth pass, the 2026-07-24 install and the 2026-07-02 distribution decision.
