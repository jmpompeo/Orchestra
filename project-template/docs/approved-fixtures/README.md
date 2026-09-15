# Approved fixtures

Store trusted, reviewable examples for behaviour where a green agent-authored
test suite is insufficient evidence: exports, parsers, transformations,
permissions, pricing, migrations, and customer-visible workflows.

Create one directory per behaviour. Include representative input, the expected
output or invariant, provenance that is safe to commit, and edge cases. Never
copy production secrets or personal data. Treat fixture changes as product or
contract changes requiring review.

Example:

```text
invoice-export/
  input.json
  expected.csv
  edge-cases.md
```
