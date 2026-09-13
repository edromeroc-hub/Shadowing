# ShadowingAI na AltStore Classic

## Pacote atual

O IPA funcional mais recente está em:

`releases/ShadowingAI-1.0-altstore-20260803-095434.ipa`

Para criar uma versão atualizada:

```bash
npm run ios:ipa
```

O novo arquivo será criado na pasta `releases`.

## Instalação no iPhone

1. Instale o AltServer no Mac e a AltStore Classic no iPhone.
2. Mantenha Mac e iPhone na mesma rede durante a instalação e renovação.
3. Envie o arquivo `.ipa` ao iPhone pelo AirDrop ou salve-o no app Arquivos.
4. Na AltStore, abra **My Apps**, toque no botão `+` e escolha o IPA.
5. A AltStore assinará o aplicativo usando o Apple ID configurado nela.

Com uma conta Apple gratuita, o aplicativo precisa ser renovado pela AltStore a cada sete dias.

## Estado funcional

- O próprio iPhone busca a legenda usando a conexão do aparelho.
- O iPhone monta e guarda uma aula local quando o backend inteligente não está configurado.
- O player nativo reproduz o fluxo MP4 e permite controlar os tempos das frases.
- Histórico, progresso, ditado e controles de shadowing continuam dentro do aplicativo.
- A tradução e a segmentação Gemini usam o endpoint HTTPS `/api/segmentTranscript` quando `VITE_SHADOWING_API_URL` é configurado antes da geração do IPA.
- O download permanente do vídeo para uso totalmente offline ainda não está incluído.

## Próxima etapa

1. Publicar o endpoint seguro de segmentação e tradução.
2. Gerar o IPA com `VITE_SHADOWING_API_URL` apontando para esse endpoint.
3. Adicionar download permanente e gerenciamento do espaço usado no iPhone.
