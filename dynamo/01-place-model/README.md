# 01 — Place one model on every GPU cluster

The platform team writes **one** DynamoGraphDeployment on the hub. Fleet copies it to every
member labelled `gpu=true`; the Dynamo operator on each member turns it into pods.

```bash
source ../env.sh
kubectl --context $HUB_CONTEXT apply -f namespace.yaml -f dgd.yaml -f crp.yaml
kubectl --context $HUB_CONTEXT get crp chat -w        # wait for Available=True
```

Look at a member:

```bash
kubectl --context $MEMBER_A -n $NS get dgd,pods
kubectl --context $MEMBER_A -n $NS port-forward svc/chat-frontend 8000:8000 &
curl -s localhost:8000/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"chat","messages":[{"role":"user","content":"Say hi in five words."}],"max_tokens":32}'
```

**What this proves:** the hub holds the intent, the members do the serving. No GPU, vLLM
flag or kubeconfig ever reaches the product teams.

First start pulls a ~10 GB runtime image and downloads the weights; allow 10–15 minutes.
