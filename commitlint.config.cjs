module.exports = {
  extends: ["@commitlint/config-conventional"],
  plugins: [
    {
      rules: {
        "scope-gh-issue": ({ scope }) => {
          return !scope
            ? [true]
            : [/^#\d+(?:-#\d+)*$/.test(scope), "scope must be empty or GitHub issue ids like #123 or #123-#456"];
        }
      }
    }
  ],
  rules: {
    "type-enum": [2, "always", ["feat", "feature", "ref", "refactor", "fix", "chore", "docs"]],
    "scope-gh-issue": [2, "always"]
  }
};
