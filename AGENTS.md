# Lion Pass workspace rules

## macOS build isolation

- Never place a Lion Pass `.app` build under `/private/tmp`, `/tmp`, the repository root, or another Spotlight-indexed directory.
- Run macOS validation through `apple/scripts/test-macos.sh`. It keeps DerivedData under `apple/.derived-data.noindex`, marks it as non-indexable, unregisters the generated app from Launch Services, and removes the temporary `.app` when it finishes.
- If a manual `xcodebuild` invocation is unavoidable, use `-derivedDataPath apple/.derived-data.noindex` and unregister every generated `Lion Pass.app` with `lsregister -u` before finishing.
- `/Applications/Lion Pass.app` is the only application bundle that may remain registered or discoverable as an installed Lion Pass application.
