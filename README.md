# Free DeepSeek 4.1 Flash (1017 line) inside opencode and any harness

Use the free DeepSeek V4.1 Flash from [Ebony-Vinyl/dsh-our-free-model](https://github.com/Ebony-Vinyl/dsh-our-free-model) in opencode, T3 Code, Claude Code, Codex, or anything that speaks OpenAI or Anthropic — through one local port.

```
opencode / T3 / Claude Code / Codex / curl
        |
        v
http://127.0.0.1:18899/v1            <- local forward port, key from the plugin
        |
        v
dsh-our-free-model  (DSH plugin, free lane = OpenCode Zen free tier)
        |
        v
deepseek-v4.1-flash-free
```

## Is it really free

Yes, and this repo does not re-host or proxy anything of its own. Facts:

- The model id is `deepseek-v4.1-flash-free`. It is served by the DSH plugin's **free lane**, which the plugin's own README describes as OpenCode's Zen gateway (`https://opencode.ai`), dialled directly, no account, no sign-up, no API key.
- Nothing in this path touches your DeepSeek API key or your DeepSeek balance. Free-lane requests go to the Zen free tier; DeepSeek billing only happens if you point a harness at `deepseek/*` or `explabs/*` providers instead.
- When the upstream free tier is busy you get **HTTP 429 rate_limit_error**, not a charge. That is the whole cost model: rate limited, never billed.
- `1017` is the snapshot suffix of the paid Experimental Labs route (`explabs/deepseek-v4.1-flash-1017`). The free id carries no snapshot suffix. Same model family, free tier.
- Free is not the same as always available: the free lane is geo- and load-sensitive. `scripts/check-port.mjs <model>` tells you the truth in one call. Kilo free-pool ids (also free, from Kilo AI's public gateway) are in the same roster as a fallback.

## Requirements

- Windows (the installer is PowerShell). The manual steps in [docs/HARNESSES.md](docs/HARNESSES.md) work anywhere.
- DSH Desktop with the `dsh-our-free-model` plugin installed in a profile. The installer verifies this and prints the official install steps if it is missing. Do **not** install the plugin from npm — the repo says that package is a third-party repackaging.
- opencode (any 2.x) for the automated provider wiring.

## Install

```powershell
git clone https://github.com/vit-cerny/free-deepseek-1017-inside-opencode
cd free-deepseek-1017-inside-opencode
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

What it does, in order:

1. Verifies the plugin is installed in `~/.dsh/profiles/<profile>/node_modules/dsh-our-free-model`.
2. Turns on the plugin's **Local forward** at `127.0.0.1:18899` in `~/.dsh/our-free-model/settings.json` (backup kept).
3. Adds a `dsh-free` provider to `~/.config/opencode/opencode.jsonc` — the 5 core free ids by default, the full free roster with `-All` (backup kept).
4. Reads the plugin's minted forward key and puts it where it is needed: inline in the `dsh-free` provider settings (so opencode resolves it without depending on the process environment) and as the user environment variable `DSH_OFM_API_KEY` (so Codex and shell tools can use it). The key is never committed to this repo and never printed by the script.
5. Pins the free ids to the top of T3's model favourites if T3 is installed (backup kept).

Then: **restart opencode** (and T3 if it is running). The picker shows a group `FREE - DSH Our Free Model` with entries named `FREE - DeepSeek V4.1 Flash`, `FREE - GLM 5.3 Flash`, `FREE - Kilo Auto Free`, and so on.

If step 4 says the key is missing, start DSH Desktop once (the plugin mints the key on boot) and re-run the installer.

## Check it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Check
node .\scripts\check-port.mjs deepseek-v4.1-flash-free
```

`-Check` prints plugin presence, forward state, port, key, provider block, and the live roster size. The node check prints the roster count and, given a model id, one real completion with its HTTP status.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

Removes the `dsh-free` provider block, the `DSH_OFM_API_KEY` user variable, and the T3 favourite pins. Restores nothing else and leaves the plugin alone — add `-Uninstall -DisableForward` to switch the plugin's local port off too. Backups of every file it edited stay next to the original with a `.bak-ofm-*` suffix.

## Use it in other harnesses

Short version — base URL `http://127.0.0.1:18899/v1`, key = `forwardKey` from `~/.dsh/our-free-model/settings.json`, model `deepseek-v4.1-flash-free`.

```bash
export ANTHROPIC_BASE_URL=http://127.0.0.1:18899
export ANTHROPIC_AUTH_TOKEN=<forwardKey>
export ANTHROPIC_MODEL=deepseek-v4.1-flash-free
```

Full recipes for Claude Code, Codex CLI, the OpenAI SDK, the Anthropic SDK and raw curl: [docs/HARNESSES.md](docs/HARNESSES.md). All of them come from the plugin's own "Connect a client" generator, not from guesswork.

## Optional: DeepSeek web search

The free models have no web search. If you want DeepSeek's own search and page fetch as agent tools, install the optional plugin — it needs **your own** DeepSeek API key (search is a paid DeepSeek platform feature, unrelated to the free model lane):

```powershell
Copy-Item .\plugins\deepseek-search.ts "$HOME\.config\opencode\plugins\deepseek-search.ts"
"<your DeepSeek API key>" | Set-Content "$HOME\.config\opencode\deepseek-key.txt"
```

Restart opencode and you get `deepseek.search` and `deepseek.fetch`. It reads `DEEPSEEK_API_KEY` first and the key file second. Uninstall = delete those two files. Details: [docs/HARNESSES.md](docs/HARNESSES.md#deepseek-web-search).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Model missing from the picker | opencode started before the provider/env existed | restart opencode; `opencode models \| findstr dsh-free` shows the truth |
| `opencode models` empty right after `opencode reload` | the service rebuilds its model snapshot | wait a few seconds and ask again |
| `401 missing or invalid API key` | `DSH_OFM_API_KEY` not in the process environment | restart the app that makes the request, or inline `"apiKey"` in the provider settings |
| `503 the forward listener is switched off` | plugin's Local forward is off | `install.ps1` again, or toggle it in DSH > Settings > Our Free Model |
| `429 RATE_LIMIT` | upstream free tier is busy from your IP | retry later, or use a Kilo id from the same roster |
| connection refused on 18899 | DSH Desktop is not running | the port lives only while DSH runs |
| port changed from 18899 | another process holds 18899, plugin walked to the next port | check the plugin settings page; re-run the installer to rewrite the base URL |

## Credits and licence

- Free model access, the plugin, and the local gateway: [Ebony-Vinyl/dsh-our-free-model](https://github.com/Ebony-Vinyl/dsh-our-free-model) (MIT). This repo is only wiring and documentation around it.
- Free lane upstream: OpenCode Zen. Kilo free pool: Kilo AI public gateway.
- This repo: MIT.
