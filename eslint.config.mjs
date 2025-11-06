import js from "@eslint/js";
import tseslint from "typescript-eslint";
import vitestPlugin from "eslint-plugin-vitest";

export default tseslint.config(
  {
    ignores: ["dist", "node_modules", "compose/realm-export.json"],
  },
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  {
    files: ["src/**/*.ts", "tests/**/*.ts"],
    languageOptions: {
      parserOptions: {
        project: "./tsconfig.eslint.json",
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: {
      vitest: vitestPlugin,
    },
    rules: {
      "@typescript-eslint/no-misused-promises": [
        "error",
        {
          checksVoidReturn: {
            attributes: false,
          },
        },
      ],
    },
  },
  {
    files: ["tests/**/*.ts"],
    plugins: {
      vitest: vitestPlugin,
    },
    languageOptions: {
      globals: vitestPlugin.configs.env.languageOptions.globals,
    },
    rules: {
      ...vitestPlugin.configs.recommended.rules,
    },
  }
);
