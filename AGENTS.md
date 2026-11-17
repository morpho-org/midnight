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

- `.github/workflows/forge-old.yml` is a backup of the main CI, which uses the latest stable forge. Bugs in the older forge version it pins are expected: don't report or warn about them.
