# Kimi Code + NVIDIA GLM-5.3 — Kit de Configuração

Kit para fazer o **Kimi Code** (CLI da Moonshot, v2.0.x) funcionar com o modelo
**`z-ai/glm-5.3`** hospedado na NVIDIA (`https://integrate.api.nvidia.com/v1`),
resolvendo um erro de incompatibilidade entre os dois (detalhes na Seção 2).

---

## Índice

1. [O que este kit faz](#1-o-que-este-kit-faz)
2. [Por que é necessário (o problema)](#2-por-que-é-necessário-o-problema)
3. [Como funciona por dentro](#3-como-funciona-por-dentro)
4. [O que você precisa antes de começar](#4-o-que-você-precisa-antes-de-começar)
5. [Instalação automática (passo a passo)](#5-instalação-automática-passo-a-passo)
6. [Instalação manual (passo a passo)](#6-instalação-manual-passo-a-passo)
7. [Testando se funcionou](#7-testando-se-funcionou)
8. [Trocando a chave da NVIDIA](#8-trocando-a-chave-da-nvidia)
9. [Solução de problemas](#9-solução-de-problemas)
10. [Remoção completa](#10-remoção-completa)
11. [Notas de segurança](#11-notas-de-segurança)
12. [Arquivos do kit](#12-arquivos-do-kit)

---

## 1. O que este kit faz

Este kit instala um **mini-proxy local** (shim) entre o Kimi Code e o endpoint
da NVIDIA. Na prática:

- O modelo `z-ai/glm-5.3` aparece e funciona no Kimi Code como qualquer outro
  (thinking em `low/high/max`, uso de ferramentas, streaming).
- O Kimi passa a usar o modelo sem encontrar o erro `400 status code (no body)`.
- O shim inicia junto com o Windows e exige manutenção zero no dia a dia.
- A troca de chave da NVIDIA fica centralizada em um único arquivo
  (`~/.kimi-code/config.toml`) — o shim não guarda nenhuma chave.

Ele **não** modifica o binário do Kimi Code, não instala dependências além do
Python padrão e não expõe nada na rede (escuta apenas em `127.0.0.1`).

## 2. Por que é necessário (o problema)

O Kimi Code envia **sempre** o parâmetro `prompt_cache_key` (com o id da sessão)
em requisições para qualquer provider do tipo `openai` — comportamento
introduzido na versão 0.29.0 do CLI ("Send the session prompt cache key to
OpenAI and OpenAI Responses providers").

O endpoint da NVIDIA (NIM) **rejeita parâmetros desconhecidos**:

```
HTTP 400  {"message":"Validation: Unsupported parameter(s): `prompt_cache_key`", ...}
```

Por isso o Kimi mostra `Error: [provider.api_error] 400 status code (no body)`
mesmo com o `config.toml` válido (`kimi doctor` OK). Não é a chave, o modelo, o
`max_tokens`, os tools nem o thinking: o mesmo payload **sem** esse campo
retorna 200; **com** o campo retorna 400.

Não existe opção de config, env var ou plugin para desativar o campo
(verificado na documentação oficial e no código-fonte — `profileService.ts`
fixa `cacheKey = sessionId` e `encodeOpenAICacheKey()` o injeta sempre).

## 3. Como funciona por dentro

```
kimi.exe ──> http://127.0.0.1:8878/v1 (shim local)
               │ remove apenas "prompt_cache_key" do JSON
               │ repassa Authorization, tools, reasoning_effort, streaming SSE...
               └──> https://integrate.api.nvidia.com/v1/chat/completions
```

- Só escuta em `127.0.0.1` (nada exposto na rede).
- Não guarda a chave da NVIDIA (apenas repassa o header `Authorization`).
- Não altera mais nada na requisição/resposta — o streaming e o uso de
  ferramentas funcionam normalmente.
- Se já houver outra instância na porta, fecha silenciosamente (idempotente).

## 4. O que você precisa antes de começar

| Requisito | Como verificar |
| --- | --- |
| Windows + **Kimi Code** 2.0.x | `kimi --version` |
| **Python 3.10+** (com `pythonw.exe`) | `python --version` |
| Chave da NVIDIA (`nvapi-...`) | Gere/revogue em <https://build.nvidia.com> |
| PowerShell | Já vem com o Windows |

A chave da NVIDIA **não acompanha este kit** — cada usuário gera a sua no
portal da NVIDIA (conta gratuita). O modelo usado é o `z-ai/glm-5.3`.

## 5. Instalação automática (passo a passo)

**Passo 1 — Abra o PowerShell nesta pasta.** Clique com o botão direito na
pasta enquanto pressiona Shift e escolha "Abrir janela do PowerShell aqui", ou
abra o PowerShell e navegue até a pasta do kit. Isso é necessário porque o
script usa o caminho da pasta atual (`$PSScriptRoot`) para localizar os arquivos
do kit.

**Passo 2 — Execute o instalador:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

O parâmetro `-ExecutionPolicy Bypass` permite rodar o script sem mudar a
política global do Windows (que por padrão bloqueia scripts baixados da
internet). O script faz o seguinte, nesta ordem:

1. Recria `~\.kimi-code\workspaces.json` (libera handles presos de antivírus
   que causam o erro `EPERM` ao abrir o Kimi)
2. Copia `nvidia_shim.py` para `~\.kimi-code\proxy\`
3. Copia `kimi-nvidia-shim.cmd` para a pasta **Startup** (auto-início)
4. Verifica o `~\.kimi-code/config.toml`: se ainda não houver provider
   `nvidia`, adiciona o bloco do `config-snippet.toml` (você preenche o
   `api_key`)
5. Inicia o shim (se ainda não estiver rodando) e faz um health-check

**Passo 3 — Confira a saída.** Se tudo funcionou, você verá na ordem:

```
[ok] workspaces.json recriado (libera handles presos que causam EPERM no fs.watch)
[ok] shim copiado: C:\Users\<voce>\.kimi-code\proxy\nvidia_shim.py
[ok] auto-inicio:   ...\Startup\kimi-nvidia-shim.cmd
[ok] config.toml criado com o bloco nvidia   (ou "ja tem o provider nvidia")
[ok] shim respondendo em http://127.0.0.1:8878
```

*Erro comum:* se aparecer `[erro] pythonw.exe nao encontrado`, o Python não
está instalado no caminho padrão nem no PATH — instale em
<https://www.python.org/downloads/> (marque "Add Python to PATH") e rode o
instalador de novo.

**Passo 4 — Preencha sua chave.** Abra `C:\Users\<voce>\.kimi-code\config.toml`
no Bloco de Notas e troque a linha do placeholder:

```toml
[providers.nvidia]
api_key = "COLOQUE_SUA_CHAVE_NVIDIA_AQUI"   # troque pela sua chave nvapi-...
```

**Passo 5 — Valide** conforme a [Seção 7](#7-testando-se-funcionou).

## 6. Instalação manual (passo a passo)

**Passo 1 —** Copie `nvidia_shim.py` para `C:\Users\<voce>\.kimi-code\proxy\`
(crie a pasta se não existir). Esse é o proxy em si; sem ele nessa pasta, o
atalho de auto-início não encontra o que executar.

**Passo 2 —** Copie `kimi-nvidia-shim.cmd` para a pasta de Startup do Windows.
Cole `shell:startup` na barra de endereços do Explorer e pressione Enter — o
Explorer abre a pasta correta. Sem esse atalho, o shim só roda quando você o
iniciar manualmente.

**Passo 3 —** Adicione ao final de `C:\Users\<voce>\.kimi-code\config.toml`
o conteúdo de `config-snippet.toml`, preenchendo o `api_key` com sua chave
`nvapi-...`. Opcional: `default_model = "nvidia/glm53"` no topo do arquivo.

**Passo 4 —** Dê dois cliques em `kimi-nvidia-shim.cmd` (ou reinicie o
Windows) para iniciar o shim.

**Passo 5 —** Valide conforme a [Seção 7](#7-testando-se-funcionou).

## 7. Testando se funcionou

Rode os três comandos abaixo, nesta ordem:

```powershell
kimi doctor                                  # config válido, sem erros
kimi provider list                           # deve listar: nvidia  type=openai  models=1
kimi --model nvidia/glm53 -p "Responda somente OK"   # deve responder "OK"
```

Se o terceiro comando respondeu `OK`, o kit está funcionando de ponta a ponta.
No TUI (`kimi`), o modelo aparece como **GLM-5.3 NVIDIA**. O thinking funciona
em `low / high / max` e pode ser desligado (`off_effort = "none"` — a NVIDIA
aceita `none/minimal/low/medium/high/xhigh/max`).

Verificação rápida do shim (opção):

```powershell
Invoke-WebRequest http://127.0.0.1:8878/health -UseBasicParsing   # StatusCode 200
```

## 8. Trocando a chave da NVIDIA

**Passo 1 —** Gere/revogue chaves em <https://build.nvidia.com>.

**Passo 2 —** Edite **apenas** o `api_key` em `~\.kimi-code\config.toml` (o
shim não guarda chave).

**Passo 3 —** Pronto: nada mais precisa mudar, nem reiniciar o shim.

## 9. Solução de problemas

| Sintoma | Causa | Solução |
| --- | --- | --- |
| `provider.api_error` com *connection refused* / *fetch failed* | Shim não está rodando | Rode `kimi-nvidia-shim.cmd` (ou `install.ps1`) e teste `http://127.0.0.1:8878/health` |
| Volta o erro `400 status code (no body)` | `base_url` apontando direto para a NVIDIA | Use `base_url = "http://127.0.0.1:8878/v1"` no provider nvidia |
| `401` / `Unauthorized` | Chave inválida/revogada | Troque o `api_key` no `config.toml` (o shim repassa o header como está) |
| Shim não sobe (porta 8878 ocupada) | Outro programa usando a porta | Edite `LISTEN_PORT` em `nvidia_shim.py` **e** o `base_url` no config |
| Modelos não aparecem no `/model` | Bloco `[models."nvidia/glm53"]` ausente | Confira o `config-snippet.toml` e rode `kimi doctor` |
| `EPERM: operation not permitted, watch '...\workspaces.json'` na abertura do Kimi | Antivírus/Windows Defender ou indexador segurando lock no arquivo (não fatal) | Recrie o arquivo (o `install.ps1` já faz isso) ou rode como Admin: `Add-MpPreference -ExclusionPath "$env:USERPROFILE\.kimi-code"` |
| Kimi atualizou e parou de enviar `prompt_cache_key` | Bug corrigido upstream | Pode remover o kit e voltar o `base_url` direto (Seção 10) |

## 10. Remoção completa

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Isso remove o auto-início, encerra o processo do shim e apaga
`~\.kimi-code\proxy\nvidia_shim.py`. O `uninstall.ps1` **não** mexe no
`config.toml` — para voltar a apontar direto para a NVIDIA:

```toml
[providers.nvidia]
type = "openai"
base_url = "https://integrate.api.nvidia.com/v1"   # porem: o erro 400 volta (Seção 2)
api_key = "nvapi-..."
```

Até a Moonshot corrigir o envio do `prompt_cache_key` (ou a NVIDIA passar a
aceitar o parâmetro), o shim é necessário. Vale reportar/acompanhar em
<https://github.com/MoonshotAI/kimi-code/issues>.

## 11. Notas de segurança

- Nenhuma chave acompanha este kit; cada usuário usa a sua (`config.toml`).
- Uma chave que foi exposta em conversas ou sites públicos deve ser considerada
  **vazada**: revogue e gere outra no portal da NVIDIA.
- O shim escuta apenas em `127.0.0.1`, não registra requisições em disco e
  remove um único campo do JSON. Todo o tráfego vai somente para
  `integrate.api.nvidia.com` (TLS).

## 12. Arquivos do kit

| Arquivo | Função |
| --- | --- |
| `README.md` | Este guia |
| `nvidia_shim.py` | O shim (proxy local, porta 8878) |
| `kimi-nvidia-shim.cmd` | Atalho de auto-início com o Windows (vai para a pasta Startup) |
| `config-snippet.toml` | Bloco a adicionar ao `~/.kimi-code/config.toml` |
| `install.ps1` | Instalação automática (copia arquivos, ajusta config, inicia o shim) |
| `uninstall.ps1` | Remove o shim e o auto-início (não mexe no config.toml) |

---

## Referências técnicas

- Código do Kimi (MIT): <https://github.com/MoonshotAI/kimi-code>
  - `packages/agent-core-v2/src/agent/profile/profileService.ts` → `cacheKey: this.sessionContext.sessionId` (sempre)
  - `packages/agent-core-v2/src/human/llm/requester/bases/openai/format.ts` → `encodeOpenAICacheKey()` → `{ prompt_cache_key: key }`
  - Changelog v0.29.0: "Send the session prompt cache key to OpenAI and OpenAI Responses providers"
- Erro da NVIDIA: `{"message":"Validation: Unsupported parameter(s): \`prompt_cache_key\`","type":"Bad Request","code":400}`
- Config oficial do Kimi: <https://moonshotai.github.io/kimi-code/en/configuration/config-files/>
- Chaves NVIDIA: <https://build.nvidia.com>
