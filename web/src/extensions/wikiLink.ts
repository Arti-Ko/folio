import { Node } from '@tiptap/core'

const WIKI_LINK_PATTERN = /^\[\[([^[\]|\n]+?)(?:\|([^[\]\n]+?))?\]\]/
const SPACE_SEPARATOR = '::'

export interface WikiTarget {
  space: string | null
  title: string
  label: string | null
}

/** Разбирает внутренность `[[Пространство::Заголовок|текст]]`. */
export function parseWikiTarget(inner: string, label?: string): WikiTarget {
  const separator = inner.indexOf(SPACE_SEPARATOR)
  const space = separator >= 0 ? inner.slice(0, separator).trim() : ''
  const title = (separator >= 0 ? inner.slice(separator + SPACE_SEPARATOR.length) : inner).trim()
  return { space: space || null, title, label: label?.trim() || null }
}

/** Ключ ссылки; нативная часть строит его так же (`WikiLink.key`). */
export function wikiLinkKey(space: string | null, title: string): string {
  return `${(space ?? '').trim()}${SPACE_SEPARATOR}${title.trim()}`.replace(/\s+/g, ' ').toLowerCase()
}

export function renderWikiLink(target: WikiTarget): string {
  const prefix = target.space ? `${target.space}${SPACE_SEPARATOR}` : ''
  const suffix = target.label ? `|${target.label}` : ''
  return `[[${prefix}${target.title}${suffix}]]`
}

/** Ссылка на страницу по заголовку, как в Confluence. */
export const WikiLink = Node.create({
  name: 'wikiLink',
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      space: { default: null },
      title: { default: '' },
      label: { default: null },
    }
  },

  parseHTML() {
    return [
      {
        tag: 'a[data-type="wikiLink"]',
        getAttrs: (element) => ({
          space: element.getAttribute('data-space') || null,
          title: element.getAttribute('data-title') ?? '',
          label: element.getAttribute('data-label') || null,
        }),
      },
    ]
  },

  renderHTML({ node }) {
    const { space, title, label } = node.attrs
    return [
      'a',
      {
        'data-type': 'wikiLink',
        'data-space': space ?? '',
        'data-title': title,
        'data-label': label ?? '',
        class: 'wiki-link',
        href: '#',
      },
      label || title,
    ]
  },

  renderText({ node }) {
    return String(node.attrs.label || node.attrs.title)
  },

  addNodeView() {
    return ({ node, editor }) => {
      const anchor = document.createElement('a')
      const apply = (space: string | null, title: string, label: string | null) => {
        anchor.className = 'wiki-link'
        anchor.href = '#'
        anchor.dataset.type = 'wikiLink'
        anchor.dataset.space = space ?? ''
        anchor.dataset.title = title
        anchor.textContent = label || title
        const exists = editor.storage.folioContext.links[wikiLinkKey(space, title)]
        anchor.classList.toggle('is-missing', exists === false)
        anchor.title = exists === false ? `Страница «${title}» не найдена` : title
      }
      apply(node.attrs.space, node.attrs.title, node.attrs.label)
      return {
        dom: anchor,
        update: (next) => {
          if (next.type.name !== 'wikiLink') return false
          apply(next.attrs.space, next.attrs.title, next.attrs.label)
          return true
        },
      }
    }
  },

  markdownTokenizer: {
    name: 'wikiLink',
    level: 'inline',
    start: (src) => src.indexOf('[['),
    tokenize: (src) => {
      const match = WIKI_LINK_PATTERN.exec(src)
      if (!match) return undefined
      const target = parseWikiTarget(match[1], match[2])
      if (!target.title) return undefined
      return { type: 'wikiLink', raw: match[0], ...target }
    },
  },

  parseMarkdown: (token, helpers) =>
    helpers.createNode('wikiLink', { space: token.space ?? null, title: token.title ?? '', label: token.label ?? null }),

  renderMarkdown: (node) =>
    renderWikiLink({
      space: node.attrs?.space ?? null,
      title: String(node.attrs?.title ?? ''),
      label: node.attrs?.label ?? null,
    }),
})
