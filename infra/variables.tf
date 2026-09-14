variable "aws_region" {
  description = "Região AWS usada no Learner Lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome base dos recursos."
  type        = string
  default     = "oficina"
}

variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
  default     = "oficina-eks"
}

variable "lab_role_name" {
  description = "Role padrão do AWS Academy/Learner Lab, usada tanto pelo cluster quanto pelo node group."
  type        = string
  default     = "LabRole"
}

variable "node_instance_type" {
  description = "Tipo da instância EC2 usada no node group."
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes no node group."
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Quantidade mínima de nodes no node group."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade máxima de nodes no node group."
  type        = number
  default     = 2
}

variable "availability_zones" {
  description = <<EOT
Availability Zones elegíveis para as subnets do EKS. Algumas AZs (ex.: us-east-1e) não suportam EKS
em determinadas contas do AWS Academy Learner Lab (UnsupportedAvailabilityZoneException) — ajuste
esta lista caso a região/conta usada tenha restrições diferentes.
EOT
  type        = list(string)
  default = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c",
    "us-east-1d",
    "us-east-1f"
  ]
}
