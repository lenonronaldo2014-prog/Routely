# Formulário de Segurança de Dados — Play Console

Respostas prontas para transcrever em **Play Console → Política → Conteúdo do
app → Segurança de dados**.

Este arquivo existe porque as respostas dependem de decisões de arquitetura que
são fáceis de esquecer meses depois. Se o app mudar — passar a ter servidor,
conta de usuário ou análise de uso — **este documento precisa mudar junto**.

> ⚠️ Declaração incorreta é motivo de remoção do app. Reconfira sempre que
> adicionar uma dependência que fale com a internet.

---

## O conceito que decide quase tudo

Para o Google, **"coletado" significa que o dado sai do aparelho**. Dado que
fica no celular do usuário — mesmo que o app leia, grave e use — **não é
coletado**.

O Routely guarda tudo em SQLite local e não tem servidor. Então quase todas as
respostas são "não".

A única exceção é o endereço enviado para os serviços de consulta de CEP e de
geocodificação. Isso sai do aparelho e precisa ser declarado.

---

## Antes de começar

| Campo | Valor |
|---|---|
| URL da política de privacidade | `https://lenonronaldo2014-prog.github.io/Routely/` |

Publicar essa URL: **Settings → Pages → Source: Deploy from a branch → branch
`main`, pasta `/docs`**. O arquivo [docs/index.html](index.html) é servido
automaticamente.

---

## Coleta e compartilhamento

### Localização

**Localização aproximada** — marcar como coletada.

| Pergunta | Resposta |
|---|---|
| Esses dados são coletados? | **Sim** |
| Esses dados são compartilhados? | **Não** |
| Processados temporariamente? | **Sim** |
| Coleta obrigatória ou opcional? | **Opcional** — o usuário pode marcar o ponto no mapa à mão |
| Finalidade | **Funcionalidade do app** |

*Por quê:* quando o usuário cadastra um endereço e tem internet, o app envia
esse endereço ao ViaCEP e ao Nominatim para descobrir a coordenada. O endereço
sai do aparelho, então conta como coleta. Nada é guardado por nós — não temos
servidor.

**Localização precisa** — marcar como **não coletada**.

*Por quê:* a posição do GPS é usada só dentro do aparelho, para calcular
distâncias. Nunca é transmitida.

### Fotos e vídeos

**Fotos** — **não coletadas**.

*Por quê:* a foto da etiqueta é lida pelo ML Kit dentro do próprio aparelho e
descartada em seguida. Não é salva na galeria nem enviada para lugar nenhum.

### Arquivos e documentos

**Arquivos e documentos** — **não coletados**.

*Por quê:* a exportação gera um arquivo que o **usuário** decide compartilhar,
pela folha de compartilhamento do sistema. Dado que o usuário envia por
iniciativa própria não é coleta do app.

### Todas as demais categorias

| Categoria | Coletado? |
|---|---|
| Informações pessoais (nome, e-mail, telefone, documento) | Não |
| Informações financeiras | Não |
| Saúde e fitness | Não |
| Mensagens | Não |
| Áudio | Não |
| Contatos | Não |
| Calendário | Não |
| Atividade no app (interações, buscas, telas) | Não |
| Navegação na Web | Não |
| Desempenho do app (falhas, diagnóstico) | Não |
| Identificadores do dispositivo ou de outros IDs | Não |

*Por quê o desempenho é "não":* o app não tem relatório de falhas nem
ferramenta de análise de uso. Se um dia entrar Firebase Crashlytics, Sentry ou
qualquer analytics, **esta linha muda**.

---

## Práticas de segurança

| Pergunta | Resposta |
|---|---|
| Os dados são criptografados em trânsito? | **Sim** — ViaCEP, Nominatim e os tiles do mapa são acessados por HTTPS |
| Você oferece um jeito de o usuário pedir a exclusão dos dados? | **Não se aplica** — nada é armazenado fora do aparelho; desinstalar apaga tudo |
| O app segue a política Famílias do Google Play? | **Não** — o app não é direcionado a crianças |
| Os dados foram avaliados por auditoria de segurança independente? | **Não** |

---

## Permissões declaradas no manifesto

Nenhuma delas é permissão sensível — não exigem formulário de declaração
separado nem vídeo de demonstração.

| Permissão | Para quê |
|---|---|
| `ACCESS_FINE_LOCATION` | Calcular a rota a partir da posição atual |
| `ACCESS_COARSE_LOCATION` | Idem, com precisão menor |
| `CAMERA` | Ler o endereço da etiqueta da encomenda |
| `INTERNET` | Consultar CEP, geocodificar e carregar o mapa |
| `ACCESS_NETWORK_STATE` | Saber se há conexão antes de tentar consultar |

### O que foi deliberadamente evitado

Estas ausências são decisões de projeto, não esquecimento — e são o que mantém
a revisão da loja simples:

- **`ACCESS_BACKGROUND_LOCATION`** — principal causa de recusa em app de rota.
  Exigiria formulário de declaração, vídeo de demonstração e revisão manual. O
  app lê a posição só com a tela aberta, e delega a navegação ao Google Maps e
  ao Waze, que já têm essa permissão.
- **`READ_MEDIA_IMAGES`** — permissão sensível. O app usa a câmera direto, sem
  galeria.
- **`QUERY_ALL_PACKAGES`** — permissão sensível. O manifesto declara apenas os
  `<queries>` dos intents que o app realmente abre.
- **Serviço em primeiro plano** — consequência de não usar localização em
  background.

---

## Quando reconferir

Marque este arquivo como desatualizado se qualquer uma destas coisas acontecer:

- [ ] Entrar backend, sincronização ou conta de usuário
- [ ] Entrar relatório de falhas ou ferramenta de análise de uso
- [ ] Entrar anúncio ou qualquer SDK de terceiro
- [ ] A leitura da etiqueta passar a enviar a foto ou o texto para um servidor
- [ ] Entrar assinatura paga (dados de compra têm declaração própria)
