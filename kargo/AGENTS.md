# Repository Guidelines

## Project Structure & Module Organization

This workspace contains two independent Git repositories:

- `kargo/`: Kubernetes-native continuous promotion platform. Main Go code lives in `pkg/`, binaries in `cmd/`, API types in `api/`, Helm charts in `charts/`, and the React/TypeScript UI in `ui/`.
- `kubefleet/`: Multi-cluster Kubernetes management project. Core APIs are in `apis/`, controllers and scheduler code in `pkg/`, binaries in `cmd/`, charts in `charts/`, examples in `examples/`, and test suites in `test/`.

Work from the subproject root when running commands. Check `kargo/AGENTS.md` or `kubefleet/CLAUDE.md` before making deeper changes.

## Build, Test, and Development Commands

Use the commands that match the repository you are editing:

- `cd kargo && make lint`: run Go, UI, chart, and repo linting.
- `cd kargo && make test-unit`: run unit tests with race detection.
- `cd kargo && make codegen`: regenerate CRDs, clients, and generated API artifacts.
- `cd kubefleet && make reviewable`: run the full pre-PR quality gate.
- `cd kubefleet && make test`: run unit and integration tests.
- `cd kubefleet && make e2e-tests`: execute Kind-based end-to-end coverage.

## Coding Style & Naming Conventions

Both projects are Go-first and prefer standard library patterns over extra dependencies. Use `gofmt`-compatible formatting and keep tests table-driven where practical.

- Kargo: use `errors` from the standard library, avoid naked returns, and follow existing package layouts. UI changes should follow the `ui/` Prettier configuration.
- KubeFleet: prefer `cmp.Diff`-style comparisons, avoid assert libraries in unit tests, and keep new APIs/controllers aligned with existing naming under `apis/` and `pkg/controllers/`.

## Testing Guidelines

Place Go tests beside the code as `*_test.go`. For KubeFleet, integration and E2E coverage lives under `test/`; for Kargo, UI tests live under `ui/tests`.

Run the narrowest relevant target first, then the repo-wide check before opening a PR.

## Commit & Pull Request Guidelines

Follow the history already in use:

- Kargo commits use Conventional Commit style such as `feat:`, `fix:`, or scoped forms like `chore(deps): ...`; sign commits with DCO via `git commit -s`.
- KubeFleet PR titles must use prefixes such as `feat:`, `fix:`, `docs:`, `test:`, or `chore:`.

PRs should include a clear summary, linked issues when applicable, and screenshots for UI or UX-visible changes.
