export interface StreamingRendererController {
  api: StreamingRendererAPI
}

export function applyRendererConfiguration(configuration: StreamingRendererConfiguration) {
  const colorScheme = configuration.colorScheme === 'dark' ? 'dark' : 'light'
  document.documentElement.style.colorScheme = colorScheme
  document.documentElement.classList.toggle('dark', colorScheme === 'dark')

  if (configuration.color) {
    document.documentElement.style.setProperty('--streaming-text-color', configuration.color)
  }
  if (configuration.linkColor) {
    document.documentElement.style.setProperty('--streaming-link-color', configuration.linkColor)
  }
  if (configuration.secondaryColor) {
    document.documentElement.style.setProperty('--streaming-secondary-color', configuration.secondaryColor)
  }
  if (configuration.tertiaryColor) {
    document.documentElement.style.setProperty('--streaming-tertiary-color', configuration.tertiaryColor)
  }
  if (configuration.separatorColor) {
    document.documentElement.style.setProperty('--streaming-separator-color', configuration.separatorColor)
  }
  if (configuration.successColor) {
    document.documentElement.style.setProperty('--streaming-success-color', configuration.successColor)
  }
  if (configuration.errorColor) {
    document.documentElement.style.setProperty('--streaming-error-color', configuration.errorColor)
  }
  if (typeof configuration.fontSize === 'number') {
    document.documentElement.style.setProperty('--streaming-font-size', `${configuration.fontSize}px`)
  }
}
