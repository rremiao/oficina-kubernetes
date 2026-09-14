# RFC-0001 — Escolha do cluster Kubernetes gerenciado

## Status

Proposto

## Contexto

O Tech Challenge Fase 3 exige um cluster Kubernetes com escalabilidade, provisionado via Terraform,
como parte da infraestrutura obrigatória. A conta usada no desenvolvimento é uma sandbox do AWS
Academy Learner Lab, com uma role fixa (`LabRole`) e sem permissão para criar roles/policies IAM
customizadas.

## Alternativas consideradas

| Opção | Prós | Contras |
|---|---|---|
| **Amazon EKS** | Serviço gerenciado nativo da AWS, já usado nas demais peças da infraestrutura (RDS, Lambda, API Gateway); integra nativamente com IAM, CloudWatch e ELB para o `LoadBalancer` do Service | Custo do control plane fora do free tier padrão (mitigado pelos créditos do Learner Lab) |
| Cluster self-managed (kubeadm em EC2) | Controle total sobre a versão do Kubernetes | Muito mais operação manual (patching, upgrade, HA do control plane) para o escopo do desafio; nenhum ganho didático adicional |
| Outro provedor (GKE/AKS) | Também atenderiam ao requisito | Exigiria migrar API Gateway, Lambda e RDS para outro provedor só para manter tudo no mesmo lugar — sem justificativa técnica, dado que a conta disponível é AWS Academy |

## Decisão

Usar **Amazon EKS**, provisionado neste repositório (`oficina-kubernetes`), com um único node group
gerenciado (`t3.small`, 1 a 2 nodes).

## Justificativa

1. **Consistência com o restante da infraestrutura**: API Gateway, Lambda e RDS já estão na AWS: usar
   EKS evita gerenciar credenciais e integrações para dois provedores de nuvem diferentes.
2. **Escalabilidade nativa**: o node group gerenciado permite `desired/min/max` configuráveis, e o
   HPA (`k8s/05-hpa.yaml`) ajusta o número de réplicas dos Pods pela utilização de CPU — atendendo ao
   requisito de "cluster Kubernetes com escalabilidade" no nível de aplicação, mesmo sem Cluster
   Autoscaler nos nodes (fora do escopo por restrição de permissões do Learner Lab).
3. **Restrição da conta AWS Academy**: o cluster e o node group usam a `LabRole` já existente na
   conta (`data.aws_iam_role.lab_role`), porque o Learner Lab não permite criar roles IAM novas — uma
   configuração 100% "de produção" criaria uma role e uma policy dedicadas para o EKS.

## Consequências

- A infraestrutura do cluster passa a ser provisionada e versionada exclusivamente neste repositório
  (`oficina-kubernetes/infra`), separada do banco (`oficina-database`) e da aplicação (`oficina`).
- Os manifests básicos do workload (`Namespace`, `ConfigMap`, `Secret`, `Deployment`, `Service` tipo
  `LoadBalancer` e `HPA`) também vivem aqui, em `k8s/`, porque descrevem a topologia do cluster em si.
  A imagem Docker da aplicação continua sendo construída e publicada pelo pipeline do repositório
  `oficina` — este repositório apenas referencia a tag da imagem no `Deployment`.
