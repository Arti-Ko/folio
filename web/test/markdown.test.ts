import { Editor } from '@tiptap/core'
import { afterEach, describe, expect, it } from 'vitest'
import { createExtensions } from '../src/extensions'
import { resolveAssetURL } from '../src/extensions/folioImage'
import { PANEL_TYPES } from '../src/extensions/panel'
import { parseWikiTarget, wikiLinkKey } from '../src/extensions/wikiLink'

const editors: Editor[] = []

function load(markdown: string): Editor {
  const editor = new Editor({ extensions: createExtensions(), content: markdown, contentType: 'markdown' })
  editors.push(editor)
  return editor
}

function roundTrip(markdown: string): string {
  return load(markdown).getMarkdown()
}

afterEach(() => {
  editors.splice(0).forEach((editor) => editor.destroy())
})

describe('панели', () => {
  it('разбирает тип, заголовок и вложенную разметку', () => {
    const doc = load(':::warning {title="Внимание"}\n\nТекст **важный**\n\n:::').getJSON()
    const panel = doc.content?.[0] as import('@tiptap/core').JSONContent | undefined
    expect(panel).toMatchObject({ type: 'panel', attrs: { type: 'warning', title: 'Внимание' } })
    expect(panel?.content?.[0].content?.[1]).toMatchObject({ text: 'важный', marks: [{ type: 'bold' }] })
  })

  it.each(PANEL_TYPES)('сохраняет панель %s без искажений', (type) => {
    const markdown = `:::${type}\n\nТекст панели\n\n:::`
    expect(roundTrip(markdown)).toBe(markdown)
  })

  it('экранирует кавычки в заголовке', () => {
    const markdown = ':::info {title="Термин \\"лид\\""}\n\nТекст\n\n:::'
    const editor = load(markdown)
    expect(editor.getJSON().content?.[0].attrs?.title).toBe('Термин "лид"')
    expect(editor.getMarkdown()).toBe(markdown)
  })

  it('оставляет незакрытый блок обычным текстом', () => {
    const doc = load(':::info\n\nТекст без закрытия').getJSON()
    expect(doc.content?.every((node) => node.type !== 'panel')).toBe(true)
  })

  it('поддерживает панель внутри раскрывающегося блока', () => {
    const markdown = ':::expand {title="Детали"}\n\n:::note\n\nВложенная заметка\n\n:::\n\n:::'
    const doc = load(markdown).getJSON()
    expect(doc.content?.[0]).toMatchObject({ type: 'expand', attrs: { title: 'Детали' } })
    expect(doc.content?.[0].content?.[0]).toMatchObject({ type: 'panel', attrs: { type: 'note' } })
    expect(roundTrip(markdown)).toBe(markdown)
  })

  it('разбирает текст после панели как отдельный абзац', () => {
    const doc = load(':::success\n\nГотово\n\n:::\n\nПосле панели').getJSON()
    expect(doc.content?.map((node) => node.type)).toEqual(['panel', 'paragraph'])
  })
})

describe('статусы', () => {
  it('разбирает цвет и текст', () => {
    const doc = load('Состояние: [status color="green"]Утверждено[/status]').getJSON()
    expect(doc.content?.[0].content?.[1]).toMatchObject({
      type: 'status',
      attrs: { label: 'Утверждено', color: 'green' },
    })
  })

  it('сохраняет серый статус без атрибута цвета', () => {
    expect(roundTrip('Сейчас [status]Черновик[/status]')).toBe('Сейчас [status]Черновик[/status]')
  })

  it('заменяет неизвестный цвет на серый', () => {
    expect(roundTrip('[status color="pink"]Странный[/status]')).toBe('[status]Странный[/status]')
  })

  it('работает внутри ячейки таблицы', () => {
    const markdown = '| Требование | Статус |\n| --- | --- |\n| Вход по СМС | [status color="blue"]В работе[/status] |'
    const json = JSON.stringify(load(markdown).getJSON())
    expect(json).toContain('"type":"status"')
    expect(json).toContain('В работе')
  })
})

describe('ссылки на страницы', () => {
  it('разбирает все формы записи', () => {
    expect(parseWikiTarget('Протокол')).toEqual({ space: null, title: 'Протокол', label: null })
    expect(parseWikiTarget('Личное::Идеи', 'мои идеи')).toEqual({ space: 'Личное', title: 'Идеи', label: 'мои идеи' })
    expect(parseWikiTarget('Встреча: заказчик')).toEqual({ space: null, title: 'Встреча: заказчик', label: null })
  })

  it.each([
    'См. [[Требования к CRM]] и дальше',
    'См. [[Требования к CRM|требования]]',
    'См. [[Личное::Список книг]]',
    'См. [[Личное::Список книг|книги]]',
  ])('сохраняет «%s» без искажений', (markdown) => {
    expect(roundTrip(markdown)).toBe(markdown)
  })

  it('не путает ссылку на страницу с обычной ссылкой', () => {
    const doc = load('[[Страница]] и [сайт](https://example.com)').getJSON()
    const types = doc.content?.[0].content?.map((node) => node.type)
    expect(types).toContain('wikiLink')
    expect(JSON.stringify(doc)).toContain('"type":"link"')
  })

  it('строит ключ без учёта регистра и лишних пробелов', () => {
    expect(wikiLinkKey(null, '  Протокол   Встречи ')).toBe('::протокол встречи')
    expect(wikiLinkKey('Личное', 'Идеи')).toBe('личное::идеи')
  })
})

describe('блоки страницы', () => {
  it('сохраняет оглавление и дочерние страницы', () => {
    const markdown = '[toc]\n\n# Раздел\n\n[children]'
    const doc = load(markdown).getJSON()
    expect(doc.content?.map((node) => node.type)).toEqual(['tableOfContents', 'heading', 'childPages'])
    expect(roundTrip(markdown)).toBe(markdown)
  })
})

describe('стандартная разметка', () => {
  it('выравнивает столбцы таблицы пробелами и дальше не меняет её', () => {
    const loose = '| ID | Требование |\n| --- | --- |\n| FR-1 | Вход по СМС |'
    const canonical = '| ID   | Требование  |\n| ---- | ----------- |\n| FR-1 | Вход по СМС |'
    expect(roundTrip(loose).trim()).toBe(canonical)
    expect(roundTrip(canonical).trim()).toBe(canonical)
  })

  it.each([
    ['список задач', '- [ ] Согласовать ТЗ\n- [x] Созвониться с заказчиком'],
    ['картинка', '![Схема процесса](схема.png)'],
    ['код', '```sql\nselect 1\n```'],
    ['цитата', '> Важная мысль'],
  ])('сохраняет: %s', (_name, markdown) => {
    expect(roundTrip(markdown)).toBe(markdown)
  })
})

describe('адреса вложений', () => {
  const base = 'folio://file/space-1/%D0%9F%D1%80%D0%BE%D0%B5%D0%BA%D1%82/'

  it('разрешает относительный путь от папки страницы', () => {
    expect(resolveAssetURL('схема 1.png', base)).toBe(`${base}%D1%81%D1%85%D0%B5%D0%BC%D0%B0%201.png`)
  })

  it('не трогает абсолютные адреса', () => {
    expect(resolveAssetURL('https://example.com/a.png', base)).toBe('https://example.com/a.png')
    expect(resolveAssetURL('data:image/png;base64,AAAA', base)).toBe('data:image/png;base64,AAAA')
  })
})
