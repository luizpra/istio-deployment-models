# External Control Plane

Testing istio external control plane deployment, reference [link](https://preliminary.istio.io/latest/docs/setup/install/external-controlplane/)

## Prepare the environment

### Unsing kind

```sh
kind create cluster --name external
kind create cluster --name remote-one
kind create cluster --name remote-two
kind create cluster --name remote-three
```
Export clusters contexts
```sh
export CTX_EXTERNAL_CLUSTER=kind-external
export CTX_REMOTE_ONE_CLUSTER=kind-remote-one
export CTX_REMOTE_TWO_CLUSTER=kind-remote-two
export CTX_REMOTE_THREE_CLUSTER=kind-remote-three
```

### Using terraform

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
export CTX_REMOTE_ONE_CLUSTER=$(terraform output -raw  remote-one-context)
export CTX_REMOTE_TWO_CLUSTER=$(terraform output -raw  remote-two-context)
```

Show status of all pods
```sh
kubectl get pods --all-namespaces --context="${CTX_EXTERNAL_CLUSTER}"
kubectl get pods --all-namespaces --context="${CTX_REMOTE_ONE_CLUSTER}"
kubectl get pods --all-namespaces --context="${CTX_REMOTE_TWO_CLUSTER}"
kubectl get pods --all-namespaces --context="${CTX_REMOTE_THEE_CLUSTER}"
```

### External cluster
External cluster will need a load balancer for istio ingress gateway, we will use metallb for this purpose. On `infrastructure/controllers` we have basic infractructure and on `clusters/external` we have configuration for it.
```sh
kubectl apply -k infrastructure/controllers --context="${CTX_EXTERNAL_CLUSTER}"
kubectl apply -k clusters/external --context="${CTX_EXTERNAL_CLUSTER}"
``` 

### Remote one cluster
```sh
kubectl apply -k infrastructure/controllers --context="${CTX_REMOTE_ONE_CLUSTER}"
kubectl apply -k clusters/remote-one --context="${CTX_REMOTE_ONE_CLUSTER}"
``` 

### Remote two cluster
```sh
kubectl apply -k infrastructure/controllers --context="${CTX_REMOTE_TWO_CLUSTER}"
kubectl apply -k clusters/remote-two --context="${CTX_REMOTE_TWO_CLUSTER}"
``` 

### Network model
The `kind docker network` has a specific ip range, the following commando will show it:
```sh
docker network inspect -f '{{.IPAM.Config}}' kind
```
Get `docker container ip address`:
```sh
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' external-control-plane
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' remote-one-control-plane
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' remote-two-control-plane
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' remote-three-control-plane
```

Use the ip range on metallb configure, this ip range will behave as `internet`. To mimic a real DNS environment (over internet) create some entrys on `/etc/hosts` file:
```
...
172.23.0.2      external.k8s
172.23.0.3      remote-one.k8s
172.23.0.4      remote-two.k8s
172.23.0.5      remote-three.k8s
172.23.255.200  external.istio.k8s
```
This is a basic solution, maybe designig a better solution will be a good idea.

## Istio 

### Environment variables
```sh
export PATH=$PATH:~/dev/istio-1.18.0/bin
export REMOTE_CLUSTER_NAME=remote-one
```

#### Set up a gateway in the external cluster
Install gateway in the `istio-system` namespace:
```sh
istioctl install -f istio-operators/controlplane-gateway.yaml --context="${CTX_EXTERNAL_CLUSTER}"
```
Confirm `gateway` is up and running:
```sh
kubectl get po -n istio-system --context="${CTX_EXTERNAL_CLUSTER}"
```

Configure your environment to expose the Istio ingress gateway service using a public hostname with TLS
```sh
export EXTERNAL_ISTIOD_ADDR=$(kubectl -n istio-system --context="${CTX_EXTERNAL_CLUSTER}" get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export SSL_SECRET_NAME=NONE
```

##### Set up the remote config cluster 
```sh
export CTX_REMOTE_CLUSTER=${CTX_REMOTE_ONE_CLUSTER}
```
```sh
kubectl create namespace external-istiod --context="${CTX_REMOTE_CLUSTER}"
istioctl manifest generate -f istio-operators/remote-config-cluster.yaml --set values.defaultRevision=default | kubectl apply --context="${CTX_REMOTE_CLUSTER}" -f -
kubectl get mutatingwebhookconfiguration --context="${CTX_REMOTE_CLUSTER}"
kubectl get validatingwebhookconfiguration --context="${CTX_REMOTE_CLUSTER}"
```

#### Set up the control plane in the external cluster
```sh
kubectl create namespace external-istiod --context="${CTX_EXTERNAL_CLUSTER}"
kubectl create sa istiod-service-account -n external-istiod --context="${CTX_EXTERNAL_CLUSTER}"
istioctl x create-remote-secret \
  --context="${CTX_REMOTE_CLUSTER}" \
  --type=config \
  --namespace=external-istiod \
  --service-account=istiod \
  --server=https://172.23.0.3:6443 \
  --create-service-account=false | \
  kubectl apply -f - --context="${CTX_EXTERNAL_CLUSTER}"
istioctl install -f istio-operators/external-istiod.yaml --context="${CTX_EXTERNAL_CLUSTER}"
kubectl get po -n external-istiod --context="${CTX_EXTERNAL_CLUSTER}"
kubectl apply -f istio-operators/external-istiod-gw.yaml --context="${CTX_EXTERNAL_CLUSTER}"
```

#### Deploy a sample application
```sh
kubectl create --context="${CTX_REMOTE_CLUSTER}" namespace sample
kubectl label --context="${CTX_REMOTE_CLUSTER}" namespace sample istio-injection=enabled
kubectl apply -f ~/dev/istio-1.18.0/samples/helloworld/helloworld.yaml -l service=helloworld -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f ~/dev/istio-1.18.0/samples/helloworld/helloworld.yaml -l version=v1 -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f ~/dev/istio-1.18.0/samples/sleep/sleep.yaml -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl get pod -n sample --context="${CTX_REMOTE_CLUSTER}"
istioctl install -f istio-operators/istio-ingressgateway.yaml --set values.global.istioNamespace=external-istiod --context="${CTX_REMOTE_CLUSTER}"
kubectl get pod -l app=istio-ingressgateway -n external-istiod --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f ~/dev/istio-1.18.0/samples/helloworld/helloworld-gateway.yaml -n sample --context="${CTX_REMOTE_CLUSTER}"
```
```sh
export INGRESS_HOST=$(kubectl -n external-istiod --context="${CTX_REMOTE_CLUSTER}" get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n external-istiod --context="${CTX_REMOTE_CLUSTER}" get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
```
```sh
curl -s "http://${GATEWAY_URL}/hello"
```


### Adding clusters to the mesh
```sh
export CTX_SECOND_CLUSTER=${CTX_REMOTE_TWO_CLUSTER}
export SECOND_CLUSTER_NAME=remote-two
```

```sh
kubectl create namespace external-istiod --context="${CTX_SECOND_CLUSTER}"
kubectl annotate namespace external-istiod "topology.istio.io/controlPlaneClusters=${REMOTE_CLUSTER_NAME}" --context="${CTX_SECOND_CLUSTER}"
istioctl manifest generate -f istio-operators/second-remote-cluster.yaml | kubectl apply --context="${CTX_SECOND_CLUSTER}" -f -
kubectl get mutatingwebhookconfiguration --context="${CTX_SECOND_CLUSTER}"
```
```sh
istioctl x create-remote-secret \
  --context="${CTX_SECOND_CLUSTER}" \
  --name="${SECOND_CLUSTER_NAME}" \
  --type=remote \
  --namespace=external-istiod \
  --server=https://172.23.0.4:6443 \
  --create-service-account=false | \
  kubectl apply -f - --context="${CTX_EXTERNAL_CLUSTER}"
```

Setup east-west gateways
```sh
~/dev/istio-1.18.0/samples/multicluster/gen-eastwest-gateway.sh \
    --mesh mesh1 --cluster "${REMOTE_CLUSTER_NAME}" --network network1 > istio-operators/eastwest-gateway-1.yaml
istioctl manifest generate -f istio-operators/eastwest-gateway-1.yaml \
    --set values.global.istioNamespace=external-istiod | \
    kubectl apply --context="${CTX_REMOTE_CLUSTER}" -f -
```
```sh
~/dev/istio-1.18.0/samples/multicluster/gen-eastwest-gateway.sh \
    --mesh mesh1 --cluster "${SECOND_CLUSTER_NAME}" --network network2 > istio-operators/eastwest-gateway-2.yaml
istioctl manifest generate -f istio-operators/eastwest-gateway-2.yaml \
    --set values.global.istioNamespace=external-istiod | \
    kubectl apply --context="${CTX_SECOND_CLUSTER}" -f -
```
```sh
kubectl --context="${CTX_REMOTE_CLUSTER}" get svc istio-eastwestgateway -n external-istiod
kubectl --context="${CTX_SECOND_CLUSTER}" get svc istio-eastwestgateway -n external-istiod
```

```
kubectl --context="${CTX_REMOTE_CLUSTER}" apply -n external-istiod -f \
    ~/dev/istio-1.18.0/samples/multicluster/expose-services.yaml
```


```sh
kubectl create --context="${CTX_SECOND_CLUSTER}" namespace sample
kubectl label --context="${CTX_SECOND_CLUSTER}" namespace sample istio-injection=enabled
kubectl apply -f ~/dev/istio-1.18.0/samples/helloworld/helloworld.yaml -l service=helloworld -n sample --context="${CTX_SECOND_CLUSTER}"
kubectl apply -f ~/dev/istio-1.18.0/samples/helloworld/helloworld.yaml -l version=v2 -n sample --context="${CTX_SECOND_CLUSTER}"
kubectl apply -f ~/dev/istio-1.18.0/samples/sleep/sleep.yaml -n sample --context="${CTX_SECOND_CLUSTER}"
kubectl get pod -n sample --context="${CTX_SECOND_CLUSTER}"

```
```sh
kubectl exec --context="${CTX_SECOND_CLUSTER}" -n sample -c sleep \
    "$(kubectl get pod --context="${CTX_SECOND_CLUSTER}" -n sample -l app=sleep -o jsonpath='{.items[0].metadata.name}')" \
    -- curl -sS helloworld.sample:5000/hello
for i in {1..100}; do curl -s "http://${GATEWAY_URL}/hello"; done
```


# Troubleshooting