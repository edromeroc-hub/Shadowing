# Auditoria — interface, recomendações e sincronização

Data: 03/10/2026. Escopo: somente `Shadowing Native`, SwiftUI, bundle `com.edromero.shadowing.next`. As versões Classic/React, comercial e `Shadowing Swift` não foram migradas nem alteradas por esta revisão. Nenhuma publicação ou alteração de infraestrutura foi feita.

## Resultado

Foram corrigidos problemas concretos de enquadramento, concorrência entre carregamentos, repetição e perda de precisão da legenda. A compilação final de Debug passou no simulador iPhone 17, iOS 26.5. Isso não equivale a certificar precisão acústica em todos os vídeos, aparelhos ou condições de rede.

## Interface e transições

- Shorts: removidas máscaras pretas fixas que encobriam o painel; fundo da barra de abas ocultado nessa tela. Vídeo, painel e barra ficam próximos, respeitando a área disponível.
- Substituído o ciclo de medição de alturas por composição flexível: vídeo ocupa o espaço restante; controles ficam fixos e texto/exercício tem rolagem interna quando necessário.
- Legendas extensas, traduções e palavras longas não dependem de truncamento em duas linhas. A troca de frase reinicia a identidade do conteúdo.
- Somente a página visível mantém o player web. Trocar de aba, sair da página, colocar o app em segundo plano ou iniciar rolagem interrompe a reprodução. A detecção de fase da rolagem usa iOS 18+; no iOS 17 ficam as proteções de visibilidade/aba/ciclo de vida.
- Carregamentos recebem identificadores; respostas antigas não substituem o novo Short, link ou tradução.
- Curtir não reorganiza retroativamente o trecho visitado do feed. Apenas as próximas sugestões são reordenadas; ocultar tem opção de desfazer.
- Botões de transporte e opções têm rótulos de acessibilidade e alvos de toque de pelo menos 44 pontos.
- Boas-vindas agora permite rolagem e quebra de texto. Hoje tem cabeçalho mais compacto, saudação conforme horário e destaque para o treino. Perfil permite editar nível, meta e interesses.
- Vídeo importado mantém o identificador carregado separado do texto que está sendo editado no campo de link.

## Sincronização: causas e correções

### 1. Tempos disponíveis estavam sendo descartados

O JSON3 pode conter `tOffsetMs` dentro de cada evento. Esses deslocamentos agora são preservados. O pedido substitui o formato existente por `json3`, em vez de deixar `srv3` prevalecer. São priorizadas faixas em inglês com tempos internos; a alternativa sem esses tempos continua disponível.

Não são mais adicionadas margens universais de início/fim nem uma duração mínima artificial de 350 ms para cada palavra. O fim de um segmento não ultrapassa o início do próximo. Pausas e pontuação ajudam a agrupar frases, sem descartar falas curtas válidas.

### 2. Eventos e relógios competiam entre si

O limite do trecho é monitorado no JavaScript junto ao player. O relógio usa o tempo observado, a velocidade de reprodução e extrapolação limitada a 120 ms; não avança artificialmente durante buffering. A mensagem de término contém a revisão do trecho, para não encerrar uma frase nova com um evento antigo.

O fluxo pausa antes do seek e só solicita play depois de observar uma posição próxima ao início pedido. Um seek que não converge em oito segundos é interrompido e apresenta erro, em vez de continuar com áudio incompatível.

Pausar cancela a espera/repetição pendente. A pausa para o aluno considera a duração do trecho e a velocidade de reprodução. Eventos de um vídeo anterior são descartados.

### 3. Limite que ainda existe

Tempo de exibição de legenda não é necessariamente início/fim acústico de uma palavra. Mesmo uma faixa com offsets pode terminar a última palavra pelo fim do evento, não pelo fim real da voz. Faixas manuais ou XML podem fornecer somente tempos de blocos. Agrupamento por texto também não garante sentenças semanticamente completas.

O IFrame é assíncrono e o seek depende do player/buffer/keyframes. Polling, mensagens e pausa não oferecem precisão de amostras de áudio. Não foi implementado alinhamento forçado com a forma de onda, nem foi comprovado um atraso universal do YouTube. Aplicar um único desconto de milissegundos a todos os vídeos seria inadequado.

Referência: [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference).

## Recomendações: correções e achados

- Mantidos os filtros por nível estimado e interesses escolhidos, sem preencher o feed com exemplos incompatíveis quando falta conteúdo.
- Adicionados sinais “Muito fácil”, “No meu ritmo” e “Muito difícil”, junto ao feedback privado por usuário já existente. Muito difícil exclui aquele vídeo; muito fácil reduz sua prioridade. Isso não altera automaticamente o nível do aluno nem o algoritmo da conta YouTube.
- Ordem determinística e alternância de criadores quando há alternativas elegíveis. Preferências não fazem o Short atual saltar ao curtir.
- Cache atualizado para descartar resultados gerados pela extração antiga; resultados vazios expiram em 15 minutos, resultados positivos em até 24 horas com verificação do dia.
- Conferidos 16 itens do catálogo estático pelo oEmbed do YouTube. Quatro foram removidos: `RQPRaWqTMTc` e `Jv-cnD17k7s` retornaram 404; `tH2w6Oxx0kQ` era uma música do Kansas, não uma conversa em Londres; `j5v8D-alAKE` era Veritasium, não English with Lucy. Títulos e criadores dos demais foram ajustados quando necessário.

Essa checagem confirma identidade/disponibilidade no momento do teste, não qualidade pedagógica, licença, duração, segurança editorial nem disponibilidade permanente. Durações e níveis do catálogo estático ainda precisam de curadoria. A ausência de itens para certos níveis é preferível a recomendar conteúdo falsamente rotulado.

## Validação realizada

| Verificação | Resultado e alcance |
| --- | --- |
| Build Debug no simulador | Passou. Aviso não bloqueante: extração de metadados App Intents sem dependência do framework. |
| Máquina de reprodução JavaScript | Oito verificações passaram: seek com posição antiga, término, evento único, pausa manual, buffering, velocidade, página inativa e timeout. Player simulado; não mede áudio real. |
| Parser/agrupamento/recomendação Swift | Passaram offsets, cobertura textual do fixture, ausência de margem adicionada, não sobreposição, domínio do link, filtros, ocultação/dificuldade, ranking estável e compatibilidade com feedback antigo. |
| Legendas públicas reais | `MHeeektLq5A`: 36 segmentos, 35 marcados com timing interno, 8 trechos, nenhuma sobreposição. `-oguR1g-imQ`: 102 segmentos, 95 marcados com timing interno, 13 trechos, nenhuma sobreposição. Não houve medição acústica. |
| Comparação da extração | O primeiro Short anteriormente virava dois blocos longos; com os offsets disponíveis passou a oito trechos. |
| Interface no simulador | Inspecionadas capturas de boas-vindas, Hoje, Explorar, Perfil, Shorts/shadowing e escuta ativa com texto longo. Fixtures de layout foram usados para legenda/tradução; não representam playback real. |

O modo de inspeção `--ui-audit` existe apenas em Debug no simulador, com preferências separadas e sem iniciar autenticação/sincronização. Aceita `--audit-screen=shorts`, `today`, `explore`, `profile`, `onboarding`, `progress` ou `login`; `--audit-active-listening` abre o exercício de escuta. Fora desses argumentos, o fluxo normal permanece.

### Não verificado nesta rodada

- Gestos/toques manuais completos: o acesso à interface do Mac estava bloqueado durante a inspeção; capturas e execução via Simulator continuaram disponíveis.
- Sincronização audível no iPhone físico, Bluetooth, anúncios, rede lenta e diferentes velocidades em vídeo real.
- Login/exclusão reais, pagamento, tradução Apple no aparelho e sincronização entre contas/dispositivos.
- Matriz completa iPad, telas pequenas, teclado em escuta avançada, VoiceOver e tamanhos de acessibilidade. O componente de palavras ainda limita Dynamic Type e merece uma revisão específica.
- Build Release/publicação. A configuração atual inclui a chave de descoberta somente em Debug; produção precisa de configuração própria e preferencialmente busca via backend. Não copiar segredos para o código.

## Próximos passos recomendados, em ordem

### 1. Qualidade de sincronização antes de aumentar a biblioteca

Montar uma amostra revisada de 20–30 vídeos/Shorts, com diferentes sotaques, velocidades, ruído e tipos de legenda. Anotar manualmente início/fim acústico de trechos e medir erro de início/fim, palavras cortadas e palavras extras. Comparar mediana e percentil 95, em vez de escolher um offset global por impressão.

Classificar legendas por confiança (offsets internos, blocos, inconsistências) e rejeitar ou revisar as inadequadas antes de recomendá-las. Para material com áudio autorizado disponível, avaliar alinhamento forçado. Sem áudio/alinhamento confiável, sinalizar precisão aproximada e oferecer “Trecho fora de sincronia”. Não prometer precisão absoluta por IA textual.

### 2. Recomendações que acompanhem o aluno

A classificação atual por velocidade/vocabulário é heurística, não CEFR. Combinar dificuldade editorial, velocidade, complexidade, sotaque, acertos em escuta ativa e necessidade de repetição. Poucos erros não devem elevar o aluno automaticamente; pedir confirmação para aumentar o desafio.

Mostrar “Por que este vídeo?” com tema, nível estimado e canal. Usar dificuldade e rejeição como sinais separados de desinteresse. Garantir diversidade entre criadores dentro dos temas escolhidos; novos temas somente com consentimento. Avaliar taxa de início, conclusão, rejeição por dificuldade e retorno ao estudo, não apenas tempo de rolagem.

### 3. Biblioteca dinâmica com cache compartilhado

A descoberta atual consulta até dois interesses/canais por rodada diária e analisa até 12 candidatos; não é um feed infinito. Implementar paginação com cursor, reposição antecipada e deduplicação por usuário. No backend, compartilhar cache de metadados/legendas entre usuários, verificar disponibilidade periodicamente e controlar cota. Classificar o vídeo individualmente: pertencer a um canal de tecnologia não garante que todo Short seja sobre tecnologia.

### 4. Polimento final de produto

Testar acessibilidade e tamanhos de tela, preservar foco/posição ao trocar frases, adicionar feedback curto ao salvar vocabulário e explicar falhas com ações claras. Validar o fluxo real completo: entrar → retomar estudo → ouvir → repetir → marcar dificuldade → próximo conteúdo. Usar as áreas seguras nativas em vez de compensações fixas por aparelho: [SwiftUI safeAreaInset](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-6gwby).
