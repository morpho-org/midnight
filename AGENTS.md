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

## Certora CI risk policy

For Protocol CI, exposure of `CERTORAKEY` is an accepted low-impact risk. Do not open security or dependency PRs, or add dependency lockfiles, solely to prevent disclosure or misuse of this key. Assess separate concrete effects on contract correctness, verification integrity, or other credentials on their own merits. This policy does not authorize logging or committing credentials.
