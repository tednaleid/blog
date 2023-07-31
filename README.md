# blog

found at: [http://www.naleid.com/](http://www.naleid.com)


Updates happen to blog via github pages jekyll processing.  Push to this repo to update the blog, they should appear after a little bit.

see:
- https://help.github.com/articles/using-jekyll-as-a-static-site-generator-with-github-pages/
- https://help.github.com/articles/configuring-jekyll/


config is in docs/_config.yml

To create a new post, create a new markdown file in docs/_posts/ with a header similar to other existing posts

Posts won't show up if they are dated in the future.



# Testing/Running Locally

As of 2023-07-06, `ruby-install` does [not work with OpenSSL 3.1](https://github.com/rvm/rvm/issues/5365), you'll want to explicitly `brew install openssl@3.0` to use that. 

This will likely be fixed soon, but if you have a bunch of dependencies that are 
on OpenSSL 3.1, it might be easiest to just wipe out `brew` and reinstall.


Install [`chruby` and `jekyll`](https://jekyllrb.com/docs/installation/macos/)

```
brew install chruby ruby-install xz

ruby-install ruby 3.2.2
```

You'll also want to put the bits that the install of `chruby` mentions in your shell rc file:

```
## brew install chruby ruby-install xz
if [[ -f "/opt/homebrew/opt/chruby/share/chruby/chruby.sh" ]]; then
  source /opt/homebrew/opt/chruby/share/chruby/chruby.sh
fi

## allows a .ruby-version file to be used to set the ruby version
if [[ -f "/opt/homebrew/opt/chruby/share/chruby/auto.sh" ]]; then
  source /opt/homebrew/opt/chruby/share/chruby/auto.sh
fi
```

now, when you're in the root dir, `which ruby` should show that it is using `3.2.2`

`jekyll` commands will be run in the `docs` directory (where the source for the blog is)

```shell
cd docs
```

Now install the gems for jekyll and webrick

```shell
bundle install
```

and you should be able to serve now (with livereload support built-in):

```shell
bundle exec jekyll serve --livereload
```

Then go to http://127.0.0.1:4000