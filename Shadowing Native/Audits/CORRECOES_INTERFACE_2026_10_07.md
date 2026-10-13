# Correções da auditoria visual — 7/10/2026

## Escopo

Somente `Shadowing Native`, esquema `ShadowingNative`, bundle `com.edromero.shadowing.next`. Não foram alterados outros projetos Xcode, Firebase, chaves, assinaturas ou versões publicadas. As prévias usadas aqui são Debug/simulador, com transcrições locais e traduções sintéticas; não certificam reprodução real ou a tradução da Apple.

## Implementado

- Segmentação compartilhada por nível: iniciante até 10 palavras/85 caracteres/4,5 s; intermediário 16/120/6,5 s; avançado 24/165/8,5 s. Limites aplicados nas junções e reparos. São parâmetros iniciais para calibrar pedagogicamente, não níveis CEFR certificados.
- Preservação das fronteiras temporais recebidas. Removido o desconto arbitrário de 100 ms no final. Frases completas adjacentes não são juntadas apenas porque têm timestamps próximos.
- Um bloco indivisível que excede os limites é explicitamente marcado como **Trecho longo**, com leitura ampliada e possibilidade de avançar. Não foram inventados tempos por palavra para dividir blocos sem fronteiras internas confiáveis.
- Altura do texto de Shorts medida no layout real; inglês e tradução têm regiões separadas, com controles fora da rolagem. Tradução inicialmente oculta, menor e em itálico; o olho afeta somente a tradução.
- Indicação de continuação e expansão para textos excepcionais. Trocar de frase recria a área rolável, voltando ao início.
- Lacunas: enunciado rolável separado das quatro alternativas, que continuam acessíveis; contagem de 1 a 5 e resultados individuais preservados, com rolagem própria dos resultados.
- Frase inteira: campo junto aos controles, referência expansível após conferir e botão **Concluído** no teclado para encerrar edição mesmo com resposta vazia. Altura do ditado em Shorts também medida, em vez de manter espaço fixo excedente.
- Shorts distingue foco de teclado efetivamente apresentado, evita redimensionar a paginação com o teclado e mantém o player montado enquanto oculta sua imagem durante edição compacta. O feed não avança durante a digitação.
- Vídeos ocupa exatamente a altura útil; removido acréscimo de 24 pontos. **Ver todos os trechos** encerra a primeira seção; a lista não invade a área segura. Rodapé deliberadamente oculto durante edição compacta, não parcialmente cortado pelo teclado.
- Prefetch usa um indicador discreto e não intercepta toques. Prévia de layout não chama descoberta real; adicionado catálogo isolado de 20 páginas para teste.

## Validação executada

- Build Debug passou sem warnings nas últimas compilações.
- `run-segmentation-layout.zsh`: limites nos três níveis, palavras/ordem preservadas, tempos pertencentes à fonte, não sobreposição e sinalização de blocos atômicos grandes/densos passaram.
- `run-recommendations.zsh`: 126 verificações em 42 perfis, isolamento de contas, equilíbrio de temas, feedback, exclusões e descoberta com respostas de teste passaram. Isto não é um teste ao vivo da API YouTube.
- iPhone 16e, iOS 26.2: inglês longo, tradução longa, alternativas visíveis, cinco respostas com resultado 2/5, teclado de software, confirmação vazia pelo botão Concluído e restauração da tela. Frase normal de 21 palavras e tradução couberam por inteiro após uma segunda correção de medição.
- Vídeos no iPhone 16e: rodapé como último texto, tradução visível sem exigir rolar o inglês, teclado sem rodapé cortado.
- iPhone 17, iOS 26.2: prática horizontal longa/tradução e ditado de Shorts com teclado real, sem sobreposição dos controles.
- iPhone 17: recomposto o ditado na compilação final com altura medida; campo, confirmação e controles acessíveis acima do teclado (print 17).
- iPad 11-inch (M5), iOS 26.2: prática horizontal longa com fonte `.xxxLarge`, tradução em itálico e rodapé sem invasão da lista (print 14); ditado com teclado de software e quatro alternativas da Escuta ativa com fonte ampliada (prints 15–16).
- Rolagem direta observada até **14/20** no cenário local, sem prévia da próxima página em repouso. A sequência foi interrompida pelo bloqueio do Mac; ida até 20 e volta não foram concluídas.

## Evidências

Capturas reais em `interface-fixes-2026-10-07/`, inspecionadas visualmente. Prints 05 e 08 registram estados intermediários da implementação, não o acabamento final: 09 corrige o corte da frase normal; 12 mostra a lógica revisada de teclado. Prints 15 e 17 já incluem a compactação final por altura medida do ditado. O print 13 capturou a tela inicial do simulador antes de o app terminar de abrir e não é evidência de layout; o print 14 registra o app corretamente.

## Pendências de validação

- Concluir ida/volta nas 20 páginas, conferir resposta multilinha e abertura da leitura ampliada por toque após a compactação final. O Mac bloqueado impediu os gestos finais; os testes visuais adicionais de iPad e iPhone foram feitos por lançamento controlado e captura, sem desbloquear o computador.
- No aparelho físico, preparar idiomas e validar tradução inglês→português, tradução de palavras e troca rápida de frases. O diagnóstico por estágio/código e timeout já existente foi preservado, mas nenhum sucesso de tradução física é alegado nesta etapa.
- Ouvir cortes reais de vídeos/Shorts e reproduzir a configuração específica do iPhone da esposa. A preservação de timestamps não garante que a legenda automática da fonte esteja acusticamente correta.

## Reprodução

Executar o esquema nativo Debug com `--ui-audit`. Acrescentar:

```text
--audit-screen=shorts --audit-level=advanced --audit-many-shorts
--audit-screen=video --audit-long-caption
--audit-show-translation --audit-translation-fixture
--audit-active-listening
--audit-typing-keyboard
--audit-large-text
```

`--audit-translation-fixture` testa somente espaço de tela; sem esse argumento, o simulador informa que a tradução nativa não pode ser validada ali.
