output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private (cluster) subnet IDs."
  value       = module.network.private_subnet_ids
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint (private)."
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks.cluster_arn
}

output "kubeconfig_command" {
  description = "Run this from inside the VPC (e.g. a bastion) to get kubectl access."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID."
  value       = module.bastion.instance_id
}

output "bastion_ssm_session_command" {
  description = "Copy-paste command to start an SSM session into the bastion."
  value       = module.bastion.ssm_session_command
}
