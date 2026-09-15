terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Configuração parcial: o nome do bucket chega por -backend-config, na pipeline ou localmente.
  # State remoto é obrigatório a partir do momento em que a pipeline também aplica Terraform — sem
  # isso, cada execução da pipeline partiria de um state vazio e tentaria recriar o EKS que já existe.
  backend "s3" {}
}
