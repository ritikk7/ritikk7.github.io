document.addEventListener("DOMContentLoaded", function() {
    const bioElement = document.querySelector(".description");
    const bioText = bioElement.getAttribute("data-bio");  // Pull bio from data attribute

    ityped.init(document.querySelector("#ityped-bio"), {
        strings: [bioText],
        loop: true,
        typeSpeed: 100,
        backSpeed: 50,
        startDelay: 500,
        showCursor: true,
        cursorChar: "|"
    });
});
