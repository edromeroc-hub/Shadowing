# Roadmap de Produto — Shadowing Native

Este documento organiza as próximas entregas da versão 100% Swift. Cada fase deve ser concluída e validada antes de iniciar a seguinte.

## Estado atual

- [x] Onboarding com nível de inglês, objetivos, interesses e meta diária.
- [x] Player oficial do YouTube integrado ao treino por frases.
- [x] Extração de legenda e segmentação em trechos de shadowing.
- [x] Feed vertical de Shorts com repetição e pausa para o aluno.
- [x] Palavras clicáveis no quadro “Ouça e repita”.
- [x] Vocabulário pessoal persistido e exibido em Progresso.
- [x] Tradução local com Apple Translation no iOS 18 ou superior.
- [x] Contagem diária de palavras e frases praticadas.
- [x] Idioma nativo e idioma de estudo configuráveis.
- [x] Modo Escuta Ativa — primeira versão funcional.
- [ ] Modo Música com letra sincronizada.

## Fase 1 — Perfil de idiomas

Objetivo: adaptar traduções, recomendações e exercícios ao idioma nativo do aluno, mantendo inglês como único idioma de estudo neste primeiro lançamento.

### Entregas

- [x] Criar um modelo de idiomas com códigos compatíveis com Apple Translation e legendas.
- [x] Adicionar ao perfil `nativeLanguage` e `learningLanguage`.
- [x] Preservar perfis já salvos por meio de migração com valores padrão.
- [x] Adicionar uma etapa de idiomas antes da escolha de nível no onboarding.
- [x] Mostrar português, espanhol, japonês e coreano como idiomas nativos iniciais.
- [x] Mostrar inglês como idioma de estudo disponível e os demais como “Em breve”.
- [x] Trocar a tradução fixa `en → pt-BR` por `learningLanguage → nativeLanguage`.
- [x] Exibir os idiomas escolhidos na tela Perfil e permitir alterá-los.
- [ ] Preparar os textos do aplicativo para localização futura.

### Critérios de pronto

- [x] Um usuário novo consegue selecionar seu idioma nativo.
- [ ] Uma palavra inglesa marcada é traduzida para o idioma nativo escolhido.
- [x] Um perfil criado antes da atualização continua abrindo normalmente.
- [ ] Alterar o idioma no Perfil atualiza novas traduções sem apagar o progresso.

## Fase 2 — Escuta Ativa

Objetivo: transformar cada trecho já segmentado em um exercício de compreensão auditiva sem depender de IA paga.

### Modos

- **Iniciante:** uma palavra ocultada e quatro alternativas.
- **Intermediário:** uma palavra ocultada, alternando alternativas e digitação; múltiplas lacunas virão depois.
- **Avançado:** uma palavra ocultada com resposta digitada; múltiplas lacunas virão depois.

### Entregas

- [x] Criar `ExerciseMode` com Shadowing, Múltipla Escolha e Digitação.
- [x] Selecionar palavras relevantes e evitar artigos, pontuação e nomes próprios quando possível.
- [x] Gerar alternativas plausíveis usando palavras da própria lição e vocabulário do nível.
- [x] Comparar respostas ignorando caixa, pontuação e diferenças simples de apóstrofo.
- [x] Mostrar acerto, resposta correta e opção de ouvir novamente.
- [x] Registrar tentativas e acertos.
- [x] Registrar palavras com maior dificuldade e priorizá-las nas próximas lacunas.
- [x] Recomendar palavras erradas para o vocabulário pessoal.
- [x] Adicionar métricas de compreensão auditiva em Progresso.

### Critérios de pronto

- [x] O mesmo trecho funciona em Shadowing e Escuta Ativa.
- [x] A dificuldade muda automaticamente conforme o nível do perfil.
- [ ] O exercício funciona offline depois que vídeo e legenda estiverem disponíveis.
- [x] Nenhuma API de IA é necessária para gerar ou corrigir respostas básicas.

## Fase 3 — Treinar com Música

Objetivo: reutilizar o player e o sistema de frases para praticar músicas com letras sincronizadas.

### Dependência importante

O player do YouTube fornece a reprodução, mas não garante letras completas nem tempos precisos para músicas. O modo precisa de uma fonte separada de letras sincronizadas, como catálogo próprio autorizado, arquivo LRC fornecido pelo usuário ou provedor licenciado.

### Entregas

- [ ] Adicionar Música aos interesses do onboarding.
- [ ] Adicionar estilos musicais e artistas favoritos ao perfil.
- [ ] Criar uma seção “Treinar com música” no Explorar.
- [ ] Criar modelo de faixa, versos e tempos sincronizados.
- [ ] Suportar inicialmente músicas de um catálogo curado ou arquivos LRC.
- [ ] Reutilizar repetição, pausa, palavras clicáveis e Escuta Ativa em cada verso.
- [ ] Avaliar e integrar um provedor licenciado antes de oferecer busca pública ampla.
- [ ] Personalizar recomendações por gênero, artista, nível e velocidade da música.

### Critérios de pronto

- [ ] O verso exibido corresponde ao trecho reproduzido.
- [ ] O aluno consegue repetir, ocultar palavras e salvar vocabulário.
- [ ] A origem da letra e a autorização de uso ficam registradas em cada faixa.
- [ ] Faixas sem sincronização confiável não entram no catálogo público.

## Ordem recomendada

1. Perfil de idiomas.
2. Escuta Ativa.
3. Música com um catálogo piloto pequeno.
4. Ampliação do catálogo e personalização das recomendações.

## Próxima entrega

Ampliar a Escuta Ativa para várias lacunas no nível avançado e validar a tradução local em aparelho físico. O uso offline completo ainda depende de uma fonte de vídeo disponível sem rede.
