# g2 / g4 Fullscreen Tiling Fix — Test Walkthrough

## What broke

`g2` and `g4` are zsh functions that shell out to `osascript` to tile Ghostty windows on macOS. When any Ghostty window was in native macOS fullscreen (green-traffic-light fullscreen, not Ghostty's own zoom), the AppleScript call `set size of ...` raised:

```
execution error: System Events got an error: AX error -10006
```

Cause: macOS Accessibility API refuses `AXSize` / `AXPosition` writes on fullscreen windows. The previous script assumed all windows were resizable.

## The fix (applied in two places)

Canonical: `~/.zshrc` (lines 28–220). Propagated into the installer: `CLI-MAXXING/step-2/ghostty-install.sh` (inside the `TILING_EOF` heredoc, inside inner `APPLESCRIPT` heredocs for `g2` and `g4`).

Two changes per function:

1. **Pre-flight un-fullscreen loop** — before geometry writes, iterate every window, read `AXFullScreen`, and if true, set it to false and `delay 0.6` to let macOS finish the transition animation.

   ```applescript
   repeat with w in wins
     try
       if value of attribute "AXFullScreen" of w is true then
         set value of attribute "AXFullScreen" of w to false
         delay 0.6
       end if
     end try
   end repeat
   ```

2. **`try` / `end try` wrappers** around every `set size`, `set position`, and `perform action "AXRaise"` call. If a window is still mid-transition or otherwise rejects the write, the error is swallowed and the next window still gets positioned instead of aborting the whole script.

Note: `step-final-install.sh` does NOT define `g2`/`g4` — it only grep-checks for the `g2()` marker in `$SHELL_RC` during the health-check phase. The functions live exclusively in `step-2/ghostty-install.sh` (which appends them to the shell rc) and in the canonical `~/.zshrc`. `x2` (external-display tiler) only exists in `~/.zshrc`; it is intentionally not shipped by the bonus installer.

## Manual repro (verify the bug is dead)

1. Quit Ghostty entirely, then reopen so you start from a clean state.
2. `Cmd+N` to create a second Ghostty window.
3. In window A, click the green traffic-light button (or `Ctrl+Cmd+F`) to enter macOS native fullscreen. Wait for the animation to finish.
4. Swipe back to the desktop space that holds window B.
5. In any shell prompt inside window B, run: `g2`
6. **Expected**: after ~1 second, both Ghostty windows are side-by-side on the main display, no `-10006` error printed. Window A is no longer fullscreen.
7. Repeat with `g4` after opening two more windows and fullscreening any one of them.

### Negative check
Run `g2` again while neither window is fullscreen. It should behave identically (the fullscreen loop is a no-op when `AXFullScreen` is false).

## Why the fix works

- AppleScript's `AXFullScreen` attribute is writable; setting it to `false` triggers the same exit-fullscreen animation as clicking the green button.
- `delay 0.6` is empirically enough for a 120Hz MacBook display to finish the transition; shorter delays (0.2–0.4) intermittently leave the window in a half-state where `set size` still returns -10006.
- The outer `try` blocks make each geometry write independent: a single failure no longer cancels the tiling of sibling windows.

## Verification performed on the installer

- `bash -n step-2/ghostty-install.sh` → syntax OK
- `bash -n step-final/step-final-install.sh` → syntax OK
- Heredoc sentinels balanced: `TILING_EOF` (1 open / 1 close), inner `APPLESCRIPT` (2 open / 2 close for g2 + g4), `STATUSLINE_EOF` / `SETTINGS_EOF` balanced in step-final.
- AXFullScreen references: 4 (expected — 2 per function × 2 functions).
- `try` / `end try`: 9 / 9 (balanced).
- Function bodies in the installer match `~/.zshrc` line-for-line (modulo the inner heredoc sentinel `APPLESCRIPT` vs `EOF`, which differs only because the installer wraps everything in a `TILING_EOF` heredoc and cannot reuse `EOF`).

## How to re-test after future changes

1. Edit `~/.zshrc` (canonical) first. Run `source ~/.zshrc` and repeat the manual repro above.
2. Propagate the change into `bonus-ghostty.sh` inside the `TILING_EOF` heredoc. Remember to rename any inner `EOF` to `APPLESCRIPT` or another unique tag.
3. Re-run the install script on a scratch account (or against a throwaway `$SHELL_RC`) and grep the result for `g2()` and `AXFullScreen` to confirm the heredoc expanded correctly.
4. Syntax-check both files:
   ```bash
   bash -n bonus-ghostty/bonus-ghostty.sh
   bash -n step-final/step-final-install.sh
   ```
5. Balance-check heredocs:
   ```bash
   grep -c "<<'TILING_EOF'" bonus-ghostty/bonus-ghostty.sh    # expect 1
   grep -c '^TILING_EOF$'   bonus-ghostty/bonus-ghostty.sh    # expect 1
   grep -c "<<'APPLESCRIPT'" bonus-ghostty/bonus-ghostty.sh   # expect 2
   grep -c '^APPLESCRIPT$'  bonus-ghostty/bonus-ghostty.sh    # expect 2
   ```
6. Run the manual repro on the real machine. Automated tests are not feasible here — the fix depends on the macOS Accessibility API and a GUI app, neither of which can be exercised from CI.
