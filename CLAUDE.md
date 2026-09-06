# blog

Jekyll site published to www.naleid.com. Source is in `docs/`; the repo root
holds tooling only.

## Build and test

- `just check` - build with production settings and validate internal links (what CI runs)
- `just serve` - local preview at http://127.0.0.1:4000 with live reload
- `just build` - build into `docs/_site`
- `just new "Title"` - scaffold a post in `docs/_posts`
- `just links-external` - audit external links, slow and network dependent, not in CI
- `just clean` - remove build output and caches, never bare `rm -rf`

Run `just check` before committing. `just install-hooks` wires it to pre-commit.

## Conventions

Post front matter carries only `title`, plus `redirect_from` on posts that
predate the current URL scheme. Layouts are assigned by `jekyll-default-layout`,
so do not add `layout:` to front matter.

`docs/_layouts`, `docs/_includes`, and `docs/_sass/minima.scss` deliberately
override the minima theme. Anything not overridden comes from the gem, so do
not copy theme files in without a reason to change them.

Images go in `docs/images/YYYY/MM/` and are referenced site-relative
(`/images/...`), never with an absolute host.

## Deploys

Pushing to `master` runs `.github/workflows/pages.yml`, which runs `just check`
and deploys only if it passes. There is no manual deploy step.
