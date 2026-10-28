# 03 — One endpoint over every region

Product teams get a single base URL. Fleet exports each cluster's public Frontend Service and
registers them as endpoints of one Azure Traffic Manager profile. Chat requests are
self-contained, so there is no cross-region KV-cache penalty.

Run `00-setup/03-traffic-manager-rbac.sh` first and wait for the role assignments to propagate.

```bash
source ../env.sh
kubectl --context $HUB_CONTEXT apply -f service.yaml -f ro-dns-label.yaml -f trafficmanager.yaml
kubectl --context $HUB_CONTEXT -n $NS get trafficmanagerprofile,trafficmanagerbackend   # wait for Accepted/Programmed
./chat.sh "Which model are you?"
./chat.sh    # run a few times; the answering cluster changes with DNS
```

**What this proves:** Dynamo's own "one endpoint, many pools" (Global Router) stops at the
cluster boundary. Fleet carries the same idea across clusters and regions.

Builds on 01. Traffic Manager is DNS-based: failover is bound by TTL, not instant. A production
team would front this with Azure Front Door for L7 routing; the Fleet side stays the same.
