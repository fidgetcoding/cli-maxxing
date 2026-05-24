---
name: bullets
description: Crush a paragraph (or any prose blob) into the shortest possible bullets — core facts only, zero fluff. Use when the user says /bullets, "bullet this", "turn this into bullets", "bulletize", "make this bullets", "shorten to bullets", or hands over text that a reader shouldn't have to wade through as a paragraph. Unlike /concise (which decides shape per reply and sometimes leaves prose), this ALWAYS outputs bullets. For handoffs where people need scannable points, not blobs.
user_invocable: true
---

# bullets

Input = a paragraph / passage / doc section. Output = the shortest bullets that carry every load-bearing fact. Always bullets. Never leave it as prose.

## Rules

1. **One fact per bullet.** Split compound sentences. If a bullet has "and"/"but"/a comma joining two ideas, it's two bullets.
2. **Shortest form that survives.** Drop articles, filler verbs, throat-clearing ("it should be noted", "in order to", "the fact that"). Telegram style — `Deploy blocked: missing API key` not `The deployment is currently blocked because the API key is missing`.
3. **Keep every signal.** Names, numbers, dates, paths, identifiers, decisions, deadlines, blockers. Cutting fluff ≠ cutting facts.
4. **No invention.** Only what's in the source. No padding, no inferred context, no "this means…".
5. **Header if the blob has a clear subject.** One `**Bold line**` or `## Header` naming what the bullets are about. Skip if it's a single tight cluster.
6. **Group only when ≥2 distinct topics.** Then a bold sub-header per group. One topic = flat list.
7. **Order by importance.** Lead with the decision / outcome / blocker. Detail under it.
8. **No recap, no preamble, no closer.** The bullets ARE the output. Don't explain what you did.

## Shape

```
**<Subject>**
- <core fact>
- <core fact>
- <core fact>
```

Multi-topic:
```
**<Subject>**

**<Topic A>**
- <fact>
- <fact>

**<Topic B>**
- <fact>
```

## Length

Each bullet ≤ ~12 words. If one runs long, it's two facts → split. A dense paragraph should collapse to 3–6 bullets. If you can't get under the source's word count, you're keeping fluff.

## Scope

- Default target = the text in the message, or the file/selection named.
- `/bullets <paste>` → bulletize the paste.
- Plain `/bullets` with no text → bulletize the previous turn's prose.
- Stays active for the turn only — not a mode switch. Re-invoke per blob.

## Boundaries

This is chat/handoff formatting, not a copy deliverable — `/copywriting` does not apply. Nate overrides still hold: "Nate" never "Nathan", absolute paths, EST timestamps, no UTC.
