# Releasing

1. Confirm the validation workflow succeeds on `main`.
2. Move completed entries from `Unreleased` into a versioned changelog section.
3. Create an annotated Semantic Versioning tag from the reviewed commit.
4. Push the tag and create a GitHub release containing the upgrade notes.
5. Update customer deployment repositories through separate reviewed pull
   requests. Never move an existing tag.

Example for the first release:

```bash
git switch main
git pull --ff-only origin main
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```
