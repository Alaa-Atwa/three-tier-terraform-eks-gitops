module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = true # only one for this project, due to the cost
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = "dev-eks"
  private_subnet_ids = module.vpc.private_subnet_ids
  # Pass those IDs into the EKS module's private_subnet_ids variable.

  node_instance_type = "t3.small"

  node_desired_size = 2
  node_min_size     = 1
  node_max_size     = 2
}

module "ecr" {
  source = "../../modules/ecr"

  backend_repository_name  = "backend-app"
  frontend_repository_name = "frontend-app"
}

module "irsa_alb"{
  source = "../../modules/irsa-alb"
  cluster_name = "dev-eks"
}

module "monitoring" {
  source = "../../modules/monitoring"
}