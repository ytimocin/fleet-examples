# POC: Kargo + KubeFleet Integration

## Idea

Use Kargo for promotion flow and use KubeFleet for fleet rollout.

Kargo already knows:

- what version should move next
- when a promotion should happen
- when to stop and wait for health

KubeFleet already knows:

- which clusters should get the workload
- how to roll it out across those clusters
- how to report status for each cluster

This POC connects the two.

## What We Build

Two pieces ship together:

1. `kubefleet-update` promotion step in Kargo
2. `kubefleet` health checker in Kargo

The step creates or updates a KubeFleet `ClusterResourcePlacement` on the hub
cluster.

Then KubeFleet handles cluster selection and rollout.

The health checker reads KubeFleet status and keeps the Kargo Stage
`Progressing` until the fleet is fully healthy.

Per-cluster rollout status is included in the Stage health output so operators
can see which clusters are healthy, progressing, or failing.

## Simple Flow

1. A new Freight reaches a Kargo Stage.
2. The Stage runs `kubefleet-update`.
3. The step creates or patches a `ClusterResourcePlacement`.
4. KubeFleet selects target clusters and rolls out the change.
5. Kargo checks the CRP status.
6. If all target clusters become `Available=True`, the Stage becomes healthy.
7. Only then can downstream promotion continue.

## Why This Is Useful

Without this integration, Kargo can still drive deployments, but it does not
have native fleet placement or fleet rollout logic.

With this integration:

- Kargo remains the release orchestrator.
- KubeFleet becomes the multi-cluster deployment engine.
- Users get one promotion flow in Kargo and detailed rollout status from
  KubeFleet.

## User Scenarios

### Scenario 1: Production Fleet Rollout

A platform team promotes version `v2.1.0` from staging to production.
Kargo starts the promotion. KubeFleet places the workload onto the production
clusters using its placement policy and rolling update strategy. Kargo waits
until the whole fleet is healthy before allowing the next promotion.

### Scenario 2: Dynamic Cluster Selection

A team wants to deploy only to clusters labeled `env=prod` and `region=us`.
They do not want to hardcode cluster names in the promotion flow. KubeFleet
selects the matching clusters at rollout time, and Kargo still tracks the
promotion as one Stage transition.

### Scenario 3: Fleet Health Gate

Four clusters are healthy, one cluster is still applying the update.
KubeFleet reports per-cluster status. Kargo keeps the Stage in progress and
does not promote downstream until the last cluster is also healthy.

## POC Scope

In scope:

- create or update a `ClusterResourcePlacement` from a Kargo step
- support common CRP fields such as resource selectors, placement policy, and
  rollout strategy
- read CRP conditions and per-cluster placement status
- map KubeFleet rollout state into Kargo health state

Out of scope:

- full UI for fleet topology
- advanced staged update orchestration
- remote KubeFleet hub support if Kargo and KubeFleet are not using the same
  API server

## Phase 2

After the core integration works, phase 2 can extend it in a few practical
ways:

- show KubeFleet rollout details in the Kargo dashboard
- add a fleet view for clusters, rollout status, and failures
- support richer rollout patterns such as staged updates
- support a separate KubeFleet hub cluster if Kargo and KubeFleet are not
  co-located

The first dashboard version does not need to be complex. A simple Stage panel
showing the CRP name, selected clusters, healthy count, progressing count, and
failing clusters would already add a lot of value.

## Implementation Order

- implement the `kubefleet-update` step first
- implement the `kubefleet` health checker next
- connect the checker output to Stage health
- validate the full flow with a sample Stage and a small fleet

## Testing

Local testing should use a small Kubernetes environment where Kargo and the
KubeFleet hub run on the same API server, plus a few member clusters managed by
KubeFleet.

Test approach:

- unit tests for the Kargo step and health checker
- integration test for create or patch of the CRP
- local end-to-end test with one hub and a few member clusters
- manual check in the Kargo UI that the Stage stays blocked until the fleet is
  healthy

For the local demo, the main success path is simple:

1. create Freight in Kargo
2. trigger a Stage with `kubefleet-update`
3. confirm KubeFleet rolls out to the selected clusters
4. confirm Kargo keeps the Stage progressing until all clusters are available

## Assumption

This POC assumes Kargo and the KubeFleet hub are co-located on the same API
server. That keeps the implementation small and matches how Kargo step runners
already access Kubernetes resources today.

## Success Criteria

The POC is successful if:

- a Kargo Stage can trigger a KubeFleet rollout
- KubeFleet performs the fleet placement and rollout
- Kargo blocks downstream promotion until the fleet is healthy
- operators can see which clusters are still progressing or failing
