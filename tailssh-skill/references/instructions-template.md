# Letting <REQUESTER> connect to this Mac (~5 minutes)

Hi <OWNER> — these steps let <REQUESTER> log into this Mac remotely to help with stuff.
Two things worth knowing up front:

- Nothing here shares your password. You keep it; nobody else learns it.
- This is one-way. <REQUESTER> can reach **this Mac only** — this Mac gets no access to
  <REQUESTER>'s computers, files, or network.

## 1. Turn on Remote Login

System Settings → General → Sharing → turn **Remote Login** ON.

## 2. Install Tailscale

Download from https://tailscale.com/download (or the Mac App Store), open it, and sign in
with **your own** Google/Apple/email account. Free for personal use.

## 3. Share this machine with <REQUESTER>

1. Go to https://login.tailscale.com and log in with the same account.
2. Click **Machines**, find this Mac in the list.
3. Click the **⋯** menu on its row → **Share** → enter `<EMAIL>` → send.

## 4. Done

<REQUESTER> accepts the invite on their side and finishes the rest remotely. The very first
connection will ask for this Mac's login password once (you can type it yourself) — after
that, never again.

To undo any of this later: Tailscale admin console → Machines → this Mac → ⋯ → remove the
share, and/or turn Remote Login back off.
