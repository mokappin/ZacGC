function userLogout() {
    if (!confirm("Are you sure you would like to do this?")) {
        return;
    }

    fetch("/api/v1/users/logout", {
        method: "POST",
    })
        .then((res) => res.json())
        .then((res) => {
            if (res.ok) {
                window.location.href = "/";
            } else {
                alert(`logout failed: ${res.message}`);
            }
        });
}

if (document.getElementById("profile_css")) {
    document.getElementById("profile_css").remove();
}

// editor
globalThis.init_editor = (
    name = "editor",
    mode = "markdown",
    element = "editor_tab",
    content_element = "editor_content",
    read_only = false,
) => {
    globalThis[name] = CodeMirror(document.getElementById(element), {
        value: (document.getElementById(content_element) || { innerHTML: "" })
            .innerHTML,
        keyMap: "default",
        mode,
        lineWrapping: true,
        readOnly: read_only,
        lineNumbers: true,
        autoCloseBrackets: true,
        autofocus: true,
        viewportMargin: Number.POSITIVE_INFINITY,
        inputStyle: "contenteditable",
        indentUnit: 4,
        tabSize: 4,
        indentWithTabs: false,
        placeholder: "",
        extraKeys: {
            Home: "goLineLeft",
            End: "goLineRight",
            Tab: "insertSoftTab",
        },
    });
};

globalThis.show_html_editor = () => {
    document.getElementById("html_editor").classList.remove("hidden");
    document.getElementById("css_editor").classList.add("hidden");

    document.getElementById("html_editor_button").classList.add("active");
    document.getElementById("css_editor_button").classList.remove("active");
};

globalThis.show_css_editor = () => {
    document.getElementById("html_editor").classList.add("hidden");
    document.getElementById("css_editor").classList.remove("hidden");

    document.getElementById("html_editor_button").classList.remove("active");
    document.getElementById("css_editor_button").classList.add("active");

    if (!CSS_EDITOR_INITIALIZED) {
        CSS_EDITOR_INITIALIZED = true;
        css_editor.refresh();
    }
};

function render_preview() {
    if (globalThis.PREVIEW_OLD_BLOB) {
        URL.revokeObjectURL(globalThis.PREVIEW_OLD_BLOB);
    }

    fetch(
        `/api/v1/preview?theme=${document.documentElement.getAttribute("data-theme") || "light"}&stylesheet=${window.location.origin}/public/style.css`,
        {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                html: editor.getValue(),
                css: css_editor.getValue(),
            }),
        },
    )
        .then((res) => res.json())
        .then((res) => {
            const blob_url = URL.createObjectURL(
                new Blob([res.payload], { type: "text/html" }),
            );
            globalThis.PREVIEW_OLD_BLOB = blob_url;
            document.getElementById("preview_frame").src = blob_url;

            // run animation
            document.getElementById("preview_frame").classList.add("updating");

            setTimeout(() => {
                document
                    .getElementById("preview_frame")
                    .classList.remove("updating");
            }, 150);
        });
}
