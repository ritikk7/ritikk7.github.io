# Repository Instructions

These instructions apply to all automated coding agents working in this
repository.

## Branch and deployment safety

- Make changes on `dev`. Treat `master` as production.
- Do not commit, push, merge, or deploy unless the user explicitly requests it.
- Before pushing, fetch the relevant remote branch and require a fast-forward.
- Never use production as the test environment.
- Keep commits focused and reversible.

## Preserve site behavior

- Preserve public URLs, content, navigation, and visible behavior unless a
  change is explicitly approved.
- Treat CSS class names as contracts between layouts and Sass. When changing a
  class, update and test every matching selector.
- Keep inherited examples in `_drafts/reference/`; do not move them back into
  `_posts` or delete their supporting components without approval.
- Do not edit generated files under `_site`.
- Do not commit `_site`, temporary screenshots, or
  `.website-cleanup-plan.md`.

## Required verification

Run these checks for every code or content change:

```powershell
bundle exec jekyll build --strict_front_matter
bundle exec ruby script/verify_site.rb _site
```

For layout, CSS, or JavaScript changes, also:

- Preview the affected pages locally.
- Check Home, Blog, Course Reviews, one post, and 404 when shared code changes.
- Review desktop and mobile behavior when layout can be affected.
- Check the browser console for errors.
- Verify reduced-motion behavior when animation code changes.

Reference drafts can be checked separately with:

```powershell
bundle exec jekyll build --drafts --destination _site-drafts --strict_front_matter
bundle exec ruby script/verify_site.rb _site-drafts --allow-drafts
```

## Repository context

- The site is built with Jekyll through the `github-pages` gem.
- `assets/css/main.scss` is the only site stylesheet entry point.
- `assets/js/particles-init.js` and particles.js are Home-only.
- `assets/js/ityped-init.js` and iTyped are limited to shared-header pages.
- If `.website-cleanup-plan.md` exists locally, use it as the working decision
  and verification log, but never add it to Git.
