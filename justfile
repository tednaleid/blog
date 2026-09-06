# ABOUTME: Build, serve, and validate the Jekyll blog that publishes to www.naleid.com.
# ABOUTME: Jekyll source lives in docs/; recipes run there via the working-directory attribute.

set unstable := true

# show available recipes
default:
    @just --list

# install the pinned ruby and all gems
[working-directory('docs')]
bootstrap:
    mise install
    bundle install

# serve at http://127.0.0.1:4000 with live reload
[working-directory('docs')]
serve *ARGS:
    bundle exec jekyll serve --livereload {{ ARGS }}

# serve including drafts in docs/_drafts and future-dated posts
serve-drafts: (serve "--drafts --future")

# build into docs/_site
[working-directory('docs')]
build:
    bundle exec jekyll build

# build the way CI and the deploy do
[working-directory('docs')]
build-prod:
    JEKYLL_ENV=production bundle exec jekyll build

# build and validate internal links, images, and scripts
check: build-prod links

# validate the built site's internal links, images, and scripts
[working-directory('docs')]
links:
    bundle exec htmlproofer _site \
        --disable-external \
        --no-enforce-https \
        --allow-hash-href \
        --checks Links,Images,Scripts \
        --swap-urls 'https\://www\.naleid\.com:'

# audit every external link and flag http:// ones, slow and depends on other people's servers
[working-directory('docs')]
links-external:
    bundle exec htmlproofer _site \
        --allow-hash-href \
        --checks Links,Images,Scripts \
        --swap-urls 'https\://www\.naleid\.com:' \
        --ignore-status-codes 403,429 \
        --hydra '{"max_concurrency": 10}'

# start a new post in docs/_posts and print its path
new TITLE:
    #!/usr/bin/env bash
    set -euo pipefail
    slug=$(printf '%s' "{{ TITLE }}" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    path="docs/_posts/$(date +%Y-%m-%d)-${slug}.markdown"
    if [ -e "$path" ]; then echo "$path already exists" >&2; exit 1; fi
    printf -- '---\ntitle: "%s"\n---\n\n' "{{ TITLE }}" > "$path"
    echo "$path"

# report common configuration problems
[working-directory('docs')]
doctor:
    bundle exec jekyll doctor

# update gems within the constraints in docs/Gemfile
[working-directory('docs')]
update:
    bundle update

# remove build output and caches
clean:
    rm -rf docs/_site docs/.jekyll-cache

# install a pre-commit hook that runs `just check`
install-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    hook="$(git rev-parse --git-dir)/hooks/pre-commit"
    printf '#!/usr/bin/env bash\nexec just check\n' > "$hook"
    chmod +x "$hook"
    echo "installed $hook"
