# Acceptance criteria: docs

- docs/curriculum/ contains all 18 required HTML pages
- Each subsystem page is >=900 words of real explanatory prose
- Each subsystem page has section ids: what-it-is, how-it-works, how-tunneld-uses-it, why, examples
- Each subsystem page has >=3 <pre> worked examples with real commands
- Each page cites at least one concrete lib/tunneld/*.ex source file
- No placeholder text (TBD/TODO/lorem/coming soon)
- All internal links resolve; index.html links every page
- No external CDN dependencies the curriculum works fully offline
- Every page is valid parseable HTML with a doctype and a title
- Every `def` shown in a code block attributed to lib/tunneld/*.ex actually exists in the codebase
- A 18-terminal-exec.html page documents the interactive terminal subsystem to the same depth as the others
