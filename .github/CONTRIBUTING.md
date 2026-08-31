# Contributing

This repository contains Ritik Keswani's production personal website. Changes
should be small, reviewable, and verified before they reach `master`.

Automated coding tools must also follow [AGENTS.md](../AGENTS.md).

## Branch workflow

1. Start from the latest `dev` branch.
2. Make one focused change.
3. Build and verify the complete site locally.
4. Review affected pages in a browser.
5. Commit and push to `dev` only after review.
6. Promote `dev` to `master` only with explicit approval and a passing build.

`master` is the production branch. Do not test changes there.

## Local setup

Install Ruby 3.3.7 and Bundler, then install the locked dependencies:

```powershell
bundle install
```

Start the local site at <http://127.0.0.1:4000/>:

```powershell
bundle exec jekyll serve --host 127.0.0.1 --port 4000
```

To render the inherited reference examples as drafts:

```powershell
bundle exec jekyll serve --drafts --host 127.0.0.1 --port 4000
```

Validate a generated draft build with:

```powershell
bundle exec ruby script/verify_site.rb _site-drafts --allow-drafts
```

## Required checks

Run both commands before requesting review:

```powershell
bundle exec jekyll build --strict_front_matter
bundle exec ruby script/verify_site.rb _site
```

The verifier checks generated HTML structure, duplicate IDs, internal
links/assets, stylesheet loading, legacy dependency leakage, and accidental
publication of reference drafts.

Layout, styling, and JavaScript changes also require browser review of the
affected pages. Shared changes should cover Home, Blog, Course Reviews, one
post, and 404. Check mobile layouts and reduced-motion behavior when relevant.

## Content and reference material

- Public page sources belong in `_pages` and must declare explicit permalinks
  so source moves cannot change published URLs.
- Production articles belong in `content/_posts`.
- Inherited implementation examples belong in `content/_drafts/reference`
  and are not included in normal builds.
- Legacy theme notes belong in `docs/reference`, which Jekyll excludes.
- Do not remove reference-only components until their examples have been
  reviewed and removal is explicitly approved.

## Pull requests

Describe the user-visible effect, verification performed, and any deferred
work. CI must pass before a pull request is merged. Never commit generated
`_site` output, temporary screenshots, credentials, or local planning files.
