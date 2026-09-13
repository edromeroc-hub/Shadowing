# Shadowing Bridge Lab

Protótipo isolado para testar a arquitetura de produto em que o frontend fica online, mas a captura/processamento de legendas roda em uma máquina residencial.

Este laboratório não altera o app atual. Ele só cria uma ponte experimental em `bridge-lab/`.

## Arquitetura

```txt
Frontend online / cliente de teste
        ↓
Relay central
        ↑
Local Bridge em uma máquina residencial
        ↓
App Shadowing local em http://localhost:3000
        ↓
YouTube captions
```

Nesta primeira versão o Bridge faz polling HTTP no Relay. Isso é proposital: é mais simples de empacotar como `.exe`/app portátil e funciona bem atrás de roteador/firewall, porque a conexão sai da máquina local.

## Rodar localmente

Terminal 1: app atual já precisa estar rodando:

```bash
npm run dev
```

Terminal 2: subir o Relay:

```bash
cd bridge-lab
npm run relay
```

Terminal 3: subir o Bridge:

```bash
cd bridge-lab
npm run bridge
```

Terminal 4: criar uma tarefa de teste:

```bash
cd bridge-lab
npm run test -- VIDEO_ID_DO_YOUTUBE
```

Exemplo:

```bash
npm run test -- S8nFNG6GFBU
```

## Como isso vira produto

1. Hospedar o Relay em Vercel/Render/Fly/Cloud Run.
2. Frontend online cria tarefas no Relay.
3. Bridge instalado no Mac/notebook/mini PC fica conectado ao Relay.
4. Bridge processa legendas localmente e devolve o resultado.
5. Frontend consulta o resultado e monta a sessão de shadowing.

## O que falta antes de produto real

- Autenticação real por usuário.
- Registro de dispositivo com código curto.
- Persistência em banco, porque este Relay é em memória.
- Criptografia/rotação dos tokens.
- Empacotamento do Bridge como `.exe`/`.app`.
- Fila por usuário e limite de uso.
- Substituir polling por WebSocket se precisarmos de menor latência.

## Decisão técnica

O ponto crítico é manter o acesso ao YouTube saindo da máquina residencial. O Relay nunca baixa legenda; ele só coordena pedidos e respostas.
