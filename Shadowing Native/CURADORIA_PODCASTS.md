# Curadoria inicial — podcasts, conversas e criadores em inglês

Lista de fontes candidatas para os interesses do onboarding. Esta é uma fila editorial, **não um catálogo de vídeos aprovados**: a existência, a qualidade e o acesso às legendas devem ser testados por vídeo antes de exibi-lo ao aluno. Links de canal não implicam autorização para baixar ou redistribuir conteúdo.

| Interesse no app | Fonte candidata | Formato a priorizar | Nível inicial sugerido |
| --- | --- | --- | --- |
| Tecnologia | [WVFRM / Waveform Clips](https://www.youtube.com/channel/UCc_ycus0q7DSd85ZkmEY5ig) | Cortes de conversa sobre produtos e tecnologia | Intermediário |
| Negócios | [The Diary of a CEO Clips](https://www.youtube.com/channel/UCnjgxChqYYnyoqO4k_Q1d6Q) | Trechos de entrevistas sobre trabalho e negócios | Intermediário / avançado |
| Viagens | [The Travel Diaries](https://www.youtube.com/@thetraveldiariespodcast) | Conversas sobre viagens e experiências pessoais | Intermediário |
| Cinema & séries | [Variety — Actors on Actors](https://www.youtube.com/Variety) e [Ringer Movies](https://www.youtube.com/channel/UCowq59Fx3ykFKujwDcisqPQ) | Conversas sobre filmes, preferindo cortes curtos | Avançado |
| Notícias | [BBC Learning English](https://www.youtube.com/@bbclearningenglish) | Notícias comentadas em inglês acessível | Iniciante / intermediário |
| Vida real | [Mel Robbins Clips](https://www.youtube.com/channel/UCAg6WsUmUZsxlJ-tOfoYR4w) | Histórias e conversas do cotidiano | Intermediário |
| Ciência | [StarTalk+](https://youtube.com/startalkplus) e [Lex Clips](https://www.youtube.com/lexclips) | Perguntas e respostas com especialistas | Avançado |
| Aviação | [Mentour Now](https://www.youtube.com/@MentourNow) | Explicações e entrevistas de aviação | Intermediário / avançado |
| Esportes | [New Heights](https://www.youtube.com/@newheightshow) | Conversa informal sobre esporte; atenção a gírias | Avançado |
| Humor | [Team Coco](https://www.youtube.com/teamcoco) | Cortes de Conan O'Brien Needs a Friend | Avançado |
| Vídeo games | [Kinda Funny Games](https://www.youtube.com/@KindaFunnyGames) | Gamescast, debates e cortes de jogos | Intermediário / avançado |
| Aviação | [Captain Steeeve](https://www.youtube.com/@CaptainSteeeve) | Histórias e análises de aviação | Intermediário / avançado |
| Academia | [Will Tennyson](https://www.youtube.com/@WillTennyson) e [Jesse James West](https://www.youtube.com/@JesseJamesWest) | Treinos, desafios e conversas com convidados | Intermediário |
| Culinária | [Guga Foods](https://www.youtube.com/@GugaFoods) | Experimentos, receitas e conversas sobre comida | Intermediário |
| Entrevistas de rua | [SubwayTakes](https://www.youtube.com/@SubwayTakes) | Shorts com opiniões e fala espontânea | Avançado |

Viagens, notícias, cinema e aviação incluem programas de conversa ou explicação, não apenas podcasts tradicionais. Isso é intencional: o critério principal é fala natural útil para shadowing, não o rótulo do programa.

## Primeiros links de vídeo para triagem

Em 30/09/2026, os vídeos abaixo retornaram legenda em inglês usando `YouTubeTranscriptService.fetchTranscript(videoID:)`, o mesmo extrator da versão Swift. A contagem é de segmentos brutos, **não de frases prontas**. Isso comprova acesso à legenda naquele teste, mas não qualidade do texto, alinhamento com áudio ou disponibilidade futura. Vídeos horizontais não devem entrar automaticamente no feed vertical.

| Interesse | Vídeo testado | Segmentos | Próxima checagem editorial |
| --- | --- | ---: | --- |
| Tecnologia | [Waveform Clips: conversa sobre novos Macs](https://www.youtube.com/watch?v=9aSKMf5nCk0) | 532 | Selecionar trechos de diálogo |
| Negócios | [The Diary of a CEO: conversa sobre negócios](https://www.youtube.com/watch?v=ls9be-9C-uk) | 815 | Dividir a entrevista longa em sessões |
| Viagens | [The Travel Diaries: conversa com Prue Leith](https://www.youtube.com/watch?v=WYcl7WOe9SI) | 1537 | Revisar sotaque e trechos |
| Cinema & séries | [The Rewatchables: melhores momentos](https://www.youtube.com/watch?v=3r63TF3Ob9w) | 268 | Revisar sobreposição de vozes |
| Humor | [Conan O'Brien Needs a Friend: Martin Short](https://www.youtube.com/watch?v=eogS70nCT2k) | 201 | Revisar velocidade e gírias |
| Vídeo games | [Kinda Funny Gamescast: What We've Been Playing](https://www.youtube.com/watch?v=6La50pZAcBo) | 2201 | Escolher cortes curtos da conversa |
| Aviação | [Captain Steeeve: EL AL 777 / JFK](https://www.youtube.com/watch?v=uKHinvo6li0) | 327 | Revisar termos de rádio/aviação |
| Academia | [Will Tennyson: I Tried EVERY Way To Build Muscle](https://www.youtube.com/watch?v=yi8WGth7Hhs) | 1116 | Escolher trechos com fala clara |
| Academia | [Jesse James West: Diamond Gym](https://www.youtube.com/watch?v=aSV2zd-qch0) | 603 | Revisar ruído da academia |
| Culinária | [Guga Foods: VIRAL Celebrity Foods](https://www.youtube.com/watch?v=XL_A1rt_qz4) | 580 | Revisar cortes de montagem |
| Entrevistas de rua | [SubwayTakes: opinião em Londres](https://www.youtube.com/shorts/iAxqIk2cnZQ) | 71 | **Não aprovado para recomendação**; buscar tema mais adequado e revisar linguagem |

O Short do SubwayTakes passou apenas no teste técnico de legenda. O tema e a linguagem do exemplo exigem seleção editorial antes de qualquer recomendação ao aluno.

## Portão de entrada para cada vídeo ou Short

1. Registrar URL, ID do vídeo, ID do canal, formato, interesse, nível e data da checagem.
2. Confirmar que o vídeo continua público, reproduz no player do app e tem fala predominantemente em inglês.
3. Buscar a legenda com o serviço **real do app**; não aceitar apenas a presença visual de `CC` no YouTube como prova.
4. Montar uma sessão de teste e revisar manualmente começo, meio e fim: frases completas, áudio alinhado, sem música alta sobre a fala e sem cortes excessivos.
5. Aprovar somente o vídeo específico. Um canal aprovado não aprova automaticamente todos os seus uploads.
6. Se a legenda deixar de funcionar, retirar o vídeo das recomendações e oferecer outro; nunca prometer que o acesso é permanente.
7. Em colaborações, registrar os criadores participantes como etiquetas adicionais, sem substituir o canal que publicou o vídeo nem aprovar automaticamente outros vídeos desses convidados.

## Próxima rodada

Revisar manualmente começo, meio e fim dos vídeos acima e selecionar 2–3 vídeos/Shorts **específicos** por interesse. Vídeo games, academia, culinária e entrevistas de rua ainda não são opções do `LearningInterest` no onboarding; precisam ser adicionadas antes de personalizar o feed por esses temas. Só os aprovados no teste editorial devem virar IDs no `VideoSuggestion.catalog` ou `YouTubeShortItem.demoCatalog`. Preferir uma fonte remota editável para a curadoria final, para trocar vídeos sem publicar nova versão do app.
