# Calibração dos limites de áudio

O app pausa o YouTube diretamente, sem rampa de volume ou fade implementado pelo app. O tempo da legenda não prova onde a fala termina; antecipar o corte sem escutar a amostra pode amputar a última palavra. Por isso, o valor de produção continua em **0 ms** até a validação acústica.

## Coleta

1. Use o app **Debug em iPhone físico**, com a mesma frase e fones, a 1×. No Xcode, adicione um argumento de inicialização `--playback-cutoff-ms=0`, `50`, `100`, `150` ou `200` para comparar. Esse argumento não existe no comportamento de Release.
2. Teste pelo menos **30 vídeos**, sendo pelo menos 12 Shorts e 12 horizontais, com no mínimo **240 finais de frase**. Inclua finais com pontuação e sem pontuação, legendas por palavra e por bloco, fala rápida, fala lenta e transições sem silêncio.
3. Para cada final, registre: ID do vídeo, início/fim da frase em segundos, formato, precisão da legenda (palavra/bloco), velocidade, avanço em ms, se a **última palavra pertence integralmente ao trecho** e se **vaza a primeira palavra seguinte**. Não registre nem envie áudio ou texto da fala nos logs técnicos.
4. Veja `PlaybackTiming` no console do Xcode para comparar `sourceEnd`, `effectiveEnd`, `requestTime`, `pausedTime` e `pauseLatencyMs`. Esses números medem o player, **não** a diferença entre legenda e fala: a classificação auditiva é indispensável.
5. Repita pelo menos 20 finais em 1,5×. Reserve seis vídeos inéditos, equilibrados entre Shorts e horizontais, para validação final sem usá-los na escolha do valor.

## Decisão

Agrupe por formato e tipo de timing da legenda. Escolha o menor avanço que reduza vazamento **sem aumentar os cortes da última palavra** em relação a 0 ms, inclusive nos vídeos reservados. Se não houver avanço seguro e consistente, mantenha 0 ms e corrija os limites de frases individualmente. Não adote um deslocamento global só porque a legenda automática aparenta atraso em alguns vídeos.

O teste automático `node 'Shadowing Native/Audits/PlaybackBoundaryAudit.js'` verifica a lógica de pausa, buffer, 1,5× e retomada, mas não substitui a escuta no dispositivo.
