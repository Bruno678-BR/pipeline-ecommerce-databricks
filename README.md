# Pipeline de Dados E-commerce — Databricks Lakehouse

Pipeline completo de engenharia de dados para um e-commerce brasileiro, construído sobre a
Arquitetura Medalhão (Bronze → Silver → Gold) no Databricks, com dashboards de negócio e um
agente de linguagem natural (Genie) conectado diretamente aos dados.

## 📌 Contexto do projeto

O objetivo foi transformar dados brutos de vendas, produtos, clientes e preços de concorrentes
em informação confiável e pronta para decisão de negócio — respondendo perguntas reais de
diferentes áreas da empresa (Vendas, CRM, Pricing) diretamente em SQL, sem depender de planilha.

## 🏗️ Arquitetura

```
Bronze (dados brutos)
   ↓
Silver (dados limpos, deduplicados, tipados e validados)
   ↓
Gold (métricas de negócio, prontas para dashboard e para o Genie Agent)
```

- **Bronze**: dados brutos, sobrescritos a cada execução, sem tratamento
- **Silver**: regras de qualidade aplicadas (deduplicação, tipagem financeira em `DECIMAL(10,2)`,
  enriquecimento geográfico, validações de integridade) — **nenhuma linha é descartada**, problemas
  de qualidade são sinalizados em colunas booleanas, nunca escondidos
- **Gold**: tabelas de negócio por área (Vendas, CRM/Segmentação de Clientes, Pricing
  Competitivo), documentadas com `COMMENT` em cada coluna para uso direto no Genie

## 🛠️ Stack técnica

- **Databricks** — Lakeflow Declarative Pipelines (DLT)
- **PySpark** — transformações da camada Silver
- **SQL** — modelagem das tabelas Gold
- **Databricks Asset Bundles (DAB)** — versionamento e deploy do pipeline como código
- **Genie Agent** — perguntas de negócio em linguagem natural direto nos dados
- **Dashboards Databricks** — visualização das métricas Gold
- **MCP (Model Context Protocol)** — integração de agente de IA com o SQL Warehouse

## 📊 Perguntas de negócio respondidas

- Qual o faturamento total e por canal de venda?
- Quais produtos estão mais caros que a concorrência (Mercado Livre, Amazon, Magalu, Shopee)?
- Em quais produtos a Diretoria de Pricing deveria agir?
- Qual a segmentação de clientes por região e comportamento de compra?
- Existem vendas de produtos não cadastrados ou anteriores ao cadastro? (qualidade de dados)

## ✅ Testes de qualidade

Cada tabela Gold possui testes automatizados (`testes/testes_qualidade.py`), validando:
- Unicidade de chave primária
- Integridade matemática (ex: `receita = quantidade * preco_unitario`)
- Taxa de exceções dentro do limite esperado (ex: vendas de produto não cadastrado < 1%)

## 🚀 Como rodar

```bash
databricks bundle validate --strict -t dev -p <seu-perfil>
databricks bundle deploy -t dev -p <seu-perfil>
databricks bundle run pipeline_ecommerce -t dev -p <seu-perfil>
```

## 🧩 Desafios técnicos e decisões de engenharia

- Configuração manual do **MCP (Model Context Protocol)** no Google Antigravity IDE para conectar
  o agente de IA ao SQL Warehouse do Databricks via `Managed MCP: SQL`
- Quando a cota do agente de IA se esgotou no meio do desenvolvimento da camada Gold de Pricing,
  o pipeline dessa tabela foi escrito manualmente em SQL, seguindo as mesmas convenções e
  validando as colunas reais das tabelas Silver antes de codar
- Debug de um deploy que não refletia mudanças no pipeline — causa raiz: arquivo salvo com
  conteúdo vazio, identificado ao inspecionar o tamanho do arquivo via terminal

## 🙏 Créditos

Este projeto foi desenvolvido durante a **Jornada de Dados**, curso do
[Luciano Vasconcelos](https://github.com/lvgalvao), que propôs a estrutura de prompts, a
arquitetura Medalhão e as regras de negócio utilizadas como base. Algumas etapas foram
adaptadas por conta própria — como a configuração do MCP no Google Antigravity IDE (o curso
demonstra o fluxo via Claude Code) e a escrita manual de parte do pipeline SQL quando a cota
do agente de IA se esgotou.

## 📎 Autor

Bruno Coimbra Rosa
[LinkedIn](https://linkedin.com/in/brunocoimbrarosa) · [GitHub](https://github.com/Bruno678-BR)
