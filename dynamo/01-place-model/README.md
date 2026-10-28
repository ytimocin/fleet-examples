# 01 — Place one model on every GPU cluster

The platform team writes **one** DynamoGraphDeployment on the hub. Fleet copies it to every
member labelled `gpu=true`; the Dynamo operator on each member turns it into pods.

```bash
source ../env.sh
kubectl --context $HUB_CONTEXT apply -f namespace.yaml -f dgd.yaml -f crp.yaml
kubectl --context $HUB_CONTEXT get crp chat -w        # Available=True within a minute
```

Fleet reports `Available` as soon as the DGD is applied; it does not know what a DGD is. Readiness
of the model lives on the member: `kubectl --context $MEMBER_A -n $NS get dgd` shows `READY True`
once the worker has pulled the image and loaded the weights.

Look at a member:

```bash
kubectl --context $MEMBER_A -n $NS get dgd,pods
kubectl --context $MEMBER_A -n $NS port-forward svc/chat-frontend 8000:8000 &
curl -s localhost:8000/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"chat","messages":[{"role":"user","content":"Say hi in five words."}],"max_tokens":32,"chat_template_kwargs":{"enable_thinking":false}}'
```

`enable_thinking: false` matters: Qwen3 otherwise spends the whole token budget inside `<think>`.

**What this proves:** the hub holds the intent, the members do the serving. No GPU, vLLM
flag or kubeconfig ever reaches the product teams.

First start pulls a ~10 GB runtime image and downloads the weights; allow 10–15 minutes.
