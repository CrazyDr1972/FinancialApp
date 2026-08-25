# Financial App

A small personal finance application for desktop, web, and mobile.

## Development

The first version will focus on importing YNAB CSV exports, reviewing
transactions, and reporting balances and net worth. Banking integrations and
automatic synchronisation are intentionally out of scope for the initial MVP.

```text
flutter pub get
flutter run -d chrome
```

Supported targets currently include Android, Web, and Windows.

## Data safety

YNAB exports and local databases are ignored by Git. Do not commit personal
financial data to the repository.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
