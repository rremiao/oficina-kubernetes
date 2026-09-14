# Runbook — subir e derrubar o ambiente completo (4 repositórios)

O AWS Academy Learner Lab dá sessões de **4 horas**, com credenciais temporárias que expiram
sozinhas. Este runbook existe porque nenhum repositório sozinho descreve a ordem entre os quatro —
cada README documenta o `apply`/`destroy` do seu próprio pedaço, mas a sequência **entre** eles (o
que depende do quê, o que precisa existir primeiro) só fica clara olhando os quatro juntos.

## Ordem de dependência

```
oficina-database (RDS)  ──┐
                           ├──> oficina-kubernetes (EKS) ──> app (Deployment) ──> oficina-lambda (API Gateway)
                           │                                       │
                           └───────────────────────────────────────┘
                             (a app conecta no RDS; a Lambda referencia
                              o RDS via data source e o LB da app via var)
```

Nenhum dos três Terraforms tem dependência *implícita* de state entre si — cada um lê o que precisa
via `data source` (RDS) ou variável (`backend_lb_dns`), não via `terraform_remote_state`. Isso é
proposital (ver [ADR-0001 do `oficina-database`](https://github.com/rremiao/oficina-database/blob/main/docs/adr/0001-segregacao-do-state-de-banco.md)),
mas significa que a ordem certa de subir/derrubar precisa ser seguida manualmente.

## Subir o ambiente do zero

1. **Sessão AWS Academy ativa** — inicia o Lab, copia as credenciais temporárias (`AWS_ACCESS_KEY_ID`,
   `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) pro `~/.aws/credentials` ou exporta como variáveis
   de ambiente.

2. **RDS** (`oficina-database/infra`):
   ```bash
   cd oficina-database/infra
   cp terraform.tfvars.example terraform.tfvars   # ajuste a senha
   terraform init
   terraform apply
   ```
   Anota o `rds_endpoint` do output — vai ser usado nos passos 4 e 5.

3. **EKS** (`oficina-kubernetes/infra`):
   ```bash
   cd oficina-kubernetes/infra
   cp terraform.tfvars.example terraform.tfvars
   terraform init
   terraform apply
   aws eks update-kubeconfig --region us-east-1 --name oficina-eks
   ```

4. **New Relic no cluster** — Infrastructure agent + APM + Postgres integration:
   ver a seção "Instalar o monitoramento" e "Monitoramento do RDS" no
   [README deste repositório](../README.md).

5. **A aplicação** (`oficina-kubernetes/k8s`):
   ```bash
   sed "s/__RDS_ENDPOINT__/<rds_endpoint do passo 2>/" \
     k8s/01-configmap.yaml.tpl > k8s/01-configmap.yaml
   kubectl apply -f k8s/00-namespace.yaml -f k8s/01-configmap.yaml -f k8s/02-secret.yaml \
     -f k8s/06-newrelic-instrumentation.yaml -f k8s/03-app-deployment.yaml \
     -f k8s/04-app-service-loadbalancer.yaml -f k8s/05-hpa.yaml
   kubectl get svc oficina-api -n oficina   # anota o EXTERNAL-IP (DNS do LoadBalancer)
   ```

6. **Lambda + API Gateway** (`oficina-lambda/infra`) — só depois do passo 5, porque precisa do DNS
   do LoadBalancer:
   ```bash
   cd oficina-lambda/infra
   BUCKET="oficina-lambda-tfstate-$(aws sts get-caller-identity --query Account --output text)"
   aws s3api create-bucket --bucket "$BUCKET" --region us-east-1   # só na primeira vez
   terraform init -backend-config="bucket=$BUCKET" \
     -backend-config="key=oficina-lambda/hml/terraform.tfstate" \
     -backend-config="region=us-east-1"
   # preencha envs/hml.tfvars com backend_lb_dns = DNS do passo 5, db_username = mesmo do passo 2
   TF_VAR_db_password=... TF_VAR_jwt_secret=... terraform apply -var-file=envs/hml.tfvars
   ```

## Derrubar o ambiente (fim da sessão do Lab)

Ordem inversa — derruba quem depende primeiro:

```bash
# 1. Lambda + API Gateway
cd oficina-lambda/infra
source .env   # ou exporte TF_VAR_db_password e TF_VAR_jwt_secret manualmente
terraform destroy -var-file=envs/hml.tfvars

# 2. Remove o LoadBalancer da app ANTES de derrubar o cluster
#    (senão o ELB fica orfão, fora do controle do Terraform)
kubectl delete svc oficina-api -n oficina

# 3. EKS (cluster + node group)
cd ../../oficina-kubernetes/infra
terraform destroy

# 4. RDS
cd ../../oficina-database/infra
terraform destroy
```

**Por quê essa ordem**: a Lambda referencia o DNS do LoadBalancer e o RDS via variável/data source —
destruir esses dois primeiro não quebra nada nela porque o Terraform não valida conectividade real no
destroy, só remove os recursos AWS. Já o contrário (derrubar RDS ou EKS antes da Lambda) deixaria a
Lambda "apontando pro nada" até ela também ser destruída — sem problema técnico, mas sem necessidade
de correr esse risco.

## O que sobrevive entre sessões (não precisa recriar)

- O **bucket S3 do state** do `oficina-lambda` (`oficina-lambda-tfstate-<account-id>`) — o
  `terraform destroy` remove os recursos AWS, não o bucket nem o arquivo de state nele.
- O **repositório ECR** (`oficina-api`), se você usou um pra testar imagens locais — armazenamento é
  barato, não crítico derrubar.
- Contas e configuração do **New Relic** (fora da AWS) — license key, dashboards, alert policy e
  Synthetic Monitor continuam existindo; só param de receber dado novo enquanto o ambiente AWS
  estiver fora do ar.

## O que é perdido e precisa ser refeito a cada ciclo

- O **usuário de monitoramento do Postgres** (`newrelic_monitor`) — vive dentro do RDS; se o RDS for
  destruído e recriado, precisa ser recriado também (ver
  [`observability/postgres-integration.md`](../observability/postgres-integration.md)).
- A **carga inicial de dados** (clientes, veículos, serviços, itens, usuário admin) — se quiser
  repetir um teste ponta a ponta, reaplique `oficina/scripts/scripts-iniciais.txt` no banco novo.
- Os **outputs** de cada `apply` (endpoint do RDS, DNS do LoadBalancer, URL da API Gateway) mudam a
  cada ciclo — não são estáveis entre uma subida e outra.
