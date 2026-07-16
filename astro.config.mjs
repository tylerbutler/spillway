import { defineConfig } from 'astro/config';
import expressiveCode from 'astro-expressive-code';

export default defineConfig({
  site: 'https://tylerbutler.github.io/spillway',
  integrations: [
    expressiveCode({
      themes: ['github-dark-default'],
      styleOverrides: {
        borderRadius: '16px',
        frames: {
          frameBoxShadowCssValue: 'none',
        },
      },
    }),
  ],
});
