(() => {
    const contentElement = document.getElementById("content");
    const sanitizeOptions = {
        USE_PROFILES: { html: true },
        ADD_TAGS: ["details", "summary", "kbd"],
        FORBID_TAGS: ["style"],
        FORBID_ATTR: ["style"],
        ALLOW_DATA_ATTR: false,
        ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto|tel):)/i,
        RETURN_DOM_FRAGMENT: true
    };
    const renderInterval = 1000 / 8;
    let pendingContent = "";
    let renderScheduled = false;
    let heightScheduled = false;
    let lastRenderTime = 0;
    let lastRenderedContent = null;
    let lastRenderUsedMarkdown = false;
    let markedRendererConfigured = false;

    const markdownRenderer = {
        code(token) {
            const language = normalizedCodeLanguage(token.lang);
            const languageClass = language ? ` class="language-${escapeAttribute(language)}"` : "";
            const languageLabel = language || "text";
            const code = token.escaped ? token.text : escapeHTML(token.text);

            return `
<div class="code-block">
<div class="code-block-header"><span class="code-block-language">${escapeHTML(languageLabel)}</span></div>
<pre><code${languageClass}>${code}</code></pre>
</div>
`;
        },

        listitem(item) {
            const className = item.task ? ' class="task-list-item"' : '';
            return `<li${className}>${this.parser.parse(item.tokens)}</li>\n`;
        },

        checkbox({ checked }) {
            const marker = checked ? "\u2611" : "\u25A1";
            return `<span class="task-list-marker" aria-hidden="true">${marker}</span> `;
        }
    };

    function normalizedCodeLanguage(language) {
        const languageName = String(language || "").trim().split(/\s+/)[0] || "";
        return languageName.replace(/^language-/i, "");
    }

    const htmlEscapeMap = { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" };
    function escapeHTML(value) {
        return String(value).replace(/[&<>"']/g, (char) => htmlEscapeMap[char]);
    }

    function escapeAttribute(value) {
        return escapeHTML(value).replace(/[^A-Za-z0-9_+.#-]/g, "-");
    }

    function postHeight() {
        heightScheduled = false;
        const height = Math.ceil(contentElement.getBoundingClientRect().height);
        const heightUpdateHandler = window.webkit?.messageHandlers?.heightUpdate;
        heightUpdateHandler?.postMessage(height);
    }

    function requestHeightUpdate() {
        if (heightScheduled) {
            return;
        }
        heightScheduled = true;
        requestAnimationFrame(postHeight);
    }

    function hasMarkdownRenderer() {
        return window.streamingRendererMarked?.parse
            && window.streamingRendererMarked?.use
            && window.streamingRendererDOMPurify?.sanitize
            && window.streamingRendererMorphdom;
    }

    function configureMarkedRenderer() {
        if (markedRendererConfigured) {
            return;
        }

        window.streamingRendererMarked.use({ renderer: markdownRenderer });
        markedRendererConfigured = true;
    }

    function renderPlainText(content) {
        contentElement.classList.add("plain-text");
        if (contentElement.textContent !== content || contentElement.childNodes.length !== 1) {
            contentElement.textContent = content;
        }
    }

    function attachDetailsEventListeners() {
        contentElement.querySelectorAll("details:not([data-toggle-listener])").forEach((details) => {
            details.setAttribute("data-toggle-listener", "true");
            details.addEventListener("toggle", () => {
                requestHeightUpdate();
                requestAnimationFrame(requestHeightUpdate);
            });
        });
    }

    function highlightCodeBlocks() {
        if (!window.streamingRendererHLJS?.highlightElement) {
            return;
        }

        contentElement.querySelectorAll("pre code").forEach((codeElement) => {
            try {
                window.streamingRendererHLJS.highlightElement(codeElement);
            } catch {
            }
        });
    }

    function renderMarkdown(content) {
        try {
            configureMarkedRenderer();
            const dirtyHTML = window.streamingRendererMarked.parse(content, { gfm: true });
            const cleanFragment = window.streamingRendererDOMPurify.sanitize(
                String(dirtyHTML),
                sanitizeOptions
            );
            const targetElement = document.createElement("div");
            targetElement.append(cleanFragment);

            contentElement.classList.remove("plain-text");
            window.streamingRendererMorphdom(contentElement, targetElement, {
                childrenOnly: true,
                onBeforeElUpdated(fromElement, toElement) {
                    if (fromElement.tagName === "DETAILS") {
                        toElement.open = fromElement.open;
                    }

                    return !fromElement.isEqualNode(toElement);
                }
            });

            // Attach event listeners to details elements after rendering
            highlightCodeBlocks();
            attachDetailsEventListeners();
        } catch {
            renderPlainText(content);
        }
    }

    function scheduleRender() {
        if (renderScheduled) {
            return;
        }
        renderScheduled = true;
        requestAnimationFrame(renderContent);
    }

    function renderContent(timestamp) {
        if (lastRenderTime > 0 && timestamp - lastRenderTime < renderInterval) {
            requestAnimationFrame(renderContent);
            return;
        }

        renderScheduled = false;
        lastRenderTime = timestamp;
        const shouldUseMarkdown = hasMarkdownRenderer();
        const contentChanged = lastRenderedContent !== pendingContent || lastRenderUsedMarkdown !== shouldUseMarkdown;

        if (contentChanged) {
            shouldUseMarkdown ? renderMarkdown(pendingContent) : renderPlainText(pendingContent);
            lastRenderedContent = pendingContent;
            lastRenderUsedMarkdown = shouldUseMarkdown;
        }
        requestHeightUpdate();
    }

    window.streamingRenderer = {
        configure(configuration) {
            const colorScheme = configuration.colorScheme === "dark" ? "dark" : "light";
            document.documentElement.style.colorScheme = colorScheme;
            document.documentElement.style.setProperty("--streaming-text-color", configuration.color);
            document.documentElement.style.setProperty("--streaming-link-color", configuration.linkColor);
            document.documentElement.style.setProperty("--streaming-font-size", `${configuration.fontSize}px`);
            requestHeightUpdate();
        },

        setContent(nextContent) {
            pendingContent = nextContent || "";
            scheduleRender();
        },

        requestHeightUpdate
    };

    window.addEventListener("streamingRendererMarkedReady", () => {
        lastRenderedContent = null;
        scheduleRender();
    });
    window.addEventListener("resize", requestHeightUpdate);
    requestHeightUpdate();
})();
