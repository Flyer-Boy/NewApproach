# Un Nuevo Enfoque para el Desarrollo de Aplicaciones con Grafos

🌐 [English](README.md) · [Português (Brasil)](Leiame%28pt-BR%29.md) · **Español**

**No pongas Grafos alrededor de tus aplicaciones. Construye las aplicaciones alrededor del Grafo.**

Este repositorio contiene los scripts, los datos y el código de los prototipos que acompañan a mis artículos sobre cómo construir **aplicaciones de línea de negocio (Line-of-Business) de forma nativa sobre un Labeled Property Graph**, donde el grafo no es solo la capa de datos, sino también el lugar en el que viven el estado, las reglas y el flujo de trabajo del negocio.

Reúne cuatro pruebas de concepto, desde una aplicación de transporte con conductor (Ride-Hailing) hasta un sistema completo de compras y gestión de pedidos, de 360 grados, que ejecuta seis procesos de negocio a la vez sobre el mismo grafo en vivo, ahora en **Neo4j, Memgraph, FalkorDB, Quine y Ultipa**. En Quine, ese negocio incluso funciona solo: una única *recipe* recibe en flujo continuo clientes, proveedores y entregas, y las *standing queries* aplican las reglas de la empresa dentro del grafo, sin ningún código de aplicación.

Y en Neo4j, un **agente de IA** trabaja ahora junto a la simulación en vivo: responde preguntas de negocio, cambia una regla de negocio bajo gobernanza, **aprende** nuevas consultas a medida que las personas las aprueban y ha empezado a **asumir parte del trabajo de la simulación**: un Asistente de Compras (Procurement Assistant) crea y reenvía pedidos de compra con las recomendaciones del agente, con una pista de auditoría completa. El agente guarda su propio grafo de conocimiento en **[Relate by Neo4j](https://relatedb.ai/)**, la nueva base de datos de grafos embebida de Neo4j para agentes de IA, mientras el negocio permanece en Neo4j Aura. Los mismos trabajos de pedidos de compra también se pueden hacer en una pequeña **interfaz web** que ejecuta el mismo Cypher gobernado: tres front ends (el script de la simulación, el agente y la interfaz), un solo grafo.

---

## Contenido

- [¿Por qué Graph-Native?](#por-qué-graph-native)
- [Los principios clave](#los-principios-clave)
- [Qué hay en este repositorio](#qué-hay-en-este-repositorio)
- [Compatibilidad con bases de datos de grafos](#compatibilidad-con-bases-de-datos-de-grafos)
- [Primeros pasos](#primeros-pasos)
- [Guía de carpetas](#guía-de-carpetas)
- [Artículos y charlas](#artículos-y-charlas)
- [Contacto](#contacto)

---

## ¿Por qué Graph-Native?

Tras décadas trabajando con RDBMS/SQL y con desarrollo de software empresarial, he dedicado más de ocho años a explorar nuevas formas de construir aplicaciones de línea de negocio sobre bases de datos de grafos, mucho más allá de sus casos de uso convencionales.

El viaje empezó en 2013, después de 17 años en Microsoft, donde trabajé en la división de Consultoría y más tarde dirigí Developer and Platform Evangelism en Brasil y Asia-Pacífico. Invertí en una startup y me incorporé a ella para construir lo que creía que podía convertirse en una plataforma Graph-Native revolucionaria, y allí nacieron muchos de los conceptos, principios y metodologías de este repositorio. La startup no sobrevivió: fuimos demasiado ambiciosos y, probablemente, nos adelantamos a nuestro tiempo en un mercado muy conservador. Pero creo que esas ideas son aún más relevantes hoy, ahora que entramos en la era de la IA.

Los grafos no son solo herramientas especializadas para Ciencia de Datos, Knowledge Graphs o Graph RAG. Creo que pueden ser la base ideal para casi cualquier aplicación de negocio:

- **Los datos deben crearse en el Grafo**, no crearse en tablas e importarse a un grafo después. Cuando el grafo es el sustrato nativo, las relaciones, la semántica, la ontología y el contexto existen desde el momento en que se crea el primer objeto de negocio.
- **La mayoría de los problemas de negocio actuales son redes y flujos de trabajo**, no tablas. A grandes rasgos, la mayoría de las aplicaciones de negocio son flujos de trabajo, y un flujo de trabajo es un grafo.
- **Los sistemas Graph-Native están preparados para la IA agéntica.** El contexto, la semántica, la ontología y el historial que un agente de IA necesita para razonar ya están en el mismo grafo que la aplicación lee y escribe cada día: sin pipelines de ETL y sin ingestas repetidas desde tablas desconectadas.

Esto ha ido mucho más allá de un proyecto personal. Es una misión de vida, y la seguiré el tiempo que haga falta.

---

## Los principios clave

Todos los modelos de este repositorio siguen el mismo pequeño conjunto de reglas. Se explican en profundidad en [el artículo sobre el concepto](https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3), y cada script Cypher las repite en su cabecera.

| Principio | Qué significa |
|---|---|
| **Nodos como Nombres Propios** (Proper Noun Nodes) | Un nodo guarda solo las propiedades que definen la unicidad de la entidad que representa. Cualquier estado, o la relevancia contextual de una entidad para otra, es una relación, nunca una propiedad. Nada queda oculto dentro de las propiedades: tú (y la IA) podéis entender el modelo completo en cualquier momento sin leerlas. |
| **No Borrar Nunca los Nodos** (Never Delete Nodes) | Los nodos no se borran nunca, para que cada entidad siga siendo trazable a lo largo del tiempo. El tiempo fluye en una sola dirección; las entidades se archivan y se marcan con fecha y hora, no se eliminan. |
| **Nodos de Solo Lectura** (Read-Only Nodes) | Una vez creados, las propiedades de los nodos no cambian. `SET` se reserva para correcciones y algunas excepciones: los *isótopos*, como los recuentos de inventario, que se aíslan en sus propios nodos pequeños. Esto simplifica mucho la concurrencia y la coherencia. |
| **Las Relaciones Mueven el Sistema** (Relationships Drive the System) | El sistema funciona creando nodos y creando o borrando sus relaciones a medida que avanza el flujo de trabajo. Un evento de negocio es un nodo que pasa de una Collection a otra. *Estado = posición.* Hay 118 elementos químicos estables que construyen todo lo que conocemos simplemente cambiando sus relaciones: es biomímesis aplicada a la arquitectura de software. |
| **Nodos Ligeros** (Lean Nodes) | Las relaciones salientes se reducen al mínimo. Las conexiones de uno a muchos pasan por nodos **Collection** (hubs) que representan estados y contextos del dominio, con una semántica de conjuntos explícita (Superconjunto, Subconjunto, Elemento de) en lugar de los joins implícitos del álgebra relacional, lo que coincide con la forma en que piensan de manera natural los expertos del dominio. |

> Si te encuentras filtrando por una propiedad de nodo que representa un estado o un contexto, es señal de que el modelo necesita una relación en su lugar: lo más probable es que se haya construido con mentalidad de tabla.

Soy consciente de que las bases de datos de grafos actuales aún no están totalmente optimizadas para este enfoque. Viví y trabajé con los primeros RDBMS y vi cómo evolucionaron a lo largo de las décadas; las bases de datos de grafos también lo harán.

---

## Qué hay en este repositorio

| Prueba de concepto | Qué demuestra | Aspectos destacados |
|---|---|---|
| [**RideHailing**](RideHailing) | Los conceptos centrales en un dominio conocido: pasajeros, conductores, coches y reservas que pasan de un estado a otro | Aplicación prototipo completa en **React + TypeScript** que funciona directamente sobre el grafo |
| [**TenderWorkflow**](TenderWorkflow) | Un sistema de licitaciones con flujos de trabajo entrelazados (revisión de proveedores, licitaciones y ofertas con aprobaciones en varios niveles) en el que el grafo es a la vez la capa de datos y la de lógica | Ontología completa, esquema **GRAPH TYPE** de Neo4j, ontología en RDF/Turtle, generador de pruebas aleatorias en Python |
| [**NorthWind**](NorthWind) | La clásica base de datos Northwind, remodelada con mentalidad de Grafo | Ficheros CSV de importación corregidos |
| [**NorthWindPLUS**](NorthWindPLUS) | Northwind ampliado a un ciclo de negocio completo de 360 grados: pedidos de clientes, detección de existencias bajas, pedidos de compra (POs) con revisión en 3 niveles, RFQs de proveedores, almacén, finanzas y gestión de pedidos | Seis bucles de simulación en Python que se ejecutan a la vez y ponen a prueba el grafo bajo carga; portado a 5 bases de datos de grafos (incluida una versión en ISO GQL para Ultipa); en Quine, las reglas de negocio se ejecutan como Standing Queries, y una **versión en recipe** ejecuta toda la simulación dentro del grafo; en Neo4j, un **agente de IA construido sobre Relate by Neo4j** responde preguntas sobre el negocio en vivo, cambia los límites de aprobación bajo gobernanza, aprende y asume la creación de POs con un Asistente de Compras: consulta el [Léame de NorthWindPLUS](NorthWindPLUS/Leame%28es-ES%29.md) y el [Léame del agente](NorthWindPLUS/Neo4jRelate/Leame%28es-ES%29.md) |

Los scripts Cypher están muy comentados y explican qué hace cada bloque y por qué, así que sirven como material de aprendizaje para aplicar los principios anteriores.

---

## Compatibilidad con bases de datos de grafos

Empecé con Neo4j y sigo probando los modelos en otras bases de datos de grafos. Cuando un modelo funciona en otro motor, publico aquí los scripts adaptados.

| | Neo4j | Memgraph | FalkorDB | Quine | Ultipa |
|---|:---:|:---:|:---:|:---:|:---:|
| RideHailing | ✅ | ✅ | | | |
| TenderWorkflow | ✅ (v7.1, GRAPH TYPE) | ✅ (v7.1) | 🧪 beta (v7.1) | | |
| NorthWind | ✅ | | | | |
| NorthWindPLUS | ✅ (v2.3.1, GRAPH TYPE; v2.3.3 + agente de IA en Relate) | ✅ | ✅ | ✅ (v2.4, Standing Queries + recipe) | ✅ (v2.3.1, ISO GQL) |

Quine no admite propiedades en las relaciones, así que la versión para Quine usa el **modelo v2.4**, en el que cada arista que llevaba datos se convierte en un pequeño nodo. Los principios no cambian.

En Neo4j, el **modelo v2.3.3** (en [`NorthWindPLUS/Neo4jRelate/model`](NorthWindPLUS/Neo4jRelate/model)) añade lo que necesita el agente de IA: un rol `ProcurementPolicyAdmin` y un nodo de auditoría `PolicyChange` (v2.3.2), para que los límites de aprobación L1/L2/L3 puedan cambiarse con seguridad mientras se ejecuta la simulación; y una pista de auditoría para agentes y personas que trabajan junto a los bucles (v2.3.3): `Source`, `Justification` y `RecommendedQt` en las decisiones sobre pedidos de compra, un estado `CancelledPoS` y franjas de aprobación contiguas.

La versión para Ultipa está escrita en **ISO GQL** en lugar de Cypher, con el mismo modelo, nodos, relaciones y propiedades que la versión para Neo4j.

Con la normalización de **GQL** (ISO/IEC 39075:2024) y la amplia adopción de **openCypher**, los scripts de grafos son cada vez más portables entre bases de datos de grafos (la versión para Ultipa, una traducción de Cypher a GQL instrucción por instrucción, es un ejemplo), pero cada motor tiene sus particularidades. Los scripts portados documentan en su cabecera los cambios que exigió cada motor.

---

## Primeros pasos

La forma más sencilla de empezar es con **Neo4j**:

1. Consigue una base de datos gratuita en [Neo4j Aura](https://neo4j.com/cloud/aura-free/) o usa Neo4j Desktop.
2. ¿Nuevo en Cypher? Empieza por [Neo4j GraphAcademy](https://graphacademy.neo4j.com/).
3. Elige una prueba de concepto, abre su script `.cypher` principal y sigue las instrucciones de la cabecera.

> ⚠️ La mayoría de los scripts empiezan con `MATCH (n) DETACH DELETE n` para vaciar la base de datos. Ejecútalos en una base de datos vacía o desechable.

Los scripts de esquema GRAPH TYPE (`TenderGraphType v1.cypher`, `NorthwindPlusGraphType_v1.cypher`, `NorthwindPlusGraphType_v2.3.3.cypher`) usan la aplicación de esquemas GRAPH TYPE de Neo4j, introducida como versión preliminar en Neo4j 2026.02 / Cypher 25. Comprueba que tu versión de Neo4j la admite antes de ejecutarlos.

Los simuladores en Python necesitan Python 3 y el driver de tu base de datos (por ejemplo, `pip install neo4j`). Los parámetros de conexión se pasan como variables de entorno, descritas al principio de cada script.

El **agente de IA** ([`NorthWindPLUS/Neo4jRelate`](NorthWindPLUS/Neo4jRelate/Leame%28es-ES%29.md)) se ejecuta en **Google Colab** o en local (terminal o Jupyter). Necesita una clave de API de Anthropic, de una cuenta de Claude Console, y tus credenciales de Neo4j Aura; su Léame explica la configuración paso a paso.

---

## Guía de carpetas

### `/RideHailing`

| Fichero | Descripción |
|---|---|
| `RideHailing.cypher` | Crea los nodos iniciales (Pasajeros, Conductores, Coches, Reservas) en distintos estados para que puedas explorar el modelo. Se puede ejecutar completo. |
| `RideHaining-MemGraph.cypher` | El mismo script adaptado para Memgraph. |
| `neo4j-RideHailingDB.backup` | Una copia de seguridad de Neo4j con los nodos iniciales y algunas reservas ya hechas, como alternativa a ejecutar el script. |
| `RideHailing_Queries.cypher` | Consultas de ejemplo para ejecutar sobre el modelo. |
| `RideHailing_Templates.cypher` | Comandos Cypher usados para construir la aplicación de maqueta que se muestra en el artículo. Sustituye las variables por valores reales antes de ejecutarlos. |
| `The RideHailingGraphModel.png` | El modelo de grafo de Ride-Hailing. |
| `RideHailingGraphApp/` | La aplicación prototipo en React + TypeScript (Vite) que funciona sobre el modelo. |

### `/TenderWorkflow`

| Fichero | Descripción |
|---|---|
| `TenderWorkflow v7.1.cypher` | **Versión actual.** La simulación del Sistema de Licitaciones con la implementación completa de la ontología (Neo4j). |
| `TenderGraphType v1.cypher` | El esquema GRAPH TYPE que acompaña a la v7.1 y aplica la ontología a nivel de base de datos. |
| `TenderGraph RDF-turtle v1.ttl` | La misma ontología expresada en RDF/OWL (Turtle). |
| `TenderWorkflow v7.1 MemGraph.cypher` | La v7.1 adaptada para Memgraph. |
| `TenderWorkflow v7.1 FalkorDB (beta).cypher` | La v7.1 adaptada para FalkorDB, en beta. |
| `Tender_Workflow_Random_Test_Generator.py` | Generador parametrizado en Python que crea licitaciones al azar, las revisa, invita a proveedores, acepta y revisa ofertas y adjudica (o no) las licitaciones, siguiendo estrictamente las reglas del flujo de trabajo. Los umbrales de aprobación se leen del grafo, no están fijados en el código. |
| `Tender_Workflow_Random_Test_Generator_MemGraph.py` | El generador adaptado para Memgraph. |
| `* ScriptOutputFile.txt` | Ejecuciones de ejemplo del generador en Neo4j Aura (con GRAPH TYPE), Neo4j Desktop y Memgraph en Docker. |
| `Tender Model v7.1 visualisation.png` / `.svg` | El modelo de grafo de la v7.1. |
| `TenderWorkflow v5.cypher`, `v6.cypher`, `v6 - MemGraph.cypher`, `v6 Graph Model.png` | Versiones anteriores, conservadas como referencia (la v6 usa la relación genérica `[:HAS]` con una propiedad `RelType`). |

### `/NorthWind`

| Fichero | Descripción |
|---|---|
| `NorthWind v2.1.cypher` | El modelo Northwind adaptado a los principios clave, con tipos de relación específicos de la ontología (la v2 abandonó el genérico `[:HAS]`). |
| `NorthWind.cypher`, `NorthWind v2.cypher` | Versiones anteriores. |
| `NorthWind Schema Only.cypher` | Solo el esquema, sin datos (creado con la aplicación Arrows). |
| `NorthWindPlus  v1.cypher`, `NorthWind_PLUS_Graph_Data_Model_Import_v2.1.cypher` | Primeras iteraciones de NorthWind PLUS, conservadas como historial. La versión actual está en `/NorthWindPLUS`. |
| `Northwind.png` | El modelo de grafo de Northwind. |
| `Import/` | **Ficheros CSV corregidos.** Los ficheros originales de [neo4j-graph-examples/northwind](https://github.com/neo4j-graph-examples/northwind) contienen comas sin escapar en algunos campos (sobre todo direcciones de Brasil, Francia y Bélgica, y algunas notas), lo que desplaza las columnas al importar. Lo comuniqué en la issue #53 de ese repositorio. |

### `/NorthWindPLUS`

La prueba de concepto más completa: Northwind convertido en un ciclo de negocio completo, además de harnesses en Python que ejecutan seis procesos de negocio independientes a la vez sobre el mismo grafo para comprobar si aguanta la carga. Incluye versiones para Memgraph, FalkorDB, Quine y [Ultipa](NorthWindPLUS/Ultipa/README.md) (en ISO GQL), un esquema GRAPH TYPE, una ontología en RDF y notas sobre una capa de IA agéntica.

➡️ **Consulta el [Léame de NorthWindPLUS](NorthWindPLUS/Leame%28es-ES%29.md)** para la guía completa y los primeros pasos con cada base de datos.

El trabajo con Quine viene en tres versiones, cada una con su propio README (en inglés):

| Carpeta | Qué es | Quién mueve el negocio |
|---|---|---|
| [`NorthWindPLUS/Quine/Full_NorthWindPLUS/Recipe_Version`](NorthWindPLUS/Quine/Full_NorthWindPLUS/Recipe_Version/Readme.md) | **El modelo completo como una única recipe de Quine.** Los flujos de ingesta hacen de mundo exterior (clientes, proveedores, el muelle del almacén). Las standing queries ejecutan las reglas de la empresa (revisión de POs, envío por el comprador, revisión de RFQs, cierre financiero). Incluye 47 consultas de ejemplo y 26 consultas rápidas con el botón derecho. | Solo Quine, sin Python |
| [`NorthWindPLUS/Quine/Full_NorthWindPLUS`](NorthWindPLUS/Quine/Full_NorthWindPLUS/Readme.md) | El modelo completo cargado mediante la API REST de Quine y movido por el harness en Python: o bien los seis bucles originales, o bien el mundo exterior en Python con las reglas como Standing Queries | Python, con o sin Standing Queries |
| [`NorthWindPLUS/Quine`](NorthWindPLUS/Quine/README.md) | Una demostración autónoma de cinco minutos de un "día de negocio" en streaming, construida por thatDot a partir del modelo | Solo Quine |

Y en Neo4j, un agente de IA trabaja junto a la simulación:

| Carpeta | Qué es |
|---|---|
| [`NorthWindPLUS/Neo4jRelate`](NorthWindPLUS/Neo4jRelate/Leame%28es-ES%29.md) | **Un agente de IA que aprende a orientarse en el grafo en vivo.** Responde preguntas de negocio en lenguaje natural, cambia los límites de aprobación bajo gobernanza (comprobación de rol, vista previa, confirmación, pista de auditoría) y guarda nuevas consultas como conocimiento reutilizable una vez que una persona las aprueba. En el modo *agents*, un Asistente de Compras asume la creación y el reenvío de POs que hacían los bucles: el agente recomienda, la persona decide y justifica, y un Cypher gobernado escribe. Su grafo de conocimiento (ontología, biblioteca de consultas, historial de preguntas) está en **Relate by Neo4j**; el negocio permanece en Neo4j Aura. Se ejecuta en Google Colab o Jupyter, con el modelo v2.3.3. En su primera ejecución en vivo encontró un error en la propia simulación. Una **interfaz web** en React + TypeScript hace los mismos trabajos de PO sobre el mismo Python y el mismo Cypher gobernado, con sugerencias a partir de la demanda reciente y borradores de justificación hechos con IA entre bastidores. |

---

## Artículos y charlas

Los artículos están en inglés; los títulos de abajo son los originales.

1. **El Concepto** — [A new approach to application development using Cypher/GQL (Graphs)](https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3)
2. **La POC de Ride-Hailing** — [Ride-Hailing Graph App Prototype Explainer](https://medium.com/@marcospinedo/ride-hailing-graph-app-prototype-explainer-071a89543a90)
3. **Flujos de trabajo en grafos** — [How Graphs simplify Business Processes and Workflows](https://medium.com/@marcospinedo/how-graphs-simplify-business-processes-and-workflows-like-moving-balls-between-baskets-c9606c9e973f)
4. **El "porqué"** — [Biomimicry in Software: Designing Business Systems using Graphs Like Nature Does](https://medium.com/@marcospinedo/biomimicry-in-software-designing-business-systems-using-graphs-like-nature-does-4c107dd2596e)
5. **El Flujo de Licitaciones** — [A Graph-Native Workflow Application using Neo4j/Cypher](https://medium.com/@marcospinedo/a-graph-native-workflow-application-using-neo4j-graph-a4406e51b4e5)
6. **Charla en NODES 2025** — [presentación en vídeo de los conceptos + demostración de la POC](https://youtu.be/ExupBmmH1Rs), y el artículo complementario con las diapositivas y la transcripción ampliada: [Rethinking Line of Business Applications: Graphs & Cypher as an Alternative to RDBMS & SQL](https://medium.com/@marcospinedo/rethinking-line-of-business-applications-graphs-cypher-as-an-alternative-to-rdbms-sql-fd1d204f99b7)
7. **Ontología y aplicación de esquemas** — [Graph-Native Business Applications with a Full Ontology — a practical use case of Neo4j's new GRAPH TYPE Schema enforcement](https://medium.com/@marcospinedo/graph-native-business-applications-with-a-full-ontology-a-practical-use-case-of-neo4js-new-graph-216c9bf20d22)
8. **NorthWind PLUS** — [A Labeled Property Graph (LPG) Masterpiece](https://marcospinedo.substack.com/p/a-labeled-property-graph-lpg-masterpiece): la prueba definitiva, con seis procesos de negocio independientes ejecutándose a la vez sobre el mismo grafo en vivo y poniendo en práctica todos los conceptos.
9. **Una perspectiva de grafo en streaming** — [Running your entire business as a Nervous System](https://marcospinedo.substack.com/p/running-your-entire-business-as-a): una perspectiva de grafo en streaming sobre un ciclo de negocio de 360°. La POC NorthWind PLUS ejecutándose sobre un grafo en streaming con Standing Queries.

Seguiré añadiendo contenido y prototipos a medida que evolucione este Nuevo Enfoque.

---

## Contacto

Si quieres conversar, saber más o probar este enfoque en tu próximo proyecto, puedes escribirme a marcos.pinedo@outlook.com o por [LinkedIn](https://www.linkedin.com/in/marcospinedo/).

Si te ha gustado lo que acabas de ver, te sugiero leer algunos de mis artículos anteriores (en [Medium](https://medium.com/@marcospinedo), [Substack](https://substack.com/@marcospinedo) o [LinkedIn](https://www.linkedin.com/in/marcospinedo/)) sobre temas relacionados, si aún no lo has hecho.


**"Alea iacta est": ¡cruzando el Rubicón de la adopción de los Grafos!** 🚀

¡Disfrútalo!

---

<sub>*Si te preguntas por el nombre "Flyer-Boy": es una historia muy, muy larga. Ahora también es mi gamertag de Xbox, "Flyerboy", mi nombre en Instagram, mi etiqueta en Discord, etcétera; ahora me sigue a todas partes, así que ten paciencia con él. ¡Lo siento!*</sub>
