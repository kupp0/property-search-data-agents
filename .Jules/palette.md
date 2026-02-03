## 2026-02-03 - [Focus Visibility Matters]
**Learning:** Custom input styles often remove default browser outlines (e.g., `focus:ring-0`). Without adding a replacement focus indicator (like `focus-within` on the parent), keyboard users lose track of their position.
**Action:** Always pair `focus:ring-0` on inputs with a visual focus indicator on the container.
