# Vendored skill

`skills/lowly-writing-framework/` is a copy of the upstream skill, unmodified, installed with the `skills` CLI from npm:

```
npx skills add lowlysre/lowly-writing-framework#v2.3.0 --skill lowly-writing-framework --agent universal --copy
```

The CLI writes to `.agents/skills/`, so the copy moves to `skills/` afterward. The CLI records the install in `skills-lock.json`, with a `ref` (the tag), a `source`, and a `computedHash` over the skill's contents. The lockfile pins the tag, and `computedHash` changes with any byte of the copy, line endings included. `.gitattributes` marks `skills/**` as `-text` so git keeps the upstream bytes.

CI runs `npx skills experimental_install` against the lockfile in a scratch directory and diffs the result against `skills/`, so a drifted copy fails the build. The `description` in `SKILL.md` is part of that copy, so it stays identical to the pinned release.

`skills/` stays committed, because a plugin installs by cloning this repo and needs the skill in the tree. [mise](https://mise.jdx.dev) pins Node and holds the tag in `mise.toml`. `mise run vendor` re-vendors the skill at that tag and refreshes `skills-lock.json`, and `mise run verify` restores from the lockfile and diffs against `skills/`.

To bump the version, change `skill_ref` in `mise.toml`, run `mise run vendor`, and update `version` in the plugin manifest if the bump should ship.
