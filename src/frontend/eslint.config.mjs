// ESLint 9 flat config (CI, deploy/ci.sh): eslint-config-next 16 no longer loads the
// upstream .eslintrc. Same rules as that file.
import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTs from 'eslint-config-next/typescript';

export default [
  ...nextVitals,
  ...nextTs,
  { ignores: ['genproto/**', 'protos/**', 'cypress/**', '.next/**', 'node_modules/**'] },
  {
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
      'react-hooks/exhaustive-deps': 'warn',
      'no-unused-vars': 'off',
      '@typescript-eslint/no-unused-vars': 'error',
      'max-len': ['error', { code: 150, ignoreComments: true, ignoreTrailingComments: true, ignoreUrls: true, ignoreStrings: true, ignoreTemplateLiterals: true }],
    },
  },
];
