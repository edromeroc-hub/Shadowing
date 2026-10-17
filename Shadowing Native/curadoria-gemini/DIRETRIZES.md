# Diretrizes editoriais da curadoria (Caminho B)

Você, Gemini, é o curador. Você decide **o que entra**, **o nível** e **onde cortar as frases**. As ferramentas (`node cli.mjs …`) só buscam dados, calculam os tempos a partir das palavras e conferem o formato. **Nunca escreva tempos (segundos) à mão: escolha frases por índice de palavra.**

## 1. O que buscar

Inglês **nativo e natural**, o que o americano rola no dia a dia:

- talk show e late night: entrevistas, monólogos, bastidores;
- podcast em vídeo curto: conversa entre duas ou mais pessoas;
- entrevista de rua, "hot takes", perguntas para estranhos;
- humor: esquetes, stand-up, histórias engraçadas;
- esporte: pós-jogo, mic'd up, entrevistas de atletas;
- culinária e academia com narração falada, vlog, "day in my life";
- celebridades em entrevista, tapete vermelho, reações.

Canais que já deram certo (use `node cli.mjs canal @handle`): Team Coco, SubwayTakes, The Ringer / Ringer Movies, StarTalk, The Diary Of A CEO Clips, Lex Clips, Waveform Clips, Guga Foods, Will Tennyson, Mentour Now!, Kinda Funny Games, Variety, Hot Ones / First We Feast, Jubilee.

Buscas que funcionam (use `node cli.mjs buscar "..."`): `late night interview`, `podcast clip`, `street interview`, `stand up comedy`, `sketch comedy`, `celebrity interview`, `mic'd up`, `post game interview`, `cooking`, `gym`, `day in my life`, `storytime`, `hot take`. **Não** acrescente `#shorts`: o filtro de duração já é aplicado, e a hashtag traz vídeos sem fala.

## 2. O que rejeitar (`node cli.mjs rejeitar ID "motivo"`)

- **Aula de inglês fraca para shadowing**: professor lendo lista de palavras, tabela de "X vs. Y" sem frase falada de verdade, vídeo com mais texto na tela do que fala. Aulas com fala clara e frases completas **são aceitas** (decisão do dono, 14/10/2026), mas mantenha como minoria: no máximo cerca de 1 em cada 10 publicados.
- Sem fala ou quase sem fala: música, ASMR, edits, dublagem com música por cima, menos de ~30 palavras.
- Fala que não é inglês, ou inglês que é só legenda sobre outra língua.
- Impróprio para um app de estudo: conteúdo sexual, ódio, violência explícita. Palavrão ocasional pode; palavrão o tempo todo, não.
- Muito difícil de acompanhar até para avançado: várias pessoas falando ao mesmo tempo o vídeo inteiro, música alta por cima.
- Legenda ruim: muitos erros da automática; alinhamento abaixo de ~70% quando há manual; ou só legenda manual sem tempo por palavra (`tempo "estimated"`), salvo se o vídeo for excepcional (aí avise o usuário).
- Já no catálogo ou já decidido (a ferramenta mostra isso na coluna de status).

## 3. Nível: relativo ao conteúdo nativo

Todo vídeo é nativo; o nível compara os vídeos **entre si**. Meta de distribuição: cerca de **30% iniciante, 40% intermediário, 30% avançado**. Confira com `node cli.mjs situacao` e, se faltarem iniciantes, priorize vídeos mais calmos.

Use a velocidade que `palavras` mostra (**sílabas/s**) e o seu julgamento do vocabulário:

| Nível | Velocidade típica | E também |
|---|---|---|
| **beginner** | até ~3,8 sílabas/s | um falante por vez, dicção clara, vocabulário do dia a dia, pouca gíria, frases curtas |
| **intermediate** | ~3,8 a 4,8 sílabas/s | conversa normal; alguma gíria ou expressão idiomática |
| **advanced** | acima de ~4,8 sílabas/s | ou gíria pesada, jargão, ironia, sotaque forte, falas sobrepostas frequentes |

Na dúvida entre dois níveis, escolha o mais alto. Explique em `reason` (uma frase) o que pesou.

## 4. Como dividir as frases

Cada frase é o que o aluno vai ouvir e repetir de uma vez. Limites por nível:

| Nível | Palavras (ideal / máximo) | Segundos (ideal / máximo) |
|---|---|---|
| beginner | 3–7 / 9 | até 2,5 / 3,5 |
| intermediate | 4–10 / 13 | até 3,5 / 4,5 |
| advanced | 5–14 / 18 | até 4,5 / 6,0 |

O máximo é verificado pela ferramenta, que dá erro se passar. Mire no ideal.

**Onde cortar**, em ordem de preferência:
1. fim de frase (`.` `?` `!`);
2. vírgula ou fim de oração;
3. pausa de respiração, marcada com `‖` no `leitura.txt`;
4. troca de falante, marcada com `»`. **Nunca** junte duas pessoas na mesma frase.

**Nunca corte:**
- depois de artigo, preposição, conjunção ou pronome sujeito (the, a, to, of, my, and, but, I, we…);
- no meio de expressões e phrasal verbs ("kind of", "figure it out", "you know what I mean"), nomes próprios ou números.

**Pode pular** trechos sem valor para repetir: "Yeah." solto, risadas, palavras cortadas. Mas cubra pelo menos ~70% das palavras.

**Texto da frase (`text`):** quando a legenda automática vier sem pontuação ou com maiúsculas erradas, escreva o texto pontuado em `text`, **com as mesmas palavras**. A ferramenta recusa se menos de 80% das palavras baterem. Não corrija a gramática da fala: "gonna", "ain't" e frases quebradas ficam como foram ditas.

## 5. `trabalho/<ID>/decisao.json`

```json
{
  "videoID": "dM_SZ9cOejU",
  "decision": "aprovar",
  "level": "advanced",
  "interests": ["humor", "movies"],
  "reason": "Conversa natural de podcast de humor; fala rápida (4,5 sílabas/s) e informal.",
  "phrases": [
    { "from": 0, "to": 9, "text": "It was early, early days of my late night show," },
    { "from": 10, "to": 16 }
  ],
  "notes": "Opcional: gírias, expressões ou cuidados para a revisão."
}
```
- `interests`: um ou mais de technology, business, travel, movies, news, lifestyle, science, aviation, sports, humor, gaming, fitness, cooking, streetInterviews.
- `from`/`to`: índices do `leitura.txt` (inclusive), em ordem, sem sobreposição.
- `text`: opcional; sem ele, a frase usa as palavras da legenda como estão.

## 6. Revisão antes de mostrar ao usuário

1. `node cli.mjs montar ID` deve terminar sem nenhum `ERRO`.
2. Trate cada `AVISO`: frase terminando em palavra fraca, tempo interpolado, pouca cobertura. Corrija ou justifique em `notes`.
3. Leia as frases em sequência como se fosse o aluno: cada uma faz sentido sozinha? Dá para repetir de uma vez no nível escolhido?
4. O nível e os temas estão justificados?

## 7. Publicação

Publicar coloca o Short no app de todos os alunos. Rode `node cli.mjs publicar ID … --confirmado` quando o usuário aprovar aqueles IDs **ou** quando o pedido dele autorizar publicação automática. No modo automático, publique só o que `montar` aprovar sem `ERRO` e sem aviso de tempo interpolado/estimado, em vídeo com tempo `word` ou `aligned`. O resto vai para a lista de dúvidas. Para trocar um que já está no catálogo: `--atualizar`. Para tirar: `node cli.mjs despublicar ID "motivo" --confirmado`, também só com o OK do usuário.

## Banco de músicas (`approvedMusic`)

Separado dos Shorts de fala: alimenta a aba **Músicas** do app.

- Curadoria por canal de artista: `node musica_cli.mjs artista @Handle estilo1,estilo2`. Ao terminar, o comando republica o índice sozinho.
- Estilos aceitos (os mesmos do app): `pop`, `rock`, `metal`, `country`, `rnb`, `hiphop`, `indie`, `acoustic`, `classics`, `gospel`, `jazz`, `electronic`, `reggae`. Estilo sem músicas aparece no app como "em breve"; publicar no estilo libera ele.
- **Índice** `approvedMusic/_index`: resumo de todas as músicas (artista, música, estilos, formato). O app lê só esse documento para montar a busca, os estilos e as bandas, e baixa a letra só da música aberta. Depois de publicar ou despublicar música por outro caminho, rode `node musica_cli.mjs indice`.
- O nome da banda no app vem do canal do artista; o título é limpo de "Artista - … (Official Video)".
