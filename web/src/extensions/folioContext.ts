import { Extension } from '@tiptap/core'

export interface ChildPageSummary {
  title: string
}

/** Данные о странице, которые знает только приложение: какие ссылки живые, дети, база вложений. */
export interface FolioContextStorage {
  links: Record<string, boolean>
  children: ChildPageSummary[]
  assetBase: string
}

declare module '@tiptap/core' {
  interface Storage {
    folioContext: FolioContextStorage
  }
}

export const FolioContext = Extension.create<Record<string, never>, FolioContextStorage>({
  name: 'folioContext',

  addStorage() {
    return { links: {}, children: [], assetBase: '' }
  },
})
