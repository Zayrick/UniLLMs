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

    const taskListRenderer = {
        listitem(item) {
            const className = item.task ? ' class="task-list-item"' : '';
            return `<li${className}>${this.parser.parse(item.tokens)}</li>\n`;
        },

        checkbox({ checked }) {
            const marker = checked ? "\u2611" : "\u25A1";
            return `<span class="task-list-marker" aria-hidden="true">${marker}</span> `;
        }
    };

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
        return window.streamingRendererMarked
            && typeof window.streamingRendererMarked.parse === "function"
            && typeof window.streamingRendererMarked.use === "function"
            && window.streamingRendererDOMPurify
            && typeof window.streamingRendererDOMPurify.sanitize === "function"
            && typeof window.streamingRendererMorphdom === "function";
    }

    function configureMarkedRenderer() {
        if (markedRendererConfigured) {
            return;
        }

        window.streamingRendererMarked.use({ renderer: taskListRenderer });
        markedRendererConfigured = true;
    }

    function renderPlainText(content) {
        contentElement.classList.add("plain-text");
        if (contentElement.textContent !== content || contentElement.childNodes.length !== 1) {
            contentElement.textContent = content;
        }
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
        if (
            lastRenderedContent !== pendingContent
            || lastRenderUsedMarkdown !== shouldUseMarkdown
        ) {
            if (shouldUseMarkdown) {
                renderMarkdown(pendingContent);
            } else {
                renderPlainText(pendingContent);
            }
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
