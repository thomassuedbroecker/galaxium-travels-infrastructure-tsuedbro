## Description

<!-- Describe what this PR does and why. Reference any related issue with "Closes #<number>". -->

## Checklist

- [ ] Ran the smallest relevant automated check from `testing/README.md`
- [ ] Updated documentation where service topology, authentication, ports, env variables, or commands changed
- [ ] Updated `ARCHITECTURE.md` when a change affects component boundaries or a documented architecture decision
- [ ] No local `.env` files, generated test output, or demo database files committed

## DCO sign-off

Commits are signed off **automatically** if you ran the one-time hook setup
after cloning:

```sh
bash setup-hooks.sh
```

If you skipped that step and the DCO check is failing, run:

```sh
# re-sign the last N commits (replace 3 with the actual count)
git rebase --signoff HEAD~3 && git push --force-with-lease
```
