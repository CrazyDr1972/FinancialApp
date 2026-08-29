# FinancialApp Project Rules

## Versioning

- Use the format `vX.Y.Z`.
- Every component is a single digit from `0` to `9`.
- Increment `Z` normally while it is below `9` (for example, `0.9.2` -> `0.9.3`).
- When `Z` is `9`, carry to `Y` and reset `Z` to `0` (for example, `0.8.9` -> `0.9.0`).
- When `Y` is also `9`, carry to `X` and reset `Y` and `Z` to `0` (for example, `0.9.9` -> `1.0.0`).
- Keep the app version, `pubspec.yaml`, and release script in sync.
