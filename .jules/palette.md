## 2024-05-22 - Chat Interface Accessibility
**Learning:** Chat interfaces often lack `aria-live` regions for new messages, making them silent for screen reader users.
**Action:** Always wrap message containers in `role="log"` and `aria-live="polite"` to ensure new content is announced automatically.
