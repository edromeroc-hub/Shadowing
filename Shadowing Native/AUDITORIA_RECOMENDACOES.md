# Auditoria de recomendações — 7 de outubro de 2026

## Escopo e resultado

Somente o projeto `ShadowingNative.xcodeproj` foi compilado e testado. As versões React, Swift antiga e comercial não foram modificadas por esta auditoria. Nenhuma publicação, mudança no Firebase ou edição de conta real foi realizada.

Os testes automatizados passaram para os 14 temas e 3 níveis (42 perfis). Houve também consultas reais ao YouTube e testes de interação no iPhone 16e simulado. Isso valida as regras e os casos exercitados; não certifica a dificuldade de todos os vídeos do YouTube.

## Correções

- A fala rápida dentro de frases substanciais também conta para estimar dificuldade. Pausas longas já não tornam automaticamente uma fala muito rápida adequada a iniciantes.
- Indicações explícitas B1/B2 e C1/C2 no título impedem classificações indevidamente fáceis.
- Uma palavra incidental no texto, como “computer” numa entrevista de emprego, não basta para classificar o vídeo como tecnologia.
- A busca contextual deixou de acrescentar “interview” a todos os temas. Os canais de cada interesse são alternados, com equilíbrio entre temas e influência das preferências individuais.
- Falha em um canal não descarta os resultados válidos dos outros. Resultados duplicados, ocultados, difíceis demais ou de outro nível são excluídos.
- Hoje e Vídeos compartilham buscas simultâneas equivalentes. Respostas antigas não substituem as recomendações de um perfil atualizado; cancelar uma tela não cancela a busca da outra.
- O feed mantém páginas estáveis ao ocultar um Short e desfazer a ação. A página seguinte recebe sua própria legenda e controle de reprodução.
- Abrir a digitação não deve alterar a altura das páginas do feed: o conteúdo do treino adapta seu espaço ao teclado. A rolagem entre Shorts fica bloqueada durante a digitação.
- Títulos e nomes de canais retornados com entidades HTML são decodificados. As versões dos caches foram atualizadas para não reutilizar resultados anteriores a essas correções.

## Testes automatizados

Executar a partir da raiz do repositório:

```sh
zsh 'Shadowing Native/Audits/run-recommendations.zsh'
```

O script compila os serviços reais em um diretório temporário próprio. As respostas HTTP e legendas usadas nos testes determinísticos são fixtures; não são 42 pesquisas comerciais no YouTube. Os dados de teste usam suites isoladas de UserDefaults.

Validações concluídas:

- 126 verificações de seleção por tema, nível e feedback nos 42 perfis.
- Pipeline de vídeos e Shorts para todos os 42 perfis, incluindo faixa de legenda em inglês.
- Dois lotes preparados sem repetição, exclusões, limites vazios e falha parcial de busca.
- Equilíbrio entre múltiplos interesses, curtidas individuais e exclusão de conteúdo ocultado/difícil.
- Isolamento entre contas, persistência do feedback e desfazer.
- Coalescência de solicitações e cancelamento de um consumidor sem prejudicar outro.
- Rejeição de legendas de outro idioma e tratamento de chave ausente.
- Regressões para fala rápida, nível declarado, palavra temática incidental e entidades HTML.

Última execução: todas as verificações passaram, com código de saída 0.

## Consultas reais

Os 18 IDs de canais presetados foram encontrados pela API oficial. O ID de SubwayTakes foi conferido pelo handle oficial. Exemplos examinados:

| Perfil | Resultado observado |
| --- | --- |
| Iniciante, academia | Conteúdo de conversa simples no ginásio e vocabulário de equipamentos; trecho rápido de Jesse James West deixou de passar como iniciante |
| Avançado, aviação | Dois lotes de três Shorts distintos, incluindo Captain Steeeve e Mentour; todos com transcrição acessível em inglês |
| Iniciante, culinária | Vídeo de inglês simples na cozinha; conteúdo identificado como B1 deixou de passar no filtro iniciante |
| Intermediário, tecnologia | Dois vídeos relacionados a tecnologia em aproximadamente 15 segundos; uma entrevista genérica com referência incidental a computador deixou de passar |
| Avançado, aviação e games | Feed real com os dois interesses, além de recomendações horizontais de Kinda Funny Games e Captain Steeeve |

Os tempos são observações locais, não garantias de latência. As consultas reais utilizam a chave já configurada no app, sem registrá-la no relatório.

## Interface e navegação

No iPhone 16e simulado:

- Hoje e Vídeos carregaram recomendações reais, preservando o histórico de estudo e os temas escolhidos.
- Uma recomendação de Captain Steeeve abriu a prática com 212 frases; o botão Voltar retornou à tela Vídeos.
- A navegação de volta também foi exercitada a partir de Hoje e no fluxo de prática usado pela prévia de auditoria.
- A rolagem do feed ativou o segundo Short, com legenda correspondente, e preparou mais três itens: 3 → 6.
- Ocultar o Short atual e desfazer manteve o enquadramento e a posição, sem mostrar parte da página seguinte.
- Frase inteira aceitou uma resposta de teste e mostrou a comparação percentual; o teclado de software foi observado na primeira página com campo e controles visíveis.
- Na segunda página, foi verificado o foco do campo e o layout compacto, mas o teclado de software não ficou disponível nessa interação do espelhamento. A reprodução exata desse caso ainda deve ser conferida num iPhone físico.

Compilação final Debug para iPhone 16e: sucesso, sem erros ou avisos reportados pelo XcodeBuildMCP. Não foi encontrada falha fatal no log de execução inspecionado.

## Limites e próximos acompanhamentos

- O nível é estimado por ritmo, estrutura e vocabulário; não equivale a certificação CEFR nem garante que cada frase será adequada a todos os alunos.
- Disponibilidade da legenda, bloqueios do YouTube, vídeos removidos e quota de busca são dependências externas. Quando nenhum resultado passa, o app deve informar isso e permitir nova tentativa, nunca preencher com conteúdo avançado para um iniciante.
- A tradução nativa da Apple não foi validada por esta auditoria no simulador. Sua validação permanece em dispositivo físico.
- A gravação de desempenho com profiling e a validação física do teclado na segunda página não fazem parte dos resultados concluídos acima.
