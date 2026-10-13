# Curadoria contínua de Shorts no Mac

O iPhone lê `approvedShorts` no Firestore. O Mac prepara legendas e trechos; o catálogo guarda links e texto, **não** arquivos de vídeo. O serviço nunca envia a credencial Firebase ao iPhone. O projeto usado é `shadowing-commercial-edromero` (Firestore Standard).

## Painel de revisão no navegador

Com o serviço de busca ativo, abra outra janela do Terminal nesta pasta e rode `npm run dashboard`. Acesse `http://127.0.0.1:4318` no navegador do **mesmo Mac**. O painel mostra o progresso, os Shorts na fila de triagem, pendentes de revisão, publicados e rejeitados, a prévia do vídeo e cada trecho com tempo quando a legenda estiver pronta. Ele atualiza a lista a cada 10 segundos. Clique num trecho para ouvir uma prévia; confira também início, meio e fim do vídeo original, pois o player incorporado pode arredondar os cortes.

**Aprovar e publicar** exige uma confirmação explícita e envia o candidato ao Firestore; **Rejeitar** apenas o retira da fila. Abrir o painel nunca publica automaticamente. A página escuta somente em `127.0.0.1`, não mostra nem envia a chave Firebase ao navegador e não pode ser acessada de outro dispositivo. Feche o terminal do painel para desligar apenas a interface; o serviço de busca continua em segundo plano.

Para manter a página acessível após fechar o Terminal ou esta conversa, execute `npm run dashboard:install`. Ela iniciará após o login no Mac, sempre limitada a `127.0.0.1:4318`. Confira com `npm run dashboard:status` e desligue com `npm run dashboard:uninstall`.

A busca da API `videoDuration=short` inclui qualquer vídeo de menos de quatro minutos, inclusive vídeos horizontais. Por isso, o curador também confere as dimensões do player e a duração permitida para Shorts na data de publicação. Execute `npm run audit-shorts` para rever os candidatos antigos; os incompatíveis vão para **Rejeitados**, sem apagar seus arquivos locais. A verificação de formato não substitui assistir ao Short antes de publicá-lo.

Os trechos agora priorizam `?`, `!`, ponto, vírgula, ponto e vírgula e dois-pontos, inclusive quando aparecem dentro de um bloco da legenda, e usam limites menores de duração e palavras. Quando o corte cai **dentro** de um bloco, o tempo é estimado proporcionalmente às palavras: o painel mostra `≈` e impede publicação automática até você ouvir e revisar. Legendas automáticas sem pontuação ainda podem exigir um corte no limite de duração; o curador não inventa pontuação nem garante sincronização exata. Para atualizar os candidatos pendentes antigos, faça uma cópia de `.state/review` e `.state/metadata`, rode `npm run resegment` e recarregue o painel. Essa operação não altera itens já publicados ou rejeitados; candidatos que continuarem impraticáveis ficam sinalizados para revisão e não podem ser publicados.

## Preparar uma vez

1. No Terminal, entre nesta pasta e rode `npm install` (Node 20 ou superior).
2. No Firebase Console desse projeto, em **Configurações do projeto → Contas de serviço**, gere uma chave privada para uma conta de serviço com acesso ao Firestore. Salve o JSON em `~/.config/shadowing-curator/firebase-service-account.json`, **fora do repositório**. Nunca cole a chave em chat, Git ou no app.
3. Crie uma chave YouTube Data API v3 autorizada para uso no Mac. Uma chave restrita ao identificador do app iOS pode não funcionar aqui.
4. Crie `~/.config/shadowing-curator/curator.env` a partir de `curator.env.example`. Preencha o caminho absoluto do JSON e a chave YouTube. Proteja ambos os arquivos:

   ```sh
   mkdir -p ~/.config/shadowing-curator
   cp curator.env.example ~/.config/shadowing-curator/curator.env
   chmod 600 ~/.config/shadowing-curator/curator.env
   chmod 600 ~/.config/shadowing-curator/firebase-service-account.json
   nano ~/.config/shadowing-curator/curator.env
   ```

   Não use `sudo` para rodar o curador. O instalador recusa credenciais ausentes, públicas, do projeto errado ou guardadas dentro do repositório. A chave nunca é escrita no `.plist` do macOS.

## Piloto e revisão

1. Execute `CURATOR_LIMIT=5 npm run scan:configured` para uma triagem curta. Ela **não publica**. Sem credencial Firebase, é possível testar só os canais locais com `CURATOR_OFFLINE=1 FIREBASE_PROJECT_ID=shadowing-commercial-edromero YOUTUBE_DATA_API_KEY=... CURATOR_LIMIT=5 npm run scan`; não digite a chave em um comando que será compartilhado.
2. Execute `npm run review`. Abra os links exibidos, ouça amostras do começo/meio/fim e confira nível, tema, legenda e cortes. Os quatro candidatos anteriores à automação não têm metadados de origem e **jamais serão publicados automaticamente**.
3. Para cada Short realmente conferido, rode `npm run publish:configured -- ID_DO_VIDEO`. Para descartar, `npm run reject -- ID_DO_VIDEO`. `publish` sem IDs não publica nada.
4. Após revisar e publicar **três vídeos distintos do mesmo canal**, rode `npm run trust-channel -- ID_DO_CANAL`. Isso autoriza a publicação automática **apenas de novos Shorts** intermediários/avançados daquele canal que vieram da busca por canal e passarem por verificações mais rígidas. Iniciantes, sugestões de usuários, temas incertos e tempos suspeitos continuam aguardando revisão. Para suspender um canal, `npm run untrust-channel -- ID_DO_CANAL`.

Esses filtros verificam consistência textual e temporal, **não** confirmam o alinhamento acústico exato. Confiança num canal não substitui revisão de amostras posteriores.

## Rodar continuamente

Depois do piloto, instale o agente da sua sessão macOS com `npm run service:install`. Confira com `npm run service:status` e acompanhe `~/Library/Logs/ShadowingCurator.log` e `~/Library/Logs/ShadowingCurator.error.log`. Para parar e remover o serviço, `npm run service:uninstall`; os candidatos e documentos publicados permanecem.

O agente inicia após login e reinicia se cair. A cada 30 minutos ele tenta novos candidatos e publicação elegível; consolida likes uma vez por dia. A busca percorre até três páginas por canal, retoma da posição salva e reinicia uma nova rodada após 24 horas, sem reprocessar IDs vistos. Por padrão, faz no máximo 20 buscas à API por dia (`CURATOR_SEARCHES_PER_DAY`) e até 100 inspeções por ciclo (`CURATOR_LIMIT`). O serviço usa `caffeinate` para impedir repouso automático **enquanto o Mac estiver na energia**; ele não funciona desligado, sem rede, antes do login ou com a tampa fechada se o Mac suspender. O catálogo já publicado continua servindo o app enquanto o Mac estiver desligado.

Para antecipar canais específicos já presentes em `seeds.json`, rode `npm run queue-channels:configured -- ID_DO_CANAL ID_DO_OUTRO_CANAL`. Isso usa até 8 buscas prioritárias adicionais por dia, pega a primeira página de cada canal e coloca os IDs novos na fila, sem alterar a posição da busca sequencial nem publicar. O serviço processará a fila no próximo ciclo; para antecipar a triagem, rode `npm run scan:configured`. Candidatos continuam exigindo revisão de áudio, trechos e nível antes da publicação manual.

Execute `npm test` para testar as regras locais. Confirme os documentos em `approvedShorts` e o carregamento no iPhone físico antes de ampliar o volume. Monitore a cota da API YouTube e leituras/gravações do Firestore. Se um vídeo ou legenda deixar de funcionar, remova o documento correspondente de `approvedShorts` e suspenda o canal se for um problema recorrente.

**Direitos:** armazenar e redistribuir legendas de terceiros para teste técnico não concede direitos de uso comercial. Revise direitos e termos antes de distribuir esse catálogo comercialmente.
