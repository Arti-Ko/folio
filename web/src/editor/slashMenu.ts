import { Extension } from '@tiptap/core'
import { PluginKey } from '@tiptap/pm/state'
import { Suggestion } from '@tiptap/suggestion'
import { PANEL_TYPES, type PanelType } from '../extensions/panel'
import { runCommand, type CommandArgs } from './commands'
import { suggestionRenderer } from './menu'

export interface SlashItem {
  title: string
  group: string
  keywords: string[]
  command: string
  args?: CommandArgs
}

const PANEL_TITLES: Record<PanelType, string> = {
  info: 'Панель «Информация»',
  note: 'Панель «Заметка»',
  success: 'Панель «Успех»',
  warning: 'Панель «Предупреждение»',
  error: 'Панель «Ошибка»',
}

export const SLASH_ITEMS: SlashItem[] = [
  { title: 'Обычный текст', group: 'Текст', keywords: ['текст', 'абзац', 'text', 'paragraph'], command: 'paragraph' },
  { title: 'Заголовок 1', group: 'Текст', keywords: ['заголовок', 'h1', 'heading'], command: 'heading1' },
  { title: 'Заголовок 2', group: 'Текст', keywords: ['заголовок', 'h2', 'heading'], command: 'heading2' },
  { title: 'Заголовок 3', group: 'Текст', keywords: ['заголовок', 'h3', 'heading'], command: 'heading3' },
  { title: 'Цитата', group: 'Текст', keywords: ['цитата', 'quote'], command: 'blockquote' },
  { title: 'Блок кода', group: 'Текст', keywords: ['код', 'code', 'sql'], command: 'codeBlock' },
  { title: 'Маркированный список', group: 'Списки', keywords: ['список', 'маркированный', 'bullet', 'ul'], command: 'bulletList' },
  { title: 'Нумерованный список', group: 'Списки', keywords: ['список', 'нумерованный', 'ordered', 'ol'], command: 'orderedList' },
  { title: 'Задачи', group: 'Списки', keywords: ['задачи', 'чеклист', 'todo', 'task'], command: 'taskList' },
  { title: 'Таблица', group: 'Вставка', keywords: ['таблица', 'table'], command: 'insertTable' },
  ...PANEL_TYPES.map((type) => ({
    title: PANEL_TITLES[type],
    group: 'Вставка',
    keywords: ['панель', 'panel', type, ...PANEL_TITLES[type].toLowerCase().split(/[\s«»]+/)],
    command: 'insertPanel',
    args: { type },
  })),
  { title: 'Раскрывающийся блок', group: 'Вставка', keywords: ['раскрывающийся', 'спойлер', 'expand', 'details'], command: 'insertExpand' },
  { title: 'Статус', group: 'Вставка', keywords: ['статус', 'status', 'метка'], command: 'insertStatus' },
  { title: 'Ссылка на страницу', group: 'Вставка', keywords: ['ссылка', 'страница', 'link', 'page'], command: 'insertPageLink' },
  { title: 'Картинка или файл', group: 'Вставка', keywords: ['картинка', 'изображение', 'файл', 'image', 'file'], command: 'requestAttachment' },
  { title: 'Оглавление', group: 'Вставка', keywords: ['оглавление', 'содержание', 'toc'], command: 'insertToc' },
  { title: 'Дочерние страницы', group: 'Вставка', keywords: ['дочерние', 'подстраницы', 'children'], command: 'insertChildren' },
  { title: 'Разделитель', group: 'Вставка', keywords: ['разделитель', 'линия', 'hr', 'divider'], command: 'horizontalRule' },
]

export function filterSlashItems(query: string): SlashItem[] {
  const needle = query.trim().toLowerCase()
  if (!needle) return SLASH_ITEMS
  return SLASH_ITEMS.filter(
    (item) => item.title.toLowerCase().includes(needle) || item.keywords.some((keyword) => keyword.startsWith(needle)),
  )
}

/** Меню вставки по «/», как в Confluence. */
export const SlashCommands = Extension.create({
  name: 'slashCommands',

  addProseMirrorPlugins() {
    return [
      Suggestion<SlashItem, SlashItem>({
        editor: this.editor,
        pluginKey: new PluginKey('slashCommands'),
        char: '/',
        items: ({ query }) => filterSlashItems(query),
        allow: ({ editor }) => editor.isEditable && !editor.isActive('codeBlock'),
        command: ({ editor, range, props }) => {
          editor.chain().focus().deleteRange(range).run()
          runCommand(editor, props.command, props.args)
        },
        render: suggestionRenderer<SlashItem>((item) => ({ title: item.title, group: item.group }), 'Ничего не найдено'),
      }),
    ]
  },
})
