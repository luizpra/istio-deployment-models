# istio-external-control-plane-test

Testing istio external control plane deployment, reference [link](https://preliminary.istio.io/latest/docs/setup/install/external-controlplane/)

## Prepare the environment

Go to [terraform folder](tf) folder:
```sh
cd tf
```
Spin up the k8s clusters with `terraform` cli:
```sh
terraform init
terraform apply
```
Export environment variables
```sh
export CTX_EXTERNAL_CLUSTER=$(terraform output -raw  external-context)
export CTX_REMOTE_CLUSTER=$(terraform output -raw  remote-one-context)
export REMOTE_CLUSTER_NAME=$(terraform output -raw  remote-two-context)
```

## External cluster

```sh
kubectl apply -k infrastructure/controllers --context="${CTX_EXTERNAL_CLUSTER}"
```


















Run `terraform init and apply`  to create clusters
```sh
cd tf
terraform init
terraform apply
```

Apply kustomization on `external` and `remote` clusters
```sh
kubectl apply -k kustomization/external --context="${CTX_EXTERNAL_CLUSTER}"
kubectl apply -k kustomization/remote --context="${CTX_REMOTE_CLUSTER}"
```
Delete kustomizations on `external` and `remote` clusters
```sh
kubectl delete -k kustomization/external --context="${CTX_EXTERNAL_CLUSTER}"
kubectl delete -k kustomization/external --context="${CTX_REMOTE_CLUSTER}"
```

## Istio configurarion

### External cluster
```sh
${ISTIO_HOME}/istioctl install -f controlplane-gateway.yaml --context="${CTX_EXTERNAL_CLUSTER}"
```
Check istio pods
```sh
kubectl get po -n istio-system --context="${CTX_EXTERNAL_CLUSTER}"
```

### Remote cluster
```sh
kubectl create namespace external-istiod --context="${CTX_REMOTE_CLUSTER}"
${ISTIO_HOME}/istioctl manifest generate -f remote-config-cluster.yaml --set values.defaultRevision=default | kubectl apply --context="${CTX_REMOTE_CLUSTER}" -f -
```

```sh
kubectl get mutatingwebhookconfiguration --context="${CTX_REMOTE_CLUSTER}"
kubectl get validatingwebhookconfiguration --context="${CTX_REMOTE_CLUSTER}"
```

Configure control plane in external cluster
```sh
kubectl create namespace external-istiod --context="${CTX_EXTERNAL_CLUSTER}"
kubectl create sa istiod-service-account -n external-istiod --context="${CTX_EXTERNAL_CLUSTER}"
```

```sh
${ISTIO_HOME}/istioctl x create-remote-secret \
  --context="${CTX_REMOTE_CLUSTER}" \
  --type=config \
  --namespace=external-istiod \
  --service-account=istiod \
  --server=https://remote-control-plane:6443 \
  --create-service-account=false | \
  kubectl apply -f - --context="${CTX_EXTERNAL_CLUSTER}"
```

```sh
${ISTIO_HOME}/istioctl install -f external-istiod.yaml --context="${CTX_EXTERNAL_CLUSTER}"
```
```sh
kubectl get po -n external-istiod --context="${CTX_EXTERNAL_CLUSTER}"
```
```sh
kubectl apply -f external-istiod-gw.yaml --context="${CTX_EXTERNAL_CLUSTER}"
```

kubectl apply -f ${ISTIO_HOME}/../samples/helloworld/helloworld.yaml -l service=helloworld -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f ${ISTIO_HOME}/../samples/helloworld/helloworld.yaml -l version=v1 -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f ${ISTIO_HOME}/../samples/sleep/sleep.yaml -n sample --context="${CTX_REMOTE_CLUSTER}"




cat <<EOF > istio-ingressgateway.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: empty
  components:
    ingressGateways:
    - namespace: external-istiod
      name: istio-ingressgateway
      enabled: true
  values:
    gateways:
      istio-ingressgateway:
        injectionTemplate: gateway
EOF
${ISTIO_HOME}/istioctl install -f istio-ingressgateway.yaml --set values.global.istioNamespace=external-istiod --context="${CTX_REMOTE_CLUSTER}"



kubectl apply -f ${ISTIO_HOME}/../samples/helloworld/helloworld-gateway.yaml -n sample --context="${CTX_REMOTE_CLUSTER}"


