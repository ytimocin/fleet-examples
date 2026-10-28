# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This is a workspace containing two independent Kubernetes projects. Each has its own CLAUDE.md with detailed guidance — always refer to the sub-project's CLAUDE.md when working within it.

### kargo/

Kubernetes-native continuous promotion platform for GitOps workflows. Warehouses watch for new artifacts (container images, Git commits, Helm charts), bundle them as Freight, and promote through a pipeline of Stages.

- **Language**: Go backend, React/TypeScript frontend
- **Build**: `make lint`, `make test-unit`, `make codegen`
- **Local dev**: `make hack-kind-up && make hack-tilt-up`
- **Single test**: `go test -run TestFuncName ./pkg/path/to/package/...`
- **Testing**: testify with `require`, table-driven tests, manual fakes (no mock frameworks)
- **Commits require DCO sign-off**: `git commit -s`
- **See**: `kargo/CLAUDE.md` (references `kargo/AGENTS.md` for full details)

### kubefleet/

CNCF sandbox project for multi-cluster Kubernetes application management using a hub-and-spoke architecture (hub agent + member agents).

- **Language**: Go
- **Build**: `make build`, `make lint`, `make reviewable`
- **Single test**: `go test -run TestFuncName ./pkg/path/to/package/...`
- **Testing**: table-driven tests with `cmp.Diff`, integration tests with `envtest`, E2E with Ginkgo/Gomega on Kind clusters
- **PR titles**: must use prefixes (`feat:`, `fix:`, `docs:`, etc.)
- **See**: `kubefleet/CLAUDE.md` (also check `kubefleet/.github/copilot-instructions.md` for domain knowledge)

## Key Differences Between Projects

| Aspect | kargo | kubefleet |
|--------|-------|-----------|
| Test framework | testify (`require`) | stdlib (`cmp.Diff`, no assert libs) |
| Mocking | manual fakes via interfaces | `gomock` + `envtest` |
| Code gen | `make codegen` | `make manifests && make generate` |
| Pre-commit check | `make lint` | `make reviewable` |
| Error style | stdlib `errors` only | stdlib `errors` |

Always check which sub-project you're working in before applying conventions — they differ significantly in testing patterns and tooling.
