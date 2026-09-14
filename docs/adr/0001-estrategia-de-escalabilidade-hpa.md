# ADR-0001 — Estratégia de escalabilidade via HPA

## Status

Aceito

## Contexto

O desafio exige um cluster Kubernetes "com escalabilidade". A conta AWS Academy Learner Lab não
permite configurar Cluster Autoscaler (exigiria uma role/policy IAM dedicada, que o Lab não libera),
então a escalabilidade fica restrita ao nível de Pods dentro da capacidade fixa do node group.

## Decisão

Usar um **HorizontalPodAutoscaler (HPA)** (`k8s/05-hpa.yaml`) sobre o `Deployment` `oficina-api`,
escalando entre 1 e 3 réplicas por utilização média de CPU (`averageUtilization: 70`), em vez de
Cluster Autoscaler ou VerticalPodAutoscaler.

## Consequências

- **Positivas**: atende ao requisito de escalabilidade do desafio dentro das permissões disponíveis
  no Learner Lab; reage a picos de carga na API sem intervenção manual, dentro do teto de nodes já
  provisionado.
- **Negativas / trade-offs**:
  - O HPA só redistribui Pods entre a capacidade dos nodes já existentes (`node_max_size = 2`). Se a
    carga exceder essa capacidade, novos Pods ficam `Pending` até alguém redimensionar o node group
    manualmente — não há Cluster Autoscaler para isso.
  - `averageUtilization: 70` e `maxReplicas: 3` foram calibrados para o volume de tráfego de um
    ambiente de demonstração/Lab, não para produção real. Uma configuração de produção precisaria de
    testes de carga para calibrar esses números.
