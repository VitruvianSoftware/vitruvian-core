// vitruviansoftware.dev — theme toggle, mobile navigation and the image
// lightbox. No dependencies.
(function () {
  "use strict";

  var root = document.documentElement;

  var themeToggle = document.querySelector("[data-theme-toggle]");
  if (themeToggle) {
    themeToggle.addEventListener("click", function () {
      var next = root.getAttribute("data-theme") === "light" ? "dark" : "light";
      root.setAttribute("data-theme", next);
      try {
        localStorage.setItem("theme", next);
      } catch (e) {
        // Private mode or storage disabled: the toggle still works for this page.
      }
    });
  }

  var navToggle = document.querySelector("[data-nav-toggle]");
  var navLinks = document.getElementById("nav-links");
  if (navToggle && navLinks) {
    var setOpen = function (open) {
      navLinks.classList.toggle("is-open", open);
      navToggle.setAttribute("aria-expanded", String(open));
      navToggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    };
    navToggle.addEventListener("click", function () {
      setOpen(!navLinks.classList.contains("is-open"));
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") setOpen(false);
    });
  }

  // ── Image lightbox ────────────────────────────────────────────────────────
  // Content images open full size in a <dialog>. The standard is documented in
  // this site's AGENTS.md: every image in .prose, every img[data-lightbox] and
  // every image inside [data-expandable] is expandable, unless it is inside a
  // link, carries (or sits inside) data-no-lightbox, or is a tiny mark.
  var EXPANDABLE = ".prose img, img[data-lightbox], [data-expandable] img";
  var TINY = 96; // px: anything narrower is an icon, avatar or logo.

  var isSvg = function (img) {
    return /\.svg(?:[?#]|$)/i.test(img.currentSrc || img.src);
  };

  // The caption, in order of preference: a <figcaption>; an <em> right after
  // the image in the same paragraph (Markdown `![..](..)` then `*Figure N: ..*`
  // on the next line); a paragraph holding only an <em>, right after an
  // image-only paragraph; the alt text. Returns nodes to clone, or a string.
  var captionFor = function (img) {
    var figure = img.closest("figure");
    var figcaption = figure && figure.querySelector("figcaption");
    if (figcaption) return figcaption;

    var next = img.nextElementSibling;
    while (next && next.tagName === "BR") next = next.nextElementSibling;
    if (next && next.tagName === "EM") return next;

    var para = img.parentElement;
    if (
      para &&
      para.tagName === "P" &&
      para.children.length === 1 &&
      para.textContent.trim() === ""
    ) {
      var after = para.nextElementSibling;
      if (
        after &&
        after.tagName === "P" &&
        after.children.length === 1 &&
        after.firstElementChild.tagName === "EM" &&
        after.textContent.trim() === after.firstElementChild.textContent.trim()
      ) {
        return after.firstElementChild;
      }
    }
    return img.getAttribute("alt") || "";
  };

  var dialog = null;
  var parts = {};
  var trigger = null;
  var zoomed = false;

  var build = function () {
    dialog = document.createElement("dialog");
    dialog.className = "lightbox";
    dialog.setAttribute("aria-label", "Image viewer");
    dialog.innerHTML =
      '<div class="lightbox-frame">' +
      '  <div class="lightbox-bar">' +
      '    <span class="lightbox-label">Plate</span>' +
      '    <div class="lightbox-actions">' +
      '      <button type="button" class="lightbox-btn" data-lightbox-zoom aria-pressed="false">1:1</button>' +
      '      <a class="lightbox-btn" data-lightbox-original target="_blank" rel="noopener">Open original</a>' +
      '      <button type="button" class="lightbox-btn" data-lightbox-close autofocus>Close <kbd>Esc</kbd></button>' +
      "    </div>" +
      "  </div>" +
      '  <div class="lightbox-stage" data-lightbox-stage><img class="lightbox-img" alt=""></div>' +
      '  <p class="lightbox-caption" data-lightbox-caption></p>' +
      "</div>";
    document.body.appendChild(dialog);

    parts.frame = dialog.querySelector(".lightbox-frame");
    parts.stage = dialog.querySelector("[data-lightbox-stage]");
    parts.img = dialog.querySelector(".lightbox-img");
    parts.caption = dialog.querySelector("[data-lightbox-caption]");
    parts.zoom = dialog.querySelector("[data-lightbox-zoom]");
    parts.original = dialog.querySelector("[data-lightbox-original]");

    dialog
      .querySelector("[data-lightbox-close]")
      .addEventListener("click", function () {
        dialog.close();
      });
    parts.zoom.addEventListener("click", function () {
      setZoom(!zoomed);
    });
    parts.img.addEventListener("click", function () {
      if (!parts.zoom.hidden) setZoom(!zoomed);
    });
    // A click on the backdrop lands on the dialog itself; one on the empty
    // stage around the image lands on the stage. Either closes.
    dialog.addEventListener("click", function (event) {
      if (event.target === dialog || event.target === parts.stage)
        dialog.close();
    });
    dialog.addEventListener("close", function () {
      root.classList.remove("lightbox-open");
      parts.img.removeAttribute("src");
      if (trigger) trigger.focus({ preventScroll: true });
      trigger = null;
    });
    window.addEventListener("resize", function () {
      if (dialog.open) relayout();
    });
  };

  // Size the image explicitly rather than trusting its intrinsic size: the
  // site's SVG diagrams declare width="100%" and only a viewBox, so the
  // browser reports a meaningless natural size for them. The aspect ratio
  // comes from the decoded image when it has one, else from the trigger as
  // laid out on the page.
  var layout = function () {
    var img = parts.img;
    var svg = isSvg(img);
    var rect = trigger.getBoundingClientRect();
    var ratio =
      img.naturalWidth && img.naturalHeight && !svg
        ? img.naturalHeight / img.naturalWidth
        : rect.height / rect.width || 0.6;
    var maxW = Math.min(1400, window.innerWidth * 0.94);
    var maxH = window.innerHeight * 0.84 - parts.caption.offsetHeight;
    var fitW = Math.min(maxW, maxH / ratio);
    // A raster image is never blown up past its own pixels; an SVG scales
    // cleanly, so it always fills the space.
    if (!svg && img.naturalWidth) fitW = Math.min(fitW, img.naturalWidth);

    // Zoom: a raster image at 1:1, an SVG at twice its fitted size, so dense
    // diagrams can be read up close. Offered only when it enlarges.
    var zoomW = svg ? Math.min(fitW * 2, 3200) : img.naturalWidth || fitW;
    var canZoom = zoomW > fitW + 32;
    parts.zoom.hidden = !canZoom;
    parts.zoom.textContent = svg ? "Zoom 2×" : "1:1";
    if (!canZoom) zoomed = false;

    parts.stage.style.maxWidth = Math.round(maxW) + "px";
    parts.stage.style.maxHeight = Math.round(maxH) + "px";
    var w = zoomed ? zoomW : fitW;
    img.style.width = Math.round(w) + "px";
    img.style.height = Math.round(w * ratio) + "px";
    // The frame follows the image, so a long caption wraps under it rather
    // than stretching the plate.
    parts.frame.style.width = Math.round(Math.min(w, maxW)) + "px";
    dialog.classList.toggle("is-zoomed", zoomed);
    dialog.classList.toggle("can-zoom", canZoom);
    parts.zoom.setAttribute("aria-pressed", String(zoomed));
  };

  // Twice: the caption wraps to the frame, the frame follows the image, and
  // the image's room depends on the caption's height.
  var relayout = function () {
    layout();
    layout();
  };

  var setZoom = function (on) {
    zoomed = on;
    layout();
    if (!on) parts.stage.scrollTo(0, 0);
  };

  var open = function (img) {
    if (!dialog) build();
    trigger = img;
    zoomed = false;

    var src = img.currentSrc || img.src;
    var caption = captionFor(img);
    parts.caption.textContent = "";
    if (typeof caption === "string") {
      parts.caption.textContent = caption;
    } else {
      Array.prototype.forEach.call(caption.childNodes, function (node) {
        parts.caption.appendChild(node.cloneNode(true));
      });
    }
    parts.caption.hidden = parts.caption.textContent.trim() === "";
    parts.img.alt = img.getAttribute("alt") || "";
    parts.original.href = src;

    parts.img.onload = relayout;
    parts.img.src = src;
    root.classList.add("lightbox-open");
    dialog.showModal();
    relayout();
  };

  var enhance = function (img) {
    if (img.closest("a, [data-no-lightbox]") || img.dataset.lightboxReady)
      return;
    var explicit =
      img.hasAttribute("data-lightbox") || img.closest("[data-expandable]");
    // An SVG's natural size means nothing (see layout), so judge it by the
    // width it is given or drawn at; 0 means not laid out yet, which is not "tiny".
    var size =
      parseFloat(img.getAttribute("width")) ||
      (isSvg(img) ? img.getBoundingClientRect().width : img.naturalWidth);
    if (!explicit && size && size < TINY) return;

    img.dataset.lightboxReady = "true";
    img.classList.add("is-expandable");
    img.setAttribute("tabindex", "0");
    img.setAttribute("role", "button");
    var alt = img.getAttribute("alt");
    img.setAttribute(
      "aria-label",
      alt ? "Expand image: " + alt : "Expand image",
    );
    img.setAttribute("aria-haspopup", "dialog");
  };

  if (typeof HTMLDialogElement === "function") {
    Array.prototype.forEach.call(
      document.querySelectorAll(EXPANDABLE),
      function (img) {
        // Wait for a lazy or slow image to know whether it is tiny.
        if (img.complete) enhance(img);
        else
          img.addEventListener(
            "load",
            function () {
              enhance(img);
            },
            { once: true },
          );
      },
    );

    document.addEventListener("click", function (event) {
      var img =
        event.target.closest && event.target.closest("img.is-expandable");
      if (img) open(img);
    });
    document.addEventListener("keydown", function (event) {
      var img = event.target;
      if (!img.classList || !img.classList.contains("is-expandable")) return;
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        open(img);
      }
    });
  }

  // ── Multi-marketplace ecosystem filter on /ai/ ──────────────────────────
  var filterBar = document.querySelector("[data-marketplace-filter-bar]");
  if (filterBar) {
    var filterBtns = Array.prototype.slice.call(
      filterBar.querySelectorAll("[data-marketplace-filter]"),
    );
    var cards = Array.prototype.slice.call(
      document.querySelectorAll("[data-extension-card]"),
    );
    var sections = Array.prototype.slice.call(
      document.querySelectorAll("[data-extension-section]"),
    );
    var statusEl = document.querySelector("[data-marketplace-status]");

    var applyFilter = function (ecoId, updateHash) {
      var target = ecoId || "all";
      var visibleCount = 0;

      filterBtns.forEach(function (btn) {
        var active = btn.getAttribute("data-marketplace-filter") === target;
        btn.classList.toggle("is-active", active);
        btn.setAttribute("aria-pressed", String(active));
      });

      cards.forEach(function (card) {
        var list = (card.getAttribute("data-ecosystems") || "all").split(/\s+/);
        var match = target === "all" || list.indexOf(target) !== -1;
        card.hidden = !match;
        if (match) visibleCount += 1;
      });

      sections.forEach(function (sec) {
        var anyVisible =
          sec.querySelectorAll("[data-extension-card]:not([hidden])").length >
          0;
        sec.hidden = !anyVisible;
      });

      if (statusEl) {
        statusEl.textContent =
          target === "all"
            ? "Showing all " +
              visibleCount +
              " first-party plugins, MCP servers, skills, and signed desktop/mobile extensions."
            : "Showing " +
              visibleCount +
              " extension" +
              (visibleCount === 1 ? "" : "s") +
              " compatible with " +
              target +
              ".";
      }

      if (updateHash && window.history && window.history.replaceState) {
        var hash =
          target === "all" ? window.location.pathname : "#eco-" + target;
        window.history.replaceState(null, "", hash);
      }
    };

    filterBtns.forEach(function (btn) {
      btn.addEventListener("click", function () {
        applyFilter(btn.getAttribute("data-marketplace-filter"), true);
      });
    });

    if (window.location.hash && window.location.hash.indexOf("#eco-") === 0) {
      applyFilter(window.location.hash.slice(5), false);
    }

    window.addEventListener("hashchange", function () {
      if (window.location.hash && window.location.hash.indexOf("#eco-") === 0) {
        applyFilter(window.location.hash.slice(5), false);
      }
    });
  }
})();
