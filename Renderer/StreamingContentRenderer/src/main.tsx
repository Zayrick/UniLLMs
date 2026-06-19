import { createRoot } from 'react-dom/client'
import './i18n'
import App from './App.tsx'
import { installStreamingRendererBridge } from './renderer/bridge'

installStreamingRendererBridge()
createRoot(document.getElementById('root')!).render(<App />)
