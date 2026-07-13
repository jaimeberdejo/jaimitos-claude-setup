# Deepening

How to deepen a cluster of shallow modules safely, given its dependencies. Assumes the vocabulary in
[SKILL.md](SKILL.md) — **module**, **interface**, **seam**, **adapter**, **depth**.

Deepening is a *design* activity, not a mandate: only deepen a cluster the current task already
touches. Restructuring code nobody asked about is scope creep, not leverage.

## Dependency categories
Classify a candidate's dependencies first — the category determines how the deepened module is
tested across its seam.

1. **In-process** — pure computation, in-memory state, no I/O. Always deepenable: merge the modules
   and test directly through the new interface. No adapter needed.
2. **Local-substitutable** — has a local stand-in (PGLite for Postgres, an in-memory filesystem).
   Deepenable if the stand-in exists; the test suite runs against it. The seam is **internal** — no
   port at the module's external interface.
3. **Remote but owned** — your own services across a network (internal APIs, queues). Define a
   **port** at the seam: the deep module owns the logic, the transport is an injected **adapter** —
   HTTP/gRPC in production, in-memory in tests. The logic stays in one deep module even though it's
   deployed across a network.
4. **True external** — third-party services you don't control (Stripe, Twilio). The deepened module
   takes the dependency as an injected port; tests supply a mock adapter.

## Seam discipline
- **One adapter is a hypothetical seam; two is a real one.** Don't add a port unless at least two
  adapters are justified (typically production + test). A single-adapter seam is just indirection —
  it fails the deletion test.
- **Internal seams are not external seams.** A deep module may have seams private to its
  implementation and used by its own tests. Don't leak them into the interface just because a test
  reaches for them.

## Testing: replace, don't layer
- **The interface is the test surface.** Write the new tests at the deepened module's interface.
- **Delete the old shallow-module unit tests** once the interface tests cover the behavior. Keeping
  both layers is waste that pins you to the old shape.
- Assert on observable outcomes through the interface, never on internal state.
- A test that must change when the implementation changes — with behavior unchanged — was testing
  past the interface. Fix the test, or the module's shape.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
