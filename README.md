# blog

found at: [http://www.naleid.com/](http://www.naleid.com)


Updates happen to blog via github pages jekyll processing.  Push to this repo to update the blog, they should appear after a little bit.

see:
- https://help.github.com/articles/using-jekyll-as-a-static-site-generator-with-github-pages/
- https://help.github.com/articles/configuring-jekyll/


config is in docs/_config.yml

To create a new post, create a new markdown file in docs/_posts/ with a header similar to other existing posts



# Testing/Running Locally

Use [`direnv`](https://direnv.net/) to automatically `rbenv init -` into your current shell when in this directory.  
You don't need to have `rbenv` in your global zsh/bash rc files

Install [`rbenv` and `jekyll`](https://jekyllrb.com/docs/installation/macos/)

```
brew install rbenv

rbenv install 3.0.1
```

`jekyll` commands will be run in the `docs` directory (where the source for the blog is)

```shell
cd docs
```

Now install the gems for jekyll and webrick

```shell
bundle install
```

and you should be able to serve now:

```shell
bundle exec jekyll serve
```

Then go to http://127.0.0.1:4000





