---
title: "Using HTTP APIs on the Command Line - Part 3 - ganda"
---

This is part 3 of a series of posts on Using HTTP APIs on the command line:

- [curl](/2017/11/26/using-http-apis-on-the-command-line-1-curl.html) - making requests on the command line
- [jq](/2017/12/17/using-http-apis-on-the-command-line-2-jq.html) - a command-line stream editor for JSON
- [ganda (with a little awk)](/2018/04/04/using-http-apis-on-the-command-line-3-ganda.html) - this post

## What is `ganda`?

`ganda` is an open-source golang app [on github](https://github.com/tednaleid/ganda).  It was designed to be able to do up to millions of parallel HTTP/HTTPS requests in just a few minutes from a single box.

It expects to be piped a stream of urls that it will request in parallel:

```
cat file_of_urls | ganda
```

or if you're averse to [useless uses of `cat`](http://porkmail.org/era/unix/award.html#cat):

```
ganda < file_of_urls
```

(for the rest of the post, I'm going to use `cat`, even though it is "useless" as I find it clearer and easier to switch to some other utility like `head` or `grep` if I don't want a full file.)

## Why `ganda` and not `curl`?

I created `ganda` to fill what I saw as a gap in command-line tooling.  We saw in [part 1](/2017/11/26/using-http-apis-on-the-command-line-1-curl.html) of this series how `curl` can be used to make individual requests which could then be saved or [piped into tools such as `jq`](/2017/12/17/using-http-apis-on-the-command-line-2-jq.html).

`curl` knows how to request a single url, but what if we want to make more than a single request and process all of the results?  Well, you can use a [utility like `xargs`](https://en.wikipedia.org/wiki/Xargs) to create many instances of `curl`:

```
time seq 10000 |\
 awk '{printf "http://localhost:1323/%s\n", $1}' |\
 xargs -I {} -P 8 curl -s {} > /dev/null
```

This creates a sequence of numbers from 1 to 10,000 and pipes them to `awk` to create the urls `http://localhost:1323/1` to `http://localhost:1323/10000`.  Those urls are then piped to `xargs` which uses 8 parallel threads to do `curl` requests to a local server running an [echoserver process](https://github.com/tednaleid/echoserver) running on port `1323`. We throw away the results by piping to `/dev/null` for this test.

`echoserver` simply echos back the path it is passed, so it returns responses from 1 through 10000.

On my 2-core, 3 Ghz mac-mini it takes slightly over 2 minutes, for `xargs` and `curl` to make those 10k requests:

```
seq 10000  0.01s user 0.00s system 84% cpu 0.010 total
awk '{printf "http://localhost:1323/%s\n", $1}'  0.02s user 0.00s system 0% cpu 44.851 total
xargs -I {} -P 8 curl -s {} > /dev/null  110.73s user 84.53s system 237% cpu 1:22.25 total
```

if we instead pipe those urls to `ganda`:

```
time seq 10000 |\
 awk '{printf "http://localhost:1323/%s\n", $1}' |\
 ganda -s > /dev/null
```

It is able to make all 10,000 requests in 1 second:

```
seq 10000  0.00s user 0.00s system 87% cpu 0.008 total
awk '{printf "http://localhost:1323/%s\n", $1}'  0.02s user 0.00s system 2% cpu 0.866 total
ganda -s > /dev/null  0.85s user 0.37s system 106% cpu 1.150 total
```

The one advantage that `curl` does have over `ganda` is that it is likely already installed on your system.  If you have to make hundreds (or more) requests, you'll save time by installing `ganda` first.

## Installing `ganda`

On Macs, you can use [`homebrew`](https://brew.sh/) to install the latest version:

```
brew tap tednaleid/homebrew-ganda
brew install ganda
```

On linux, you can download a binary from the [releases page](https://github.com/tednaleid/ganda/releases) and put it in your path.

or compile it from source if you have the golang toolchain available:

```
go get -u github.com/tednaleid/ganda
```

## How to use `ganda`

`ganda` wants to be piped urls. You can create a list of urls as a pre-step.  This creates `/tmp/list_of_urls` with 3 httpbin urls and then pipes them to ganda:

```
cat << EOF > /tmp/list_of_urls
http://httpbin.org/anything/1
http://httpbin.org/anything/2
http://httpbin.org/anything/3
EOF

cat /tmp/list_of_urls | ganda
```

the output of this is:

```
Response: 200 http://httpbin.org/anything/3
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept-Encoding": "gzip",
    "Connection": "close",
    "Host": "httpbin.org",
    "User-Agent": "Go-http-client/1.1"
  },
  "json": null,
  "method": "GET",
  "url": "http://httpbin.org/anything/3"
}
Response: 200 http://httpbin.org/anything/1
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept-Encoding": "gzip",
    "Connection": "close",
    "Host": "httpbin.org",
    "User-Agent": "Go-http-client/1.1"
  },
  "json": null,
  "method": "GET",
  "url": "http://httpbin.org/anything/1"
}
Response: 200 http://httpbin.org/anything/2
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept-Encoding": "gzip",
    "Connection": "close",
    "Host": "httpbin.org",
    "User-Agent": "Go-http-client/1.1"
  },
  "json": null,
  "method": "GET",
  "url": "http://httpbin.org/anything/2"
}
```

As you can see, the results are not guaranteed to come back in the same order that they were requested (on this run they came back in 3, 1, 2 order).  The `Response: <STATUS_CODE> url` line is written to stderr and the body of the response is written to stdout.  This lets us use a tool like `jq` to process the results:

```
cat /tmp/list_of_urls | ganda | jq -c '[.method, .url]'

Response: 200 http://httpbin.org/anything/2
["GET","http://httpbin.org/anything/2"]
Response: 200 http://httpbin.org/anything/1
["GET","http://httpbin.org/anything/1"]
Response: 200 http://httpbin.org/anything/3
["GET","http://httpbin.org/anything/3"]
```

The `Response` line can be silenced with the `-s` flag so that you only see the info piped to stdout:

```
cat /tmp/list_of_urls | ganda -s | jq -c '[.method, .url]'

["GET","http://httpbin.org/anything/1"]
["GET","http://httpbin.org/anything/2"]
["GET","http://httpbin.org/anything/3"]
```

### Using `awk` to construct urls in a pipeline to `ganda`

Say I have a file of IDs (and other values that vary in the url):

```
cat << EOF > /tmp/list_of_id_and_param
1000 foo
2000 bar
3000 baz
EOF
```

I can use `awk` to construct urls out of that file:

```
cat /tmp/list_of_id_and_param |\
  awk '{printf "http://httpbin.org/anything/%s?value=%s\n", $1, $2}'
```

outputs:

```
http://httpbin.org/anything/1000?value=foo
http://httpbin.org/anything/2000?value=bar
http://httpbin.org/anything/3000?value=baz
```

Instead of creating a file out of that, I'll just pipe it directly to `ganda` and then process the results:

```
cat /tmp/list_of_id_and_param |\
  awk '{printf "http://httpbin.org/anything/%s?value=%s\n", $1, $2}' |\
  ganda -s |\
  jq -c "[.url, .args]"
```

results in:

```
["http://httpbin.org/anything/2000?value=bar",{"value":"bar"}]
["http://httpbin.org/anything/3000?value=baz",{"value":"baz"}]
["http://httpbin.org/anything/1000?value=foo",{"value":"foo"}]
```

## Workers and throttling

*WARNING `ganda` used without some care can easily send more requests than many servers can handle.*  

Please don't abuse it or free services like `httpbin.org` with thousands of requests.  Use it on your own servers however you like.

By default, `ganda` uses 30 parallel workers (goroutines that listen to a channel of incoming requests).  This is the maximum number of requests that will be made in parallel.  You can adjust the number of workers with the `-W` flag, using `-W 1` will make `ganda` use a single worker and a single request at a time:

```
cat /tmp/list_of_urls | ganda -W 1 | grep url
Response: 200 http://httpbin.org/anything/1
  "url": "http://httpbin.org/anything/1"
Response: 200 http://httpbin.org/anything/2
  "url": "http://httpbin.org/anything/2"
Response: 200 http://httpbin.org/anything/3
  "url": "http://httpbin.org/anything/3"
```

You can also throttle the number of requests that are made per second with the `-t <max per second>` flag.  This throttles it to 1 request per second, even though it is using 30 workers:

```
time cat /tmp/list_of_urls | ganda -W 30 -t 1 > /dev/null
Response: 200 http://httpbin.org/anything/1
Response: 200 http://httpbin.org/anything/2
Response: 200 http://httpbin.org/anything/3
cat /tmp/list_of_urls  0.00s user 0.00s system 75% cpu 0.004 total
ganda -W 30 -t 1 > /dev/null  0.01s user 0.01s system 0% cpu 3.131 total
```

## Saving results to individual files

If you want to save the response data rather than using them in a pipe, you can use the `-o <directory>` flag to specify a directory where the individual results should be saved:


```
cat /tmp/list_of_urls | ganda -o /tmp/output
Response: 200 http://httpbin.org/anything/1 -> /tmp/output/http-httpbin-org-anything-1
Response: 200 http://httpbin.org/anything/2 -> /tmp/output/http-httpbin-org-anything-2
Response: 200 http://httpbin.org/anything/3 -> /tmp/output/http-httpbin-org-anything-3
```

It will transform the url into a filename within that directory and save the results:

```
cat /tmp/output/http-httpbin-org-anything-1
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept-Encoding": "gzip",
    "Connection": "close",
    "Host": "httpbin.org",
    "User-Agent": "Go-http-client/1.1"
  },
  "json": null,
  "method": "GET",
  "url": "http://httpbin.org/anything/1"
}
```

If you will be saving more than a few thousand results to files, you likely want to save them in multiple subdirectories otherwise your operating system will be cranky when you `ls` that directory.  `ganda` can hash the url and put the response in a subdirectory with the `-S <subdir length>` flag, use `2` for more than about 5k urls, and `4` for more than 5 million urls:

```
cat /tmp/list_of_urls | ganda -o /tmp/output -S 2
Response: 200 http://httpbin.org/anything/2 -> /tmp/output/64/http-httpbin-org-anything-2
Response: 200 http://httpbin.org/anything/1 -> /tmp/output/99/http-httpbin-org-anything-1
Response: 200 http://httpbin.org/anything/3 -> /tmp/output/b6/http-httpbin-org-anything-3
```

Notice that the files are now in subdirectories within the `/tmp/output` output directory.

## Authentication with headers

Like `curl`, `ganda` supports the `-H <header>` flags to send headers with each request:


```
cat /tmp/list_of_urls | ganda -H "Authorization: Bearer <mytoken>" | grep -E "Authorization|url"
Response: 200 http://httpbin.org/anything/1
    "Authorization": "Bearer <mytoken>",
  "url": "http://httpbin.org/anything/1"
Response: 200 http://httpbin.org/anything/3
    "Authorization": "Bearer <mytoken>",
  "url": "http://httpbin.org/anything/3"
Response: 200 http://httpbin.org/anything/2
    "Authorization": "Bearer <mytoken>",
  "url": "http://httpbin.org/anything/2"
```

## Using other request methods

By default, `ganda` makes `GET` requests.  You can use the `-X <method>` flag to use another request type, ex:

```
cat /tmp/list_of_urls | ganda -X POST | grep -E "method|url"
Response: 200 http://httpbin.org/anything/2
  "method": "POST",
  "url": "http://httpbin.org/anything/2"
Response: 200 http://httpbin.org/anything/1
  "method": "POST",
  "url": "http://httpbin.org/anything/1"
Response: 200 http://httpbin.org/anything/3
  "method": "POST",
  "url": "http://httpbin.org/anything/3"
```

### adding data to the body of the request

`ganda` allows sending a templated request body via the `-d` flag.  If you want the same thing sent with every request you can use a literal string:

```
cat /tmp/list_of_urls | ganda -X POST -d "foo=bar" | grep -E 'data|url'
Response: 200 http://httpbin.org/anything/1
  "data": "foo=bar",
  "url": "http://httpbin.org/anything/1"
Response: 200 http://httpbin.org/anything/2
  "data": "foo=bar",
  "url": "http://httpbin.org/anything/2"
Response: 200 http://httpbin.org/anything/3
  "data": "foo=bar",
  "url": "http://httpbin.org/anything/3"
```

but ganda also allows you to parameterize the template body if you'd like to vary the body that gets posted with each request.  It will replace each `%s` in the body template with a space-delimited values after the urls that it is streamed, so with the file:

```
cat << EOF > /tmp/list_of_urls_and_values
http://httpbin.org/anything/1 bar 111
http://httpbin.org/anything/2 baz 222
http://httpbin.org/anything/3 qux 333
EOF
```

We have each url followed by values that should be used in the body that we POST to that url:

```
cat /tmp/list_of_urls_and_values | ganda -X POST -d '{"first": "%s", "second": "%s"}' | grep -E 'data|url'
Response: 200 http://httpbin.org/anything/3
  "data": "{\"first\": \"qux\", \"second\": \"333\"}",
  "url": "http://httpbin.org/anything/3"
Response: 200 http://httpbin.org/anything/2
  "data": "{\"first\": \"baz\", \"second\": \"222\"}",
  "url": "http://httpbin.org/anything/2"
Response: 200 http://httpbin.org/anything/1
  "data": "{\"first\": \"bar\", \"second\": \"111\"}",
  "url": "http://httpbin.org/anything/1"
```

This can be very useful for hitting things like GraphQL services.

## When to use `ganda`

I tend to use `ganda` for anything beyond a single url, but still use `curl` for singular urls as it is more portable.  It is useful any time I want to make a number of requests and perform an analysis across urls.

Unix tools are best when they do "one thing well" and `ganda`'s whole purpose is to make lots and lots of http/https requests.  It composes really well with tools like `jq`, `sort`, `uniq` and `grep` and enables many ad-hoc analysis possibilities when you have access to an HTTP endpoint but not direct access to a database.
