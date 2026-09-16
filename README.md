# three-tier-terrafrom-eks-gitops
## Structure 
![project-structure](./docs/imgs/project_structure.png)

---

## Flow 

```
Developer
   │
   ▼
GitHub (source: this repo)
   │
   ▼
GitHub Actions CI  ──▶  lint / build / Trivy scan / build image / push to ECR
   │
   ▼
Update image tag in GitOps config (Helm values or k8s manifest)
   │
   ▼
Argo CD detects the Git change  ──▶  Sync  ──▶  Kubernetes API (EKS)
   │
   ▼
EKS cluster (provisioned by Terraform)
   │
   ├── Frontend Deployment + Service
   ├── Backend Deployment + Service
   ├── MongoDB (StatefulSet)
   ├── AWS Load Balancer Controller → ALB → Ingress → users
   └── Prometheus + Grafana (via Helm) → scrape metrics from pods & cluster
```
**AWS structure**
```
Internet
   │
   ▼
Application Load Balancer (public subnet)
   │
   ▼
VPC
 ├── Public subnets  (2 AZs) — NAT Gateway, ALB
 └── Private subnets (2 AZs) — EKS worker nodes
        └── EKS
             ├── Control plane (AWS-managed)
             └── Worker node group
                  ├── frontend pods
                  ├── backend pods
                  └── monitoring pods (Prometheus/Grafana)

ECR ── holds frontend & backend images
IAM ── IRSA roles scoped per-service (least privilege)
S3 + DynamoDB ── Terraform remote state + lock
```
---

**repo structure**
```
three-tier-eks-iac/
├── app/              
│   ├── backend/
│   │   └── Dockerfile 
│   └── frontend/
│       └── Dockerfile
├── terraform/
│   ├── modules/        
│   └── environments/dev/
├── kubernetes/          
├── helm/                 
├── argocd/   
├── monitoring/
├── .github/workflows/
├── docs/    
└── README.md
```
---

## EKS structure 
        eks
        │
        ├── aws_eks_cluster (control plane — AWS-managed) --> needs Cluster IAM Role
        ├── aws_eks_node_group (worker nodes — live in PRIVATE subnets) --> needs Node IAM Role 
        ├── IAM role for the cluster itself
        ├── IAM role for the node group
        └── OIDC provider FOR THE CLUSTER 

        ecr   
        └── aws_ecr_repository x2 (backend, frontend) —> IaC-managed

---

**IRSA**
- iam role for service account.
- it enables Kubernetes pod get AWS permissions without giving those permissions to every EC2 node.

**OIDC**
- open id connect 
- OIDC allows one system to make verifiable identity claims that another system can trust.
Pod
 └── ServiceAccount
       └── OIDC
            └── IAM Role
                 └── temporary credentials

**Review Roles**
```
Role #1
EKS Control Plane
       ↓
Cluster IAM Role

Purpose:

Give EKS the AWS permissions it needs.

Role #2
EC2 Worker Nodes
       ↓
Node IAM Role

Purpose:

Give worker nodes the AWS permissions they need.

Then later, for IRSA:

Role #3
Kubernetes ServiceAccount
       ↓
Pod IAM Role

Purpose:

Give a specific workload AWS permissions.
```
---
**Why does IRSA need OIDC?**

- OIDC provides a trusted identity mechanism that lets AWS IAM verify that a Kubernetes ServiceAccount belongs to the EKS cluster and should be allowed to assume a particular IAM role.
---

**Access Summarized**
```
                         AWS
                          │
                 ┌────────┴─────────┐
                 │                  │
                VPC                ECR
                 │              ┌────┴────┐
          ┌──────┴──────┐       │         │
          │             │    backend   frontend
       Public        Private
       subnet        subnets
                       │
                       ▼
                     EKS
                       │
              ┌────────┴────────┐
              │                 │
        Control Plane       Node Group
        AWS-managed             │
              │                 │
       Cluster IAM Role         ▼
                          EC2 Worker Nodes
                                │
                                ▼
                               Pods
                                │
                                ▼
                         ServiceAccount
                                │
                                ▼
                         EKS OIDC Provider
                                │
                                ▼
                            IAM Role
                                │
                                ▼
                         AWS permissions
```

## gitops flow 

Developer
    │
    ▼
Git push
    │
    ▼
GitHub Actions
    │
    ├── Test
    ├── Build Docker image
    ├── Trivy scan
    └── Push image → ECR
              │
              ▼
        new image tag
              │
              ▼
        helm/values.yaml
              │
              ▼
          Git commit
              │
              ▼
           Argo CD
              │
              ▼
       helm template/render
              │
              ▼
             EKS