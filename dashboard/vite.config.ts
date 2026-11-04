import { defineConfig, loadEnv, type Plugin } from 'vite';
import preact from '@preact/preset-vite';
import { parseConfig } from './src/core/config';
import { headersFile } from './build/headers';

// Writes dist/_headers with a CSP that allows only our Supabase project.
// The build fails when the Supabase settings are missing or not publishable.
function securityHeaders(supabaseUrl: string, turnstile: boolean): Plugin {
  return {
    name: 'azm-security-headers',
    apply: 'build',
    generateBundle() {
      this.emitFile({ type: 'asset', fileName: '_headers', source: headersFile({ supabaseUrl, turnstile }) });
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = { ...loadEnv(mode, process.cwd(), 'VITE_'), ...pick(process.env) };
  const config = parseConfig(env);
  return {
    plugins: [preact(), securityHeaders(config.supabaseUrl, config.turnstileSiteKey !== null)],
    build: {
      // No inline script: the CSP has no 'unsafe-inline'.
      modulePreload: { polyfill: false },
      // No data: URIs (img-src/font-src are 'self' only).
      assetsInlineLimit: 0,
      sourcemap: false,
      target: 'es2022',
    },
    server: { port: 5173, strictPort: true },
    preview: { port: 4173, strictPort: true },
  };
});

function pick(source: NodeJS.ProcessEnv): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(source)) if (k.startsWith('VITE_') && typeof v === 'string') out[k] = v;
  return out;
}
