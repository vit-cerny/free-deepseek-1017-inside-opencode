// Optional DeepSeek web search and page fetch as opencode tools.
//
// Copy to ~/.config/opencode/plugins/deepseek-search.ts
//
// Key (this is a PAID DeepSeek platform feature, unrelated to the free model lane):
//   1. set DEEPSEEK_API_KEY, or
//   2. write the key on one line in ~/.config/opencode/deepseek-key.txt
//
// Why a file fallback exists: a long-lived desktop app keeps whatever environment
// it was started with, so a key exported after launch never reaches the running
// service. The file is read on every call; the environment is the first choice.
import { Plugin } from "@opencode/plugin"
import { existsSync, readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const BASE = "https://api.deepseek.com"
const KEY_FILE = join(homedir(), ".config", "opencode", "deepseek-key.txt")

function apiKey(): string {
  const fromEnv = process.env.DEEPSEEK_API_KEY
  if (fromEnv && fromEnv.trim() !== "") return fromEnv.trim()
  if (existsSync(KEY_FILE)) return readFileSync(KEY_FILE, "utf8").trim()
  return ""
}

type SearchResult = {
  title?: string
  url?: string
  snippet?: string
  summary?: string
  content?: string
  rerank_score?: number
}

export default Plugin.define({
  id: "deepseek-search",
  async setup(ctx) {
    await ctx.tool.transform((editor) => {
      editor.namespace({
        name: "deepseek",
        description: "DeepSeek web search and page fetch",
      })

      editor.add({
        name: "search",
        description:
          "Search the live web with DeepSeek's in-house engine. Returns titles, URLs, snippets and optional page content. Supports operators: site:, -site:, \"exact phrase\", lang:, after:, before:.",
        input: {
          type: "object",
          properties: {
            query: { type: "string", description: "Search query, 1-128 characters" },
            count: { type: "integer", description: "Results to return, 1-50 (default 10)" },
            need_content: {
              type: "boolean",
              description: "Also return full page content as markdown (slower, larger)",
            },
            ori_question: {
              type: "string",
              description: "The user's original question, to improve query understanding",
            },
          },
          required: ["query"],
          additionalProperties: false,
        },
        options: { namespace: "deepseek", codemode: true },
        execute: async (input, context) => {
          const key = apiKey()
          if (key === "") return { content: "DeepSeek key missing: set DEEPSEEK_API_KEY or write ~/.config/opencode/deepseek-key.txt" }
          const body: Record<string, unknown> = { query: input.query }
          if (typeof input.count === "number") body.count = input.count
          if (input.need_content === true) body.need_content = true
          if (typeof input.ori_question === "string") body.ori_question = input.ori_question

          const response = await fetch(`${BASE}/v1/tools/search`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${key}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(body),
            signal: context.signal,
          })

          if (!response.ok) {
            const text = await response.text()
            return { content: `DeepSeek search failed (HTTP ${response.status}): ${text.slice(0, 500)}` }
          }

          const data = (await response.json()) as { results?: SearchResult[] }
          const results = data.results ?? []
          if (results.length === 0) return { content: "No results." }

          const lines = results.map((r, i) => {
            const head = `${i + 1}. ${r.title ?? "(untitled)"}\n   ${r.url ?? ""}`
            const summary = r.summary || r.snippet || ""
            const extra = input.need_content === true && r.content ? `\n   ---\n   ${r.content}` : ""
            return summary ? `${head}\n   ${summary}${extra}` : `${head}${extra}`
          })
          return { content: lines.join("\n\n") }
        },
      })

      editor.add({
        name: "fetch",
        description: "Fetch one web page through DeepSeek and return its content as markdown.",
        input: {
          type: "object",
          properties: {
            url: { type: "string", description: "Absolute http(s) URL to fetch" },
          },
          required: ["url"],
          additionalProperties: false,
        },
        options: { namespace: "deepseek", codemode: true },
        execute: async (input, context) => {
          const key = apiKey()
          if (key === "") return { content: "DeepSeek key missing: set DEEPSEEK_API_KEY or write ~/.config/opencode/deepseek-key.txt" }
          const response = await fetch(`${BASE}/v1/tools/fetch`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${key}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ url: input.url }),
            signal: context.signal,
          })

          if (!response.ok) {
            const text = await response.text()
            return { content: `DeepSeek fetch failed (HTTP ${response.status}): ${text.slice(0, 500)}` }
          }

          const data = (await response.json()) as { content?: string; title?: string }
          const title = data.title ? `# ${data.title}\n\n` : ""
          return { content: title + (data.content ?? "(empty page)") }
        },
      })
    })
  },
})
