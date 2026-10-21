# Use the free models in any harness

Everything below points at the same local endpoint. No adapter, no extra service, no account.

| Value | Where it comes from |
|---|---|
| Base URL | `http://127.0.0.1:18899/v1` (or whatever port the plugin reports) |
| API key | `forwardKey` in `~/.dsh/our-free-model/settings.json` |
| Model | `deepseek-v4.1-flash-free` |
| Anthropic surface | same host, `/v1/messages` (no `/v1` suffix on `ANTHROPIC_BASE_URL`) |

```powershell
# print the values on Windows
$s = Get-Content "$HOME\.dsh\our-free-model\settings.json" -Raw | ConvertFrom-Json
"base: http://127.0.0.1:$($s.forward.port)/v1"
"key : $($s.forwardKey)"
```

The snippets are the plugin's own "Connect a client" recipes, generated from the port it actually bound.

## opencode

Automated by `install.ps1`. Manual: paste [../config/opencode-provider.jsonc](../config/opencode-provider.jsonc) as the first entry of the top-level `providers` object in `~/.config/opencode/opencode.jsonc`, set `DSH_OFM_API_KEY`, restart opencode.

Verify from a shell without restarting anything:

```powershell
opencode models | Select-String dsh-free/
```

## T3 Code

T3 reads its model list through the opencode driver, so every `dsh-free/*` id shows up there automatically after opencode has the provider. `install.ps1` also pins the free ids to the top of the T3 model favourites (`~/.t3/userdata/client-settings.json`). Restart T3 to reload.

## Claude Code

```bash
export ANTHROPIC_BASE_URL=http://127.0.0.1:18899
export ANTHROPIC_AUTH_TOKEN=<forwardKey>
export ANTHROPIC_MODEL=deepseek-v4.1-flash-free
# the gateway speaks /v1/messages natively - no translation shim needed
```

PowerShell:

```powershell
$env:ANTHROPIC_BASE_URL = 'http://127.0.0.1:18899'
$env:ANTHROPIC_AUTH_TOKEN = $s.forwardKey
$env:ANTHROPIC_MODEL = 'deepseek-v4.1-flash-free'
```

## Codex CLI

`~/.codex/config.toml`:

```toml
model_provider = "ofm"
model = "deepseek-v4.1-flash-free"

[model_providers.ofm]
name = "Our Free Model"
base_url = "http://127.0.0.1:18899/v1"
wire_api = "responses"
env_key = "DSH_OFM_API_KEY"
```

`env_key` names the environment variable that holds the key, so the same `DSH_OFM_API_KEY` used by opencode works here too.

## OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:18899/v1", api_key="<forwardKey>")
print(client.chat.completions.create(
    model="deepseek-v4.1-flash-free",
    messages=[{"role": "user", "content": "hi"}],
).choices[0].message.content)
```

## Anthropic SDK

```python
from anthropic import Anthropic

client = Anthropic(base_url="http://127.0.0.1:18899", api_key="<forwardKey>")
print(client.messages.create(
    model="deepseek-v4.1-flash-free",
    max_tokens=1024,
    messages=[{"role": "user", "content": "hi"}],
).content[0].text)
```

## curl

```bash
curl http://127.0.0.1:18899/v1/chat/completions \
  -H "authorization: Bearer <forwardKey>" \
  -H "content-type: application/json" \
  -d '{"model":"deepseek-v4.1-flash-free","messages":[{"role":"user","content":"hi"}]}'

# the Anthropic surface answers on the same port
curl http://127.0.0.1:18899/v1/messages \
  -H "x-api-key: <forwardKey>" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"deepseek-v4.1-flash-free","max_tokens":64,"messages":[{"role":"user","content":"hi"}]}'
```

## Any other harness

Point it at an OpenAI-compatible endpoint: base URL `http://127.0.0.1:18899/v1`, bearer key `forwardKey`, model id as served by `GET /v1/models`. Thinking effort is real on this port: the plugin accepts `reasoning_effort` in its own ladder (`disabled/low/medium/high` or `light/balanced/deep`, depending on the model) and enforces it as an output budget.

## DeepSeek web search

The free models have no browsing. DeepSeek's search/fetch API is a separate, paid platform feature that needs your own key.

```powershell
Copy-Item .\plugins\deepseek-search.ts "$HOME\.config\opencode\plugins\deepseek-search.ts"
"<your DeepSeek API key>" | Set-Content "$HOME\.config\opencode\deepseek-key.txt"
```

Then restart opencode. Two tools appear in the `deepseek` namespace: `deepseek.search` (title, URL, snippet, optional full page content) and `deepseek.fetch` (one page as markdown). The plugin reads `DEEPSEEK_API_KEY` first and the key file second.

Remove it by deleting the two files. Nothing else was touched.

## Notes

- The port exists only while DSH Desktop runs. Everything above fails with a connection error otherwise; that is the intended off switch.
- Port 18899 can move if another process holds it. If the plugin says it is listening on 18900, re-run `install.ps1` to rewrite the base URL.
- `combo:recommended-free` is a virtual model: a fallback chain over free ids, so a rate-limited link is skipped instead of failing the turn.
