import Image from '@tiptap/extension-image'

const ABSOLUTE_URL = /^[a-z][a-z0-9+.-]*:/i

/** Относительный путь вложения превращается в адрес внутри пространства; в файле он остаётся относительным. */
export function resolveAssetURL(src: string, base: string): string {
  if (!src || !base || ABSOLUTE_URL.test(src)) return src
  try {
    return new URL(src, base).href
  } catch {
    return src
  }
}

export const FolioImage = Image.extend({
  addNodeView() {
    return ({ node, editor }) => {
      const image = document.createElement('img')
      image.loading = 'lazy'
      image.decoding = 'async'

      const apply = (attrs: Record<string, unknown>) => {
        image.src = resolveAssetURL(String(attrs.src ?? ''), editor.storage.folioContext.assetBase)
        image.alt = String(attrs.alt ?? '')
        if (attrs.title) image.title = String(attrs.title)
        else image.removeAttribute('title')
      }
      apply(node.attrs)

      return {
        dom: image,
        update: (next) => {
          if (next.type.name !== node.type.name) return false
          apply(next.attrs)
          return true
        },
      }
    }
  },
}).configure({ inline: true, allowBase64: true })
