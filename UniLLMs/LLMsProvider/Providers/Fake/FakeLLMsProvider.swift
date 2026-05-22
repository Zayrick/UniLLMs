//
//  FakeLLMsProvider.swift
//  UniLLMs
//
//  Provides a no-configuration fake LLM provider with deterministic static and streaming models.
//  Created by Zayrick on 2026/5/12.
//

import Foundation

nonisolated extension LLMsProviderKind {
    static let fake = LLMsProviderKind(rawValue: "fake")
}

struct FakeLLMsProvider: LLMsProviderAdapter {
    private enum Metadata {
        static let displayName = "Fake"
        static let staticResponse = "This is a fake static response returned after a short delay."
        static let streamResponse = "This is a fake streaming response. It arrives gradually so the streaming UI can be checked without a real provider."
        static let markdownResponse = #"""
# UniLLMs Markdown Torture Fixture

This deterministic response is intentionally dense. It mixes common GitHub Flavored Markdown shapes with mainstream language fences, nested structures, tables, raw HTML, and LaTeX so the chat renderer has one broad fixture to chew on.

## Inline Formatting

Plain text can sit next to **bold**, *italic*, ***bold italic***, ~~strikethrough~~, `inline code`, <kbd>Cmd</kbd> + <kbd>K</kbd>, superscript<sup>2</sup>, subscript<sub>n</sub>, and escaped punctuation like \*literal asterisks\* or \[literal brackets\].

Links can be inline like [GitHub Flavored Markdown](https://github.github.com/gfm/), reference-style like [the reference link][gfm-reference], bare URLs such as https://github.com/openai, and email autolinks like <hello@example.com>.

![Markdown fixture image alt text](https://dummyimage.com/300x200.png "Optional image title")

[gfm-reference]: https://github.github.com/gfm/

### Heading Level 3

#### Heading Level 4

##### Heading Level 5

###### Heading Level 6

---

## GitHub Alerts

> [!NOTE]
> Notes should render as a GitHub-style alert when supported.

> [!TIP]
> Tips can contain **formatting**, `code`, and [links](https://github.com).

> [!IMPORTANT]
> Important content should still preserve nested markdown.
>
> - First nested item
> - Second nested item with $\alpha + \beta = \gamma$

> [!WARNING]
> Warning blocks test icon, label, color, and multiline wrapping behavior.

> [!CAUTION]
> Caution blocks are useful for high-contrast styling checks.

## Blockquotes

> A top-level quote.
>
> > A nested quote with a list:
> >
> > 1. Ordered item inside nested quote
> > 2. Another item with `inline code`
>
> Back to the top-level quote.

## Lists

- Unordered level 1
  - Unordered level 2
    - Unordered level 3 with **bold text**
      - Unordered level 4 with `deepInlineCode()`
- Item with a following paragraph.

  The paragraph belongs to the list item and should keep its indentation.

- Item with a nested blockquote:

  > This quote is nested under a list item.
  > It should not escape the list's visual hierarchy.

1. Ordered level 1
   1. Ordered level 2
      1. Ordered level 3
2. Ordered item with mixed children:
   - Mixed unordered child
   - Another child with a task list:
     - [x] Completed task
     - [ ] Incomplete task
     - [ ] Incomplete task with **bold**, `code`, and [a link](https://example.com)

## Task List

- [x] Parse headings
- [x] Parse fenced code
- [ ] Render nested lists without layout drift
- [ ] Render LaTeX blocks and inline math

## Tables

| Feature | Syntax | Expected Alignment | Notes |
| :-- | :-: | --: | :-- |
| Bold | `**text**` | Left / center / right | Works in cells |
| Escaped pipe | `a \| b` | 123.45 | Cell keeps the pipe |
| Link | `[OpenAI](https://openai.com)` | 678.90 | Inline link in a table |
| Code | `` `let x = 1` `` | 42 | Inline code in a table |

| Language | Example Concept | Renderer Stress |
| :-- | :-- | :-- |
| Swift | async streams | generics and string interpolation |
| Python | dataclasses | indentation |
| TypeScript | discriminated unions | angle brackets |
| SQL | joins and aggregates | uppercase keywords |

## Footnotes

Here is a short footnote reference.[^short]

Here is a longer footnote reference with nested content.[^long]

[^short]: A compact footnote.

[^long]: A longer footnote with multiple pieces.

    It has an indented continuation paragraph.

    - A nested list in the footnote
    - Another nested list item with `code`

## Collapsible Details

<details>
<summary>Open nested markdown details</summary>

Inside details:

- A list item
- A task item: [ ] unchecked
- Inline math: $a^2 + b^2 = c^2$

```json
{
  "inside": "details",
  "works": true
}
```

</details>

## Raw HTML

<dl>
  <dt>Definition title</dt>
  <dd>Definition body with <strong>strong HTML</strong> and <code>inline HTML code</code>.</dd>
</dl>

<table>
  <tr>
    <th>HTML table head</th>
    <th>Status</th>
  </tr>
  <tr>
    <td>Raw HTML block</td>
    <td>Rendered or safely ignored</td>
  </tr>
</table>

## LaTeX

Inline math examples: $E = mc^2$, $\sum_{i=1}^{n} i = \frac{n(n + 1)}{2}$, and $\nabla \cdot \vec{E} = \rho / \varepsilon_0$.

Display math:

$$
\int_{0}^{\infty} e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

Aligned equations:

$$
\begin{aligned}
f(x) &= x^2 + 2x + 1 \\
     &= (x + 1)^2
\end{aligned}
$$

Matrix:

$$
A =
\begin{bmatrix}
1 & 2 & 3 \\
4 & 5 & 6 \\
7 & 8 & 9
\end{bmatrix}
$$

## Diagrams

```mermaid
sequenceDiagram
    participant User
    participant App
    participant FakeProvider
    User->>App: Select Markdown Stream
    App->>FakeProvider: streamChat(request)
    FakeProvider-->>App: Markdown chunks
    App-->>User: Render incrementally
```

## Code Fences

### Swift

```swift
import Foundation

struct Message: Codable, Identifiable {
    let id: UUID
    let role: String
    let content: String
}

func renderGreeting(name: String) async -> String {
    "Hello, \(name)"
}
```

### Objective-C

```objective-c
#import <Foundation/Foundation.h>

@interface Greeter : NSObject
- (NSString *)messageForName:(NSString *)name;
@end

@implementation Greeter
- (NSString *)messageForName:(NSString *)name {
    return [NSString stringWithFormat:@"Hello, %@", name];
}
@end
```

### JavaScript

```javascript
const items = ["markdown", "tables", "math"];
const rendered = items.map((item, index) => ({
  id: index + 1,
  label: item.toUpperCase(),
}));

console.log(rendered);
```

### TypeScript

```typescript
type ChatDelta =
  | { type: "content"; text: string }
  | { type: "reasoning"; text: string };

function appendDelta(buffer: string, delta: ChatDelta): string {
  return `${buffer}${delta.text}`;
}
```

### Python

```python
from dataclasses import dataclass

@dataclass
class Token:
    text: str
    index: int

def chunks(text: str, size: int = 8):
    for start in range(0, len(text), size):
        yield text[start:start + size]
```

### Java

```java
import java.util.List;

public final class MarkdownFixture {
    public static String joinLines(List<String> lines) {
        return String.join("\n", lines);
    }
}
```

### Kotlin

```kotlin
data class Model(val id: String, val name: String?)

fun Model.displayName(): String = name?.takeIf { it.isNotBlank() } ?: id
```

### Go

```go
package main

import "fmt"

func main() {
    for _, word := range []string{"stream", "direct", "markdown"} {
        fmt.Println(word)
    }
}
```

### Rust

```rust
#[derive(Debug)]
struct Delta<'a> {
    content: &'a str,
}

fn main() {
    let delta = Delta { content: "hello" };
    println!("{delta:?}");
}
```

### C

```c
#include <stdio.h>

int main(void) {
    const char *message = "hello markdown";
    printf("%s\n", message);
    return 0;
}
```

### C++

```cpp
#include <iostream>
#include <vector>

int main() {
    std::vector<int> values{1, 2, 3};
    for (const auto value : values) {
        std::cout << value << "\n";
    }
}
```

### C#

```csharp
using System;

public record ChatMessage(string Role, string Content);

Console.WriteLine(new ChatMessage("assistant", "hello"));
```

### Ruby

```ruby
class Renderer
  def initialize(theme:)
    @theme = theme
  end

  def call(text)
    "#{@theme}: #{text}"
  end
end
```

### PHP

```php
<?php
$items = ["markdown", "gfm", "latex"];
foreach ($items as $item) {
    echo strtoupper($item) . PHP_EOL;
}
```

### Shell

```bash
set -euo pipefail

for name in markdown table math; do
  printf 'fixture:%s\n' "$name"
done
```

### SQL

```sql
SELECT provider_id, COUNT(*) AS message_count
FROM chat_messages
WHERE created_at >= DATE('now', '-7 days')
GROUP BY provider_id
ORDER BY message_count DESC;
```

### HTML

```html
<article class="message">
  <h1>Markdown Fixture</h1>
  <p>HTML code fences should preserve tags.</p>
</article>
```

### CSS

```css
.message {
  display: grid;
  gap: 0.75rem;
  color: color-mix(in srgb, CanvasText 88%, transparent);
}
```

### JSON

```json
{
  "provider": "fake",
  "models": ["markdown-static", "markdown-stream"],
  "features": {
    "tables": true,
    "latex": true,
    "nestedLists": true
  }
}
```

### YAML

```yaml
provider: fake
fixture:
  modes:
    - direct
    - stream
  markdown:
    tables: true
    latex: true
```

### XML

```xml
<fixture provider="fake">
  <mode>direct</mode>
  <mode>stream</mode>
</fixture>
```

### Markdown Inside Markdown

````markdown
# Nested Markdown Sample

```swift
print("A fenced block inside a fenced block")
```

- [x] Nested task item
````

### Diff

```diff
diff --git a/Renderer.swift b/Renderer.swift
@@ -1,3 +1,3 @@
-let mode = "plain"
+let mode = "markdown"
 render(mode)
```

### Dockerfile

```dockerfile
FROM swift:latest
WORKDIR /app
COPY . .
CMD ["swift", "test"]
```

## Mixed Stress Case

1. A numbered item with a nested table:

   | Nested | Table |
   | :-- | --: |
   | Alpha | 1 |
   | Beta | 2 |

2. A numbered item with code and math:

   ```swift
   let formula = "$x^2 + y^2 = z^2$"
   ```

   $$
   x^2 + y^2 = z^2
   $$

3. A numbered item with a blockquote:

   > The quote belongs to the numbered item.
   >
   > - Quoted list item
   > - Quoted list item with `code`

The fixture ends with trailing punctuation, a final inline code span `done`, and a final math span $\omega = 2\pi f$.
"""#
        static let streamInitialDelayNanoseconds: UInt64 = 2_000_000_000
        static let streamCharacterDelayNanoseconds: UInt64 = 100_000_000
        static let markdownStreamChunkDelayRangeNanoseconds: ClosedRange<UInt64> = 30_000_000...50_000_000
        static let markdownStreamChunkSizeRange: ClosedRange<Int> = 1...6
        static let staticResponseDelayNanoseconds: UInt64 = 3_000_000_000
    }

    enum ModelID {
        static let staticResponse = "static"
        static let stream = "stream"
        static let markdownStatic = "markdown-static"
        static let markdownStream = "markdown-stream"
    }

    private let staticResponseDelayNanoseconds: UInt64
    private let streamInitialDelayNanoseconds: UInt64
    private let streamCharacterDelayNanoseconds: UInt64
    private let markdownStreamChunkDelayRangeNanoseconds: ClosedRange<UInt64>
    private let markdownStreamChunkSizeRange: ClosedRange<Int>

    init(
        staticResponseDelayNanoseconds: UInt64 = Metadata.staticResponseDelayNanoseconds,
        streamInitialDelayNanoseconds: UInt64 = Metadata.streamInitialDelayNanoseconds,
        streamCharacterDelayNanoseconds: UInt64 = Metadata.streamCharacterDelayNanoseconds,
        markdownStreamChunkDelayRangeNanoseconds: ClosedRange<UInt64> = Metadata.markdownStreamChunkDelayRangeNanoseconds,
        markdownStreamChunkSizeRange: ClosedRange<Int> = Metadata.markdownStreamChunkSizeRange
    ) {
        self.staticResponseDelayNanoseconds = staticResponseDelayNanoseconds
        self.streamInitialDelayNanoseconds = streamInitialDelayNanoseconds
        self.streamCharacterDelayNanoseconds = streamCharacterDelayNanoseconds
        self.markdownStreamChunkDelayRangeNanoseconds = markdownStreamChunkDelayRangeNanoseconds
        self.markdownStreamChunkSizeRange = markdownStreamChunkSizeRange
    }

    var kind: LLMsProviderKind {
        .fake
    }

    var displayName: String {
        Metadata.displayName
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.modelList, .streamingChat]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration()
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        []
    }

    var modelSource: LLMsProviderModelSource {
        .`static`
    }

    var staticModels: [LLMsProviderModel] {
        [
            LLMsProviderModel(id: ModelID.staticResponse, name: "Static"),
            LLMsProviderModel(id: ModelID.stream, name: "Stream"),
            LLMsProviderModel(id: ModelID.markdownStatic, name: "Markdown Static"),
            LLMsProviderModel(id: ModelID.markdownStream, name: "Markdown Stream")
        ]
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch request.modelID {
                    case ModelID.staticResponse:
                        try await Task.sleep(nanoseconds: staticResponseDelayNanoseconds)
                        try Task.checkCancellation()
                        continuation.yield(ChatResponseDelta(content: Metadata.staticResponse))
                    case ModelID.stream:
                        try await Task.sleep(nanoseconds: streamInitialDelayNanoseconds)
                        try await streamResponseCharacters(Metadata.streamResponse, into: continuation)
                    case ModelID.markdownStatic:
                        try await Task.sleep(nanoseconds: staticResponseDelayNanoseconds)
                        try Task.checkCancellation()
                        continuation.yield(ChatResponseDelta(content: Metadata.markdownResponse))
                    case ModelID.markdownStream:
                        try await streamResponseRandomMarkdownChunks(
                            Metadata.markdownResponse,
                            into: continuation
                        )
                    default:
                        throw FakeLLMsProviderError.unsupportedModel(request.modelID)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func streamResponseCharacters(
        _ response: String,
        into continuation: AsyncThrowingStream<ChatResponseDelta, Error>.Continuation
    ) async throws {
        for character in response {
            try Task.checkCancellation()
            continuation.yield(ChatResponseDelta(content: String(character)))
            try await Task.sleep(nanoseconds: streamCharacterDelayNanoseconds)
        }
    }

    private func streamResponseRandomMarkdownChunks(
        _ response: String,
        into continuation: AsyncThrowingStream<ChatResponseDelta, Error>.Continuation
    ) async throws {
        let chunkSizeRange = normalizedMarkdownStreamChunkSizeRange
        var currentIndex = response.startIndex

        while currentIndex < response.endIndex {
            try Task.checkCancellation()
            try await Task.sleep(
                nanoseconds: UInt64.random(in: markdownStreamChunkDelayRangeNanoseconds)
            )

            let remainingCharacterCount = response.distance(from: currentIndex, to: response.endIndex)
            let chunkCharacterCount = min(
                Int.random(in: chunkSizeRange),
                remainingCharacterCount
            )
            let chunkEndIndex = response.index(currentIndex, offsetBy: chunkCharacterCount)
            continuation.yield(
                ChatResponseDelta(content: String(response[currentIndex..<chunkEndIndex]))
            )

            currentIndex = chunkEndIndex

            guard currentIndex < response.endIndex else {
                return
            }
        }
    }

    private var normalizedMarkdownStreamChunkSizeRange: ClosedRange<Int> {
        let lowerBound = max(1, markdownStreamChunkSizeRange.lowerBound)
        let upperBound = max(lowerBound, markdownStreamChunkSizeRange.upperBound)
        return lowerBound...upperBound
    }
}

enum FakeLLMsProviderError: LocalizedError, Equatable {
    case unsupportedModel(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedModel(modelID):
            return "Fake provider does not support model: \(modelID)"
        }
    }
}
