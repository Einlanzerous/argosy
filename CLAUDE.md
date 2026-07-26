# Argosy

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

- ALWAYS read graphify-out/GRAPH_REPORT.md before reading any source files, running grep/glob searches, or answering codebase questions. The graph is your primary map of the codebase.
- IF graphify-out/wiki/index.md EXISTS, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- If `graphify` is not installed: `uv tool install graphifyy`
- To regenerate the report locally: `graphify extract .` then `graphify cluster-only . --no-viz --backend=claude` (0.9.x split the report out of extract; the explicit backend keeps community naming from being skipped — if you still see "Community N" placeholders, run `graphify label . --backend=claude`). Semantic extraction needs `ANTHROPIC_API_KEY`; CI refreshes the committed report + cache on every push to main.
