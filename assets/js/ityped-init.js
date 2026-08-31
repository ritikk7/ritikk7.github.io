document.addEventListener("DOMContentLoaded", function () {
    const bioElement = document.querySelector(".description[data-bio]");
    const bioTarget = document.querySelector("#ityped-bio");

    if (!bioElement || !bioTarget) {
        return;
    }

    const bioText = bioElement.getAttribute("data-bio");
    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (!bioText || prefersReducedMotion || !window.ityped || typeof window.ityped.init !== "function") {
        bioTarget.textContent = bioText || "";
        return;
    }

    bioTarget.textContent = "";
    window.ityped.init(bioTarget, {
        strings: [bioText],
        loop: true,
        typeSpeed: 100,
        backSpeed: 50,
        startDelay: 500,
        showCursor: true,
        cursorChar: "|"
    });
});
