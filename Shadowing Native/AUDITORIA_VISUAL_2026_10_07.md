# Auditoria visual de prática — 7 de outubro de 2026

## Resumo

Atualização: as correções de produção desta auditoria foram implementadas. Consulte `Audits/CORRECOES_INTERFACE_2026_10_07.md` para testes executados, evidências e validações ainda pendentes. Os problemas e prints abaixo descrevem o estado anterior.

O principal problema reproduzido não é um crash: é um trecho grande demais para praticar e para o espaço disponível. Há também problemas de acesso ao conteúdo e de aproveitamento da tela com o teclado.

Foram capturados e inspecionados 18 prints no iPhone 16e, iOS 26.2, tela lógica de 390 × 844 pontos. Os controles são os componentes reais do projeto **Shadowing Native**, com transcrições sintéticas para reprodução determinística. O retângulo “Prévia de layout” substitui somente a imagem/reprodução do YouTube; não representa uma falha de carregamento do vídeo.

Esta auditoria **não certifica** reprodução audiovisual, sincronização real do YouTube, tradução Apple no aparelho físico, nem todos os tamanhos de iPhone/iPad. Não houve envio de build ao TestFlight, mudanças no Firebase ou alterações nos outros projetos Xcode.

## Bugs e problemas confirmados

### P1 — O segmentador aceita um trecho individual enorme

Um segmento de entrada com **61 palavras, 348 caracteres e 23 segundos** saiu como uma única frase. Também saiu inteiro quando sua duração foi reduzida para 6 segundos: limitar somente segundos não resolve uma fala muito densa.

Os limites atuais de 8,5 segundos e 165 caracteres são verificados nas junções, não na entrada de cada segmento nem como garantia final de saída. Não há política de tamanho da frase por nível do aluno em `ShadowingLessonBuilder`.

- Origem: `ShadowingNative/Services/ShadowingLessonBuilder.swift`, criação de `PhraseGroup` nas linhas 20 e 29, normalização na linha 165.
- Reprodução: `zsh "Shadowing Native/Audits/run-segmentation-layout.zsh"`, executado na raiz do repositório.
- Evidência visual: prints 03, 05, 10 e 14.
- Consequência: o aluno precisa lembrar um parágrafo, não uma unidade curta de shadowing.

### P1 — Tradução e parte do inglês ficam fora da área inicialmente visível

Com a frase longa, o inglês ocupa toda a área rolável de Shorts e Vídeos. Ligar o olho não torna a tradução imediatamente visível: ela fica depois do texto em inglês, na mesma rolagem interna.

Isso **não significa perda do texto** nem letras sobrepostas. Em Vídeos, uma rolagem interna trouxe a tradução ao campo visível, sem deslocar os controles — print 15. Porém não há indicador de rolagem, e o corte no meio de uma linha parece uma tela quebrada.

- Origem: rolagens internas com `.scrollIndicators(.hidden)` e altura de texto limitada.
- Shorts: `ShortsFeedView.swift`, `panelContentHeight`, linha 654: teto de 110 pontos sem tradução, 126 com tradução, além do limite relativo de 25% da altura.
- A fonte cai até 14 pontos, mas não resolve uma frase de 61 palavras.
- Evidência: prints 04 e 14, comparados com 15 e 17.

### P1 — As alternativas de Lacunas ficam escondidas pelo enunciado

No teste longo, o texto mascarado ocupa a região do exercício; nenhuma alternativa aparece na primeira visualização. O player continua disponível, mas a ação principal de responder exige descobrir a rolagem interna.

- Evidência: print 05.
- O card precisa reservar espaço para responder, não apenas para exibir o enunciado.

### P2 — O teclado não sobrepôs os controles, mas o enquadramento fica desequilibrado

Com o teclado de software realmente aberto, no primeiro e no segundo Short, o vídeo foi ocultado e o campo/controles permaneceram utilizáveis. Uma resposta longa também coube sem sobreposição.

Mesmo assim, sobra muito espaço antes do cabeçalho e entre o card e o teclado, enquanto a área útil de resposta é pequena. A troca brusca entre vídeo grande e vídeo ausente prejudica a continuidade visual.

- Evidência: prints 06, 07 e 09.
- Origem a revisar: ocultação do vídeo baseada no foco do campo, cálculo manual de `keyboardOverlap`, alinhamento e estado de digitação em cada página.
- No módulo Vídeos, o texto “Ver todos os trechos” ficou parcialmente atrás do teclado — print 16. O campo e os controles não foram encobertos.

### P2 — “Concluído” com resposta vazia não encerra a edição

A tecla de confirmação com o campo vazio manteve o teclado aberto. `checkResponse()` retorna antes de remover o foco quando a resposta é vazia.

- Origem: `VocabularyPhraseView.swift`, linha 530.
- Separar “encerrar edição” de “avaliar resposta”. O aluno deve poder dispensar o teclado sem precisar inventar uma resposta.

### Observação — Gestos competem entre áreas roláveis

A troca de Short foi reproduzida com gesto direto na margem do feed. Gestos dentro do exercício podem rolar o texto, em vez de trocar a página. Não classifico isso como crash; é uma ambiguidade de interação a resolver.

Após avançar até o terceiro Short, o enquadramento estabilizou sem mostrar a próxima página atrás da barra inferior — print 18. Isso não substitui um teste prolongado com players YouTube reais.

O aviso “Preparando próximos Shorts…” apareceu sobre a janela do player durante prefetch — print 08. Pode ser menos intrusivo. A coleção de prévia também recebeu itens da descoberta real; a prévia de layout ainda não isola completamente o prefetch. Não usar essa execução para avaliar qualidade das recomendações.

## O que funcionou nos testes

- Inglês de 21 palavras coube no Short; inglês e tradução sintética juntos também couberam, sem colisão — prints 01 e 17.
- O olho mostrou/ocultou somente a tradução, mantendo o inglês no Shadowing.
- A frase curta em Vídeos mostrou tradução menor, abaixo do inglês, com controles na base — print 13.
- A rolagem interna em Vídeos preservou a posição dos controles — prints 14 e 15.
- A confirmação da resposta digitada calculou 70% para o texto de teste, sem crash.
- Primeiro → segundo → terceiro Short funcionou por gesto direto, sem prévia da próxima página no enquadramento final.
- O rodapé de Vídeos em repouso, por toque direto, mostrou “Ver todos os trechos” como último texto, sem letras da lista — prints 13 e 14.

## Cuidados para interpretar os prints

- Prints 11 e 12 foram capturados após ações por acessibilidade que deslocaram a rolagem externa. Esse deslocamento **não** se repetiu ao tocar diretamente no espelho do simulador: prints 13 e 14. Não atribuir automaticamente esse efeito ao toque normal do aluno.
- O spinner do print 12 vinha da primeira implementação do fixture de tradução, que usava `onAppear`. O fixture foi corrigido para reagir à troca de frase com `.task(id: phrase.id)` e recompilado; a tradução sintética apareceu no print 13. Isso **não é diagnóstico nem correção da tradução Apple**.
- As traduções usadas para verificar espaço foram textos locais previamente definidos. Nenhuma API de IA foi acionada para traduzi-los.
- A simulação padrão, sem o fixture, mostrou o aviso de indisponibilidade da tradução nativa no simulador — print 02.

## Plano de correção, na ordem

### 1. Corrigir a unidade pedagógica antes de diminuir fontes

Definir uma política compartilhada de tamanho por nível. Como ponto inicial de experimento, não regra já validada: iniciante 4–8 palavras/2–4 segundos; intermediário 8–14/3–6; avançado 12–20/4–8. Priorizar cláusulas com sentido completo; não forçar os limites mínimos em uma frase naturalmente curta.

Aplicar a política tanto aos segmentos recebidos quanto às junções e à saída final. Usar os timestamps de palavras/unidades quando existirem. Não dividir um bloco sem tempos precisos inventando durações iguais: isso pode piorar a sincronização. Sem fronteira confiável, sinalizar o trecho como inadequado ao treino curto e permitir pular ou usar uma apresentação expandida.

Critério: nenhum segmento excepcional passa silenciosamente como um treino normal; conservar palavras, ordem e limites temporais da fonte. Testar falas densas, pausas, preposições, pontuação ausente e blocos gigantes.

### 2. Tornar o card adaptativo, preservando controles

Medir a altura real do texto e do exercício, em vez de decidir apenas pelo número de palavras. Reservar primeiro o espaço dos controles e da resposta; entregar o restante ao texto e ao vídeo.

Manter tradução menor/em itálico e olho independente. Para conteúdo excepcional, mostrar uma indicação discreta de continuação e uma expansão deliberada, sem cortar letras no limite da caixa. Preservar a posição da rolagem externa ao ligar o olho; reiniciar a rolagem do texto ao trocar de frase.

Critério: uma frase adequada ao nível deve caber sem rolagem interna; inglês, tradução e botões não se sobrepõem. O aluno não precisa rolar para descobrir que existe uma tradução.

### 3. Priorizar a resposta na Escuta ativa

Em Lacunas, separar enunciado e alternativas: não deixar o enunciado consumir o espaço reservado às opções. Mostrar claramente a lacuna corrente e seu resultado; garantir acesso às demais lacunas sem empurrar os controles.

Em Frase inteira, manter o campo perto dos controles, resultado compacto e referência expansível depois de confirmar.

Critério: opções e confirmação são visíveis nos exercícios normais; 1 a 5 lacunas continuam respondíveis; resposta longa não aumenta indefinidamente o card.

### 4. Unificar teclado e paginação

Distinguir foco do campo de teclado efetivamente apresentado. Fazer a região de prática ocupar exatamente o espaço livre acima do teclado, sem faixas vazias artificiais. Em Vídeos, substituir o acréscimo fixo de 24 pontos por cálculo coerente de área segura/rodapé.

Permitir fechar o teclado com resposta vazia, preservando rascunho. Definir o gesto do texto versus o gesto do feed; durante edição, evitar troca involuntária de página. Ao fechar/avançar, restaurar o enquadramento sem salto para outra página.

Critério: campo, confirmação e controles acessíveis; “Ver todos os trechos” inteiramente visível ou deliberadamente oculto durante edição, nunca cortado pela borda do teclado.

### 5. Repetir a matriz visual e validar o aparelho físico

Após as correções: iPhone pequeno, iPhone 17 e iPad; frases curtas/normais/longas; tradução ligada/desligada; 1 e 5 lacunas; teclado vazio e resposta multilinha; retorno à frase anterior; ida/volta por pelo menos 20 Shorts; título de duas linhas; tamanho de texto ampliado.

No aparelho físico: reproduzir a sessão que falha na esposa do usuário, registrar iOS e configuração de texto/teclado, verificar tradução Apple e sincronização ouvindo o áudio. Sem esses testes não declarar o problema do dispositivo resolvido.

## Artefatos e reprodução

Capturas em `Audits/interface-2026-10-07/`. Resultado do teste de segmentação em `Audits/interface-2026-10-07/segmentation-results.txt`.

Executar o app Debug no simulador com:

```text
--ui-audit --audit-screen=shorts --audit-long-caption --audit-translation-fixture
```

Trocar `--audit-screen=shorts` por `--audit-screen=video` para a prática horizontal. Remover `--audit-long-caption` para a frase normal de 21 palavras. Remover `--audit-translation-fixture` para o aviso real do simulador.

Para abrir o teclado manualmente: entrar em **Escuta ativa → Frase inteira**, tocar o campo; em Device Hub usar **Device → Keyboard → Toggle Software Keyboard** se necessário. A entrada automatizada de texto pode ocultar o teclado de software; apresentá-lo novamente antes de tirar o print.

As mudanças desta auditoria são cenários Debug/simulador e ferramentas de diagnóstico. O segmentador e os layouts de produção **ainda não foram corrigidos nesta etapa**.

### Exemplos principais

Frase longa: alternativas fora da primeira visualização.

![Lacunas com texto longo](/Users/eduardoromero/Documents/immersive-shadowing/Shadowing%20Native/Audits/interface-2026-10-07/05-lacunas-estresse.png)

Teclado aberto depois da troca de Short: controles acessíveis, mas espaço mal aproveitado.

![Teclado no segundo Short](/Users/eduardoromero/Documents/immersive-shadowing/Shadowing%20Native/Audits/interface-2026-10-07/09-segundo-short-teclado.png)

Frase normal com tradução: sem sobreposição.

![Short com tradução](/Users/eduardoromero/Documents/immersive-shadowing/Shadowing%20Native/Audits/interface-2026-10-07/17-short-normal-traducao.png)
