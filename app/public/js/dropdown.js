function close_dropdowns() {
    for (const dropdown of Array.from(
        document.querySelectorAll(".inner.open"),
    )) {
        dropdown.classList.remove("open");
    }
}

globalThis.open_dropdown = (event) => {
    event.stopImmediatePropagation();
    let target = event.target;

    while (!target.matches(".dropdown")) {
        target = target.parentElement;
    }

    // close all others
    close_dropdowns();

    // open
    setTimeout(() => {
        for (const dropdown of Array.from(target.querySelectorAll(".inner"))) {
            // check y
            const box = target.getBoundingClientRect();

            let parent = dropdown.parentElement;

            while (!parent.matches("html, .window")) {
                parent = parent.parentElement;
            }

            let parent_height = parent.getBoundingClientRect().y;

            if (parent.nodeName === "HTML") {
                parent_height = window.screen.height;
            }

            const scroll = window.scrollY;
            const height = parent_height;
            const y = box.y + scroll;

            if (y > height - scroll - 375) {
                dropdown.classList.add("top");
            } else {
                dropdown.classList.remove("top");
            }

            // open
            dropdown.classList.add("open");

            if (dropdown.classList.contains("open")) {
                dropdown.removeAttribute("aria-hidden");
            } else {
                dropdown.setAttribute("aria-hidden", "true");
            }
        }
    }, 5);
};

globalThis.init_dropdowns = (bind_to) => {
    for (const dropdown of Array.from(document.querySelectorAll(".inner"))) {
        dropdown.setAttribute("aria-hidden", "true");
    }

    bind_to.addEventListener("click", (event) => {
        if (
            event.target.matches(".dropdown") ||
            event.target.matches("[exclude=dropdown]")
        ) {
            return;
        }

        for (const dropdown of Array.from(
            document.querySelectorAll(".inner.open"),
        )) {
            dropdown.classList.remove("open");
        }
    });
};

document.addEventListener("DOMContentLoaded", () => {
    init_dropdowns(document.body);
});
