# Agent Documentation Maintenance Contract

This project is expected to be maintained by LLM agents over time.
Every code change must keep docs coherent with implementation.

## Required Updates Per Change

When an agent changes behavior, it must update all impacted docs in the same change set:

1. `README.md`
- user-visible capabilities
- run/build instructions
- caveats or prerequisites

2. `docs/architecture.md`
- component boundaries
- data flow or interface updates

3. `docs/dev-notes.md`
- operational caveats
- defaults and implementation details

4. `docs/roadmap.md`
- move delivered items out of roadmap
- add new deferred work explicitly

## Invariants

- Do not leave stale feature claims in docs.
- If tests are added/removed, keep testing section accurate.
- If APIs/interfaces change, document old/new behavior and migration impact.
- Keep docs short, factual, and directly mapped to code.

## PR/Change Checklist for Agents

- [ ] Code updated
- [ ] Tests updated and run (or limitation documented)
- [ ] README updated if user-facing behavior changed
- [ ] Architecture/dev-notes updated if internal flow changed
- [ ] Roadmap adjusted for shipped/deferred scope

## Ownership Rule

If an agent touches a file in `PulseBar/`, it owns documentation consistency for that area in the same task.
