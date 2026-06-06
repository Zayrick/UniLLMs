(() => {
    const contentElement = document.getElementById("content");
    const renderInterval = 1000 / 20;
    let pendingContent = "";
    let renderScheduled = false;
    let heightScheduled = false;
    let lastRenderTime = 0;

    function postHeight() {
        heightScheduled = false;
        const height = Math.ceil(contentElement.getBoundingClientRect().height);
        window.webkit.messageHandlers.heightUpdate.postMessage(height);
    }

    function requestHeightUpdate() {
        if (heightScheduled) {
            return;
        }
        heightScheduled = true;
        requestAnimationFrame(postHeight);
    }

    function renderContent(timestamp) {
        if (lastRenderTime > 0 && timestamp - lastRenderTime < renderInterval) {
            requestAnimationFrame(renderContent);
            return;
        }

        renderScheduled = false;
        lastRenderTime = timestamp;
        if (contentElement.textContent !== pendingContent) {
            contentElement.textContent = pendingContent;
        }
        requestHeightUpdate();
    }

    window.streamingRenderer = {
        configure(configuration) {
            document.body.style.color = configuration.color;
            document.body.style.fontSize = `${configuration.fontSize}px`;
            document.body.style.lineHeight = `${configuration.lineHeight}px`;
            requestHeightUpdate();
        },

        setContent(nextContent) {
            pendingContent = nextContent || "";
            if (renderScheduled) {
                return;
            }
            renderScheduled = true;
            requestAnimationFrame(renderContent);
        },

        requestHeightUpdate
    };

    window.addEventListener("resize", requestHeightUpdate);
    requestHeightUpdate();
})();
