# 01 — A second lock through `uvm_acquire_lock`

**Conclusion.** The function takes the lock's name as a new first argument, `install` or `repair`,
and derives both the path (`${uvm_root}/.<name>.lock`) and the words its messages use from it. The
body of the wait loop, the owner write, the timeout guard and `uvm_unlock` do not change. There is
one call site today (`uvm_install`), and it gains the word `install`. Provisioning's messages are
byte-identical afterwards, which a drive asserts, and `tests/lock-race.sh` is the regression drive.

## The change

```
uvm_acquire_lock LOCK ON_TIMEOUT PREDICATE [ARG...]
  LOCK  install | repair   path ${uvm_root}/.LOCK.lock
```

- Arity check `(( $# >= 3 ))`, keeping the explicit count. `lock-simplification` recorded why: an
  empty `"$@"` is a successful no-op, and `${1:?}` exits 0 under the EXIT trap on bash 3.2.
- `case "${kind}"` sets `what` (`provisioning lock` | `repair lock`) and `doing` (`provisioning` |
  `repairing`). An unknown name dies naming it. That is a programming error, never user input.
- Five message strings change from a literal to `${what}` or `${doing}`: `cannot create … at`, the
  notice's first line, the notice's `If nothing is … this tree`, the timeout `die`, and `cannot
  record ownership of the …`. Provisioning's text comes out unchanged.

A path argument was the alternative. It would leave the message words to a second argument or to a
lookup on the basename. A name keeps the path and the wording in one table inside the function that
prints them, and nothing outside it spells `.repair.lock` except `uvm doctor` and `uvm clean lock`.
Those already spell `.install.lock` today.

## Blast radius

- **Call sites.** One, `uvm_install`: `uvm_acquire_lock install proceed "${satisfied[@]}"`. The
  repair caller is new: `uvm_acquire_lock repair fail uvm_repair_recorded`.
- **State.** `uvm_lock` is still one global, and `uvm_unlock` still releases by it. That is sound
  because no call holds both locks: `uvm_ensure_uv` returns from `uvm_install`, which releases before
  it returns, before the repair begins.
- **Traps.** Unchanged. Both locks release on EXIT, INT and TERM through `uvm_unlock`.
- **Tests and harnesses.** `tests/lock-race.sh` observes `.install.lock` by path and never calls the
  function, so it is unaffected. `lock-simplification`'s P1 gate sourced the lock section by its
  banners and called the old signature. That gate is retained history and is never re-run. The new
  P1 gate extracts the two functions by name, so a banner rename cannot blind it.
- **Documentation.** `invariants.md` §5 quotes the signature. `issues/purge-tree-repair.md` quotes
  it too, and that seed is retired at landing.

## Measured (prototype in a throwaway copy, bash 3.2.57)

- A repair caller on a standing `.repair.lock` with a 2 s timeout: rc 1 at 2 s. The notice and the
  timeout line say `repair lock` and `If nothing is repairing this tree` and carry the planted owner
  line. Nothing says `provisioning`. `.install.lock` is not created and the plant is intact.
- Against the current tree, the same call returns 0 and runs its critical section: `repair` is read
  as ON_TIMEOUT, the predicate is the command `fail`, and the lock taken is `.install.lock`. That is
  the gate's red.
- Provisioning with a live `.install.lock` plant and a 2 s timeout prints the notice unchanged,
  proceeds, and prints `uv 9.9.9 (fixture)`.
- `tests/lock-race.sh` control 32×2, held 16×2 and pin 6.6.6 16×2: `progress=ok`, exit 0.
