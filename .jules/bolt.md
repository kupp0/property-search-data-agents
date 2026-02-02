## 2024-10-24 - [Inline Component Definition Anti-Pattern]
**Learning:** Found `PropertyCard` defined *inside* the `App` component's render function. This causes the child component to be redefined on every render of the parent, defeating React's reconciliation optimization and causing unnecessary unmounts/remounts.
**Action:** Always scan for function definitions inside functional components that return JSX. Extract them to separate files or define them outside the component scope, and apply `React.memo` if they are pure presentation components.
