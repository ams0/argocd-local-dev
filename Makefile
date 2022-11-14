#the below is mac-specific
#local=`pwd|cut -c7-`

#if run in Codespaces, uncomment the following
local=`pwd`

local_folder="/minikube-host${local}/.git"

all: start gitea repo argocd root portforward

start:
	echo "starting minikube"
	@minikube start --driver docker --mount

gitea:	
	echo "Adding gitea helm repo"
	@helm repo add gitea-charts https://dl.gitea.io/charts/ >> /dev/null 2>&1  
	@helm repo update  >> /dev/null 2>&1  

	echo "Installing gitea and syncing the ${local_folder} folder"
	
	helm upgrade --wait -i -n gitea --create-namespace gitea gitea-charts/gitea \
        --set "extraVolumes[0].name=host-mount" \
        --set extraVolumes[0].hostPath.path=$(local_folder) \
        --set "extraContainerVolumeMounts[0].name=host-mount" \
        --set "extraContainerVolumeMounts[0].mountPath=/data/git/gitea-repositories/gitea_admin/local-repo.git" \
        --set "initPreScript=mkdir -p /data/git/gitea-repositories/gitea_admin/"
repo:
	echo "Adding the local repo to gitea"
	bash -c 'kubectl --namespace gitea port-forward svc/gitea-http 3000:3000 &';  sleep 2; curl -v -s -XPOST -H "Content-Type: application/json" -k -u 'gitea_admin:r8sA8CPHD9!bt6d' http://localhost:3000/api/v1/admin/unadopted/gitea_admin/local-repo &&  curl -v -s -XPATCH -H "Content-Type: application/json" -k -d '{"private": false}' -u 'gitea_admin:r8sA8CPHD9!bt6d' http://localhost:3000/api/v1/repos/gitea_admin/local-repo
	kill -9 `pgrep kubectl`	

argocd:
	echo "Adding argocd helm repo"
	@helm repo add argo https://argoproj.github.io/argo-helm >> /dev/null 2>&1  
	@helm repo update  >> /dev/null 2>&1  

	echo "installing ArgoCD..."
	@helm upgrade --wait -i argocd -n argocd --create-namespace argo/argo-cd \
	--set server.config."timeout\.reconciliation"="10s" \
	--set configs.params."server\.disable\.auth"=true \
	--set configs.params."server\.insecure"=true \
	--set configs.repositories.local.name=local \
	--set "configs.repositories.local.url=http://gitea-http.gitea.svc.cluster.local:3000/gitea_admin/local-repo.git" >> /dev/null 2>&1  

root:		
	echo "Deploying root app"
	kubectl apply -f root-app.yaml

portforward:
	echo "port forwarding"
	@kubectl port-forward -n argocd svc/argocd-server 8088:80 & 
	echo "opening ArgoCD interface on port 8088"
	@open http://localhost:8088

clean:
	minikube delete
