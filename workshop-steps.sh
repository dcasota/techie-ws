#!/bin/sh

echo -n "Enter your Docker Hub username and press [ENTER]: "
read DOCKER_USERNAME
echo -n "Enter your Docker Hub password and press [ENTER]: "
read DOCKER_PASSWORD

echo -n "Enter your Github Node https://github.com/yourname/node and press [ENTER]: "
read GITHUB_NODE

echo -n "Enter your Github Petclinic fork https://github.com/yourname/spring-petclinic and press [ENTER]: "
read GITHUB_PETCLINIC


cd /root

tdnf install -y curl tar kubernetes git openjdk11 conntrack jq kubernetes-kubeadm

iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 8080 -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables-save >/etc/systemd/scripts/ip4save
curl -LO https://github.com/pivotal/kpack/releases/download/v0.2.2/release-0.2.2.yaml
kubectl get ns
kubectl apply -f release-0.2.2.yaml
kubectl get crds
kubectl get all -n kpack
echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin

cat <<EOFCred> ./dockerhub-registry-credentials.yaml
apiVersion: v1
kind: Secret
metadata:
  name: dockerhub-registry-credentials
  annotations:
    kpack.io/docker: https://index.docker.io/v1/
type: kubernetes.io/basic-auth
stringData:
  username: $DOCKER_USERNAME
  password: $DOCKER_PASSWORD
EOFCred
kubectl apply -f ./dockerhub-registry-credentials.yaml
read -p "Press a key to continue."

cat <<EOFsvc> ./dockerhub-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dockerhub-service-account
secrets:
- name: dockerhub-registry-credentials
imagePullSecrets:
- name: dockerhub-registry-credentials
EOFsvc
kubectl apply -f ./dockerhub-service-account.yaml
read -p "Press a key to continue."

cat <<EOFstore> ./store.yaml
apiVersion: kpack.io/v1alpha1
kind: ClusterStore
metadata:
  name: default
spec:
  sources:
  - image: gcr.io/paketo-buildpacks/nodejs
EOFstore
kubectl apply -f ./store.yaml
kubectl get clusterstore
kubectl describe clusterstore
read -p "Press a key to continue."


cat <<EOFpaketo> ./stack.yaml
apiVersion: kpack.io/v1alpha1
kind: ClusterStack
metadata:
  name: base
spec:
  id: "io.buildpacks.stacks.bionic"
  buildImage:
    image: "paketobuildpacks/build:1.0.24-base-cnb"
  runImage:
    image: "paketobuildpacks/run:1.0.24-base-cnb"
EOFpaketo
kubectl apply -f ./stack.yaml
kubectl get clusterstack
kubectl describe clusterstack
read -p "Press a key to continue."

cat <<EOFbuilder> ./builder.yaml
apiVersion: kpack.io/v1alpha1
kind: Builder
metadata:
  name: ws-builder
  namespace: default
spec:
  serviceAccount: dockerhub-service-account
  tag: index.docker.io/<DOCKER_USERNAME>/ws-builder
  stack:
    name: base
    kind: ClusterStack
  store:
    name: default
    kind: ClusterStore
  order:
  - group:
    - id: paketo-buildpacks/nodejs
EOFbuilder
kubectl apply -f ./builder.yaml
kubectl get builders
kubectl describe builder ws-builder
read -p "Press a key to continue."

curl -s -S "https://registry.hub.docker.com/v2/repositories/$DOCKER_USERNAME/" | jq .
read -p "Press a key to continue."

cat <<EOFimagenode> ./dockerhub-image-node.yaml
apiVersion: kpack.io/v1alpha1
kind: Image
metadata:
  name: hello-node
  namespace: default
spec:
  tag: index.docker.io/$DOCKER_USERNAME/cnb-hello-node
  serviceAccount: dockerhub-service-account
  builder:
    name: ws-builder
    kind: Builder
  source:
    git:
      url: $GITHUB_NODE
      revision: main
EOFimagenode
kubectl apply -f ./dockerhub-image-node.yaml
read -p "Press a key to continue."

cat <<EOFlog> ./logs.sh
#!/bin/bash

if [ "$1" == "" ]
then
  echo "usage: $0 image-build-pod-name"
  exit 1
fi

BLUE="\033[0;36m"; NORM="\033[0m"

POD="$1"

CONTAINERS=$(kubectl get pod $POD -o json | jq ".spec.initContainers[].name" | tr -d '"')

for container in $CONTAINERS completion
do
  echo ""; echo -e "${BLUE}---- $container ----${NORM}"; echo ""
  kubectl logs $POD -c $container -f
  if [ $container != "completion" ]
  then
    read -p "[Enter to continue]" ans
  fi
done
EOFlog
chmod 755 ./logs.sh
kubectl get pods

# run log
./logs.sh 

kubectl create deployment cnb-hello-node --image=$DOCKER_USERNAME/cnb-hello-node
kubectl expose deployment/cnb-hello-node --port 8080 --type LoadBalancer
minikube service cnb-hello-node

cat <<EOFfullstore> ./store-full.yaml
apiVersion: kpack.io/v1alpha1
kind: ClusterStore
metadata:
  name: default
spec:
  sources:
  - image: gcr.io/paketo-buildpacks/java
  - image: gcr.io/paketo-buildpacks/graalvm
  - image: gcr.io/paketo-buildpacks/java-azure
  - image: gcr.io/paketo-buildpacks/nodejs
  - image: gcr.io/paketo-buildpacks/dotnet-core
  - image: gcr.io/paketo-buildpacks/go
  - image: gcr.io/paketo-buildpacks/php
  - image: gcr.io/paketo-buildpacks/nginx
EOFfullstore
kubectl apply -f ./store-full.yaml
read -p "Press a key to continue."

cat <<EOFfullbuilder> ./builder-full.yaml
apiVersion: kpack.io/v1alpha1
kind: Builder
metadata:
  name: ws-builder
  namespace: default
spec:
  serviceAccount: dockerhub-service-account
  tag: index.docker.io/demosteveschmidt/ws-builder
  stack:
    name: base
    kind: ClusterStack
  store:
    name: default
    kind: ClusterStore
  order:
  - group:
    - id: paketo-buildpacks/java
  - group:
    - id: paketo-buildpacks/java-azure
  - group:
    - id: paketo-buildpacks/graalvm
  - group:
    - id: paketo-buildpacks/nodejs
  - group:
    - id: paketo-buildpacks/dotnet-core
  - group:
    - id: paketo-buildpacks/go
  - group:
    - id: paketo-buildpacks/nginx
EOFfullbuilder
kubectl apply -f ./builder-full.yaml
read -p "Press a key to continue."

curl -s -S "https://registry.hub.docker.com/v2/repositories/$DOCKER_USERNAME/ws-builder/tags/" | jq .
read -p "Press a key to continue."

cat <<EOFpetclinic> ./dockerhub-image.yaml
apiVersion: kpack.io/v1alpha1
kind: Image
metadata:
  name: petclinic-image
  namespace: default
spec:
  tag: index.docker.io/$DOCKER_USERNAME/petclinic
  serviceAccount: dockerhub-service-account
  builder:
    name: ws-builder
    kind: Builder
  source:
    git:
      url: $GITHUB_PETCLINIC
      revision: e2fbc561309d03d92a0958f3cf59219b1fc0d985
EOFpetclinic
kubectl apply -f ./dockerhub-image.yaml
kubectl get pods
kubectl get image
read -p "Press a key to continue."


kubectl get build
kubectl get pods
kubectl logs petclinic-image-build-1-bh9r4-build-pod -c build -f


curl -s -S '"https://registry.hub.docker.com/v2/repositories/$DOCKER_USERNAME/" | jq .





