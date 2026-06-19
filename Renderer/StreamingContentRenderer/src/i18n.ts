import i18next from 'i18next'
import { initReactI18next } from 'react-i18next'
import en from './i18n/locales/en.json'
import zhHans from './i18n/locales/zh-Hans.json'

void i18next
  .use(initReactI18next)
  .init({
    fallbackLng: 'en',
    interpolation: {
      escapeValue: false,
    },
    resources: {
      en: { translation: en },
      'zh-Hans': { translation: zhHans },
      zh: { translation: zhHans },
    },
    supportedLngs: ['en', 'zh-Hans', 'zh'],
  })
