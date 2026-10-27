# Mermaid diagrams

Open this file in **Preview** or **Split**. Switch appearance or resize the window to see the diagrams update.

## Flowchart

```mermaid
flowchart LR
    A[Write Markdown] --> B{Valid syntax?}
    B -->|Yes| C[Render with Pele]
    B -->|No| D[Show an error]
```

## Sequence

```mermaid
sequenceDiagram
    participant Reader
    participant App
    Reader->>App: Open document
    App-->>Reader: Show diagram
```

## State

```mermaid
stateDiagram-v2
    [*] --> Editing
    Editing --> Preview: Switch view
    Preview --> Editing: Edit source
```

## Pie chart

```mermaid
pie title Document contents
    "Text" : 65
    "Tables" : 20
    "Diagrams" : 15
```

## Normal source code stays code

```swift
let message = "Hello, Markdown"
```
