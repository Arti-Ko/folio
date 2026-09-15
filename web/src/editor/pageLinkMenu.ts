import { Extension } from '@tiptap/core'
import { PluginKey } from '@tiptap/pm/state'
import { Suggestion } from '@tiptap/suggestion'
import type { PageSummary } from '../extensions/folioContext'
import { suggestionRenderer } from './menu'

const RESULT_LIMIT = 30

function rank(page: PageSummary, currentSpace: string, needle: string): number {
  const spacePenalty = page.space === currentSpace ? 0 : 2
  const prefixPenalty = needle && page.title.toLowerCase().startsWith(needle) ? 0 : 1
  return spacePenalty + prefixPenalty
}

/** Страницы для подсказки: сначала своё пространство и совпадения с начала заголовка. */
export function filterPages(pages: PageSummary[], currentSpace: string, query: string): PageSummary[] {
  const needle = query.trim().toLowerCase()
  const matches = needle ? pages.filter((page) => page.title.toLowerCase().includes(needle)) : pages
  return [...matches]
    .sort(
      (a, b) =>
        rank(a, currentSpace, needle) - rank(b, currentSpace, needle) || a.title.localeCompare(b.title, 'ru'),
    )
    .slice(0, RESULT_LIMIT)
}

/** Подсказка страниц после «[[». */
export const PageLinkSuggestion = Extension.create({
  name: 'pageLinkSuggestion',

  addProseMirrorPlugins() {
    const { editor } = this
    return [
      Suggestion<PageSummary, PageSummary>({
        editor,
        pluginKey: new PluginKey('pageLinkSuggestion'),
        char: '[[',
        allowSpaces: true,
        allowedPrefixes: null,
        items: ({ query }) => {
          const context = editor.storage.folioContext
          return filterPages(context.pages, context.spaceName, query)
        },
        allow: ({ editor: current }) => current.isEditable && !current.isActive('codeBlock'),
        command: ({ editor: current, range, props }) => {
          const space = props.space === current.storage.folioContext.spaceName ? null : props.space
          current
            .chain()
            .focus()
            .deleteRange(range)
            .insertContent([
              { type: 'wikiLink', attrs: { space, title: props.title, label: null } },
              { type: 'text', text: ' ' },
            ])
            .run()
        },
        render: suggestionRenderer<PageSummary>(
          (page) => ({ title: page.title, subtitle: page.space }),
          'Страница не найдена',
        ),
      }),
    ]
  },
})
