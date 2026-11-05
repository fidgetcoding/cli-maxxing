# cli-maxxing: how it got here

## Short version

It started as a setup script on 2026-03-23 and took 60 commits on day one. It looked solid on my machine, because my machine masked the bugs. Then I ran it on my mom's Mac. Half the install bailed, and the part that worked was invisible to her shell. A 15-agent swarm rewrote the path handling the same day. Five audit passes later, everything was green, and in July a friend's Mac proved green could still mean broken. So on 2026-11-01 I stopped trusting my own machine: CI now runs the real one-liner as a brand new account on five operating systems. Its first run found more bugs. On 2026-11-04 I added tests that break the installer on purpose without installing anything, and fixed what they found. I built it with Claude Code swarms, and I decided what to test and what to fix.

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
| 2026-11-01 | `3075b66` | ESSENCE and EVOLUTION published |
| 2026-11-04 | `b3d5ebd` | Recovery: whole-step downloads, honest failure counts, settings that survive reruns, 32 offline tests |
| 2026-11-04 | `fd3998f` | Ubuntu 22.04's optional hyperresearch skip stops failing Step 3, 35 offline tests |
| 2026-11-05 | this commit | SwiftKit dropped from Step 5 because its site went dead. Superhuman, Google Drive and Vercel move up to 8, 9 and 10. Uninstall still removes old SwiftKit installs |

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

**Round 7: break it on purpose (11-04).**
Built: offline tests that run the installers against throwaway home folders, with fake downloads and fake commands, so nothing gets installed on the machine running them. They throw repeat runs, cut-off downloads, missing tools, broken settings files, shell paths with spaces and odd characters, and junk status line input at it.
Broke, and fixed (`b3d5ebd`):
- A step could run before its download finished. Now each step downloads all the way first, so a cut-off download can't run half a script.
- A step that hit errors could still get marked done, and an old "done" marker could hide a step that never finished. Failed steps now get reported, counted errors block the marker, and stale markers get cleared.
- nvm's own unset variables now load fine, and the PATH lines quote their folders, so a path with spaces in it survives.
- A rerun could stomp on things people had set up themselves: their Ghostty config, a project's status line, a custom global status line, their Telegram access settings. Those all survive now. Settings and memory hook merges check the JSON first, write in one go behind a lock, and keep any other Stop hooks you had. The PDF helper cleans up its temp files whether it works or not.
- The status line checks that numbers are numbers before doing math with them, and reads its JSON once instead of six times. Step 5's menu reads the MCP list once instead of eleven. On the same offline fixtures, 20 alternating runs each, the status line script's median went from 90.57 ms to 27.99 ms. That's the script on its own, not how fast Claude feels.

Tested: 32 offline tests on Bash 3.2 and Bash 5.3, then wired into the preflight CI job on Linux and macOS. I didn't run a live install on my machine for this. That's what the throwaway CI machines are for.
Broke in release CI: Ubuntu 22.04. It has no Python new enough for hyperresearch, which is optional, and the new honest error counting turned that planned skip into a failed Step 3.
Fixed: `fd3998f`. On Linux the skip now warns and Step 3 still completes. On a Mac it still counts as a failure and tells you to run `brew install python@3.13`. Three more tests cover the Linux skip, a failed Python install on macOS and a failed hyperresearch install, and a real install failure still blocks the completion marker. 35 tests passed on Bash 3.2 and 5.3, then in CI on Linux and macOS, and the fresh-machine install passed on every OS in the push matrix.
What it made me want next: nothing on fire. Signed-in MCP connections and the real Claude UI are the parts CI can't reach.

## Feature family tree

```
trial and error on my own machine → numbered steps, each safe to rerun
├─ my mom's Mac → reload PATH between steps, write every shell's files
│  ├─ "CLAUDE ALWAYS DOWNLOADS" → subscription gate up front, retries, hard gate after Step 1
│  └─ five audit passes → credentials unset after use, checksums synced, ShellCheck clean
├─ a friend's Mac, all green and broken → self-test from a clean login shell
│  └─ fresh-machine CI on five operating systems, twice per run
│     ├─ preflight → no sudo, old macOS, blocked networks, handled before any change
│     ├─ daily pin check → pins that can't silently drift
│     └─ offline maintenance tests → recovery, settings that survive reruns, older Linux skip
└─ shipped skills audited → private details scrubbed, PII gate in CI
```

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
| 2026-11-04 | Offline maintenance tests, local, Bash 3.2 and 5.3 | 32 of 32, then 35 of 35 after the Linux skip fix |
| 2026-11-04 | CI, fresh install at `b3d5ebd` | Ubuntu 22.04 failed on the hyperresearch skip. Fixed in `fd3998f` |
| 2026-11-04 to 05 | CI at `fd3998f` | Fresh install green on every job in the push matrix, 39 of 39 preflight and 35 of 35 maintenance on Linux and macOS, pins, lint and security checks pass |
| 2026-11-04 | Status line benchmark, offline fixtures | Median 90.57 ms before, 27.99 ms after, 20 runs each |
| 2026-11-05 | shellcheck 0.11.0 -S warning, fresh clone at `fd3998f` | 28 scripts, 0 warnings |

CI can't click the Xcode Command Line Tools dialog, so that part is proven only by the real Macs above.

## Roads not taken

- **Reordering Step 1 to get Claude on earlier.** On a fresh Mac it has to be Command Line Tools, then Homebrew, Git, Node, Claude, because the stock `git` is a stub that pops up a dialog.
- **A plugin marketplace.** Benched on 2026-07-02. Auto-update trades "people drift stale" for "one bad push hits everyone silently". Pinned releases and a manual `update.sh` stayed.
- **Windows.** The README says no, and I don't plan to port it.
- **Installing everything automatically.** Steps 5, 6 and 7 stay manual because they need your accounts and tokens.

## Sources

- Git log of `fidgetcoding/cli-maxxing`. A history rewrite on 2026-04-25 changed older SHAs.
- `CHANGELOG.md`, `README.md`, `scripts/check-pii.sh`, `tests/fresh-install/`, `tests/pins/`, `tests/preflight/`, `tests/maintenance/`, and the bodies of the commits above.
- CI runs on the repo's Actions tab.
- Private notes from the 2026-04-17 install, the 2026-04-21 fifth pass, the 2026-07-24 install and the 2026-07-02 distribution decision, plus the 2026-11-04 release record.
