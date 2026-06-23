import { defineConfig, type Plugin } from 'vite'
import react, { reactCompilerPreset } from '@vitejs/plugin-react'
import babel from '@rolldown/plugin-babel'
import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath } from 'node:url'

function webViewFileScriptPlugin() {
  return {
    name: 'webview-file-script',
    apply: 'build' as const,
    enforce: 'post' as const,
    transformIndexHtml(html: string) {
      return html
        .replace(/<script type="module" crossorigin src=/g, '<script defer src=')
        .replace(/<script type="module" src=/g, '<script defer src=')
        .replace(/\s+crossorigin(?=[\s>])/g, '')
    },
  }
}

function classicScriptImportMetaUrlPlugin(): Plugin {
  const currentScriptURLExpression = '((document.currentScript&&document.currentScript.src)||location.href)'

  return {
    name: 'classic-script-import-meta-url',
    apply: 'build',
    enforce: 'post',
    generateBundle(_options, bundle) {
      Object.values(bundle).forEach((asset) => {
        if (asset.type !== 'chunk') {
          return
        }

        asset.code = asset.code.replaceAll('import.meta.url', currentScriptURLExpression)
      })
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  base: './',
  plugins: [
    tailwindcss(),
    react(),
    babel({ presets: [reactCompilerPreset()] }),
    classicScriptImportMetaUrlPlugin(),
    webViewFileScriptPlugin(),
  ],
  build: {
    outDir: fileURLToPath(new URL('../../UniLLMs/Resources/StreamingContentRenderer', import.meta.url)),
    emptyOutDir: true,
    modulePreload: false,
    assetsDir: 'StreamingContentRendererAssets.bundle',
    rolldownOptions: {
      output: {
        codeSplitting: false,
      },
    },
  },
})
