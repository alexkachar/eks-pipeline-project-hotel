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
