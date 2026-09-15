import { Editor, type JSONContent } from '@tiptap/core'
import { afterEach, describe, expect, it } from 'vitest'
import { runCommand } from '../src/editor/commands'
import { filterPages } from '../src/editor/pageLinkMenu'
import { normalizeHref } from '../src/editor/popover'
import { filterSlashItems } from '../src/editor/slashMenu'
import { createExtensions } from '../src/extensions'

const editors: Editor[] = []

function editable(markdown = '', isEditable = true): Editor {
  const editor = new Editor({ extensions: createExtensions(), content: markdown, contentType: 'markdown', editable: isEditable })
  editors.push(editor)
  return editor
}

function markdownOf(editor: Editor): string {
  return editor.getMarkdown().trim()
}

afterEach(() => {
  editors.splice(0).forEach((editor) => editor.destroy())
})

describe('команды редактора', () => {
  it('вставляет панель, и она переживает сохранение', () => {
    const editor = editable('Текст')
    editor.commands.focus('end')
    editor.commands.enter()
    expect(runCommand(editor, 'insertPanel', { type: 'warning' })).toBe(true)
    const markdown = markdownOf(editor)
    expect(markdown).toContain(':::warning')
    expect(markdownOf(editable(markdown))).toBe(markdown)
  })

  it('оборачивает выделенный текст в панель', () => {
    const editor = editable('Важный абзац')
    editor.commands.selectAll()
    runCommand(editor, 'insertPanel', { type: 'note' })
    expect(markdownOf(editor)).toBe(':::note\n\nВажный абзац\n\n:::')
  })

  it('вставляет таблицу со строкой заголовка', () => {
    const editor = editable('')
    runCommand(editor, 'insertTable')
    const markdown = markdownOf(editor)
    expect(markdown.split('\n')).toHaveLength(4)
    expect(markdown.split('\n')[1]).toMatch(/^\| -+ \| -+ \| -+ \|$/)
  })

  it('вставляет статус и ссылку на страницу', () => {
    const editor = editable('Состояние')
    editor.commands.focus('end')
    runCommand(editor, 'insertStatus', { label: 'В работе', color: 'blue', silent: true })
    runCommand(editor, 'insertPageLink', { title: 'Требования' })
    expect(markdownOf(editor)).toBe('Состояние[status color="blue"]В работе[/status][[Требования]]')
  })

  it('превращает набранную [[ссылку]] в ссылку на страницу', () => {
    const editor = editable('См. [[Идеи]')
    editor.commands.focus('end')
    const { view } = editor
    const position = view.state.selection.from
    const handled = view.someProp('handleTextInput', (handler) =>
      handler(view, position, position, ']', () => view.state.tr.insertText(']', position, position)),
    )
    expect(handled).toBe(true)
    const paragraph = editor.getJSON().content?.[0] as JSONContent
    expect(paragraph.content?.some((node) => node.type === 'wikiLink')).toBe(true)
    expect(markdownOf(editor)).toBe('См. [[Идеи]]')
  })

  it('переносит блок вниз', () => {
    const editor = editable('Первый\n\nВторой')
    editor.commands.setTextSelection(2)
    expect(runCommand(editor, 'moveBlockDown')).toBe(true)
    expect(markdownOf(editor)).toBe('Второй\n\nПервый')
  })

  it('в режиме чтения команды не выполняются', () => {
    const editor = editable('Текст', false)
    expect(runCommand(editor, 'bold')).toBe(false)
  })
})

describe('документ целиком', () => {
  const source = [
    '# Заголовок',
    '',
    '[toc]',
    '',
    ':::info {title="Контекст"}',
    '',
    'Текст с **жирным**, *курсивом*, ~~зачёркнутым~~ и `кодом`.',
    '',
    ':::',
    '',
    '## Таблица',
    '',
    '| ID | Требование | Статус |',
    '| --- | --- | --- |',
    '| FR-1 | Вход | [status color="green"]Готово[/status] |',
    '',
    '- [x] Сделано',
    '- [ ] Не сделано',
    '',
    '1. Первый',
    '2. Второй',
    '',
    '> Цитата',
    '',
    ':::expand {title="Расшифровка"}',
    '',
    'Спикер 1: привет',
    '',
    ':::',
    '',
    '```sql',
    'select 1;',
    '```',
    '',
    '---',
    '',
    'Ссылки: [[Требования]], [[Личное::Идеи|идеи]], [сайт](https://example.com), ![Схема](схема.png)',
    '',
    '[children]',
  ].join('\n')

  it('после первого сохранения больше не меняется', () => {
    const once = markdownOf(editable(source))
    expect(markdownOf(editable(once))).toBe(once)
    for (const fragment of [
      ':::info {title="Контекст"}',
      '[toc]',
      '[children]',
      '[[Личное::Идеи|идеи]]',
      '[status color="green"]Готово[/status]',
      '- [x] Сделано',
      ':::expand {title="Расшифровка"}',
      '![Схема](схема.png)',
    ]) {
      expect(once).toContain(fragment)
    }
  })
})

describe('меню и адреса', () => {
  it('находит пункты меню «/» по началу слова', () => {
    expect(filterSlashItems('табл')[0]?.title).toBe('Таблица')
    expect(filterSlashItems('пан').every((item) => item.command === 'insertPanel')).toBe(true)
    expect(filterSlashItems('h2')[0]?.command).toBe('heading2')
  })

  it('подсказывает сначала страницы своего пространства', () => {
    const pages = [
      { space: 'Личное', title: 'Требования к ремонту' },
      { space: 'Работа', title: 'Сбор требований' },
      { space: 'Работа', title: 'Требования к CRM' },
    ]
    expect(filterPages(pages, 'Работа', 'треб').map((page) => page.title)).toEqual([
      'Требования к CRM',
      'Сбор требований',
      'Требования к ремонту',
    ])
  })

  it('дополняет адрес протоколом, но не трогает файлы', () => {
    expect(normalizeHref('example.com')).toBe('https://example.com')
    expect(normalizeHref('https://sber.ru/путь')).toBe('https://sber.ru/путь')
    expect(normalizeHref('схема.pdf')).toBe('схема.pdf')
    expect(normalizeHref('  ')).toBe('')
  })
})
