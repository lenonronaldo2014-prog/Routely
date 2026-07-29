# Routely

App de roteirização para entregador autônomo. Você cadastra os endereços do dia
e ele monta alternativas de rota a partir de onde você está — com tempo e
distância de cada uma — para **você** escolher qual fazer.

**[⬇️ Baixar o APK](https://github.com/lenonronaldo2014-prog/Routely/releases/latest)**
 · [Política de privacidade](https://lenonronaldo2014-prog.github.io/Routely/)

Baixe o `arm64-v8a` (~32 MB) — cobre praticamente todo Android atual. Os APKs
são assinados com a chave de release, a mesma que vai para a Play Store, então
quem instala hoje atualiza direto quando o app for publicado.

## A ideia central

A maioria dos apps de roteirização cospe uma rota "ótima" e pronto. O Routely
mostra alternativas com trade-offs explícitos, porque o entregador sabe coisas
que o algoritmo não sabe: que o cliente da parada 7 só atende depois das 14h,
que a rua da parada 3 alaga quando chove, que aquele bairro é ruim de noite.

Três estratégias, sempre calculadas a partir da localização atual:

| Estratégia | Otimiza | Quando serve |
|---|---|---|
| ⚡ **Mais rápida** | menor tempo total | dia cheio, prazo apertado |
| ⛽ **Mais econômica** | menor quilometragem | combustível é lucro direto |
| 📍 **Mais próxima primeiro** | tirar entregas da lista rápido | quando o volume assusta |

## Estado atual

Funciona ponta a ponta, **sem nenhuma API key**:

- Cadastro de entrega com busca automática de CEP (ViaCEP)
- **CEP offline** — base por estado + dedução da UF pela faixa numérica
- **Autocomplete de endereço** — sugestões com coordenada, debounce de 400ms
- Geocoding via Geoapify, com Nominatim/OpenStreetMap como plano B
- Cálculo das 3 rotas a partir do GPS
- **Roadmap visual** — linha do tempo numerada com a sequência das paradas
- **Recalcular no meio do caminho** — reordena o que falta de onde você está
- **Rota persistida** — sobrevive ao app ser morto ou à bateria acabar
- **Agrupamento** — 8 entregas por rota no plano gratuito, o resto no próximo grupo
- Navegação delegada ao Google Maps / Waze
- Marcar entregue, editar, remover, limpar concluídas
- **Leitura da etiqueta por foto** — OCR on-device, sem custo e sem rede
- **Ajuste manual no mapa** — quando o geocoding erra, o usuário marca o ponto
- **Histórico** — o que foi entregue, por dia, com quilometragem
- **Backup** — exportar/importar e backup automático do Android
- **Configurações** — tema claro/escuro/sistema, tempo por entrega, velocidade média
- Offline-first: SQLite é a fonte da verdade

## Custo de operação: zero

Nenhuma peça do app depende de serviço pago. Isso é decisão de arquitetura, não
sorte:

| Peça | Como resolve | Custo |
|---|---|---|
| Ordenar as entregas | Cálculo local (haversine + 2-opt) | Zero |
| Navegar até o ponto | Delega ao Google Maps/Waze do usuário | Zero |
| GPS | Do aparelho | Zero |
| CEP → endereço | Base offline, depois ViaCEP | Zero |
| **Endereço → coordenada** | **Geoapify (plano gratuito), cache no banco** | **Zero** |
| Não perder dados | Backup do Android + export manual | Zero |

O único ponto que escalaria em custo é o geocoding. Ele é gratuito aqui por
duas razões: o plano gratuito do Geoapify dá 3000 consultas por dia, e o app é
construído para gastar o mínimo possível delas.

### Por que Geoapify e não OpenStreetMap

O OSM não cobre cidade pequena no Brasil. Medido contra o Nominatim, o endereço
**Rua Carlos Olig, 20, Apiaí/SP** não existe lá em nenhuma forma de consulta:

| Consulta | Nominatim | Geoapify |
|---|---|---|
| rua + número | `[]` | prédio exato |
| só a rua | `[]` | — |
| CEP 18320-620 | `[]` | — |
| bairro | `[]` | — |
| cidade | achou | — |

O melhor que o Nominatim conseguia era o centro de Apiaí, a 1,6 km do destino.
O Geoapify devolve `-24.49358, -48.84348`, na quadra certa.

O Nominatim continua no projeto como **plano B**, com a cascata inteira. Ficar
sem geocoding é pior que geocodificar mal.

### Como a cota gratuita é suficiente

| Medida | Efeito |
|---|---|
| Geocodifica uma vez, no cadastro, e grava | Recalcular a rota não consulta nada |
| Cache no banco por endereço, com a precisão | Endereço repetido é grátis |
| Debounce de 400ms no autocomplete | "Avenida Paulista" custa 1 consulta, não 16 |
| Texto repetido sai da memória | Apagar e redigitar não consulta |
| Menos de 4 letras não consulta | Devolveria o Brasil inteiro |
| A sugestão escolhida já traz a coordenada | Salvar a parada não consulta |
| Teto diário abaixo do limite do plano | Cai no plano B antes de o provedor recusar |

`StopsRepositoryImpl.saveStop` grava a coordenada uma vez. O cálculo de rota lê
o banco e **nunca** geocodifica — seria pagar toda vez que o entregador
recalcula o roteiro, várias vezes por dia, pelo mesmo endereço.

Resultado de nível cidade é recusado no salvamento. Um erro de quarteirões não
muda a ordem das paradas; o centroide da cidade colocaria bairros opostos no
mesmo ponto e produziria um roteiro que parece calculado e está errado.

### A chave da API

Fica em `geoapify.json` na raiz, que está no `.gitignore`. Copie de
`geoapify.example.json` e compile assim:

```
flutter build apk --release --dart-define-from-file=geoapify.json
```

**Sem o arquivo o app compila e funciona igual**, usando o Nominatim. Um clone
do repositório não vira um app quebrado.

Chave embarcada em APK pode ser extraída por quem descompactar o arquivo. Isso
é aceito de propósito: o plano gratuito do Geoapify não cobra excedente, ele
para de responder — então uma chave vazada causa indisponibilidade, não conta a
pagar, e o app cai no Nominatim. Se um dia valer esconder a chave, existe
`GEOAPIFY_PROXY`: apontando para um servidor próprio (um Cloudflare Worker
serve, e é gratuito), o app deixa de mandar chave nenhuma. É mudança de
configuração, não de código.

## Histórico e backup

"Limpar concluídas" **arquiva**, não apaga. Antes deletava, e o entregador
perdia o registro do próprio dia de trabalho.

O histórico agrupa por dia e mostra quantas entregas e quantos quilômetros. A
distância vem do trecho da rota (`LEFT JOIN active_route_legs` no momento do
arquivamento) — entrega concluída fora de rota simplesmente aparece sem
distância, em vez de mentir um número.

Para "troquei de celular e perdi tudo", dois caminhos, ambos grátis:

1. **Backup automático do Android** — o sistema sobe o banco e as preferências
   para o Google Drive da conta do usuário e restaura sozinho no aparelho novo.
   Configurado em [backup_rules.xml](android/app/src/main/res/xml/backup_rules.xml)
   e [data_extraction_rules.xml](android/app/src/main/res/xml/data_extraction_rules.xml).
   Fotos temporárias de etiqueta ficam de fora — têm nome e endereço de cliente.
2. **Exportar/importar** em Configurações → Meus dados. Gera um JSON legível
   que o usuário manda para si mesmo. Ele fica dono do próprio backup.

A base de CEP não entra no arquivo de propósito: são centenas de milhares de
linhas e ela é reimportável a qualquer momento.

## Ler a etiqueta por foto

Fotografar a etiqueta é o caminho rápido para quem tem uma pilha de pacotes na
frente — por isso "Escanear etiqueta" é a ação promovida na tela inicial, com
"ou digitar endereço" como alternativa.

O reconhecimento roda **no próprio aparelho** (ML Kit): sem chave de API, sem
custo por leitura, sem rede, e sem enviar para servidor nenhum uma foto que tem
nome e endereço de cliente.

### O parser ancora em rótulos, não adivinha por formato

Etiqueta de marketplace escreve os campos com nome:

```
Endereço: Rua Carlos Ollig 20, Pinheiros
CEP: 18320620
Cidade de destino: Apiai, São Paulo
Complemento: Sobrado esquina
```

Isso resolve de graça o problema mais perigoso: **a etiqueta também traz o
endereço do remetente**, mas sem rótulo nenhum, em letra miúda na borda.
Procurar por `CEP:` e `Endereço:` seleciona o destinatário sozinho — mandar o
entregador para o centro de distribuição do vendedor seria o erro mais caro
possível.

Também há armadilha numérica: código de rastreio, número de venda e a chave do
DANFE (44 dígitos) parecem CEP para uma regex ingênua.
[label_parser.dart](lib/features/stops/domain/services/label_parser.dart)
descarta sequências de 9+ dígitos por isso.

Sem rótulos ainda sobra um caminho por formato (prefixo `Rua|Av|Alameda…` e CEP
isolado), mas marcado como leitura parcial.

### Calibrado com etiquetas reais

[label_parser_test.dart](test/features/stops/label_parser_test.dart) usa a
transcrição de **duas etiquetas reais do Mercado Livre** do mesmo destinatário —
uma de frente, outra girada e com o bloco do remetente visível. Os testes que
mais importam:

- pega o CEP do destinatário (`18320620`), não o do remetente (`07174530`)
- ignora a chave de 44 dígitos do DANFE
- separa `Rua Carlos Ollig 20` em rua e número, sem vírgula entre eles
- converte "São Paulo" (por extenso) em `SP`
- continua funcionando se o OCR comer os acentos ("Endereco", "Sao Paulo")

### Nunca salva sozinho

O resultado abre o formulário **preenchido**, com um aviso pedindo conferência —
com destaque para número e complemento, que é onde a foto mais erra. OCR errado
que vira entrega errada destrói a confiança no app inteiro; um segundo
conferindo vale o roteiro do dia.

> ⚠️ **A precisão real só dá para medir em aparelho físico.** O emulador mostra
> uma cena virtual na câmera, então o que foi validado nele é o encanamento:
> permissão, preview, captura, ML Kit e o caminho de erro. O parser está coberto
> por teste com o texto real das etiquetas.

## Recalcular no meio do caminho

A ordem foi montada de onde o dia começou. Depois de algumas entregas o
entregador está longe daquele ponto, e a sequência que era ótima deixou de ser.

**O app sugere, não reordena sozinho.** Mudar a ordem das paradas sem avisar
desorientaria quem já decorou as próximas duas. A sugestão aparece quando a
parada mais próxima da posição atual não é a próxima da fila — com margem de
300m, senão o app cutucaria o usuário a cada semáforo.

**As entregas já feitas ficam no lugar.** Quem entregou 5 de 8 continua vendo
"5 de 8"; reiniciar em "0 de 3" apagaria a sensação de progresso do dia. A
estratégia escolhida e o horário de início também são preservados.

### O total sobe, e isso precisa ser explicado

Depois de recalcular, o número na tela **aumenta** — porque o total antigo era
medido de onde o dia começou, e o novo é medido de onde o entregador está.
Comparar os dois é comparar coisas diferentes.

A comparação honesta é: quanto ele rodaria seguindo a ordem antiga **a partir
daqui** contra a ordem nova. Foi validado no emulador: recalculando de volta na
Sé, o total foi de 8,7 para 8,1 km — mas a mensagem mostrou o ganho real,
**"7,6 km a menos do que seguindo a ordem anterior"**.

Sem esse número, o usuário olharia "26min → 28min" e concluiria que piorou.

## Quando o geocoding erra

Geocoding falha — e falha **com internet**. Num teste com 4 endereços reais de
São Paulo, um não foi encontrado. Como o fluxo é "cadastra de manhã com sinal,
roda o dia sem", um endereço que falha vira buraco no roteiro inteiro.

### Não achou o número? Abre perto, não longe

Antes, um endereço não encontrado caía na localização do próprio usuário — que
podia estar do outro lado da cidade. A busca agora afrouxa em degraus e conta
em qual parou:

| Precisão | Zoom | O que a tela diz |
|---|---|---|
| `exact` | 18 | "Achei este endereço. Toque na porta certa para ajustar" |
| `street` | 17 | "Achei a rua, mas não o número" |
| `postalCode` | 17 | "Este é o ponto do CEP" |
| `neighborhood` | 15 | "Achei só o bairro" |
| `city` | 13 | "Achei só a cidade" |

O aviso muda junto porque prometer precisão que não existe faz o usuário
confirmar um ponto errado achando que estava conferido. Errar 200m dentro do
bairro certo é outra história: ele arrasta o pino e segue.

### O mapa

[location_picker_page.dart](lib/features/stops/presentation/pages/location_picker_page.dart).

- **Tocar no mapa põe o pino ali, e o pino também pode ser arrastado.** Tocar é
  mais preciso; arrastar é o gesto que a maioria espera. Ter os dois evita a
  frustração de descobrir qual é o certo.
- **O pino sobe 56px em relação ao dedo enquanto é arrastado** — sem isso o dedo
  tapa justamente a ponta, que é o ponto que se quer enxergar.
- **Botão de usar a localização atual**, porque o entregador costuma estar na
  região do destino.
- **A coordenada aparece embaixo** — é o único feedback possível quando os
  tiles ainda não carregaram por falta de sinal.
- **Rotação desligada**: mapa torto atrapalha quem só quer marcar um ponto, e é
  fácil de disparar sem querer com dois dedos.

Duas armadilhas do Flutter que custaram caro aqui:

- **`GestureDetector` no pino não funciona.** O `flutter_map` disputa o gesto de
  arraste na arena e ganha, então só o mapa deslizava. A solução é `Listener`,
  que recebe os eventos de ponteiro sem entrar na disputa.
- **`onPositionChanged` com `setState` trava o app.** Reconstruía a página
  inteira a cada quadro do movimento do mapa — o log mostrou "Skipped 133
  frames" e o Android abriu o diálogo de ANR. Como o pino virou marcador com
  posição própria, o callback deixou de ser necessário e foi removido.

O ponto marcado à mão **vence o geocoding** — quem marcou estava olhando para a
porta. A precedência está testada em
[stop_form_bloc_test.dart](test/features/stops/stop_form_bloc_test.dart).

Dois caminhos até lá: o botão na seção "Localização" do formulário, e o atalho
"Marcar no mapa" direto no card da entrega sem localização — o aviso e a
solução no mesmo lugar.

`flutter_map` + OpenStreetMap em vez do SDK do Google: sem chave, sem custo por
carregamento, e é o mesmo caminho para tiles offline depois.

> ⚠️ Os tiles vêm de `tile.openstreetmap.org`, que tem política de uso e não é
> feito para volume. Serve para validar; em produção, self-host ou provider de
> tiles. A atribuição ao OSM na tela é exigência de licença, não enfeite.

## A rota não pode se perder

Perder o roteiro no meio de um dia de 20 entregas é o pior que pode acontecer
com este app. Por isso a rota escolhida vai para o SQLite no momento em que o
usuário toca em "Iniciar esta rota", e cada entrega marcada grava na hora.

Ao abrir o app, se existe rota gravada ela volta no topo da tela com o
progresso e a próxima parada. Validado no emulador com `am force-stop` no meio
do roteiro — voltou em "1/3", próxima parada correta, tempo restante recalculado.

Os trechos guardam só o **id** da parada, não uma cópia. Assim editar o endereço
ou marcar entregue reflete na rota sem sincronização manual.

> ⚠️ Armadilha achada por teste: `INSERT OR REPLACE` **apaga e reinsere** a
> linha. Com `foreign_keys = ON`, esse DELETE dispara o `ON DELETE CASCADE` dos
> trechos e **remove a parada da rota gravada** — ou seja, marcar como entregue
> a excluía do roteiro. Por isso `upsertStop` faz UPDATE-depois-INSERT, nunca
> `ConflictAlgorithm.replace`.

### Migração não pode perder dado

[migration_test.dart](test/core/database/migration_test.dart) monta um banco no
schema v1, abre com a versão atual e verifica que entregas, status, coordenadas
e cache continuam lá — e que reabrir várias vezes seguidas não perde nada.

Existe porque, num teste manual no emulador, as entregas sumiram do banco entre
duas sessões. Não consegui reproduzir a causa (as tabelas de CEP sobreviveram
na mesma base, então não foi limpeza de dados do app). Como "a rota não pode se
perder" é requisito, o caminho de atualização passou a ser verificado a cada
build em vez de depender de observação pontual.

## Agrupamento e planos

O plano gratuito roteiriza **8 entregas por vez**. O limite não é técnico (o
otimizador aguenta 150) — é de produto.

O usuário **nunca** é impedido de cadastrar endereços. Cadastrou 20? Cadastrou.
O app roteiriza as 8 mais próximas de onde ele está e informa quantas ficaram
para o próximo grupo. Bloquear o cadastro faria o app parecer quebrado; adiar é
honesto e ainda resolve o problema.

E fatiar tem um efeito colateral bom: o segundo grupo é calculado a partir de
onde o entregador **realmente parou**, não de onde começou o dia. Isso dá um
roteiro mais preciso do que resolver 30 paradas de uma vez com a origem defasada.

O critério de seleção é distância em linha reta até a origem — não o "melhor
subconjunto de 8", que seria um problema de otimização bem mais caro. Na
prática as mais próximas já formam um agrupamento geográfico coerente.

Trocar de plano é uma linha: `PlanTier` em
[plan_limits.dart](lib/core/config/plan_limits.dart).

## Arquitetura

Clean Architecture + BLoC, mesmo padrão do `niLeon-admin`.

```
lib/
├── core/
│   ├── database/      SQLite (stops, cep_cache, geocode_cache)
│   ├── error/         Failure / Exception
│   ├── geo/           GeoPoint + haversine
│   ├── services/      NavigationLauncher (deep links)
│   ├── settings/      tempo de parada, velocidade média
│   ├── theme/         paleta e tema
│   ├── usecases/      UseCase<T, Params>
│   └── util/          CEP, gerador de ID
└── features/
    ├── location/      GPS (somente primeiro plano)
    ├── routing/       matriz de custos, otimizador, rotas
    └── stops/         CRUD de entregas, CEP, geocoding
```

### Offline-first, não "online com cache"

O SQLite é a fonte da verdade. A rede só **enriquece** o que já está gravado:

| Camada | Com rede | Sem rede |
|---|---|---|
| CEP → endereço | ViaCEP | base do estado → `cep_cache` → faixa numérica |
| Endereço → coordenada | Nominatim | `geocode_cache` |
| Tempo entre pontos | *(pluggable)* | haversine × 1.35 ÷ 28 km/h |

#### A cadeia do CEP

Quatro degraus, do mais barato ao mais caro:

1. **Base do estado instalada** — instantânea, cobre CEPs nunca vistos antes.
   É o que torna o offline uma promessa real e não só "funciona pro que você
   já usou".
2. **Cache** — CEPs já consultados neste aparelho.
3. **Rede** (ViaCEP).
4. **Faixa numérica** — devolve só a UF.

O degrau 4 não precisa de nenhum arquivo de dados. O CEP brasileiro não é um
número arbitrário: a primeira metade codifica região, e a alocação por estado é
pública e estável ([cep_range_resolver.dart](lib/core/util/cep_range_resolver.dart)).
Isso dá de graça a validação do que o usuário digitou, o preenchimento
instantâneo da UF e um resultado parcial honesto quando falta tudo o mais —
melhor que uma tela de erro.

A UI mostra de onde veio (`AddressSource`): "Preenchido pela base offline",
"Preenchido de uma consulta anterior" ou "Só deu para identificar o estado". As
três situações são diferentes e não podem parecer a mesma coisa.

Validado no emulador em modo avião: CEP na base preencheu rua/bairro/cidade;
CEP fora da base preencheu só a UF, com o aviso correspondente.

#### Instalar uma base

> ℹ️ **A tela de bases está fora da UI de propósito.** O fluxo real do app é
> cadastrar os endereços com internet e rodar o dia inteiro sem — e isso já
> funciona, porque a coordenada fica salva no banco. Instalar base só ajudaria
> para cadastrar endereço novo no meio da rua sem sinal, que é caso de borda.
> Expor a tela obrigaria o usuário a decidir sobre algo que ele não precisa.
>
> O código está inteiro e testado. Para reativar, basta um `_HeaderAction`
> abrindo a `CepPacksPage` em [stops_page.dart](lib/features/stops/presentation/pages/stops_page.dart).
>
> A cadeia de consulta segue ativa: sem base instalada, ela pula o primeiro
> degrau e vai direto para cache → rede → faixa.

Formato do arquivo:

```
cep;logradouro;bairro;cidade;uf
cep;logradouro;bairro;cidade;uf;latitude;longitude
```

As duas últimas colunas são **opcionais mas valiosas**: com elas, o app resolve
a coordenada sem rede e sem custo. Arquivo antigo de 5 colunas continua válido.

Um CEP por linha; linhas em branco e começadas com `#` são ignoradas; linhas
malformadas são puladas sem abortar a importação. Coordenada fora de faixa ou
zerada é descartada — melhor campo vazio do que mandar o entregador para o
oceano. A leitura é em fluxo e a
gravação em lotes de 2000 — uma base estadual tem centenas de milhares de
linhas e não cabe na memória de um aparelho modesto, que é o público do app.

Separado por UF porque a base do Brasil inteiro não cabe no APK, e entregador
autônomo trabalha num estado só.

O seletor de arquivo usa o Storage Access Framework do Android, que **não exige
permissão de armazenamento** — mantém a lista de permissões enxuta.

> ⚠️ **O arquivo de dados não vem no repositório.** A base oficial dos Correios
> (DNE) é licenciada e paga; dumps públicos variam em procedência e qualidade.
> Qual usar é uma decisão com implicação legal para quem publica o app, então
> fica com você. O app aceita qualquer arquivo no formato acima.

Cadastrar entrega **nunca** falha por falta de rede. A parada é salva sem
coordenada, aparece marcada como "sem localização" e fica de fora do cálculo
até ser resolvida — puxar a lista para baixo com internet resolve o pendente.

O cache não é otimização opcional: entregador autônomo trabalha em região fixa
e repete endereço o tempo todo. Depois de alguns dias, a maior parte das
consultas nem sai do aparelho.

### Trocar a fonte dos tempos de viagem

`HaversineMatrixProvider` é o padrão porque roda em qualquer lugar e não custa
nada. Para plugar roteamento real (OSRM próprio, Google, Mapbox), implemente
`TravelMatrixProvider` e troque **uma linha** no `injection_container.dart`:

```dart
sl.registerLazySingleton<TravelMatrixProvider>(() => OsrmMatrixProvider(...));
```

Nada acima disso muda. `RouteOption.isEstimate` já controla o aviso na UI.

> ⚠️ A matriz é N×N. Com serviço cobrado por elemento, 15 entregas = 225
> elementos por cálculo. Por isso ela é calculada **uma vez** e reaproveitada
> pelas três estratégias.

### Design system

Tokens em `core/theme/`, widgets compartilhados em `core/widgets/`.

- **Cores** vivem numa `ThemeExtension` (`AppColors`), não em constantes
  estáticas — é o que permite modo claro e escuro de verdade. Widget nenhum
  escolhe cor sozinho: pede `context.colors.textSecondary` e recebe a do tema
  ativo. Modo escuro não é enfeite aqui: entregador trabalha à noite.
- **Espaçamento** em escala fechada de múltiplos de 4 (`AppSpacing`). Escala
  fechada é o que impede o layout de virar uma coleção de 13, 17, 22.
- **Alto contraste** de propósito — a tela é lida sob sol, muitas vezes de luva.
  Alvo mínimo de toque de 56dp, acima dos 48dp do Material.

O usuário escolhe o tema em **Configurações → Aparência**: claro, escuro ou
seguir o sistema (padrão). A escolha fica gravada e a troca é instantânea — o
`SettingsCubit` vive acima do `MaterialApp` justamente para isso.

O seletor mostra uma **miniatura de cada tema** em vez de radio buttons. Radio
com a palavra "Escuro" não mostra nada; a miniatura mostra o resultado antes da
escolha, que é o ponto de um seletor de aparência.

Configurações também expõe os dois valores que mais afetam a precisão da
estimativa — tempo por entrega e velocidade média. Um valor fixo no código
erraria para todo mundo: quem entrega documento em prédio comercial gasta 2 min
por parada; quem entrega móvel em condomínio gasta 15.

#### Responsividade

`ResponsiveBody` centraliza e limita a largura (560dp em formulários, 720dp em
listas). Sem isso, num tablet cada linha atravessa 1200px.

A centralização é feita com **padding**, não com `Align` + `ConstrainedBox`.
Parece equivalente e não é: aquele par afrouxa as constraints, e um `ListView`
embaixo perde a altura — a tela do formulário saía totalmente em branco no
aparelho. Há teste de regressão para isso em
[responsive_body_test.dart](test/core/widgets/responsive_body_test.dart).

Também não existe `FloatingActionButton`: flutuando sobre a lista, ele cobria o
primeiro card em paisagem. As duas ações moram na mesma barra inferior.

### O otimizador

TSP de caminho aberto com origem fixa. Vizinho-mais-próximo para a solução
inicial + 2-opt para refinar — fica dentro de ~5% do ótimo, bem mais preciso do
que a estimativa de tempo que o alimenta.

`nearestFirst` é o guloso **sem** refinamento, de propósito: refinar faria ela
deixar de cumprir o que promete ao usuário.

## Play Store

Decisões tomadas para a revisão ser trivial:

- ✅ **Sem `ACCESS_BACKGROUND_LOCATION`** — principal causa de recusa em app de
  rota. Exigiria formulário de declaração, vídeo de demonstração e revisão
  manual. A posição é lida só quando o usuário toca em "calcular", com o app
  aberto.
- ✅ **Sem serviço em primeiro plano** — consequência direta do item acima.
- ✅ **Sem `QUERY_ALL_PACKAGES`** — permissão sensível. O manifest declara
  apenas os `<queries>` dos intents que o app realmente usa.
- ✅ **Sem navegação turn-by-turn própria** — delegada ao Google Maps/Waze, que
  já têm as permissões.
- ✅ **`android.hardware.location.gps` como `required="false"`** — não filtra
  dispositivos sem GPS.
- ✅ **Sem `READ_MEDIA_IMAGES`** — a câmera é usada direto, sem galeria. Acesso
  à galeria é permissão sensível e não traria nada: ninguém fotografa a
  etiqueta hoje para cadastrar amanhã.
- ✅ **Permissões totais: 5** — localização fina, grossa, internet, estado da
  rede e câmera. A câmera é permissão comum de runtime, não sensível.

### Ícone

A arte fica em `assets/icon/source.png`. **Todo o redimensionamento é do
`flutter_launcher_icons`** — ele gera as 5 densidades do Android, os tamanhos
do iOS e aplica o recuo da camada adaptativa (que é XML, nem processa imagem).

```bash
dart run tool/generate_icon.dart      # recorte + cor de fundo + marca do app
dart run flutter_launcher_icons       # todas as densidades
```

[tool/generate_icon.dart](tool/generate_icon.dart) faz só o que a biblioteca
não faz:

1. **Recorta a arte.** A original é de divulgação — tem nome, slogan e tarja.
   Isso funciona num banner, mas na gaveta o ícone aparece com ~48px e o texto
   vira mancha. O recorte fica com a ilustração. Enquadramento nas três
   constantes no topo do arquivo.
2. **Casa a cor de fundo.** No ícone adaptativo a arte entra recuada e em volta
   aparece o fundo; se a cor não bater, dá para ver o quadrado da ilustração
   flutuando dentro do recorte. A cor sai da borda da própria arte, por mediana
   — troque a arte e o fundo acompanha.
3. **Gera `app_mark.png` (256px)** para a marca no cabeçalho do app, para não
   carregar o PNG de 1024 num widget de 44dp.

#### Tamanho da arte

Com o recorte de 65%, a arte precisa ser **≥ 1600×1600** para o resultado cair
em 1024 sem ampliação. `1024 ÷ 0,65 ≈ 1576`. Sem recorte, 1024×1024 basta.

A zona segura do ícone adaptativo é o que manda no enquadramento: **cerca de
1/3 pode ser cortado em qualquer lado**, dependendo da forma do launcher. Nada
essencial pode encostar na borda.

> A arte completa, com o nome e o slogan, não serve como ícone — mas é
> exatamente o que a Play Console pede como **gráfico de destaque** (1024×500).
> A ficha da loja também precisa de um **ícone próprio, 512×512**, separado do
> ícone do app.

### Assinatura e distribuição

```bash
flutter build apk --release --split-per-abi
```

O build lê a chave de `android/key.properties` (fora do repositório) e, quando
esse arquivo não existe, cai na chave de debug — assim quem clonar o projeto
consegue compilar sem ter a chave. Modelo e comando de geração em
[key.properties.example](android/key.properties.example).

Conferir com qual chave um APK foi assinado:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

> ⚠️ **Armadilha do Windows:** editores gravam `key.properties` com marca de
> ordem de bytes (BOM), e aí o Java lê a primeira chave com o marcador colado
> no nome — ela some. O Gradle agora acusa isso com mensagem explícita em vez
> de `null cannot be cast to non-null type kotlin.String`.

> ⚠️ Perder o `.jks` significa nunca mais atualizar o app na loja. Ao publicar,
> aceite o **Play App Signing**: o Google passa a guardar a chave real e a sua
> vira chave de upload, que eles conseguem resetar.

### Pendente antes do primeiro envio à loja

- [ ] **`applicationId` definitivo** — é permanente após publicar. Hoje está
      `com.routely.routely` em [build.gradle.kts](android/app/build.gradle.kts).
      Não precisa ser um domínio seu; o Google não verifica isso.
- [ ] Screenshots, descrição e gráfico de destaque (1024×500).
- [x] ~~Keystore de release~~
- [x] ~~Ícone~~
- [x] ~~[Política de privacidade](https://lenonronaldo2014-prog.github.io/Routely/)~~ —
      servida pelo GitHub Pages a partir de [docs/](docs/)
- [x] ~~Formulário de Segurança de Dados~~ — respostas prontas em
      [docs/play-store-data-safety.md](docs/play-store-data-safety.md)

## Roadmap

1. ✅ Cadastro manual + rota + navegação
2. ✅ Roadmap visual, rota persistida, agrupamento de 8
3. ✅ Base de CEP offline por estado
4. ✅ Leitura da etiqueta por foto (ML Kit on-device)
5. ✅ Recalcular no meio do caminho
6. **Ajustar o parser com etiquetas de outras transportadoras** — hoje está
   calibrado com Mercado Livre. Shopee, Correios e Amazon têm layouts próprios.
6. **Mapa com as paradas** — `flutter_map` já está no projeto; falta desenhar a
   rota e os pinos numerados sobre ele.

## Rodar

```bash
flutter pub get
flutter test

# Sem chave: funciona pelo Nominatim.
flutter run

# Com Geoapify (copie geoapify.example.json para geoapify.json antes):
flutter run --dart-define-from-file=geoapify.json
```

## Dívidas conhecidas

- **Sem sincronização entre aparelhos.** Backup e restauração resolvem trocar
  de celular; usar dois ao mesmo tempo, não. Isso exigiria servidor — e a
  decisão consciente foi manter o custo de operação em zero.

- **A cota do Geoapify é por chave, não por usuário.** São 3000 consultas por
  dia somando todo mundo que instalar o app. As economias descritas acima fazem
  isso durar bastante, mas com muitos usuários ativos o teto chega — e aí todos
  caem no plano B ao mesmo tempo. Antes disso valeria pôr o proxy no ar e
  medir o consumo real por usuário.
- **Sem autocomplete quando o Geoapify não está disponível.** O Nominatim
  proíbe autocomplete na própria política de uso, e ser bloqueado lá derrubaria
  também o geocoding, que importa mais. Sem sugestão, o usuário digita o
  endereço à mão, como sempre pôde.
- **2-opt assume matriz simétrica.** Vale para haversine e é aproximadamente
  verdade em malha viária. Com provider fortemente assimétrico (muitas mãos
  únicas), o ganho continua válido mas o delta calculado vira aproximação.
- **Geocoding ainda falha às vezes**, mesmo com internet. O ajuste manual no
  mapa cobre o caso, mas depende do usuário perceber.

- **`timeLimit` do geolocator não é confiável.** No emulador, o botão de
  localização girou indefinidamente porque ele não disparou. Corrigido com um
  `.timeout()` do Dart por cima, coberto em
  [location_repository_test.dart](test/features/location/location_repository_test.dart).
  Tela travada é pior que mensagem de erro — o future tem que completar sempre.
