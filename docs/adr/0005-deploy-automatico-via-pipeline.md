# ADR-0005 — Deploy automático do Terraform via pipeline, com state remoto

## Status

Aceito

## Contexto

O enunciado do Tech Challenge exige que as pipelines dos repositórios de infraestrutura "validem e
apliquem" o Terraform, não só validem. Até este ADR, `infra-kubernetes.yml` só validava (Terraform +
manifests) — o `apply` era sempre manual, e o Terraform usava **state local**, nunca commitado.

Os mesmos dois problemas do `oficina-database` valiam aqui:

1. **State local não sobrevive entre execuções da pipeline** — sem state remoto, um `apply`
   automático tentaria recriar o cluster EKS que já existe.
2. **Credenciais do AWS Academy são de sessão** — não impedem um `apply` pontual automatizado, mas
   impedem que a pipeline funcione sozinha indefinidamente sem alguém atualizar os secrets.

## Decisão

1. Adotar **backend S3 parcial** (`backend "s3" {}`), bucket criado manualmente uma vez (bootstrap,
   documentado no README) — mesmo padrão do `oficina-lambda` e do `oficina-database`.
2. Adicionar um job `deploy` que roda `terraform apply -auto-approve` em push na `main` (ou disparo
   manual), usando os 3 secrets de credenciais AWS + a variável `TF_STATE_BUCKET`.
3. **Escopo do `deploy` limitado ao Terraform** (o cluster EKS) — não estender pra `kubectl apply`
   dos manifests nem pro `helm install` do New Relic nesta pipeline. Esses dois passos continuam
   manuais, documentados no [runbook](../runbook-ambiente-completo.md).

## Justificativa

- Resolve o "deploy automático" exigido pelo enunciado dentro do que é honestamente possível no AWS
  Academy — automático enquanto a sessão do Lab está ativa e os secrets foram atualizados, mesma
  lógica já aceita pro `oficina`/`oficina-lambda`.
- **Por que não automatizar também os manifests/New Relic nesta mesma pipeline**: esses passos
  dependem de segredos (license key do New Relic, senha do usuário `newrelic_monitor` do Postgres)
  que hoje só existem como Secret do Kubernetes dentro do cluster, não como GitHub Secret — trazê-los
  pra cá duplicaria onde os segredos moram, sem necessidade. Também dependem da ordem de outros
  repositórios (o `ConfigMap` da app só pode ser aplicado depois do RDS existir, no
  `oficina-database`), o que uma única pipeline deste repositório não tem como orquestrar sozinha
  sem acoplar os 3 repositórios de infraestrutura numa única pipeline — o que contrariaria a própria
  segregação de repositórios pedida no desafio.

## Consequências

- **Positivas**: pipeline atende literalmente ao texto do enunciado pra provisionamento do cluster.
- **Negativas / trade-offs**:
  - Mesmo trade-off do `oficina-database`: secrets de AWS precisam ser atualizados manualmente a
    cada sessão nova do Lab.
  - Mais um bucket S3 (`oficina-kubernetes-tfstate-<account-id>`) fora do ciclo de vida do
    `terraform destroy` deste repositório.
  - A automação fica "parcial" no sentido de que só o cluster sobe sozinho — a aplicação em si
    (manifests + New Relic) continua exigindo os passos manuais do runbook. Aceito conscientemente:
    o alternativa (orquestrar os 3 repositórios de infra numa pipeline só) seria pior pro objetivo de
    repositórios independentes que o desafio pede.
