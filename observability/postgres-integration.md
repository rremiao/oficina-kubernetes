# Monitoramento do RDS (oficina-database) via nri-postgresql

A integração `nri-postgresql` se conecta **direto no banco** pela rede (mesma VPC do EKS) — não
depende de IAM nem de CloudWatch, funciona dentro das restrições do AWS Academy Learner Lab.

Diferente do que a primeira versão deste documento assumia, ela **não** roda dentro do `nri-bundle`
principal: a arquitetura atual do bundle (`newrelic-infrastructure`/`nri-kubernetes`, DaemonSets
`nrk8s-*`) não expõe um campo `integrations:` no `values.yaml` para declarar on-host integrations
como Postgres. Por isso o Postgres é monitorado por um **componente à parte**:
[`k8s/07-newrelic-postgresql.yaml`](../k8s/07-newrelic-postgresql.yaml), um `Deployment` próprio
rodando a imagem `newrelic/infrastructure-bundle` (o agent clássico completo, que ainda suporta
`integrations.d/`), independente do bundle Helm.

## 1. Usuário de monitoramento no banco

Antes de habilitar essa integração, o RDS precisa de um usuário read-only dedicado:

```sql
CREATE USER newrelic_monitor WITH PASSWORD '<gerar uma senha forte>';
GRANT pg_monitor TO newrelic_monitor;
GRANT CONNECT ON DATABASE oficina TO newrelic_monitor;
```

Como o RDS não é publicamente acessível, esse `CREATE USER` precisa ser executado de dentro da VPC.
O jeito mais simples, sem precisar rebuildar a imagem da aplicação, é um pod temporário no cluster:

```bash
kubectl run psql-temp --rm -i --restart=Never --image=postgres:16-alpine -n oficina -- \
  env PGPASSWORD='<senha master do RDS>' psql \
  -h <rds_endpoint> -U <db_username> -d oficina -c "
CREATE USER newrelic_monitor WITH PASSWORD '<senha gerada>';
GRANT pg_monitor TO newrelic_monitor;
GRANT CONNECT ON DATABASE oficina TO newrelic_monitor;
"
```

Numa entrega definitiva, o correto é versionar isso como uma migration Flyway no repositório
`oficina` (ex.: `V11__create_usuario_monitoramento.sql`, com a senha vindo de um placeholder do
Flyway, não hardcoded), já que é lá que o schema é a fonte de verdade. A execução manual acima serve
para validar a integração sem depender de rebuild+redeploy da aplicação.

## 2. Secret com a senha do usuário de monitoramento

```bash
cp observability/nri-postgresql-secret.example.yaml observability/nri-postgresql-secret.yaml
# edite observability/nri-postgresql-secret.yaml com a senha gerada acima
kubectl apply -f observability/nri-postgresql-secret.yaml
```

## 3. Aplicar o Deployment de monitoramento

```bash
sed "s/__RDS_ENDPOINT__/$(terraform -chdir=../oficina-database/infra output -raw rds_endpoint)/" \
  k8s/07-newrelic-postgresql.yaml > /tmp/07-final.yaml
kubectl apply -f /tmp/07-final.yaml
```

## Detalhe importante: como a senha chega na integração

A senha **não** é passada como variável de ambiente comum lida via `${VAR}` dentro do
`postgresql-config.yml` — essa sintaxe não é expandida nesse contexto pelo agent (foi testado e
falhou: o valor literal `${NRI_POSTGRESQL_PASSWORD}` era enviado como senha, causando erro de
autenticação). O mecanismo correto é o
["secrets management"](https://docs.newrelic.com/docs/infrastructure/host-integrations/installation/secrets-management/)
do próprio agent: um bloco `variables` no YAML da integração que roda um comando (aqui, `cat` lendo
o arquivo do Secret montado como volume) e referencia o resultado via `${nome_da_variavel}`:

```yaml
variables:
  postgres_pw:
    command:
      path: '/bin/cat'
      args: ['/etc/newrelic-infra/secrets/postgres-password']
      ttl: 1h
integrations:
  - name: nri-postgresql
    env:
      PASSWORD: ${postgres_pw}
```

O Secret é montado como arquivo (não env var) no Deployment, em `/etc/newrelic-infra/secrets/`.

## Outras pegadinhas de configuração descobertas na prática

- `COLLECTION_LIST` é um **array JSON simples de nomes de banco** (`'["oficina"]'`), não um objeto
  aninhado por schema/tabela — um valor no formato errado falha silenciosamente com
  `Error creating list of entities to collect: failed to parse collection list`.
- `TRUST_SERVER_CERTIFICATE: "true"` é obrigatório em RDS/Aurora (o certificado é gerenciado pela
  AWS). `IS_RDS: "true"` habilita ajustes de query performance monitoring específicos desses
  ambientes gerenciados.

## O que essa integração cobre

- Conexões ativas, locks, tamanho do banco, cache hit ratio.
- Queries lentas (`pg_stat_statements`, se habilitado no RDS via parameter group).

## O que fica de fora

Métricas de infraestrutura física da instância RDS (IOPS, storage físico, throughput de rede) — essas
só vêm da AWS Integration nativa (via IAM role), bloqueada no Learner Lab. Ver
[ADR-0002](../docs/adr/0002-escolha-da-ferramenta-de-observabilidade.md) para a justificativa completa
dessa limitação, e [ADR-0003](../docs/adr/0003-licoes-da-primeira-implantacao-real.md) para o
histórico completo dos ajustes desta integração.
