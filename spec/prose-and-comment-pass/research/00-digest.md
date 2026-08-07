# Research digest — prose-and-comment-pass

Small appetite, so no subagent fan-out. The high-blast-radius exception still applied — the pass edits
comment and message text inside `uvm_resolve_root`, `uvm_install`, `uvm_acquire_lock` and
`uvm_trampolines` — so the exact contracts were pinned by reading all 1724 in-scope lines and by
driving the script, rather than by inspection alone.

Baseline output is captured verbatim in [`01-baseline-output.md`](01-baseline-output.md).

## Verified by driving, not by reading

**The census baseline is exactly what `GOAL.md` claims.** 13 hits, 10 from the word pattern and 3 from
the phrase pattern; 1724 aggregate lines; 200 comment lines in the script. The GOAL's warning about
`-w` versus `\b` is real — the first run of the census here returned zero hits because zsh does not
word-split an unquoted `$F`, and a pathspec of four concatenated paths silently matches nothing. Any
census command in a phase gate must spell the four paths out.

**`README.md:448` is factually wrong.** It describes each trampoline as "a four-line `sh` script". A
trampoline generated in the sandbox is thirteen lines. This is the single most damaging line in the
in-scope text for the GOAL's stated purpose: an operator who checks one claim and finds it wrong stops
trusting the rest.

**The `printf`-versus-heredoc concern does not reproduce, so nothing is being deferred for it.**
`uvm_doctor`'s closing block and `uvm_resolve_root`'s failure block both emit multi-line output through
a series of `printf`s rather than the heredoc that invariant §7 prescribes. Driven as
`uvm doctor | head -1` and `uvm status 2>&1 | head -1`, neither leaks `write error: Broken pipe`, with
default signal disposition or with `trap "" PIPE` in the parent: bash takes the default SIGPIPE death
silently. No `issues/` seed was filed, because a seed describing a defect that does not reproduce is
worse than none.

## Decisions carried into the design

**Six of the thirteen census hits go; seven stay.** The three `Note that` constructions are pure
filler. Three more uses of `just` are removable at no cost to the sentence. The remaining seven are
all the load-bearing "not just X" construction, meaning *not merely*, plus `keep it just as cheap`
meaning *equally*. Deleting those would change what the sentences claim. R1 anticipates this and
requires the survivors be listed in the PR body with reasons.

**The gate for R4 is behavioral, plus a function-skeleton diff.** No textual gate can separate a
legitimate message rewording from an accidental logic edit, because R5 explicitly licenses rewording
message text. Comparing the ordered list of function definitions against `main` catches a rename, and
the sandbox drives catch anything that changed what the script does.

**The status-output gate is a subset test, not a diff.** `README.md`'s sample is abridged: it carries
five of the eighteen field labels and closes with `...`. Asserting that its labels are a subset of a
real drive's labels catches a renamed field without forbidding the abridgement.

## Judgment calls, settled at the planning gate

Two edits were defensible either way and were put to the human rather than decided silently. Both were
settled in favour of the correction, and `PLAN.md` §2 records them as decisions:

- The `README.md` sample gains the `invoked as:` line it drops mid-block. A quoted sample that differs
  from a real drive is the same credibility failure as the "four-line" claim.
- The modulefile's description loses "extremely". It is Astral's own tagline, but it is user-facing
  text in `module help`, and the sentence loses nothing factual.
