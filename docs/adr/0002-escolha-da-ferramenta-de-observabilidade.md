# ADR-0002 — Escolha da ferramenta de monitoramento e observabilidade

## Status

Aceito

## Contexto

O Tech Challenge Fase 3 exige integração com uma ferramenta de observabilidade, citando Datadog ou
New Relic como exemplos, mas permitindo explicitamente "outra solução equivalente". O ambiente é uma
conta AWS Academy Learner Lab, que impõe uma restrição relevante: **não é possível criar roles ou
policies IAM novas** (só existe a `LabRole` pré-provisionada, sem permissão para editar sua trust
policy). Isso elimina, de saída, qualquer integração baseada em role cross-account assumível por
terceiros — o modelo usado pela "AWS Integration" nativa tanto do Datadog quanto do New Relic.

## Alternativas consideradas

| Opção | Prós | Contras |
|---|---|---|
| **Datadog** | Setup simples, UI polida | Free tier real é muito restrito; o caminho viável é o trial de 14 dias, que expira antes de reavaliações/demonstrações futuras |
| **New Relic** | Setup simples, UI polida, **free tier permanente** (sem cartão, ~100 GB/mês) | Vendor lock-in na instrumentação (mitigável não usando SDKs proprietários onde possível) |
| Prometheus + Grafana + Loki + Tempo (self-hosted no EKS) | Zero conta externa, zero custo, controle total | Esforço de setup e manutenção bem maior (storage, retenção, upgrade) para o escopo do desafio |
| Grafana Cloud | Free tier permanente, baseado em OpenTelemetry (padrão aberto) | Setup de dashboards um pouco mais manual que o New Relic |
| CloudWatch Container Insights + X-Ray (nativo AWS) | Zero conta externa, usa só a AWS Academy já disponível | Instrumentação de tracing (X-Ray) mais trabalhosa; UI de dashboard mais limitada para a demonstração em vídeo |

## Decisão

Usar **New Relic**, com integração via **agentes/coletores** (Infrastructure agent no EKS, APM agent
na aplicação, Lambda Layer nas functions), nunca via a "AWS Integration" nativa baseada em IAM role.

## Justificativa

1. **Restrição de IAM do Academy**: elimina de saída a integração nativa AWS de qualquer ferramenta
   (Datadog, New Relic ou CloudWatch com IRSA completo). O modelo de agente com license key, que só
   precisa de tráfego de saída (HTTPS/443), não esbarra nessa restrição.
2. **Facilidade de setup**: entre as opções restantes, New Relic e Datadog têm o menor esforço de
   configuração (instaladores guiados, charts Helm prontos, dashboards pré-construídos), contra um
   esforço bem maior de um Prometheus/Grafana self-hosted.
3. **Durabilidade do ambiente de demonstração**: diferente do Datadog (cujo caminho viável sem cartão
   é um trial de 14 dias), o free tier do New Relic não expira — importante porque o desafio exige um
   vídeo com os dashboards funcionando, e o ambiente pode precisar continuar demonstrável após a data
   de entrega (reavaliação, apresentação).
4. **Cobertura dos 4 repositórios sem duas integrações desconectadas**: o Infrastructure agent
   instalado uma única vez no EKS cobre 3 dos 4 componentes (cluster, aplicação via APM, banco via
   `nri-postgresql` conectando direto na rede) — só a Lambda precisa de um mecanismo à parte (Layer),
   por ser um modelo de execução efêmero que não comporta um agente de fundo. Essa divisão é inerente
   à diferença entre computação de longa duração e serverless, não uma limitação da ferramenta
   escolhida.

## Consequências

- **Positivas**: setup rápido, sem necessidade de manter infraestrutura própria de observabilidade,
  sem risco de expiração de trial, cobertura completa dos requisitos do desafio (latência, CPU/
  memória, healthchecks, alertas, logs correlacionados, dashboards).
- **Negativas / trade-offs**:
  - Vendor lock-in na instrumentação (os agentes e SDKs são específicos do New Relic). Mitigação
    considerada e descartada por ora: usar OpenTelemetry puro (portável entre ferramentas) exigiria
    mais esforço de setup, contrariando o critério de "fácil" priorizado nesta decisão.
  - Métricas de infraestrutura física do RDS (IOPS, storage) ficam fora de alcance, porque dependem
    da AWS Integration nativa bloqueada pelo Academy — ver
    [`observability/postgres-integration.md`](../../observability/postgres-integration.md) para o que
    é coberto pela alternativa (`nri-postgresql` via conexão direta).
  - Dependência de uma conta externa (ainda que gratuita e permanente): se a conta New Relic for
    perdida ou desativada, o histórico de observabilidade não é recuperável — risco aceito dado o
    escopo educacional do projeto.
