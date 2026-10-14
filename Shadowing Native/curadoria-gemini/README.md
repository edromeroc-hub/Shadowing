# Curadoria pelo Gemini (Caminho B)

O **Gemini no Antigravity** faz a curadoria dos Shorts: procura, avalia, define o nível, divide as frases, revisa e (com o seu OK) publica no catálogo `approvedShorts`, que o app já lê. Usa a sua assinatura do Antigravity, **sem chave de API nova**.

É um caminho **independente** do curador automático em `curator/` (Caminho A). Os dois publicam no mesmo catálogo; um Short que já está lá aparece como "já no catálogo" e não é publicado de novo.

## Como usar no Antigravity

Abra a pasta `Shadowing Native/` e digite no chat:

| Comando | O que o Gemini faz |
|---|---|
| `/curar-shorts` | Busca Shorts naturais, analisa um por um, rejeita o que não serve, monta as lições e mostra uma tabela para você aprovar |
| `/publicar-shorts` | Publica os Shorts que você aprovou |
| `/revisar-shorts` | Revisa um Short já publicado (ou em rascunho), corrige frases e nível, e republica com o seu OK |

Exemplos: `/curar-shorts 5 iniciantes de culinária`, `/curar-shorts canal @SubwayTakes`.

As regras editoriais estão em [DIRETRIZES.md](DIRETRIZES.md).

## Ferramentas (`node cli.mjs <comando>`)

| Comando | Para quê | Cota do YouTube |
|---|---|---|
| `buscar "consulta" [--recentes]` | Shorts dos EUA em inglês, mais vistos dos últimos 180 dias | 100 + 1 |
| `canal @handle` ou `canal UC…` | Últimos Shorts de um canal | 2 a 3 |
| `info ID…` | Duração, formato, categoria, idioma, se já está no catálogo | 1 |
| `palavras ID` | Baixa a legenda, alinha manual + automática e grava `trabalho/ID/leitura.txt` | 0 (rate limit do YouTube) |
| `montar ID` | Lê `trabalho/ID/decisao.json`, calcula os tempos, valida e grava `documento.json` | 0 |
| `rejeitar ID "motivo"` | Registra a rejeição | 0 |
| `publicar ID… --confirmado [--atualizar]` | Publica no catálogo (**só com o OK do usuário**) | 0 |
| `baixar ID` | Mostra o que está publicado (para revisão) | 0 |
| `despublicar ID "motivo" --confirmado` | Tira do catálogo (**só com o OK do usuário**) | 0 |
| `situacao` | Publicados por nível, rejeitados, rascunhos em andamento | 0 |

- **Cota:** 10.000 unidades por dia na chave do YouTube, compartilhada com o curador. Prefira `canal` (barato) a `buscar` (100 por busca).
- **Legendas:** a ferramenta faz no máximo 2 pedidos simultâneos. Se aparecer o erro do limite 429, pare por pelo menos 30 minutos.

## Requisitos

- Node 20+ e `npm install` nesta pasta (já feito).
- `~/.config/shadowing-curator/curator.env` com `YOUTUBE_DATA_API_KEY`, `FIREBASE_PROJECT_ID` e `GOOGLE_APPLICATION_CREDENTIALS`. É o mesmo arquivo do curador, e as ferramentas nunca mostram as chaves.

## Arquivos

- `trabalho/<ID>/`: `palavras.json`, `leitura.txt`, `decisao.json` (escrita pelo Gemini), `documento.json`. Fica fora do git (legendas de terceiros).
- `registro.jsonl`: histórico de publicações, rejeições e despublicações (fica no git).
- `npm test`: testes das ferramentas, sem rede.

O documento publicado usa o formato v1 do catálogo, com `source: "antigravity-gemini"` e um bloco `curation` (motivo, notas, qualidade do tempo).
