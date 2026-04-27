locals {
  cluster_name = "${var.project_name}-${var.environment}-cluster"
}

module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment
  cluster_name = local.cluster_name
}

module "iam_roles" {
  source = "./modules/iam-roles"

  project_name = var.project_name
  environment  = var.environment
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

module "eks" {
  source = "./modules/eks"

  project_name        = var.project_name
  environment         = var.environment
  cluster_name        = local.cluster_name
  cluster_version     = var.cluster_version
  subnet_ids          = module.network.private_subnet_ids
  cluster_role_arn    = module.iam_roles.cluster_role_arn
  node_role_arn       = module.iam_roles.node_role_arn
  ebs_csi_role_arn    = module.iam_roles.ebs_csi_role_arn
  admin_principal_arn = var.admin_principal_arn
}

module "rds" {
  source = "./modules/rds"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.network.vpc_id
  db_subnet_ids             = module.network.db_subnet_ids
  cluster_security_group_id = module.eks.cluster_security_group_id
}

module "bastion" {
  source = "./modules/bastion"

  project_name = var.project_name
  environment  = var.environment
  region       = var.region
  vpc_id       = module.network.vpc_id
  vpc_cidr     = module.network.vpc_cidr

  # Spec deviation, see modules/bastion/README.md. The bastion is launched
  # in the runner subnet (NAT egress) rather than the private subnet (no
  # default route) so its first-boot user-data can download kubectl, helm
  # and the argocd CLI. SSM-only access posture is unchanged.
  subnet_id = module.network.runner_subnet_ids[0]

  cluster_name              = module.eks.cluster_name
  cluster_arn               = module.eks.cluster_arn
  cluster_security_group_id = module.eks.cluster_security_group_id
}
