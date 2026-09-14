# ADR-0004 — Dashboards, alerta de negócio e Synthetic Monitor

## Status

Aceito

## Contexto

Além da coleta de infraestrutura (EKS, RDS, Lambda — ADRs 0002 e 0003) e do APM da aplicação, o
Tech Challenge Fase 3 pede explicitamente:

- Alertas para falhas no processamento de ordens de serviço.
- Dashboards de volume diário de OS, tempo médio de execução por status (Diagnóstico, Execução,
  Finalização) e erros/falhas nas integrações.
- Healthchecks e uptime.

Diferente do resto da infraestrutura deste repositório, essas três peças foram configuradas
**direto na UI do New Relic**, não via Terraform/Helm — o New Relic não oferece um provider
Terraform completo para dashboards/alertas dentro do escopo e tempo deste projeto, e configurar via
UI é significativamente mais rápido para o volume de itens aqui (3 widgets, 1 condição de alerta, 1
monitor). Este ADR existe para que a configuração continue rastreável mesmo não estando em código.

## Decisão

### Dashboard: "Oficina - Ordens de Serviço"

Um dashboard com 3 widgets, cada um mapeado a um evento customizado emitido pelo `oficina`
(documentados em [`docs/observabilidade/eventos-customizados.md`](https://github.com/rremiao/oficina/blob/main/docs/observabilidade/eventos-customizados.md)
no repositório da aplicação):

| Widget | Query NRQL | Tipo de gráfico |
|---|---|---|
| Volume diário de ordens de serviço | `SELECT count(*) FROM OrdemServicoStatusAlterado WHERE statusAnterior = 'N/A' TIMESERIES 1 day SINCE 30 days ago` | Line |
| Tempo médio de execução por status | `SELECT average(duracaoMs)/1000 AS 'Duração média (segundos)' FROM OrdemServicoEtapaConcluida FACET etapa SINCE 7 days ago` | Bar |
| Erros e falhas nas integrações | `SELECT count(*) FROM OrdemServicoTransicaoInvalida TIMESERIES 1 day SINCE 30 days ago FACET acao` | Bar |

A terceira query cobre falhas de **regra de negócio** no processamento da OS (ex.: tentar aprovar
uma OS já entregue) — é o sentido de "falha no processamento" mais diretamente ligado ao módulo
`ordemservico`. Falhas técnicas de integração entre componentes (Lambda, API Gateway, banco) já são
cobertas separadamente pelos alarmes do `oficina-lambda` (`infra/observability.tf`) e pela taxa de
erro geral do APM da aplicação.

### Alert Policy: "Oficina - Processamento de OS"

Uma NRQL Alert Condition, "Falha no processamento de ordem de serviço":

- **Query**: `SELECT count(*) FROM OrdemServicoTransicaoInvalida`
- **Threshold**: `above 0`, `for at least 1 minute`, severidade `Critical`
- **Agregação**: janela de 1 minuto, streaming method `Event flow`, delay de 2 minutos (padrão)
- Sem destination de notificação configurado no momento — o issue aparece em
  **Alerts → Issues & Activity** mesmo sem canal de notificação (email/Slack), o que já atende ao
  requisito de "alertas configurados". Adicionar uma notificação real é natural de fazer depois, se
  quiser receber aviso ativo em vez de só consultar o painel.

### Synthetic Monitor: "oficina-api - uptime"

- **Tipo**: Ping
- **URL**: endpoint público do `Service` LoadBalancer, rota `/oficina/v1/api-docs` (mesma usada
  pelos probes de liveness/readiness do `Deployment` — reaproveita um endpoint que já precisa estar
  de pé para o próprio Kubernetes considerar o pod saudável)
- **Locations**: Washington DC (EUA) e Columbus OH (EUA) — proximidade geográfica com a região AWS
  (`us-east-1`) onde a aplicação roda — mais Dublin (IE), para diversificar região e reduzir falso
  positivo de rede local, conforme a própria recomendação do New Relic ("pelo menos 3 locations em
  regiões diferentes")
- **Frequência**: a cada 5 minutos
- **Response code esperado**: 200

## Validação

Testado numa implantação real:

1. **Dashboards**: os 3 widgets populados com dado real de uma OS (`OS-2026-000001`) levada pelo
   ciclo de vida completo — gráfico de volume mostrou o pico da criação, o de duração por etapa
   mostrou os três estágios (Diagnóstico/Execução/Finalização), e o de erros mostrou a tentativa de
   transição inválida.
2. **Alerta**: a mesma transição inválida (tentar aprovar uma OS já entregue) foi disparada de novo
   propositalmente, e um issue `Active`/`Critical` apareceu em Alerts → Issues & Activity dentro de
   ~1-2 minutos, com a entidade `oficina-api` associada.
3. **Synthetic Monitor**: criado e habilitado; a primeira execução real depende da frequência
   configurada (até 5 minutos após a criação).

## Consequências

- **Positivas**: os três requisitos de dashboards, o alerta de negócio e o uptime ficam cobertos
  com evidência de funcionamento real, não só configuração no papel.
- **Negativas / trade-offs**:
  - Configuração feita via UI, não versionada como código — uma reinstalação do zero da conta New
    Relic exigiria refazer esses passos manualmente, seguindo este documento como roteiro.
  - Sem canal de notificação (email/Slack) configurado no alerta — o issue fica visível só pra quem
    olha o painel do New Relic, não gera um aviso ativo. Fácil de adicionar depois
    (Alerts → Destinations → Email), não fizemos por não ser exigido pelo enunciado.
