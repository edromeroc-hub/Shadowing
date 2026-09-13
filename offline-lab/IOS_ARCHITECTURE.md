# Arquitetura do downloader no iPhone

O objetivo é manter a interface React atual e substituir apenas as funções que precisam conversar diretamente com o sistema operacional.

## Componentes

### React + Capacitor

- mantém as telas atuais do Shadowing;
- inicia e acompanha downloads;
- mostra a biblioteca offline;
- reproduz as frases e controla o loop;
- salva preferências e histórico do aluno.

### Extrator do YouTube

- recebe o link e identifica o vídeo;
- consulta metadados e formatos disponíveis;
- seleciona MP4 progressivo com áudio e vídeo juntos;
- encontra a legenda em inglês e preserva os tempos originais;
- devolve URLs temporárias e os cabeçalhos necessários ao downloader nativo.

O laboratório usa `youtubei.js`. A biblioteca também suporta navegadores modernos, então a primeira tentativa no Capacitor será reaproveitar esse extrator. O transporte HTTP poderá ser encaminhado para Swift caso o WebView bloqueie alguma requisição.

### Plugin Swift

- usa `URLSessionDownloadTask` para gravar o vídeo sem manter tudo na memória;
- publica progresso para a interface React;
- move o arquivo concluído para o diretório permanente do aplicativo;
- permite pausar, cancelar, listar e excluir downloads;
- mantém o download ativo pelo tempo permitido pelo iOS.

## Contrato do plugin

```ts
type OfflineVideo = {
  videoId: string;
  title: string;
  author: string;
  videoPath: string;
  captionsPath: string;
  lessonPath?: string;
};

interface ShadowingDownloads {
  probe(options: { url: string; quality: string }): Promise<DownloadProbe>;
  download(options: { url: string; quality: string }): Promise<{ jobId: string }>;
  list(): Promise<{ videos: OfflineVideo[] }>;
  cancel(options: { jobId: string }): Promise<void>;
  remove(options: { videoId: string }): Promise<void>;
}
```

## Estrutura persistente

```txt
Application Support/Shadowing/
  VIDEO_ID/
    video.mp4
    captions.en.srt
    captions.raw.json
    metadata.json
    lesson.json
```

`lesson.json` guarda as frases escolhidas pela IA, tradução, tempos calibrados e progresso do aluno. Depois que esse arquivo é gerado, a sessão pode funcionar completamente offline.

## Ordem de implementação

1. Integrar o motor do laboratório ao servidor local atual.
2. Adicionar a biblioteca offline na interface React.
3. Substituir o YouTube Player pelo elemento de vídeo local nessa modalidade.
4. Criar o projeto Capacitor mantendo o React.
5. Implementar o plugin Swift e o adaptador de transporte HTTP.
6. Gerar e autenticar o IPA para distribuição pela AltStore PAL.

O extrator deve permanecer atrás de uma interface própria. O YouTube altera formatos e assinaturas com frequência; essa separação permite atualizar o motor sem modificar o player, as aulas ou a interface.
