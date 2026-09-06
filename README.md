# blog

Source for [www.naleid.com](https://www.naleid.com).

Jekyll source lives in `docs/`. Pushing to `master` triggers
`.github/workflows/pages.yml`, which builds the site and deploys it to GitHub
Pages. A push whose build or link check fails does not deploy.

## Setup

Requires [`mise`](https://mise.jdx.dev), [`just`](https://just.systems), and
optionally [`direnv`](https://direnv.net).

```shell
brew install mise just direnv
```

`mise` reads `.ruby-version` and supplies the pinned ruby. `direnv` reads
`.envrc` and points `BUNDLE_GEMFILE` at `docs/Gemfile` so `bundle exec` works
from any directory in the repo.

```shell
direnv allow
just bootstrap
```

## Working on the blog

```shell
just                 # list every recipe
just serve           # http://127.0.0.1:4000 with live reload
just new "Post Title"  # create docs/_posts/YYYY-MM-DD-post-title.markdown
just check           # build and validate internal links, what CI runs
```

Posts dated in the future are not published. `just serve-drafts` renders them
along with anything in `docs/_drafts`.

Front matter needs only a `title`. Layouts are assigned by
`jekyll-default-layout`, and `redirect_from` preserves URLs from the original
`/blog/YYYY/MM/DD/slug` scheme.

## Checking links

`just check` validates links and images within the site and is fast enough to
run on every commit. It ignores the outside world.

`just links-external` follows every external link and flags any that are dead
or still on `http`. It depends on other people's servers staying up, so it is
run by hand rather than in CI.
