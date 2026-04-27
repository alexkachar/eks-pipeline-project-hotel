variable "project_name" {
  description = "Short project identifier used in SSM parameter paths."
  type        = string
}

variable "environment" {
  description = "Environment name used in KMS key naming."
  type        = string
}
