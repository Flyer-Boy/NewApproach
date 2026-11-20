# Uma Nova Abordagem para o Desenvolvimento de Aplicações usando Grafos

🌐 [English](README.md) · **Português (Brasil)** · [Español](Leame%28es-ES%29.md)

**Não coloque Grafos ao redor das suas aplicações. Construa as aplicações ao redor do Grafo.**

Este repositório contém os scripts, os dados e o código dos protótipos por trás dos meus artigos sobre a construção de **aplicações de linha de negócio (Line-of-Business) nativamente sobre um Labeled Property Graph** — em que o grafo não é apenas a camada de dados, mas também o lugar onde vivem o estado, as regras e o fluxo de trabalho do negócio.

Ele reúne quatro provas de conceito, de um aplicativo de transporte por aplicativo (Ride-Hailing) até um sistema completo de compras e atendimento de pedidos, de 360 graus, que executa seis processos de negócio simultaneamente sobre o mesmo grafo vivo — agora em **Neo4j, Memgraph, FalkorDB, Quine e Ultipa**. No Quine, esse negócio chega a funcionar sozinho: uma única *recipe* recebe em fluxo contínuo clientes, fornecedores e entregas, e *standing queries* aplicam as regras da empresa dentro do grafo, sem nenhum código de aplicação.

E no Neo4j, um **agente de IA** agora trabalha ao lado da simulação ao vivo: ele responde a perguntas de negócio, altera uma regra de negócio sob governança, **aprende** novas consultas à medida que as pessoas as aprovam e começou a **assumir parte do trabalho da simulação**: um Assistente de Compras (Procurement Assistant) cria e reenvia pedidos de compra com as recomendações do agente, com uma trilha de auditoria completa. O agente mantém o próprio grafo de conhecimento no **[Relate by Neo4j](https://relatedb.ai/)**, o novo banco de dados de grafos embarcado da Neo4j para agentes de IA, enquanto o negócio permanece no Neo4j Aura. Os mesmos trabalhos de pedidos de compra também podem ser feitos em uma pequena **interface web** que executa o mesmo Cypher governado: três front ends (o script da simulação, o agente e a interface), um só grafo.

---

## Conteúdo

- [Por que Graph-Native?](#por-que-graph-native)
- [Os princípios fundamentais](#os-princípios-fundamentais)
- [O que há neste repositório](#o-que-há-neste-repositório)
- [Suporte a bancos de dados de grafos](#suporte-a-bancos-de-dados-de-grafos)
- [Primeiros passos](#primeiros-passos)
- [Guia das pastas](#guia-das-pastas)
- [Artigos e palestras](#artigos-e-palestras)
- [Contato](#contato)

---

## Por que Graph-Native?

Depois de décadas trabalhando com RDBMS/SQL e com desenvolvimento de software corporativo, passei mais de oito anos explorando novas formas de construir aplicações de linha de negócio sobre bancos de dados de grafos, muito além dos seus casos de uso convencionais.

A jornada começou em 2013, depois de 17 anos na Microsoft, onde trabalhei na divisão de Consultoria e, mais tarde, liderei a área de Developer and Platform Evangelism no Brasil e na Ásia-Pacífico. Investi em uma startup e me juntei a ela para construir o que eu acreditava que poderia se tornar uma plataforma Graph-Native revolucionária, e foi lá que nasceram muitos dos conceitos, princípios e metodologias deste repositório. A startup não sobreviveu — fomos ambiciosos demais e, possivelmente, estávamos à frente do nosso tempo em um mercado muito conservador. Mas acredito que essas ideias são ainda mais relevantes hoje, quando entramos na era da IA.

Grafos não são apenas ferramentas especializadas para Ciência de Dados, Knowledge Graphs ou Graph RAG. Acredito que eles podem ser a base ideal para praticamente qualquer aplicação de negócio:

- **Os dados devem ser criados no Grafo**, e não criados em tabelas e importados para um grafo depois. Quando o grafo é o substrato nativo, relacionamentos, semântica, ontologia e contexto existem desde o momento em que o primeiro objeto de negócio é criado.
- **A maioria dos problemas de negócio de hoje são redes e fluxos de trabalho**, não tabelas. Em linhas gerais, a maioria dos aplicativos de negócio são fluxos de trabalho — e um fluxo de trabalho é um grafo.
- **Sistemas Graph-Native estão prontos para a IA agêntica.** O contexto, a semântica, a ontologia e o histórico de que um agente de IA precisa para raciocinar já estão no mesmo grafo que a aplicação lê e escreve todos os dias — sem pipelines de ETL, sem ingestões repetidas a partir de tabelas desconectadas.

Isso evoluiu muito além de um projeto paralelo. É uma missão de vida — que vou perseguir pelo tempo que for necessário.

---

## Os princípios fundamentais

Todos os modelos deste repositório seguem o mesmo pequeno conjunto de regras. Eles são explicados em profundidade [no artigo sobre o conceito](https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3), e todo script Cypher os repete no seu cabeçalho.

| Princípio | O que significa |
|---|---|
| **Nós como Substantivos Próprios** (Proper Noun Nodes) | Um nó armazena apenas as propriedades que definem a unicidade da entidade que representa. Qualquer estado, ou a relevância contextual de uma entidade para outra, é um relacionamento — nunca uma propriedade. Nada fica escondido dentro das propriedades: você (e a IA) pode entender o modelo inteiro a qualquer momento sem precisar lê-las. |
| **Nunca Excluir Nós** (Never Delete Nodes) | Os nós nunca são excluídos, para que toda entidade continue rastreável ao longo do tempo. O tempo flui em uma só direção; as entidades são arquivadas e registradas com data e hora, não apagadas. |
| **Nós Somente Leitura** (Read-Only Nodes) | Depois de criados, as propriedades dos nós não mudam. O `SET` fica reservado para correções e algumas exceções — os *isótopos*, como as contagens de estoque, isolados em seus próprios nós pequenos. Isso simplifica muito a concorrência e a consistência. |
| **Os Relacionamentos Movem o Sistema** (Relationships Drive the System) | O sistema funciona criando nós e criando/excluindo seus relacionamentos à medida que o fluxo de trabalho avança. Um evento de negócio é um nó passando de uma Collection para outra. *Estado = posição.* Existem 118 elementos químicos estáveis que constroem tudo o que conhecemos apenas mudando seus relacionamentos — isso é biomimética aplicada à arquitetura de software. |
| **Nós Enxutos** (Lean Nodes) | Os relacionamentos de saída são minimizados. Conexões de um para muitos passam por nós **Collection** (hubs) que representam estados e contextos do domínio, usando semântica explícita de conjuntos (Superconjunto, Subconjunto, Elemento de) em vez dos joins implícitos da álgebra relacional — o que corresponde à forma como os especialistas do domínio pensam naturalmente. |

> Se você se pegar filtrando por uma propriedade de nó que representa estado ou contexto, isso é um sinal de que o modelo precisa de um relacionamento — muito provavelmente ele foi construído com mentalidade de tabela.

Sei que os bancos de dados de grafos atuais ainda não estão totalmente otimizados para essa abordagem. Eu presenciei e trabalhei com os primeiros RDBMS e vi como eles evoluíram ao longo das décadas; os bancos de dados de grafos também vão evoluir.

---

## O que há neste repositório

| Prova de conceito | O que demonstra | Destaques |
|---|---|---|
| [**RideHailing**](RideHailing) | Os conceitos centrais em um domínio familiar: passageiros, motoristas, carros e reservas passando de um estado para outro | Aplicativo protótipo completo em **React + TypeScript** rodando diretamente sobre o grafo |
| [**TenderWorkflow**](TenderWorkflow) | Um sistema de licitações com fluxos de trabalho entrelaçados — aprovação de fornecedores, licitações e propostas em vários níveis — em que o grafo é ao mesmo tempo a camada de dados e a de lógica | Ontologia completa, esquema **GRAPH TYPE** do Neo4j, ontologia em RDF/Turtle, gerador de testes aleatórios em Python |
| [**NorthWind**](NorthWind) | O clássico banco de dados Northwind, remodelado com mentalidade de Grafo | Arquivos CSV de importação corrigidos |
| [**NorthWindPLUS**](NorthWindPLUS) | O Northwind estendido para um ciclo de negócio completo de 360 graus: pedidos de clientes, detecção de estoque baixo, pedidos de compra (POs) com aprovação em 3 níveis, RFQs de fornecedores, almoxarifado, financeiro e atendimento de pedidos | Seis loops de simulação em Python, executados simultaneamente, colocando o grafo sob carga; portado para 5 bancos de dados de grafos (incluindo uma versão em ISO GQL para o Ultipa); no Quine, as regras de negócio rodam como Standing Queries — e uma **versão em recipe** executa a simulação inteira dentro do grafo; no Neo4j, um **agente de IA construído sobre o Relate by Neo4j** responde a perguntas sobre o negócio ao vivo, altera limites de aprovação sob governança, aprende e assume a criação de POs com um Assistente de Compras — veja o [Leiame do NorthWindPLUS](NorthWindPLUS/Leiame%28pt-BR%29.md) e o [Leiame do agente](NorthWindPLUS/Neo4jRelate/Leiame%28pt-BR%29.md) |

Os scripts Cypher são muito comentados e explicam o que cada bloco faz e por quê, então funcionam bem como material de estudo para aplicar os princípios acima.

---

## Suporte a bancos de dados de grafos

Comecei com o Neo4j e continuo testando os modelos em outros bancos de dados de grafos. Quando um modelo funciona em outro mecanismo, publico aqui os scripts adaptados.

| | Neo4j | Memgraph | FalkorDB | Quine | Ultipa |
|---|:---:|:---:|:---:|:---:|:---:|
| RideHailing | ✅ | ✅ | | | |
| TenderWorkflow | ✅ (v7.1, GRAPH TYPE) | ✅ (v7.1) | 🧪 beta (v7.1) | | |
| NorthWind | ✅ | | | | |
| NorthWindPLUS | ✅ (v2.3.1, GRAPH TYPE; v2.3.3 + agente de IA no Relate) | ✅ | ✅ | ✅ (v2.4, Standing Queries + recipe) | ✅ (v2.3.1, ISO GQL) |

O Quine não suporta propriedades em relacionamentos, então a versão para o Quine usa o **modelo v2.4**, no qual cada aresta que carregava dados se torna um pequeno nó. Os princípios não mudam.

No Neo4j, o **modelo v2.3.3** (em [`NorthWindPLUS/Neo4jRelate/model`](NorthWindPLUS/Neo4jRelate/model)) acrescenta o que o agente de IA precisa: um papel `ProcurementPolicyAdmin` e um nó de auditoria `PolicyChange` (v2.3.2), para que os limites de aprovação L1/L2/L3 possam ser alterados com segurança enquanto a simulação roda; e uma trilha de auditoria para agentes e pessoas que trabalham ao lado dos loops (v2.3.3): `Source`, `Justification` e `RecommendedQt` nas decisões sobre pedidos de compra, um estado `CancelledPoS` e faixas de aprovação contíguas.

A versão para o Ultipa é escrita em **ISO GQL** em vez de Cypher, com o mesmo modelo, nós, relacionamentos e propriedades da versão para o Neo4j.

Com a padronização do **GQL** (ISO/IEC 39075:2024) e a ampla adoção do **openCypher**, os scripts de grafos estão cada vez mais portáveis entre bancos de dados de grafos — a versão para o Ultipa, uma tradução de Cypher para GQL instrução por instrução, é um exemplo —, mas cada mecanismo tem suas particularidades. Os scripts portados documentam no cabeçalho as mudanças que cada mecanismo exigiu.

---

## Primeiros passos

A forma mais fácil de começar é com o **Neo4j**:

1. Obtenha um banco de dados gratuito no [Neo4j Aura](https://neo4j.com/cloud/aura-free/) ou use o Neo4j Desktop.
2. Novo no Cypher? Comece pela [Neo4j GraphAcademy](https://graphacademy.neo4j.com/).
3. Escolha uma prova de conceito, abra o script `.cypher` principal e siga as instruções do cabeçalho.

> ⚠️ A maioria dos scripts começa com `MATCH (n) DETACH DELETE n` para limpar o banco de dados. Execute-os em um banco de dados vazio ou descartável.

Os scripts de esquema GRAPH TYPE (`TenderGraphType v1.cypher`, `NorthwindPlusGraphType_v1.cypher`, `NorthwindPlusGraphType_v2.3.3.cypher`) usam a imposição de esquema GRAPH TYPE do Neo4j, introduzida como prévia no Neo4j 2026.02 / Cypher 25. Verifique se a sua versão do Neo4j a suporta antes de executá-los.

Os simuladores em Python precisam do Python 3 e do driver do seu banco de dados (por exemplo, `pip install neo4j`). As configurações de conexão são passadas como variáveis de ambiente, descritas no início de cada script.

O **agente de IA** ([`NorthWindPLUS/Neo4jRelate`](NorthWindPLUS/Neo4jRelate/Leiame%28pt-BR%29.md)) roda no **Google Colab** ou localmente (terminal ou Jupyter). Ele precisa de uma chave de API da Anthropic, de uma conta no Claude Console, e das suas credenciais do Neo4j Aura; o Leiame dele explica a configuração passo a passo.

---

## Guia das pastas

### `/RideHailing`

| Arquivo | Descrição |
|---|---|
| `RideHailing.cypher` | Cria os nós iniciais (Passageiros, Motoristas, Carros, Reservas) em diferentes estados para você explorar o modelo. Pode ser executado por completo. |
| `RideHaining-MemGraph.cypher` | O mesmo script adaptado para o Memgraph. |
| `neo4j-RideHailingDB.backup` | Um backup do Neo4j com os nós iniciais e algumas reservas já feitas — uma alternativa a executar o script. |
| `RideHailing_Queries.cypher` | Consultas de exemplo para executar sobre o modelo. |
| `RideHailing_Templates.cypher` | Comandos Cypher usados para construir o aplicativo de demonstração mostrado no artigo. Substitua as variáveis por valores reais antes de executar. |
| `The RideHailingGraphModel.png` | O modelo de grafo do Ride-Hailing. |
| `RideHailingGraphApp/` | O aplicativo protótipo em React + TypeScript (Vite) que roda sobre o modelo. |

### `/TenderWorkflow`

| Arquivo | Descrição |
|---|---|
| `TenderWorkflow v7.1.cypher` | **Versão atual.** A simulação do Sistema de Licitações com a implementação completa da ontologia (Neo4j). |
| `TenderGraphType v1.cypher` | O esquema GRAPH TYPE que acompanha a v7.1, impondo a ontologia no nível do banco de dados. |
| `TenderGraph RDF-turtle v1.ttl` | A mesma ontologia expressa em RDF/OWL (Turtle). |
| `TenderWorkflow v7.1 MemGraph.cypher` | A v7.1 adaptada para o Memgraph. |
| `TenderWorkflow v7.1 FalkorDB (beta).cypher` | A v7.1 adaptada para o FalkorDB — beta. |
| `Tender_Workflow_Random_Test_Generator.py` | Gerador parametrizado em Python que cria licitações aleatoriamente, as aprova, convida fornecedores, aceita e aprova propostas e adjudica (ou não) as licitações, seguindo estritamente as regras do fluxo de trabalho. Os limites de aprovação são lidos do grafo, não fixados no código. |
| `Tender_Workflow_Random_Test_Generator_MemGraph.py` | O gerador adaptado para o Memgraph. |
| `* ScriptOutputFile.txt` | Exemplos de execução do gerador no Neo4j Aura (com GRAPH TYPE), no Neo4j Desktop e no Memgraph em Docker. |
| `Tender Model v7.1 visualisation.png` / `.svg` | O modelo de grafo da v7.1. |
| `TenderWorkflow v5.cypher`, `v6.cypher`, `v6 - MemGraph.cypher`, `v6 Graph Model.png` | Versões anteriores, mantidas como referência (a v6 usa o relacionamento genérico `[:HAS]` com uma propriedade `RelType`). |

### `/NorthWind`

| Arquivo | Descrição |
|---|---|
| `NorthWind v2.1.cypher` | O modelo Northwind adaptado aos princípios fundamentais, com tipos de relacionamento específicos da ontologia (a v2 abandonou o genérico `[:HAS]`). |
| `NorthWind.cypher`, `NorthWind v2.cypher` | Versões anteriores. |
| `NorthWind Schema Only.cypher` | Apenas o esquema, sem dados (criado com o aplicativo Arrows). |
| `NorthWindPlus  v1.cypher`, `NorthWind_PLUS_Graph_Data_Model_Import_v2.1.cypher` | Primeiras iterações do NorthWind PLUS, mantidas como histórico. A versão atual fica em `/NorthWindPLUS`. |
| `Northwind.png` | O modelo de grafo do Northwind. |
| `Import/` | **Arquivos CSV corrigidos.** Os arquivos originais em [neo4j-graph-examples/northwind](https://github.com/neo4j-graph-examples/northwind) contêm vírgulas sem escape em alguns campos (principalmente endereços no Brasil, na França e na Bélgica, e algumas observações), o que desloca as colunas na importação. Relatei isso na issue #53 daquele repositório. |

### `/NorthWindPLUS`

A prova de conceito mais completa: o Northwind transformado em um ciclo de negócio completo, além de harnesses em Python que executam seis processos de negócio independentes, simultaneamente, sobre o mesmo grafo, para testar se ele aguenta a carga. Inclui versões para Memgraph, FalkorDB, Quine e [Ultipa](NorthWindPLUS/Ultipa/README.md) (em ISO GQL), um esquema GRAPH TYPE, uma ontologia em RDF e anotações sobre uma camada de IA agêntica.

➡️ **Veja o [Leiame do NorthWindPLUS](NorthWindPLUS/Leiame%28pt-BR%29.md)** para o guia completo e os primeiros passos para cada banco de dados.

O trabalho com o Quine vem em três versões, cada uma com seu próprio README (em inglês):

| Pasta | O que é | Quem conduz o negócio |
|---|---|---|
| [`NorthWindPLUS/Quine/Full_NorthWindPLUS/Recipe_Version`](NorthWindPLUS/Quine/Full_NorthWindPLUS/Recipe_Version/Readme.md) | **O modelo completo como uma única recipe do Quine.** Fluxos de ingestão fazem o papel do mundo externo (clientes, fornecedores, a doca do almoxarifado). Standing queries executam as regras da empresa (aprovação de POs, envio pelo comprador, aprovação de RFQs, fechamento financeiro). Vem com 47 consultas de exemplo e 26 consultas rápidas pelo botão direito. | Somente o Quine — sem Python |
| [`NorthWindPLUS/Quine/Full_NorthWindPLUS`](NorthWindPLUS/Quine/Full_NorthWindPLUS/Readme.md) | O modelo completo carregado pela API REST do Quine e conduzido pelo harness em Python: ou os seis loops originais, ou o mundo externo em Python com as regras como Standing Queries | Python, com ou sem Standing Queries |
| [`NorthWindPLUS/Quine`](NorthWindPLUS/Quine/README.md) | Uma demonstração autocontida, de cinco minutos, de um "dia de negócios" em streaming, construída pela thatDot a partir do modelo | Somente o Quine |

E no Neo4j, um agente de IA trabalha ao lado da simulação:

| Pasta | O que é |
|---|---|
| [`NorthWindPLUS/Neo4jRelate`](NorthWindPLUS/Neo4jRelate/Leiame%28pt-BR%29.md) | **Um agente de IA que aprende a se orientar no grafo vivo.** Ele responde a perguntas de negócio em linguagem natural, altera os limites de aprovação sob governança (verificação de papel, prévia, confirmação, trilha de auditoria) e salva novas consultas como conhecimento reutilizável depois que uma pessoa as aprova. No modo *agents*, um Assistente de Compras assume dos loops a criação e o reenvio de POs: o agente recomenda, a pessoa decide e justifica, e um Cypher governado grava. Seu grafo de conhecimento (ontologia, biblioteca de consultas, histórico de perguntas) fica no **Relate by Neo4j**; o negócio permanece no Neo4j Aura. Roda no Google Colab ou no Jupyter, com o modelo v2.3.3. Na sua primeira execução ao vivo, encontrou um bug na própria simulação. Uma **interface web** em React + TypeScript faz os mesmos trabalhos de PO sobre o mesmo Python e o mesmo Cypher governado, com sugestões a partir da demanda recente e rascunhos de justificativa feitos por IA nos bastidores. |

---

## Artigos e palestras

Os artigos estão em inglês; os títulos abaixo são os originais.

1. **O Conceito** — [A new approach to application development using Cypher/GQL (Graphs)](https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3)
2. **A POC de Ride-Hailing** — [Ride-Hailing Graph App Prototype Explainer](https://medium.com/@marcospinedo/ride-hailing-graph-app-prototype-explainer-071a89543a90)
3. **Fluxos de trabalho em grafos** — [How Graphs simplify Business Processes and Workflows](https://medium.com/@marcospinedo/how-graphs-simplify-business-processes-and-workflows-like-moving-balls-between-baskets-c9606c9e973f)
4. **O "porquê"** — [Biomimicry in Software: Designing Business Systems using Graphs Like Nature Does](https://medium.com/@marcospinedo/biomimicry-in-software-designing-business-systems-using-graphs-like-nature-does-4c107dd2596e)
5. **O Fluxo de Licitações** — [A Graph-Native Workflow Application using Neo4j/Cypher](https://medium.com/@marcospinedo/a-graph-native-workflow-application-using-neo4j-graph-a4406e51b4e5)
6. **Palestra no NODES 2025** — [apresentação em vídeo dos conceitos + demonstração da POC](https://youtu.be/ExupBmmH1Rs), e o artigo complementar com os slides e a transcrição estendida: [Rethinking Line of Business Applications: Graphs & Cypher as an Alternative to RDBMS & SQL](https://medium.com/@marcospinedo/rethinking-line-of-business-applications-graphs-cypher-as-an-alternative-to-rdbms-sql-fd1d204f99b7)
7. **Ontologia e imposição de esquema** — [Graph-Native Business Applications with a Full Ontology — a practical use case of Neo4j's new GRAPH TYPE Schema enforcement](https://medium.com/@marcospinedo/graph-native-business-applications-with-a-full-ontology-a-practical-use-case-of-neo4js-new-graph-216c9bf20d22)
8. **NorthWind PLUS** — [A Labeled Property Graph (LPG) Masterpiece](https://marcospinedo.substack.com/p/a-labeled-property-graph-lpg-masterpiece) — o teste definitivo: seis processos de negócio independentes executados simultaneamente sobre o mesmo grafo vivo, colocando todos os conceitos em prática.
9. **Uma perspectiva de grafo em streaming** — [Running your entire business as a Nervous System](https://marcospinedo.substack.com/p/running-your-entire-business-as-a) — Uma perspectiva de grafo em streaming sobre um ciclo de negócio de 360°. A POC NorthWind PLUS rodando em um grafo em streaming com Standing Queries.

Vou continuar acrescentando conteúdo e protótipos à medida que esta Nova Abordagem evolui.

---

## Contato

Se você quiser conversar, saber mais ou experimentar esta abordagem no seu próximo projeto, pode falar comigo em marcos.pinedo@outlook.com ou pelo [LinkedIn](https://www.linkedin.com/in/marcospinedo/).

Se você gostou do que acabou de ver, sugiro ler alguns dos meus artigos anteriores (no [Medium](https://medium.com/@marcospinedo), no [Substack](https://substack.com/@marcospinedo) ou no [LinkedIn](https://www.linkedin.com/in/marcospinedo/)) sobre temas relacionados, caso ainda não tenha lido.


**"Alea iacta est" — atravessando o Rubicão da adoção de Grafos!** 🚀

Aproveite!

---

<sub>*Se você está curioso sobre o nome "Flyer-Boy": é uma longa, longa história. Hoje ele também é minha gamertag do Xbox, "Flyerboy", meu nome no Instagram, minha tag no Discord e assim por diante — agora ele me acompanha em todo lugar, então tenha paciência com ele. Desculpe!*</sub>
