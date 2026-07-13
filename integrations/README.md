# Upstream integrations

`upstreams.lock.json` records the upstream work Jaimitos has actually adopted or materially
consulted — pinned by commit SHA, with the license, the exact files read, the Jaimitos files they
influenced, and every meaningful deviation.

It exists so that "where did this come from, and how much of it is still theirs?" has an auditable
answer. It is **not** a dependency manifest: nothing here is fetched at runtime, and the toolkit
works offline after cloning.

## What the three adoption types mean

| `adoption` | Meaning |
|---|---|
| `copied` | Upstream text kept substantially verbatim. (Nothing is currently `copied`.) |
| `adapted` | Rewritten for this scaffold's docs model and pipeline; the idea and often the structure are upstream, the words are ours. |
| `merged` | Folded into an existing Jaimitos capability rather than added as a new one. |
| `concept-only` | Only the idea was taken; no upstream text was used. |

Every adapted file also carries a one-line attribution comment at the bottom of the file itself,
so provenance survives even when the file is read alone.

## Updating an upstream — manual, on purpose

There is **no automatic updater**, and this release does not add one. Fetching and overwriting
adaptations automatically is exactly how a careful adaptation silently reverts to someone else's
opinions.

```text
inspect the pinned SHA
  → select a candidate new SHA
  → diff only the upstream files listed in paths_consulted
  → human review of what actually changed
  → adapt the selected changes by hand into the Jaimitos files
  → update upstreams.lock.json (sha, inspected, deviations)
  → run the tests and dogfood the change
```

Never:

```text
fetch → overwrite adaptations automatically
```

Clone upstreams read-only, at the pinned SHA, into a temp dir **outside this repo**:

```bash
UPSTREAM_DIR="$(mktemp -d)"
git clone --filter=blob:none https://github.com/obra/superpowers "$UPSTREAM_DIR/superpowers"
git -C "$UPSTREAM_DIR/superpowers" checkout <sha-from-lockfile>
```

`jaimitos-os/scripts/test-skills.sh` validates the lockfile's schema and asserts that every path in
`jaimitos_files_influenced` still exists — so a deleted or renamed file cannot silently orphan its
provenance.
