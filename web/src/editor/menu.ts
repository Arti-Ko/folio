import type { SuggestionKeyDownProps, SuggestionProps } from '@tiptap/suggestion'
import { element } from './dom'

export interface MenuEntry {
  title: string
  subtitle?: string
  group?: string
}

const MENU_GAP = 6
const MENU_MAX_HEIGHT = 320
const VIEWPORT_MARGIN = 8

/** Всплывающий список в духе системного меню: для «/» и «[[». */
export class FloatingList {
  readonly element: HTMLDivElement
  private readonly emptyText: string
  private readonly onChoose: (index: number) => void
  private entries: MenuEntry[] = []
  private activeIndex = 0

  constructor(emptyText: string, onChoose: (index: number) => void) {
    this.emptyText = emptyText
    this.onChoose = onChoose
    this.element = element('div', 'folio-menu')
    this.element.setAttribute('role', 'listbox')
    this.element.addEventListener('mousedown', (event) => event.preventDefault())
    document.body.append(this.element)
  }

  update(entries: MenuEntry[], anchor: DOMRect | null): void {
    this.entries = entries
    this.activeIndex = Math.min(this.activeIndex, Math.max(entries.length - 1, 0))
    this.render()
    if (anchor) this.position(anchor)
  }

  move(step: number): void {
    if (this.entries.length === 0) return
    this.activeIndex = (this.activeIndex + step + this.entries.length) % this.entries.length
    this.syncActive()
  }

  choose(): boolean {
    if (this.entries.length === 0) return false
    this.onChoose(this.activeIndex)
    return true
  }

  destroy(): void {
    this.element.remove()
  }

  private render(): void {
    if (this.entries.length === 0) {
      this.element.replaceChildren(element('div', 'folio-menu-empty', this.emptyText))
      return
    }
    const nodes: HTMLElement[] = []
    let group: string | undefined
    this.entries.forEach((entry, index) => {
      if (entry.group && entry.group !== group) {
        group = entry.group
        nodes.push(element('div', 'folio-menu-group', entry.group))
      }
      const item = element('div', 'folio-menu-item')
      item.setAttribute('role', 'option')
      item.dataset.index = String(index)
      item.append(element('span', 'folio-menu-title', entry.title))
      if (entry.subtitle) item.append(element('span', 'folio-menu-subtitle', entry.subtitle))
      item.addEventListener('mouseenter', () => {
        this.activeIndex = index
        this.syncActive()
      })
      item.addEventListener('click', () => this.onChoose(index))
      nodes.push(item)
    })
    this.element.replaceChildren(...nodes)
    this.syncActive()
  }

  private syncActive(): void {
    for (const item of this.element.querySelectorAll<HTMLElement>('.folio-menu-item')) {
      const isActive = item.dataset.index === String(this.activeIndex)
      item.setAttribute('aria-selected', String(isActive))
      if (isActive) item.scrollIntoView({ block: 'nearest' })
    }
  }

  private position(anchor: DOMRect): void {
    const menu = this.element
    menu.style.maxHeight = `${MENU_MAX_HEIGHT}px`
    const height = Math.min(menu.scrollHeight, MENU_MAX_HEIGHT)
    const below = anchor.bottom + MENU_GAP
    const above = anchor.top - MENU_GAP - height
    const top = below + height > window.innerHeight && above > VIEWPORT_MARGIN ? above : below
    const left = Math.min(anchor.left, window.innerWidth - menu.offsetWidth - VIEWPORT_MARGIN)
    menu.style.top = `${top}px`
    menu.style.left = `${Math.max(VIEWPORT_MARGIN, left)}px`
  }
}

/** Отрисовка подсказок TipTap через FloatingList. */
export function suggestionRenderer<Item>(toEntry: (item: Item) => MenuEntry, emptyText: string) {
  return () => {
    let list: FloatingList | null = null
    let current: SuggestionProps<Item, Item> | null = null

    const choose = (index: number) => {
      const item = current?.items[index]
      if (current && item !== undefined) current.command(item)
    }
    const sync = (props: SuggestionProps<Item, Item>) => {
      current = props
      list ??= new FloatingList(emptyText, choose)
      list.update(props.items.map(toEntry), props.clientRect?.() ?? null)
    }

    return {
      onStart: sync,
      onUpdate: sync,
      onKeyDown: ({ event }: SuggestionKeyDownProps): boolean => {
        if (!list) return false
        switch (event.key) {
          case 'ArrowDown':
            list.move(1)
            return true
          case 'ArrowUp':
            list.move(-1)
            return true
          case 'Enter':
          case 'Tab':
            return list.choose()
          case 'Escape':
            list.destroy()
            list = null
            return true
          default:
            return false
        }
      },
      onExit: () => {
        list?.destroy()
        list = null
        current = null
      },
    }
  }
}
