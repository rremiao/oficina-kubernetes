# oficina-kubernetes

Infraestrutura como código (Terraform) do **cluster Kubernetes (EKS)** usado pela API da oficina mecânica — Tech Challenge Fase 3 (POS Tech / SOAT).

Extraído do `infra/aws/` do repositório principal ([`oficina`](https://github.com/Franciscojr08/oficina)), mantendo somente a parte de cluster. O banco de dados gerenciado tem seu próprio repositório: [`oficina-database`](https://github.com/rremiao/oficina-database). A aplicação (imagem Docker + manifests Kubernetes) continua no repositório principal.

## O que este repositório provisiona

- Tags nas subnets padrão da VPC (`kubernetes.io/cluster/...`, `kubernetes.io/role/elb`) — necessárias para o EKS e para o LoadBalancer.
- Cluster **EKS** (`oficina-eks`), usando o `LabRole` do AWS Academy Learner Lab (nenhuma IAM role própria é criada).
- **Node Group** gerenciado (1-2 nós `t3.small` por padrão).

Não provisiona: banco de dados (repo `oficina-database`), API Gateway/Lambda (repo `oficina-lambda`), nem os manifests da aplicação (repo `oficina`, pasta `k8s/aws/`).

## Pré-requisitos

- Sessão ativa do **AWS Academy Learner Lab**, com credenciais temporárias exportadas (ou configuradas no profile `academy`).
- Terraform >= 1.5.0, AWS CLI, kubectl.

## Como rodar localmente

```bash
export TF_VAR_db_password=  # não usado aqui, mantido só se reaproveitar scripts do repo principal

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

Após o `apply`, configure o `kubectl`:

```bash
aws eks update-kubeconfig --region us-east-1 --name oficina-eks --profile academy
kubectl get nodes
```

Instale o metrics-server (necessário para o HPA da aplicação funcionar):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get deployment metrics-server -n kube-system
```

## Deploy pelo GitHub Actions

Workflow `.github/workflows/deploy.yml`, disparo manual (`workflow_dispatch`) para não gastar crédito do Learner Lab fora de hora.

Secrets necessários no repositório:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
AWS_REGION=us-east-1
```

Rode `deploy` para criar/atualizar o cluster, `destroy` para removê-lo.

## ⚠️ Ordem importante ao destruir (orçamento do AWS Academy Lab)

**Sempre destrua a aplicação (repositório `oficina`) antes de destruir este cluster.** O Service `oficina-api` cria um Load Balancer que precisa ser removido primeiro — senão o `terraform destroy` do cluster pode falhar ou deixar o Load Balancer órfão consumindo crédito. O workflow de `destroy` deste repositório já tenta detectar e limpar os recursos da aplicação como rede de segurança, mas não confie só nisso.

Fim de cada sessão de uso: rode `destroy` aqui **e** no repositório `oficina-database`. O cluster EKS sozinho já custa por hora mesmo sem nós rodando.
