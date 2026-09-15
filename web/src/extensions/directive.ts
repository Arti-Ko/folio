import type { MarkdownLexerConfiguration, MarkdownToken } from '@tiptap/core'

/** Блок вида `:::имя {key="value"}` … `:::` после разбора. */
export interface DirectiveToken extends MarkdownToken {
  type: string
  raw: string
  name: string
  attributes: Record<string, string>
  tokens: MarkdownToken[]
}

const ATTRIBUTE_PATTERN = /([\w-]+)="((?:[^"\\]|\\.)*)"/g
const FENCE_LINE_SOURCE = '^:::([\\w-]*)(.*)$'

export function parseDirectiveAttributes(source: string): Record<string, string> {
  const entries = [...source.matchAll(ATTRIBUTE_PATTERN)].map(
    (match) => [match[1], match[2].replace(/\\(.)/g, '$1')] as const,
  )
  return Object.fromEntries(entries)
}

/** Возвращает ` {key="value"}` или пустую строку, если значимых атрибутов нет. */
export function serializeDirectiveAttributes(attributes: Record<string, unknown>): string {
  const parts = Object.entries(attributes)
    .filter((entry): entry is [string, string] => typeof entry[1] === 'string' && entry[1].length > 0)
    .map(([key, value]) => `${key}="${value.replace(/[\\"]/g, '\\$&')}"`)
  return parts.length > 0 ? ` {${parts.join(' ')}}` : ''
}

export function findDirectiveStart(src: string, names: readonly string[]): number {
  const match = new RegExp(`^:::(?:${names.join('|')})(?=[ \\t{]|$)`, 'm').exec(src)
  return match ? match.index : -1
}

export function tokenizeDirective(
  src: string,
  names: readonly string[],
  tokenType: string,
  lexer: MarkdownLexerConfiguration,
): DirectiveToken | undefined {
  const opening = new RegExp(`^:::(${names.join('|')})(?:[ \\t]+\\{([^}\\n]*)\\})?[ \\t]*\\n`).exec(src)
  if (!opening) return undefined

  const bodyStart = opening[0].length
  const rest = src.slice(bodyStart)
  const fence = new RegExp(FENCE_LINE_SOURCE, 'gm')
  let depth = 1

  for (let line = fence.exec(rest); line !== null; line = fence.exec(rest)) {
    const [whole, name, tail] = line
    if (name) {
      depth += 1
      continue
    }
    // `:::` с текстом после — не закрывающая строка.
    if (tail.trim() !== '') continue
    depth -= 1
    if (depth > 0) continue

    const body = rest.slice(0, line.index)
    return {
      type: tokenType,
      raw: src.slice(0, bodyStart + line.index + whole.length),
      name: opening[1],
      attributes: parseDirectiveAttributes(opening[2] ?? ''),
      tokens: body.trim() ? blockTokensWithInline(body, lexer) : [],
    }
  }
  return undefined
}

function blockTokensWithInline(body: string, lexer: MarkdownLexerConfiguration): MarkdownToken[] {
  return lexer.blockTokens(body).map((token) =>
    token.text && (!token.tokens || token.tokens.length === 0)
      ? { ...token, tokens: lexer.inlineTokens(token.text) }
      : token,
  )
}
