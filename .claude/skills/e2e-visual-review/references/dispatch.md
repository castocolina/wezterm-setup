# External dispatch

**Load this file only after the user picked an external id.**
**Do NOT load** it when judging in this session.

The Step 5 table in `SKILL.md` is canonical for this session. This prompt
repeats each A.4 item with Applies + FAIL observables so a dispatched
model, which never loads the skill, can actually judge.

## opencode

`-m` and `--model` are equivalent; `-f`/`--file` attaches the PNG.

```bash
opencode run --model <id> --file <screenshot.png> "<prompt>"
```

Use this prompt verbatim (`<name>` is the only substitution):

```
Score WezTerm E2E scenario <name> against PRD Appendix A.4.
Reply with exactly six lines, nothing else:
<n> | PASS|FAIL|N/A | <one-line reason>

1. Tab titles fully legible and even-width across same-title tabs (AI-vision)
   Applies: legibility on dev/ai/docker/tabbar; even-width on tabbar only.
   FAIL: truncated/ellipsized/overlapping titles; two same-title tabs at different widths.
2. No raw escape characters visible in any pane after a scene launch (AI-vision)
   Applies: all four scenarios.
   FAIL: literal CSI/^[ /OSC bytes, printf ' fragments, \nnn octal runs, or a stuck quote> prompt.
3. Focused/first pane is clean after wez scene launch (AI-vision)
   Applies: all four scenarios.
   FAIL: leftover command echo, incomplete prompt, or stray glyphs in the focused pane.
4. Distinct per-pane background tints render (AI-vision / snapshot)
   Applies: dev/ai/docker; tabbar only if tints are in frame.
   FAIL: every pane the same background; tint only on chrome, not content.
5. Emoji icons occupy two cells and align (AI-vision)
   Applies: all four (tabbar launches dev).
   FAIL: clipped to one cell, sitting on the title baseline, tofu/replacement box, or 3+ cells with a gap.
6. Fancy tab active vs inactive visual distinction (snapshot)
   Applies: tabbar only.
   FAIL: both tabs identical chrome (same bg/underline/weight).

Looks wrong but is not a defect: glyph-edge hinting, subpixel LCD fringes, one-frame compositor lag.
Looks right but is a defect: every pane the same charcoal (tints washed out); an escape leak that reads as prompt color until you see ^[ or quote>; an emoji that looks 2 cells wide but is tofu; active vs inactive tabs that only differ by a 1px underline.

N/A is not PASS. No percentage, no numeric threshold, no partial-credit.
```

Free-form is not a verdict — re-ask once with the same prompt. Second
miss or attach failure: return to Step 3; never retry a different id.

If dispatch returns a six-line table, that is a starting verdict, not
the last word. If this session also saw the PNG and the table
contradicts the pixels, the pixels win — do not approve; report the
contradiction.

## Any other CLI

Only after Step 3 collected the exact attach invocation. A valid paste
names the binary, a model flag, a file/attach flag, and a message.
