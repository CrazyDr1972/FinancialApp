# FinancialApp Project Rules

## Versioning

- Use the format `vX.Y.Z`.
- Every component is a single digit from `0` to `9`.
- When `Z` would become `10`, carry to `Y` and reset `Z` to `0`.
- When `Y` would become `10`, carry to `X` and reset `Y` to `0`.
- Examples: `0.8.9` -> `0.9.0`, `0.9.9` -> `1.0.0`.
- Keep the app version, `pubspec.yaml`, and release script in sync.
