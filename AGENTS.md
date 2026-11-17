## Review guidelines

Flag notably these issues:
- Typos, broken links, and inconsistent formatting
- State not being fully reconstructible through events
- Caller being ambiguous and not being logged
- Outdated documentation
- Inconsistent naming
- Major issues in tests
- Major gas optimizations
- Readability issues

Don't flag breaking changes, the code is not in production and will be immutable.
Flag all issues, including those that were not introduced in this commit or pull request.

## Agent guidance

- `.github/workflows/forge-old.yml` is a backup CI running an older, pinned forge version. Bugs in that forge version are expected: don't report or warn about them.
- `CERTORAKEY` exposure in the Certora workflow is an accepted low-impact risk. Do not add dependency hardening solely to protect it; assess verification integrity and other credentials separately.
