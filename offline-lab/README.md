# Shadowing Offline Lab

Protótipo isolado do downloader integrado do Shadowing. Ele recebe um link do YouTube e cria um pacote local com:

- `video.mp4` com áudio e vídeo juntos;
- `captions.en.srt` para reprodução da legenda;
- `captions.raw.json` com os tempos originais;
- `metadata.json` com título, canal, duração e formato.

O app principal não é alterado por este laboratório.

## Testar sem baixar o vídeo inteiro

```bash
cd offline-lab
npm run probe -- "https://www.youtube.com/watch?v=VIDEO_ID"
```

O probe valida metadados, legenda e os primeiros 64 KB do vídeo.

## Baixar o pacote completo

```bash
cd offline-lab
npm run download -- "https://www.youtube.com/watch?v=VIDEO_ID"
```

Os arquivos são gravados em `offline-lab/library/VIDEO_ID/`. A biblioteca está ignorada pelo Git.

Nesta primeira versão usamos MP4 progressivo de até 360p. Essa qualidade evita a necessidade de juntar arquivos separados de áudio e vídeo e reduz bastante o espaço usado no celular.

## Arquitetura prevista

O motor expõe duas operações: `probe()` e `download()`. A interface React chamará essas operações por uma API local no Mac e, posteriormente, por um plugin nativo no iPhone.

No iOS, os arquivos devem ser gravados no diretório permanente do aplicativo, não em cache temporário. A interface React pode continuar sendo empacotada com Capacitor; Swift será usado somente na implementação nativa de download, armazenamento e reprodução local.

## Próximas etapas

1. Criar API local com progresso de download.
2. Adicionar biblioteca offline na interface React.
3. Reproduzir `video.mp4` com as frases do `captions.raw.json`.
4. Salvar tradução e segmentação da IA em `lesson.json`.
5. Empacotar o projeto com Capacitor e implementar o adaptador iOS.
