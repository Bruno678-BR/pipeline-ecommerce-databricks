# Aula 3: Claude Code & Engenharia de Dados

> **Objetivo do dia:** transformar o dado cru da bronze em tabelas em que o negócio confia (**silver** e **gold**) e fazer isso como profissional: código no Git, especificação escrita, testes que param o Job quando o dado está errado e deploy com um comando. Tudo com a IA como par de programação.

| | |
|---|---|
| **Notebooks** | [`01_silver.py`](./01_silver.py), [`02_gold.sql`](./02_gold.sql) e [`testes/03_testes_qualidade.py`](./testes/03_testes_qualidade.py) |
| **Apoio** | [`PRD.md`](./PRD.md), [`CLAUDE.md`](../CLAUDE.md), [`databricks.yml`](../databricks.yml) e [`resources/`](../resources/) |
| **Duração** | ~120 minutos |
| **Pré-requisito** | Aula 2 feita; computador com terminal; conta no GitHub |

### Aula 2 × Aula 3: qual a diferença?

| | Aula 2 | Aula 3 |
|---|---|---|
| O que entrega | A ingestão: o dado chega sozinho na bronze | A transformação: silver, gold e a garantia de que estão certas |
| Ideia | **Eu construo e entendo** | **Eu profissionalizo com IA** |
| Onde o código mora | Notebooks no workspace | Repositório Git |
| Como o Job existe | Clicado na interface | Arquivo YAML versionado |
| Como sei que está certo | Olho o resultado | Testes automáticos falham o Job |
| Como vai para produção | Rodo na mão | `databricks bundle deploy` |
| Quem escreve o código | Eu | Eu, com o Claude Code executando e eu revisando |

## Roteiro

| Bloco | Tempo | O que acontece |
|---|---|---|
| Teoria | 15 min | Engenharia de software em dados, IA como par de programação |
| Setup | 15 min | Git, Databricks CLI, autenticação e Claude Code |
| Silver | 20 min | Limpar, tipar, enriquecer e marcar problemas (`01_silver.py`) |
| Gold | 20 min | As tabelas de cada diretoria (`02_gold.sql`), com `CASE WHEN` e window functions |
| Testes de qualidade | 15 min | O que testar e por que o Job deve falhar |
| Nova feature com PRD | 20 min | `gold.vendas_por_regiao`, do PRD ao Job verde |
| Deploy | 15 min | `dev` → `prod`, dashboard sobre a gold |

---

## Parte 1: base teórica

### Dados também são software

Um pipeline de dados é código, e código em produção precisa das mesmas práticas de qualquer software:

| Prática | Em dados significa | Neste projeto |
|---|---|---|
| **Versionamento** | Todo notebook, SQL e configuração no Git, com histórico de quem mudou o quê | Repositório no GitHub |
| **Infraestrutura como código** | Job, dashboard e permissões descritos em arquivo, e não em cliques | `databricks.yml` + `resources/*.yml` |
| **Ambientes separados** | Testar sem estragar o que os diretores estão vendo | Targets `dev` e `prod` |
| **Testes** | Provar que o dado está certo antes de alguém usar | `testes/03_testes_qualidade.py` |
| **Especificação** | Escrever o que o sistema deve fazer antes de fazer | `PRD.md` |

### Declarative Automation Bundles (antigos Databricks Asset Bundles)

Um bundle é o projeto Databricks descrito em arquivos. O `databricks.yml` diz **o que** deve existir no workspace, e a CLI cuida de criar, atualizar ou apagar o que for preciso.

```
databricks.yml                       ← nome do projeto, variáveis e ambientes (dev, prod)
resources/
├── pipeline_ecommerce.job.yml       ← o Job da Aula 2, agora com testes e documentação
├── diretoria_aula01.dashboard.yml   ← dashboard da Aula 1 (sobre a bronze)
├── diretoria_gold.dashboard.yml     ← o mesmo painel sobre a gold
└── diretoria.genie_space.yml        ← o Genie da Aula 4
```

| Comando | O que faz |
|---|---|
| `databricks bundle validate --strict` | Confere se a configuração está correta, sem mudar nada |
| `databricks bundle deploy -t dev` | Sobe os arquivos e cria ou atualiza os recursos no ambiente `dev` |
| `databricks bundle run pipeline_ecommerce -t dev` | Executa o Job e mostra o resultado de cada tarefa |
| `databricks bundle summary -t prod` | Lista os recursos implantados e seus links |
| `databricks bundle destroy -t dev` | Remove tudo o que o bundle criou naquele ambiente |

**Ambientes (targets):**
- `dev` (modo *development*): os recursos ganham o prefixo `[dev seu_usuario]` e o agendamento fica **pausado**. É para experimentar.
- `prod` (modo *production*): nomes limpos e Job agendado todo dia às 6h. É o que os diretores usam.

### Testes de qualidade de dados

Teste de software verifica se o **código** faz o que deveria. Teste de dados verifica se o **dado** que chegou está como deveria, porque o código pode estar perfeito e a fonte mandar lixo.

| Tipo | Pergunta | Exemplo no projeto |
|---|---|---|
| Unicidade | Existe ID repetido? | `id_venda` único na silver |
| Não nulo | Campo obrigatório vazio? | Toda venda tem cliente, produto e preço |
| Domínio | Valor fora da lista? | Canal só `ecommerce` ou `loja_fisica` |
| Regra de negócio | A regra foi aplicada certo? | VIP tem receita ≥ R$ 22.000 |
| Reconciliação | O total bate entre camadas? | Receita da silver = receita de cada gold |
| Limite tolerado | Um problema conhecido cresceu? | Vendas sem cadastro abaixo de 1% |

Cada teste é uma consulta que **conta linhas com problema**. Zero é sucesso. Qualquer outro número faz o notebook levantar um erro, o Job fica vermelho, você recebe um e-mail, e a tarefa seguinte (que documenta o dado para o Genie) nem roda.

### IA como par de programação

O **Claude Code** é um agente que roda no terminal, dentro da pasta do projeto. Diferente de um chat, ele:

- **lê** os arquivos do repositório para entender o contexto;
- **edita** arquivos e mostra o que mudou;
- **executa** comandos (`databricks bundle validate`, consultas SQL, `git`), lê o resultado e corrige o que deu errado;
- **pede permissão** antes de ações que alteram coisas.

Três arquivos fazem a IA trabalhar bem:

| Arquivo | Papel |
|---|---|
| [`CLAUDE.md`](../CLAUDE.md) | A "memória" do projeto: estrutura, comandos, convenções e números de referência. O Claude Code lê automaticamente ao abrir a pasta. |
| [`PRD.md`](./PRD.md) | O que o sistema deve fazer. Você muda o PRD, e a IA implementa a partir dele. |
| Os testes | A forma objetiva de saber se a IA acertou. |

> **Regra de ouro:** a IA escreve, **você revisa**. Leia cada diff, rode os testes, confira os números de referência. Quem responde pelo número do diretor é você.

### Alternativa gratuita: Genie Code

O Claude Code é uma ferramenta paga (precisa de um plano Claude Pro, Max ou de uma chave de API). Se você não tem assinatura, dá para acompanhar a aula com o **Genie Code**, o assistente de código que já vem dentro do Databricks, inclusive na Free Edition:

- abra um notebook e use o assistente para gerar, explicar ou refatorar células;
- use o **Git folder** para fazer commit e push pela interface;
- faça o deploy do bundle pela interface (botão de deploy no Git folder), sem instalar a CLI.

Você perde a execução de comandos no seu computador, mas o fluxo PRD → código → teste → deploy é o mesmo.

---

## Parte 2: setup (faça antes da aula se puder)

### 1. Git e o repositório

```bash
# faça um fork de github.com/lvgalvao/Imersao-Jornada-Databricks no GitHub, depois:
git clone https://github.com/SEU_USUARIO/Imersao-Jornada-Databricks.git
cd Imersao-Jornada-Databricks
```

### 2. Databricks CLI

| Sistema | Comando |
|---|---|
| macOS | `brew tap databricks/tap && brew install databricks` |
| Windows | `winget install Databricks.DatabricksCLI` |
| Linux | `curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh \| sh` |

Confira com `databricks --version` (precisa ser 0.281 ou mais recente; este projeto foi testado na 1.13).

### 3. Autenticação no workspace

Pegue a URL do seu workspace (o endereço do navegador até `.com`, por exemplo `https://dbc-1234abcd-5678.cloud.databricks.com`).

**Opção A, login pelo navegador (recomendado):**

```bash
databricks auth login --host https://SEU-WORKSPACE.cloud.databricks.com --profile imersao
```

**Opção B, token pessoal:**
1. No Databricks: seu avatar → **Settings → Developer → Access tokens → Generate new token**.
2. No terminal:
   ```bash
   databricks configure --host https://SEU-WORKSPACE.cloud.databricks.com --profile imersao
   # cole o token quando pedir
   ```

Teste: `databricks current-user me -p imersao`.

> **Validado na Free Edition:** login pelo navegador, criação de token pessoal, `bundle deploy` e `bundle run` funcionam. Um detalhe: a API não cria catálogo na Free Edition (falta um local de armazenamento), mas o SQL `CREATE CATALOG` funciona. Por isso o pipeline cria o catálogo com SQL.

### 4. Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash     # macOS / Linux
# Windows (PowerShell): irm https://claude.ai/install.ps1 | iex
```

Dentro da pasta do projeto, rode `claude` e faça login com sua conta Claude.

---

## Parte 3: a aula na prática

### 1. Primeiro deploy

```bash
databricks bundle validate --strict -t dev -p imersao
databricks bundle deploy -t dev -p imersao
databricks bundle run pipeline_ecommerce -t dev -p imersao
```

Se o seu fork ainda não tem a pasta `dados/` publicada, passe a origem dos arquivos:

```bash
databricks bundle run pipeline_ecommerce -t dev -p imersao \
  --params url_base=https://raw.githubusercontent.com/lvgalvao/Imersao-Jornada-Databricks/main/dados
```

Resultado esperado: as 5 tarefas verdes (`ingestao_bronze`, `silver`, `gold`, `testes_qualidade` e `documentar_para_genie`).

### 2. Construindo a silver e a gold

Rode [`01_silver.py`](./01_silver.py) e [`02_gold.sql`](./02_gold.sql), nessa ordem, e confira:

| O que conferir | Esperado |
|---|---|
| `silver.vendas` com produto não cadastrado | 20 linhas |
| Clientes por região | Norte 17, Nordeste 12, Centro-Oeste 9, Sudeste 8 e Sul 4 |
| Reconciliação da receita | R$ 974.077,28 na silver e em todas as golds |
| `gold.clientes_segmentacao` | 10 VIP, 25 TOP_TIER e 15 REGULAR |
| `gold.precos_competitividade` | 35 produtos mais caros que todos os concorrentes |

> **Por que PySpark na silver e SQL na gold?** Limpeza é uma sequência de passos pequenos, e cada passo vira uma linha de Python fácil de testar. Já as regras de negócio da gold são escritas em SQL, a língua que o analista e o diretor leram na Aula 1.

### 3. Conhecendo o projeto com o Claude Code

Abra o `claude` na pasta e experimente:

```
Explique a arquitetura deste projeto e o caminho de uma venda desde o arquivo Parquet até o dashboard.
```

```
Rode os testes de qualidade contra o workspace (perfil imersao) e me diga se algum número
foge dos valores de referência do CLAUDE.md.
```

### 4. Veja um teste falhar (de propósito)

Peça ao Claude Code:

```
Mude o limite de produtos não cadastrados em testes/03_testes_qualidade.py de 1% para 0,5%,
faça o deploy em dev e rode o Job. Me explique o que aconteceu.
```

O teste falha (são 0,66% de vendas sem cadastro), o Job fica vermelho e a tarefa `documentar_para_genie` não roda. É isso que você quer em produção: **parar antes de mostrar número errado**. Depois, peça para voltar o limite.

### 5. Nova feature a partir do PRD

A seção 9 do [`PRD.md`](./PRD.md) descreve `gold.vendas_por_regiao`. Peça:

```
Implemente a próxima feature descrita na seção 9 do PRD.md, seguindo o CLAUDE.md.
Antes de editar, me mostre o plano. Depois do deploy em dev, rode o Job e confira
a reconciliação da receita.
```

Revise o que ele propõe, aprove, e acompanhe:
1. a nova tabela em `03_gold.sql`;
2. o novo teste de reconciliação;
3. os comentários para o Genie;
4. `bundle validate`, `deploy` e `run` até ficar verde.

### 6. Commit e produção

```bash
git add -A && git commit -m "Adiciona gold.vendas_por_regiao"
git push
databricks bundle deploy -t prod -p imersao
```

Em `prod`, o Job fica agendado para todo dia às 6h, e o dashboard **Diretoria E-commerce** passa a ler da gold. Encontre os links com:

```bash
databricks bundle summary -t prod -p imersao
```

---

## Erros comuns

| Erro | Causa | Como resolver |
|---|---|---|
| `cannot configure default credentials` | Faltou o perfil | Use `-p imersao` em todo comando |
| `Metastore storage root URL does not exist` | Tentou criar catálogo pela API | Crie com SQL (`CREATE CATALOG IF NOT EXISTS ecommerce`) ou rode a Aula 1 |
| `warehouse "Serverless Starter Warehouse" not found` | O warehouse foi renomeado | Ajuste `variables.warehouse_id.lookup` no `databricks.yml` |
| `HTTPError: 404` na ingestão | `url_base` aponta para um fork sem a pasta `dados/` | Passe `--params url_base=...` |
| Job vermelho em `testes_qualidade` | Algum teste encontrou problema | Abra a saída da tarefa: a tabela mostra qual teste falhou e quantas linhas |

## Amanhã

O dado está organizado, testado e atualizado todo dia. Na [Aula 4](../aula-04-genie/) os diretores deixam de depender de você para perguntar: eles vão conversar com a gold em português, pelo **Genie**.
