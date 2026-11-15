# ADR-0006 — Capacidade do cluster para a Fase 4

## Status

Aceito

## Contexto

Na Fase 3 o cluster rodava um único backend. O pipeline aplica o Terraform só com os valores padrão
de `infra/variables.tf` (o `terraform.tfvars` não é versionado), e esses padrões eram 1 node
`t3.small` — menos até do que o [ADR-0003](0003-licoes-da-primeira-implantacao-real.md) já tinha
mostrado ser necessário.

Na Fase 4 o namespace `oficina` passa a ter:

| Workload | Pods |
|---|---|
| OS Service, Billing Service, Execution Service (Java, com agente New Relic) | 3 ou mais (HPA) |
| RabbitMQ (StatefulSet do OS Service) | 1 |
| MongoDB do Execution Service | 1 |
| Bundle e operator do New Relic | cerca de 8 |
| Sistema do EKS (aws-node, kube-proxy, CoreDNS) | cerca de 4 |

Um `t3.small` aceita 11 pods (limite de ENI/IP) e tem 2 GB de memória. Só os três serviços Java pedem
perto disso em memória, e a soma de pods passa do limite de dois nodes.

## Decisão

Padrões do node group: `t3.medium` (17 pods e 4 GB por node), `desired_size = 2`, `min_size = 1`,
`max_size = 3`. Os mesmos valores estão em `terraform.tfvars.example`.

## Consequências

- Cabem cerca de 34 pods e 8 GB, com folga para o HPA subir réplicas.
- Custa mais crédito do Learner Lab por hora do que `t3.small`. Destruir o cluster ao fim de cada
  rodada de testes continua sendo a recomendação.
- Se a conta do Learner Lab recusar `t3.medium`, a alternativa é voltar para `t3.small` com
  `node_desired_size = 3` e `node_max_size = 3`.
