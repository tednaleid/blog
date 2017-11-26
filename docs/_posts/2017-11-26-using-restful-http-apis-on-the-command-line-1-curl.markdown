---
title: "Using RESTful HTTP APIs on the Command Line - Part 1 - curl"
---

This is part 1 of a series of posts on Using HTTP APIs on the command line:
- curl - this post
- [jq]() - TBD
- [ganda (with a little awk)]() - TBD

## What is `curl`?

`curl` is a command line app that lets you make requests (http, as well as a variety of other types) and view/save the results.

It has pretty [good docs on the web](https://ec.haxx.se/usingcurl.html) and an extensive `man curl` page.

Example using [httpbin](http://httpbin.org/) (a great service that I'll use for a number of examples):

```
curl "http://httpbin.org/uuid"
{
  "uuid": "339d635c-e5d0-4f5a-afac-0ee954ed508a"
}
```


## Why use `curl`?

I use `curl` because it is almost everywhere.  It is on my work laptop, home desktop, every machine I ssh into, and every box of every developer that I work with.  Its interface is a little crufty, but if you learn a few simple options you'll be able to use anywhere.

There are friendier command-line alternatives like [httpie](https://github.com/jakubroztocil/httpie) and [resty](https://github.com/micha/resty).  I don't use those because they are likely to only be where I've manually installed them.  Other developers won't have them, so sending them commands via slack has barriers to usage and understanding ("What's `httpie`? Oh, I don't have that installed... <yak shaving starts>")


Why not [postman](https://www.getpostman.com/)?  Because it isn't everywhere, it doesn't compose easily with other commands (like `jq`), and it isn't easy to share with others via slack chat.

I can see why those tools are useful for others, but this is why I use `curl` over those alternatives.

## `curl` usage

`curl` is used on the command line, so I always use double-quotes to encode my url so that I do not have to escape any special characters (like `?` and `&`) that have other meanings in the shell.

```
curl "http://httpbin.org/response-headers?key=val"
{
  "Content-Type": "application/json",
  "key": "val"
}
```

### Seeing verbose output for debugging

It is often useful to use the `-v` (verbose) flag to see metadata about what is being sent/recieved by curl:

```
curl -v "http://httpbin.org/uuid"
*   Trying 54.243.202.193...
* TCP_NODELAY set
* Connected to httpbin.org (54.243.202.193) port 80 (#0)
> GET /uuid HTTP/1.1
> Host: httpbin.org
> User-Agent: curl/7.54.0
> Accept: */*
>
< HTTP/1.1 200 OK
< Connection: keep-alive
< Server: meinheld/0.6.1
< Date: Sun, 26 Nov 2017 19:14:47 GMT
< Content-Type: application/json
< Access-Control-Allow-Origin: *
< Access-Control-Allow-Credentials: true
< X-Powered-By: Flask
< X-Processed-Time: 0.000504970550537
< Content-Length: 53
< Via: 1.1 vegur
<
{
  "uuid": "78c816c8-857b-4726-9070-65e182e3c8c7"
}
* Connection #0 to host httpbin.org left intact
```

### HTTP Methods (POST, PUT, DELETE) and sending form data

The default http method in curl is `GET`:

```
curl "http://httpbin.org/post"
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<title>405 Method Not Allowed</title>
<h1>Method Not Allowed</h1>
<p>The method is not allowed for the requested URL.</p>
```

You can change the method with the `-X` parameter and post form data fields with `-F`:

```
curl -X POST -F "field=value" "http://httpbin.org/post"
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "field": "value"
  },
  ...
```

POST data can be sent with `-d` either inline:

```
curl -X POST -d '{"field":"value"}' "http://httpbin.org/post"
```

or as a file using a `@` before the filename:

```
echo '{"field":"value"}' > postme.json
curl -X POST -d @postme.json "http://httpbin.org/post"
```

You can make a `HEAD` request with the `-I` flag, this can be useful in a script for checking if website is up:

```
curl -I "http://httpbin.org/uuid"
HTTP/1.1 200 OK
Connection: keep-alive
Server: meinheld/0.6.1
Date: Sun, 26 Nov 2017 19:12:25 GMT
Content-Type: application/json
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
X-Powered-By: Flask
X-Processed-Time: 0.000476121902466
Content-Length: 53
Via: 1.1 vegur
```

### Headers

Headers (like authorization tokens/basic auth) can be sent with `-H`:

```
curl -H "Authorization: Bearer <mytoken>" "http://httpbin.org/headers"
{
  "headers": {
    "Accept": "*/*",
    "Authorization": "Bearer <mytoken>",
    "Connection": "close",
    "Host": "httpbin.org",
    "User-Agent": "curl/7.54.0"
  }
}
```


### Cookies

If the service you are hitting uses cookies and you need to make an authorization request first followed by using the saved cookie in further requests, you can use the `-c` parameter to write the cookies and then `-b` to use them in subsequent requests (`-L` follows 302 redirects which are sometimes sent in auth requests):


```
curl -c cookie.txt -L "http://httpbin.org/cookies/set?key=value"
{
  "cookies": {
    "key": "value"
  }
}
```

You can re-use that cookie file on subsequent requests with `-b`


```
curl -b cookie.txt "http://httpbin.org/cookies"
{
  "cookies": {
    "key": "value"
  }
}
```

### HTTPS SSL/TLS
HTTPS endpoint certificate can be easily ignored (if you know you don't care about cert verification) with `-k` switch for quick manual commands. If you want to use and verify certificates, that is a longer topic that is [covered in the official docs](https://ec.haxx.se/usingcurl-tls.html).


### Custom request timing output

There are a number of additional output settings that you can use.  One I've found useful when debugging slow connections is to see the various timings that `curl` keeps track of when making a request.

If you have a curl template file at `/tmp/curl-format.txt` like this:

```
   namelookup:  %{time_namelookup}\n
      connect:  %{time_connect}\n
   appconnect:  %{time_appconnect}\n
  pretransfer:  %{time_pretransfer}\n
     redirect:  %{time_redirect}\n
starttransfer:  %{time_starttransfer}\n
   time_total:  %{time_total}\n
```

You can use the `-w` switch to emit timing for a request (the `@` at the beginning of the property tells `curl` to load a file rather that inline formatting):

```
curl -w "@/tmp/curl-format.txt" "http://httpbin.org/uuid"
{
  "uuid": "63846b2b-7502-45c4-b578-4bb04ba0c0b9"
}
   namelookup:  0.065418
      connect:  0.114471
   appconnect:  0.000000
  pretransfer:  0.114569
     redirect:  0.000000
starttransfer:  0.165436
   time_total:  0.165513
```

This can also be done inline (which is great for copy/paste commands, but is a bit uglier):

```
curl -w '   namelookup: %{time_namelookup}\n      connect: %{time_connect}\n   appconnect: %{time_appconnect}\n  pretransfer: %{time_pretransfer}\n     redirect: %{time_redirect}\nstarttransfer: %{time_starttransfer}\n        total: %{time_total}\n\n' "http://httpbin.org/uuid"
{
  "uuid": "fcec0ce4-5374-403e-9786-1ebabaadb3b0"
}
   namelookup: 0.004505
      connect: 0.050844
   appconnect: 0.000000
  pretransfer: 0.050907
     redirect: 0.000000
starttransfer: 0.102053
        total: 0.102116
```

### Saving output to a file

You can just redirect stdout to a file, when curl is not sending the response to stdout, it adds a progress indicator:

```
curl "http://httpbin.org/uuid" > output.json
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100    53  100    53    0     0    417      0 --:--:-- --:--:-- --:--:--   420


cat output.json
{
  "uuid": "856320f6-2d90-4bf2-800c-edaef59eec57"
}
```

You can suppress the progress indicator with `-s`:


```
curl -s "http://httpbin.org/uuid" > output.json

cat output.json
{
  "uuid": "a4ce5649-6bb2-49c0-af93-e97f731c7483"
}
```

You can also use the `-o` (output) flag:

```
curl -s -o output.json "http://httpbin.org/uuid"


cat output.json
{
  "uuid": "1246c5ac-2906-4998-aee7-6f5a63b6da66"
}
```

If you don't care about the output (but still want to request it, maybe to look at verbose output with `-v` or other metadata with `-w`), you can just send it to `/dev/null`:

```
curl -s -w '%{http_code}' -o /dev/null "http://httpbin.org/uuid"
200%
```


### Composing curl with other commands using pipes

By default, `curl` output is sent to stdout which makes it easy to compose with other commands using the `|` operator:

```
curl -s -H "Authorization: Bearer <mytoken>" "http://httpbin.org/headers" |\
       grep Authorization

    "Authorization": "Bearer <mytoken>",
```


For JSON output, grep is often a bad tool to use to find the information you want, the [next blog post details how `jq` can be used to parse and manipulate JSON]().

