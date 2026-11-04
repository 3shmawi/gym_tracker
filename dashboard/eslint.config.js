import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist/', 'node_modules/', 'test-results/', 'playwright-report/'] },
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    rules: {
      // Untrusted text is never parsed as HTML.
      'no-restricted-properties': [
        'error',
        { property: 'innerHTML', message: 'Render text with JSX; never parse HTML.' },
        { property: 'outerHTML', message: 'Render text with JSX; never parse HTML.' },
        { property: 'insertAdjacentHTML', message: 'Render text with JSX; never parse HTML.' },
      ],
      'no-restricted-syntax': [
        'error',
        { selector: "JSXAttribute[name.name='dangerouslySetInnerHTML']", message: 'Never inject HTML.' },
        { selector: "MemberExpression[object.name='localStorage']", message: 'Only supabase-js stores the session; use core/prefs.ts for theme and language.' },
      ],
      'no-eval': 'error',
      'no-implied-eval': 'error',
      '@typescript-eslint/restrict-template-expressions': ['error', { allowNumber: true }],
    },
  },
  {
    files: ['src/core/prefs.ts'],
    rules: { 'no-restricted-syntax': 'off' },
  },
  {
    files: ['eslint.config.js', 'scripts/**/*.mjs'],
    extends: [tseslint.configs.disableTypeChecked],
    languageOptions: { globals: { process: 'readonly', console: 'readonly', URL: 'readonly' } },
  },
);
