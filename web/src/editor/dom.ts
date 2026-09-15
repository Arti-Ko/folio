const SVG_NS = 'http://www.w3.org/2000/svg'

export function element<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className?: string,
  text?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text !== undefined) node.textContent = text
  return node
}

/** Кнопка, которая не забирает фокус у редактора. */
export function actionButton(label: string, className: string, onClick: () => void): HTMLButtonElement {
  const button = element('button', className, label)
  button.type = 'button'
  button.addEventListener('mousedown', (event) => event.preventDefault())
  button.addEventListener('click', (event) => {
    event.preventDefault()
    onClick()
  })
  return button
}

/** Контурный значок 16×16 из готовых путей. */
export function strokeIcon(paths: string[]): SVGSVGElement {
  const svg = document.createElementNS(SVG_NS, 'svg')
  svg.setAttribute('viewBox', '0 0 16 16')
  svg.setAttribute('fill', 'none')
  svg.setAttribute('stroke', 'currentColor')
  svg.setAttribute('stroke-width', '1.5')
  svg.setAttribute('stroke-linecap', 'round')
  svg.setAttribute('stroke-linejoin', 'round')
  svg.setAttribute('aria-hidden', 'true')
  for (const d of paths) {
    const path = document.createElementNS(SVG_NS, 'path')
    path.setAttribute('d', d)
    svg.append(path)
  }
  return svg
}

export interface LabeledInput {
  label: HTMLLabelElement
  field: HTMLInputElement
}

export function labeledInput(caption: string, value: string, placeholder: string): LabeledInput {
  const label = element('label', 'folio-field')
  const text = element('span', undefined, caption)
  const field = element('input')
  field.type = 'text'
  field.value = value
  field.placeholder = placeholder
  field.spellcheck = false
  label.append(text, field)
  return { label, field }
}
