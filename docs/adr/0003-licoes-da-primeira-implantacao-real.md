# ADR-0003 — Ajustes descobertos na primeira implantação real do New Relic

## Status

Aceito

## Contexto

O [ADR-0002](0002-escolha-da-ferramenta-de-observabilidade.md) decidiu usar New Relic via agentes.
Este documento registra os ajustes necessários, descobertos apenas ao aplicar a infraestrutura de
verdade numa conta AWS Academy — nenhum deles era previsível só lendo a documentação do chart. Existe
para que a próxima pessoa (ou a próxima sessão) não repita a mesma depuração.

## Ajustes necessários

### 1. `t3.small` satura com 1 node só

O node group foi criado com `node_desired_size = 1`. O `helm install` do `nri-bundle` ficou parado
até estourar o timeout de 5 minutos: um dos pods (`nri-metadata-injection-admission-patch`, um job de
patch de certificado do webhook) nunca conseguia ser agendado — `0/1 nodes are available: 1 Too many
pods`. Uma instância `t3.small` no EKS suporta um número baixo de pods (limite de ENI/IP da própria
instância, não de CPU/memória), e os pods de sistema (CoreDNS, kube-proxy, aws-node) somados aos 7
pods do bundle já esgotavam essa cota.

**Correção**: `node_desired_size = 2` (dentro do `node_max_size` que já existia). Refletido no
[`terraform.tfvars.example`](../../infra/terraform.tfvars.example).

### 2. `Instrumentation` CR: `apiVersion` errado e campo obrigatório faltando

A primeira versão do [`06-newrelic-instrumentation.yaml`](../../k8s/06-newrelic-instrumentation.yaml)
usava `apiVersion: newrelic.com/v1alpha2` com só `agent.language: java`. O admission webhook rejeitou
com `"agent is empty"` — mensagem enganosa, porque o campo *não* estava vazio.

Duas causas, encontradas consultando o
[CRD instalado](https://github.com/newrelic/k8s-agents-operator) diretamente (`kubectl explain`) e um
[sample real do repositório](https://github.com/newrelic/k8s-agents-operator/blob/main/config/samples/v1alpha2_instrumentation.yaml):

- O CRD tem 4 versões (`v1alpha2`, `v1beta1`, `v1beta2`, `v1beta3`), mas só `v1beta3` é a *storage
  version*. Usar uma versão não-storage aciona conversão entre schemas, que nesse caso perdia o
  valor do campo.
- **`agent.image` é obrigatório**, não só `agent.language`. Sem ele, o agent é considerado "vazio"
  mesmo com a linguagem definida — é a imagem do init container que efetivamente injeta o
  `newrelic-agent.jar` (`newrelic/newrelic-java-init:latest`).

**Correção**: `apiVersion: newrelic.com/v1beta3` + `agent.image` explícito no manifest.

### 3. Nome da chave dentro do Secret da license key

O `Instrumentation` CR aponta `licenseKeySecret: newrelic-license`, mas o operator busca uma chave
**com nome fixo** dentro desse Secret: `new_relic_license_key`. O resto do bundle (Infrastructure
agent) usa a chave `licenseKey`, configurável via `global.customSecretLicenseKey` — uma convenção
completamente diferente, e nenhuma delas gera erro quando a chave não existe (a referência é
`optional: true`), então o sintoma não é "Secret not found", é o agente Java logando
`license_key is empty in the config. Not starting New Relic Agent.` — só visível nos logs do pod, não
em `kubectl get`/`describe`.

**Correção**: o Secret no namespace `oficina` (onde o `Instrumentation` e os Pods da app vivem)
precisa ter as duas chaves — `licenseKey` e `new_relic_license_key` — com o mesmo valor. Refletido em
[`newrelic-secret.example.yaml`](../../observability/newrelic-secret.example.yaml).

### 4. `nri-postgresql`: `COLLECTION_LIST` e SSL

A integração de Postgres (usada para monitorar o RDS do `oficina-database`) tem duas pegadinhas de
configuração, encontradas só depois de consultar o
[sample oficial do `nri-postgresql`](https://github.com/newrelic/nri-postgresql/blob/master/postgresql-config.yml.sample):

- `COLLECTION_LIST` é um **array JSON simples de nomes de banco** (`'["oficina"]'`), não um objeto
  aninhado por schema/tabela. Um valor no formato errado falha silenciosamente com
  `Error creating list of entities to collect: failed to parse collection list`, sem indicar qual
  parte do valor está errada.
- Em RDS/Aurora, além de `TRUST_SERVER_CERTIFICATE: "true"` (obrigatório porque o certificado é
  gerenciado pela AWS, não por quem está configurando a integração), também vale setar
  `IS_RDS: "true"` para habilitar os ajustes de query performance monitoring específicos desses
  ambientes gerenciados.

**Correção**: refletida em [`k8s/07-newrelic-postgresql.yaml`](../../k8s/07-newrelic-postgresql.yaml).

### 5. Arquitetura "nrk8s" do bundle não expõe on-host integrations pelo `values.yaml`

A versão atual do `nri-bundle` usa a arquitetura mais nova (`newrelic-infrastructure`/`nri-kubernetes`,
DaemonSets `nrk8s-*`), que **não tem** um campo `integrations:` no `values.yaml` do Helm chart para
declarar integrações on-host como Postgres — diferente da documentação clássica do
`newrelic-infra` (agent legado), que descrevia esse mecanismo. A integração de Postgres precisou ser
um componente **à parte**: um `Deployment` próprio rodando a imagem
`newrelic/infrastructure-bundle`, com a integração declarada via `ConfigMap` montado em
`/etc/newrelic-infra/integrations.d/`.

**Consequência prática**: o Postgres não é monitorado pelo mesmo Helm release do resto do cluster —
é um segundo componente, gerenciado separadamente (`k8s/07-newrelic-postgresql.yaml`), fora do
`observability/newrelic-values.yaml`.

## Consequências

- O tempo de setup real do New Relic (do zero até dado aparecendo na UI) foi bem maior do que sugere
  a documentação oficial, por causa desses cinco pontos — nenhum é documentado de forma clara nos
  guias públicos do New Relic para Kubernetes.
- Uma reaplicação limpa (`terraform apply` + `helm install` + `kubectl apply`) com os manifests já
  corrigidos neste repositório não deve reproduzir nenhum desses problemas — eles só aparecem na
  primeira tentativa, com a configuração ainda não descoberta.
