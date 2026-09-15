import { Extension } from '@tiptap/core'

export interface ChildPageSummary {
  title: string
}

export interface PageSummary {
  space: string
  title: string
}

/** Данные, которые знает только приложение: живые ссылки, дети, база вложений, список страниц для подсказки. */
export interface FolioContextStorage {
  links: Record<string, boolean>
  children: ChildPageSummary[]
  assetBase: string
  pages: PageSummary[]
  spaceName: string
}

declare module '@tiptap/core' {
  interface Storage {
    folioContext: FolioContextStorage
  }
}

export const FolioContext = Extension.create<Record<string, never>, FolioContextStorage>({
  name: 'folioContext',

  addStorage() {
    return { links: {}, children: [], assetBase: '', pages: [], spaceName: '' }
  },
})
