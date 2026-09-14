# Infraestrutura do cluster Kubernetes (EKS) da oficina.
#
# Extraído do repositório `oficina` (infra/aws/main.tf), que hoje concentra tanto o cluster quanto o
# RDS num único state. Este repositório passa a ser dono apenas do EKS, conforme a segregação de
# repositórios exigida pelo Tech Challenge Fase 3.

data "aws_caller_identity" "current" {}

data "aws_iam_role" "lab_role" {
  name = var.lab_role_name
}

data "aws_vpc" "default" {
  default = true
}

# Subnets válidas para o EKS neste AWS Academy/Learner Lab. Algumas AZs são excluídas via
# var.availability_zones porque o EKS retornou UnsupportedAvailabilityZoneException nelas.
data "aws_subnets" "eks" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availability-zone"
    values = var.availability_zones
  }
}

locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
    Lab       = "aws-academy"
    Repo      = "oficina-kubernetes"
  }
}

resource "aws_ec2_tag" "subnet_cluster_tag" {
  for_each = toset(data.aws_subnets.eks.ids)

  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "subnet_elb_tag" {
  for_each = toset(data.aws_subnets.eks.ids)

  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.lab_role.arn

  vpc_config {
    subnet_ids              = data.aws_subnets.eks.ids
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = merge(local.common_tags, {
    Name = var.cluster_name
  })

  depends_on = [
    aws_ec2_tag.subnet_cluster_tag,
    aws_ec2_tag.subnet_elb_tag
  ]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = data.aws_iam_role.lab_role.arn
  subnet_ids      = data.aws_subnets.eks.ids

  instance_types = [var.node_instance_type]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-node-group"
  })

  depends_on = [
    aws_eks_cluster.this
  ]
}
