#!/usr/bin/env bash 
# DON'T run this randomly , i created it when i was building this project 
# these are separate commands to run during stages to build different stages 

# create two ECR repos on AWS (one for backend, and another for frontend)
# reference: https://docs.aws.amazon.com/AmazonECR/latest/userguide/getting-started-cli.html
aws ecr create-repository --repsoitory-name backend-app --region us-east-1 
aws ecr create-repository --repsoitory-name frontend-app --region us-east-1 

# to delete ecr repo : 
aws ecr delete-repository --repository-name --force backend-app --region us-east-1
aws ecr delete-repository --repository-name --force frontend-app --region us-east-1


#=====================================================================
# configure the s3 backend for terrafrom 
# create the s3 bucket 
aws s3api create-bucket \
  --bucket three-tier-terraform-eks-gitops-bucket \
  --region us-east-1

# enbale versioning 
aws s3api put-bucket-versioning \
  --bucket three-tier-terraform-eks-gitops-bucket \
  --versioning-configuration Status=Enabled

# create a dynamoDB table with a table named "lockID", terraform requires this exact name
# dynamodb locking became legacy now, use s3-native locking these days.
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1


## for me 

private_subnet_ids = [
  "subnet-0893a1fb5eb8d13c2",
  "subnet-082ea9bba24e66b2b",
]
public_subnet_ids = [
  "subnet-022a1996339ca3db1",
  "subnet-0710689555f475ac0",
]
vpc_id = "vpc-0d5652fcb82a0ff6b"

## import the two ECR repositories 
terraform import \
  'module.ecr.aws_ecr_repository.backend' \
  backend-app

terraform import \
  'module.ecr.aws_ecr_repository.frontend' \
  frontend-app


# connect kubectl to the eks cluster 
aws eks update-kubeconfig --region us-east-1 --name dev-eks

# ECR
# get images tags for repos
aws ecr describe-repositories   # list repos 
aws ecr describe-images --repsoitory-name frontend-app 

#===============================================================================
# helm 
#===============================================================================
# create helm chart
cd helm 
helm create my-app  # it will create the template files.

# after adding all helm files and configure values:
helm lint ./helm   # check for common problems 
helm template three-tier ./helm  # render but don't apply  (replace templates with actual values from values.yaml)

# install once the rendering from helm template looks right.
# at install time provide your secrets with --set 
helm install three-tier ./helm -n three-tier --set backend.mongoConnStr='mongodb://user:pass@host:27017/tasks?authSource=admin'


# inspect
helm list -n three-tier 
helm status three-tier -n three-tier
kubectl get all -n three-tier


# to verify that helm is controlling it :
# change replicas in values to 3 
# then 
helm upgrade three-tier ./helm -n three-tier 

k get all -n three-tier 

# check history and rollback to another version 
helm history three-tier -n three-tier
helm rollback three-tier 1 -n three-tier

# helm commands in a glance 
helm lint ./helm
helm template three-tier ./helm
helm install three-tier ./helm -n three-tier
helm list -n three-tier
helm status three-tier -n three-tier
helm upgrade three-tier ./helm -n three-tier
helm history three-tier -n three-tier
helm rollback three-tier <revision> -n three-tier

#===============================================================================
# Argo CD 
#===============================================================================

# 1. create the namespace 
kubectl create namespace argocd 

# 2. add the argo helm repo
helm repo add argo https://argoproj.github.io/argo-helm

# 3. update 
helm repo update 

# 4. install argocd 
helm install argocd argo/argo-cd -n argocd 

# 5. forward the traffic (a temp solution before using ingress)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 6. access the ui 
browse --> localhost:8080

# 7. write the application.yaml file and deploy it 
kubectl apply -f argocd/application.yaml


# 8. check status 
kubectl get applications -n argocd

# 9. apply some changes in helm/values.yaml 

##################################################################################### 

# install the service account and controller 
kubectl apply -f kubernetes/alb-controller-serviceaccount.yaml

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=dev-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set vpcId=fdsajl239dsskj

################## monitoring ############################
cd app/backend 
npm install prom-client 

