# ShadowingAI — Plano da versão comercial

## Objetivo

Esta branch preserva o estado funcional atual do ShadowingAI e inicia uma versão separada, preparada para distribuição comercial pela App Store. A versão original continua na branch `main`; esta versão vive na branch `commercial-appstore` e na pasta `immersive-shadowing-commercial`.

O produto comercial não deve baixar, extrair, converter ou redistribuir vídeos e legendas do YouTube. O mecanismo de estudo será mantido, mas passará a consumir uma biblioteca própria de conteúdo com licença comercial comprovada.

## Decisão principal

Não existe uma quantidade universal de segundos ou minutos que torne seguro usar um trecho de filme sem autorização. O uso de trechos é analisado caso a caso, e um trecho pequeno ainda pode infringir direitos se representar parte relevante da obra.

Para a biblioteca comercial, a regra será: **nenhum conteúdo é publicado sem licença comercial ou prova documentada de domínio público**.

## Produto-alvo

O app comercial mantém:

- player de shadowing com repetição e pausa;
- frases sincronizadas, tradução e ajuste fino de tempo;
- segmentação de frases por IA;
- treino de escuta, gravação e comparação;
- histórico, progresso e recomendações;
- download offline apenas dos arquivos hospedados e licenciados pelo próprio ShadowingAI.

O app comercial remove ou desativa:

- campo para baixar mídia por URL do YouTube;
- extração automática de legendas de terceiros;
- dependência de IP residencial para contornar bloqueios;
- qualquer ferramenta que possa ser interpretada como downloader genérico.

## Arquitetura recomendada

### Aplicativo

- Catálogo editorial de aulas.
- Reprodução online por HLS e opção offline autorizada.
- Autenticação real por Sign in with Apple e/ou e-mail.
- Progresso sincronizado por usuário.
- Assinatura e limites definidos no servidor.
- Nenhuma chave de IA dentro do IPA.

### API e banco

- Postgres/Supabase para usuários, catálogo, progresso, assinaturas e registro de direitos.
- API autenticada para entregar metadados, legendas, segmentos e URLs temporárias.
- Chaves de IA somente no backend.
- Controle de quota por usuário, recurso e período.

### Mídia

- Arquivos originais enviados pelo titular ou obtidos de fonte com licença verificável.
- Object storage compatível com S3, como Cloudflare R2 ou AWS S3.
- CDN para HLS, miniaturas, áudio e WebVTT.
- URLs assinadas com validade curta para reduzir redistribuição.
- Pacote offline criptografado ou protegido pelo armazenamento privado do app.

### Pipeline editorial

1. Cadastrar fonte, titular e licença.
2. Guardar documento ou captura permanente da autorização.
3. Enviar o arquivo original diretamente, sem extração do YouTube.
4. Gerar MP4/HLS, áudio, miniatura e WebVTT.
5. Transcrever e segmentar com IA no servidor.
6. Fazer revisão humana de texto, tradução e sincronização.
7. Publicar somente após aprovação jurídica e editorial.
8. Retirar imediatamente o item se a licença for questionada.

## Modelo mínimo de dados

### Conteúdo

- `content_id`, título, descrição, nível, tema e sotaque;
- duração, idioma, autor/canal e imagem;
- caminhos de HLS, MP4 offline, áudio e WebVTT;
- estado: `draft`, `rights_review`, `processing`, `qa`, `published` ou `withdrawn`.

### Direitos

- `rights_holder` e contato;
- `source_url` e hash SHA-256 do arquivo original;
- `license_type`, `license_url` e texto de atribuição;
- permissão comercial, permissão para adaptações e territórios;
- documentos de cessão, licenciamento e autorização de imagem/voz;
- responsável pela revisão, data de aprovação e eventual expiração.
- territórios autorizados; uma lista vazia impede a publicação.

### Aula

- início e fim de cada frase;
- legenda original e tradução;
- dificuldade, vocabulário e observações;
- versão do modelo de IA e estado da revisão humana.

## Fases de execução

### Fase 0 — isolamento concluído

- branch `commercial-appstore`;
- pasta independente `immersive-shadowing-commercial`;
- snapshot do app funcional sem copiar segredos, IPAs ou biblioteca local baixada.

### Fase 1 — conformidade do aplicativo

- remover o fluxo público de URL do YouTube;
- criar um `ContentProvider` para separar player e origem da mídia;
- substituir dados de vídeo por catálogo local de demonstração licenciado;
- adicionar tela de créditos e licenças por aula;
- revisar privacidade, login e exclusão de conta.

### Fase 2 — backend comercial

- autenticação e banco;
- storage/CDN;
- API de catálogo e progresso;
- registro auditável de direitos;
- URLs assinadas e controle de acesso.

### Fase 3 — estúdio editorial

- painel de ingestão;
- transcodificação;
- geração de legenda e segmentação por IA;
- editor de sincronização;
- aprovação humana e publicação.

### Fase 4 — catálogo piloto

- começar com 20 a 40 aulas curtas;
- priorizar conteúdo próprio, encomendado, CC0 ou CC BY;
- testar compreensão, timing, retenção e custo de CDN;
- documentar atribuição e prova de direitos de cada item.

### Fase 5 — App Store

- novo build identificado como versão comercial;
- screenshots e metadados sem referência a download do YouTube;
- política de privacidade e termos publicados;
- fornecer à Apple documentação de direitos do catálogo, se solicitada;
- conta de demonstração e roteiro de revisão.

## Estratégia de conteúdo recomendada

Ordem de menor risco:

1. Vídeos produzidos pelo próprio ShadowingAI.
2. Criadores contratados, com licença mundial, comercial, sublicenciável e autorização de imagem/voz.
3. Conteúdo CC0.
4. Conteúdo CC BY, com atribuição completa.
5. Conteúdo CC BY-SA, somente após revisão das obrigações de compartilhamento pela mesma licença.
6. Obras em domínio público, verificadas nos territórios em que o app será oferecido.

Evitar filmes e séries comerciais, vídeos com licença padrão do YouTube, conteúdo “sem copyright” sem documento e qualquer licença com cláusula `NC`.

## Custos e escala

- A segmentação por IA acontece uma vez na ingestão, não a cada reprodução.
- O mesmo pacote de aula atende todos os alunos.
- CDN reduz carga do servidor e melhora reprodução global.
- Download offline deve ter qualidade e duração limitadas para controlar tráfego e armazenamento.
- Traduções podem ser geradas uma vez, revisadas e versionadas.

## Critério de pronto para lançamento

- nenhum downloader de terceiros no binário;
- catálogo 100% vinculado a registros de direitos;
- autenticação e segredo de IA no servidor;
- política de privacidade, termos, suporte e exclusão de conta;
- mecanismo de retirada de conteúdo;
- auditoria jurídica de amostra e do contrato-padrão de criadores;
- revisão completa em iPhone e iPad.

## Observação jurídica

Este documento organiza risco de produto e engenharia; não substitui parecer jurídico. Antes de vender o app, um advogado de propriedade intelectual deve revisar a política de catálogo, o contrato com criadores e a distribuição internacional.
