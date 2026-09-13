# ShadowingAI iPhone e iPad — 1.1.0 (2)

Um único IPA suporta iPhone e iPad, com bundle ID `com.edromero.shadowing`, permitindo atualizar a instalação anterior com a mesma identidade de assinatura. O pacote é compilado sem assinatura para instalação pela AltStore Classic/AltServer. Ele não é um ADP para AltStore PAL.

## Funções portadas

- Download de MP4 com áudio para Application Support, junto com a aula e suas legendas. O indicador offline só é ativado após validar as faixas de vídeo e áudio e concluir a gravação dos arquivos.
- Reprodução do arquivo local com o mesmo componente web de vídeo usado no Mac, repetição com intervalo para o aluno falar, navegação entre frases e ajustes de tempo.
- Histórico e progresso locais, gravação da pronúncia e ditado.
- Busca de vídeos por tema e canal no dispositivo.
- Leitura de legendas JSON3, XML clássico e SRV3. As URLs de legendas são preservadas como fornecidas pelo YouTube.
- Tradução e agrupamento das legendas com Gemini diretamente do dispositivo. A IA retorna índices de trechos; os tempos e o texto em inglês vêm da legenda original. Respostas que omitem ou duplicam trechos são rejeitadas.
- Chave Gemini armazenada no Keychain, sem embutir uma chave do desenvolvedor no IPA.
- Importação manual de SRT/VTT com preparação local ou IA.

## Primeiro uso

1. Instale o IPA com AltStore Classic e AltServer.
2. Abra a engrenagem e configure sua própria chave Gemini antes de baixar aulas, se quiser tradução, segmentação por IA e avaliação de pronúncia. Requisições usam a cota dessa chave. Texto da legenda e, ao solicitar avaliação, a gravação são enviados ao Google.
3. Cole o link e toque em Baixar. Mantenha o aplicativo aberto até aparecer Pronto offline.
4. Abra o vídeo e faça o treino. Vídeo e aula já baixados podem ser usados sem conexão; preparar aulas, buscar vídeos e avaliar pronúncia requer internet.

## Limites e validação

O download depende de o YouTube disponibilizar um MP4 progressivo com áudio e de a legenda estar acessível. Não há garantia para todos os vídeos ou redes. Downloads ainda não são retomados após encerramento do app. A biblioteca do Mac não é transferida automaticamente para o aparelho.

Sem chave Gemini, o agrupamento usa regras locais e não gera tradução. Aulas já baixadas preservam o conteúdo preparado no momento do download.

Verificações executadas: TypeScript, compilação Release arm64 para iPhone/iPad, leitura Swift de uma legenda real com 791 trechos, leitura de fixtures SRV3/XML com validação de unidades, acesso a uma faixa de MP4 e testes com respostas simuladas da IA para preservar cobertura, texto e tempos entre lotes.

Pendente no aparelho físico: instalação, download completo, abrir após reiniciar em modo avião, sincronização audível, gravação/permissões do microfone, Gemini com chave válida, layout em retrato/paisagem e atualização preservando dados. Compilar com sucesso não substitui esses testes.

## Gerar novo pacote

Execute `npm run ios:ipa`. O script lê a versão do Info.plist compilado e grava um IPA com data e hora em `releases`. A source pública anterior ainda aponta para 1.0; só atualize depois de validar esta versão no aparelho.
