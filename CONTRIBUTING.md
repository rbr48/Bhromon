# Contributing to Bhromon

Thanks for helping. Bhromon is free and open source, with no business model.

## Before you start

- Check the open issues and pull requests so you don't duplicate work.
- For a large change, open an issue first to agree on the approach.

## Setup

See the **Local Development Setup** section of the [README](README.md).

## Checks

Run these before you open a pull request. CI runs the same checks.

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test --coverage
cd functions && npx tsc --noEmit && npx jest src
```

## Pull requests

- Work on a branch, and open a pull request into `main`.
- Keep each change focused, and describe what it does and how you tested it.
- Keep the Dart Format check passing. The CI formatter may differ from your local one; use the version CI uses.
- Never commit credentials, API keys or session cookies. Read them from environment variables.

## Code

- Follow the patterns in `AGENTS.md` for the feature you are changing.
- Add translations for both Bengali and English when you add user-facing text.
- Test logic in pure Dart where you can.

## License

Contributions have no license until the project chooses one. See the README.
