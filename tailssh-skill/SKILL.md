---
name: tailssh
description: >
  Set up permanent passwordless SSH into someone else's Mac over Tailscale — the exact playbook
  from the Kai's-laptop run (2026-07-10). Fires on "/tailssh", "set up ssh to <person>'s
  laptop/computer", "onboard <person>'s machine", "add <person> to tailscale", "make ssh <alias>
  work for <person>'s machine", or when the user is at (or coordinating with) a friend's/client's
  Mac and wants permanent remote access from their own Mac. Covers: Tailscale device share
  (one-directional), ~/.ssh/config alias, ssh-copy-id key install, end-to-end verification — and
  generates a plain-English instructions doc the machine owner can follow solo.
user_invocable: true
allowed-tools: Bash, Read, Edit, Write
---

# tailssh — passwordless `ssh <name>` into someone's Mac over Tailscale

End state: `ssh <alias>` from the user's Mac lands on the other person's Mac with no password,
over Tailscale, with zero access granted in the reverse direction.

## Security model (lead with this if the user hesitates)

- **The share is one-directional.** Their device gets shared TO the user's tailnet. The user can
  reach that one machine; the machine's owner cannot see or reach any of the user's machines.
- **Only the PUBLIC key lands on their Mac** (`~/.ssh/authorized_keys`). It's a lock, not a key —
  it lets the user in, it grants nothing back. The private key never leaves the user's machine.
- **Their password auth stays on.** This setup stops the *user* from needing the password; it does
  not weaken or change how the owner logs in.
- Direction check: putting THEIR key on the user's machine would be the reverse grant. Never do it.

## Intake — ONE combined ask

1. Alias for `ssh <alias>` (default: their first name, lowercase).
2. Their macOS username (`whoami` on their machine — NOT their display name).
3. Are you sitting at their machine now, or handing them instructions? (hand-off → generate the doc)

Share-invite email defaults to `nate@lorecraft.io` — confirm silently unless it's clearly not Nate.

## Phase 1 — on THEIR machine

If handing off: fill `references/instructions-template.md` placeholders (`<OWNER>`, `<REQUESTER>`,
`<EMAIL>`, `<ALIAS>`) and save to `~/Desktop/ssh-setup-<alias>.md` for AirDrop. If present in
person, walk through live:

1. **Remote Login ON** — System Settings → General → Sharing → Remote Login. Off by default on
   most Macs; skipping this is the #1 cause of "Connection refused" later.
2. **Install Tailscale** — https://tailscale.com/download (or Mac App Store).
3. **Sign in with THEIR OWN account** (Google/Apple/email — anything). They do not join the
   user's account or tailnet.
4. **Share the device** — login.tailscale.com → Machines → this machine → **⋯ → Share** → enter
   the user's email → send invite.
5. **Capture their username** — `whoami` in Terminal on their machine.

## Phase 2 — on the USER'S machine

1. **Accept the share invite** from the email link. The device appears as a shared node.
2. **Get its Tailscale IP** (100.x.y.z) — `tailscale status` or the accept page / admin console.
3. **Add the alias** — Read `~/.ssh/config` first, preserve everything, append:
   ```
   Host <alias>
     HostName <100.x.y.z>
     User <their-username>
   ```
4. **Install the key** — interactive password prompt, so it must run in the user's own terminal,
   never through the agent's Bash tool. In Claude Code, tell them to run:
   ```
   ! ssh-copy-id <alias>
   ```
   They type the owner's password once. No keypair yet? `ssh-keygen -t ed25519` first.
5. **Verify** (agent runs these):
   ```bash
   ssh -G <alias> | grep -E '^(hostname|user) '
   ssh -o PasswordAuthentication=no -o BatchMode=yes <alias> true && echo PASS
   ```
   PASS = done. Report both results.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Connection refused | Remote Login off on their Mac (Phase 1 step 1) |
| Timeout / no route | Tailscale not running on one side (`tailscale status`), or invite not accepted |
| Still asks for password | ssh-copy-id didn't land — rerun; on their Mac check `chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/authorized_keys` |
| Permission denied | Wrong `User` — must be `whoami` output on their machine |

Tailscale 100.x IPs are stable for the life of the node; if MagicDNS is on you can use
`<machine>.<tailnet>.ts.net` as `HostName` instead — optional, not required.

## Rules

- Never place the other person's key on the user's machine.
- Never change sshd config / disable password auth on their machine — not ours to harden.
- All password entry happens in the user's own terminal (`!` prefix), never via agent Bash.
- Read `~/.ssh/config` before editing; append, don't rewrite.
