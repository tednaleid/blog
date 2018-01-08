---
title: "Using HTTP APIs on the Command Line - Part 2 - jq"
---

This is part 2 of a series of posts on Using HTTP APIs on the command line:
- [curl](/2017/11/26/using-http-apis-on-the-command-line-1-curl.html) - making requests on the command line
- [jq](/2017/12/17/using-http-apis-on-the-command-line-2-jq.html) - this post
- [ganda (with a little awk)]() - TBD

## What is `jq`?

[`jq`](https://stedolan.github.io/jq/) is a command-line JSON stream editor.  It's like `awk` for JSON.

It is one of my favorite command line tools, it is _great_ at one thing, parsing JSON and composes well with other command line utilities (`curl`, `cat`, `awk`, etc).

It has an excellent [manual](https://stedolan.github.io/jq/manual/) on the web (most of which is also in the `man jq` page).

There is also an online "playground" called [jqplay](https://jqplay.org/) where you can try out `jq` input with expressions to see what the output would be without installing.

## Installation

Quick install instructions:

OSX:

Use [homebrew](https://brew.sh/): `brew install jq`

Debian/Ubuntu Linux:

`sudo apt-get install jq`

Fedora:

`sudo dnf install jq`

Full instructions, including downloadable binaries for all platforms, are [on the jq site](https://stedolan.github.io/jq/download/).


## `jq` basics

### simple value extraction

`jq` has a concise mini-programming language for selecting and transforming JSON.  The most basic expression is the `.` path selector, which simply selects the root of the current document. By itself it will work as a pretty-printer:

```
echo '{"foo": "bar", "baz": [1, 2, 3]}' | jq '.'
{
  "foo": "bar",
  "baz": [
    1,
    2,
    3
  ]
}
```

If you're running in a terminal with color support, it'll also colorize the output.

You can add to a path selector to narrow what `jq` will select:

```
echo '{"foo": "bar", "baz": [1, 2, 3]}' | jq '.foo'

"bar"
```

A nested value can be accessed with dot-notation, just like many programming languages:

```
echo '{"a": {"b": {"c": {"d": "value"}}}}' | jq '.a.b.c.d'
"value"
```

### Output Options

#### compact output (reverse-pretty printing) with `-c`

This example uses a [heredoc](http://www.tldp.org/LDP/abs/html/here-docs.html) to give `jq` pretty-printed JSON and having it compact it to a single line:

```
cat <<EOF | jq -c '.'
{
  "foo": "bar",
  "baz": [
    1,
    2,
    3
  ]
}
EOF
{"foo":"bar","baz":[1,2,3]}
```

#### raw string output with `-r`

By default, if the result is a string, `jq` will emit it with double-quotes around it:

```
echo '{"foo": "bar", "baz": [1, 2, 3]}' | jq '.foo'

"bar"
```

If you want those quotes stripped off (maybe for piping to another command), you can use `-r` for raw string output:

```
echo '{"foo": "bar", "baz": [1, 2, 3]}' | jq -r '.foo'

bar
```

#### Output Sorted JSON Keys with `-S`

If you want the JSON that is emitted to have sorted keys (maybe for diffing/comparing to other output), you 

```
echo '{"z": "fourth", "a": "first", "y": "third", "b": "second"}' | jq -S '.'

{
  "a": "first",
  "b": "second",
  "y": "third",
  "z": "fourth"
}
```

### Formatting/Constructing output

`jq`'s selectors (like `.` and `.foo`) will emit whatever matches their expression, but those selectors can be surrounded with valid JSON to create remixed JSON output.

#### Creating Arrays

if you want to turn a couple of JSON object values into an array, just use `[]` in your expression:

```
echo '{"first": "Ted", "last": "Naleid"}' | jq -c '[.first]'
["Ted"]
```

You can use multiple selectors in your expression to have multiple values in your output:

```
echo '{"first": "Ted", "last": "Naleid"}' | jq -c '[.first, .last]'
["Ted","Naleid"]
```

#### Creating JSON Objects

You can also create remixed JSON objects from your input. Here we are moving the fields in the `user` object to the top-level:

```
cat <<EOF | jq '{first: .user.first, last: .user.last, username: .username}'
{
  "user": {
    "first": "Ted",
    "last": "Naleid"
  },
  "username": "tnaleid"
}
EOF
{
  "first": "Ted",
  "last": "Naleid",
  "username": "tnaleid"
}
```

### Other Selectors

#### Array Selectors

Each element in an array can be emitted with `[]`, this will "unwrap" the array:

```
echo '[1, 2, 3]' | jq '.[]'
1
2
3
```

It can also be done on arrays that are nested:

```
echo '{"ids":[1, 2, 3]}' | jq '.ids[]'
1
2
3
```

If you know you want a particular index or slice of an array, you can pass values to the `[]`. 

To get the first element out of an array pass a `0` (it is zero-based):

```
echo '[1, 2, 3]' | jq '.[0]'
1
```

Negative offsets can be used to get elements from the end of an array whose length you are unsure of:

```
echo '[1, 2, 3, 4, 5, 6, 7]' | jq '.[-1]'
7

echo '[1, 2, 3, 4, 5, 6, 7]' | jq '.[-3]'
5
```

Array slices can be created by giving the start and end element you want, here we get the "tail" of the array by getting the 2nd element (1 as it is zero-based) to the last element in the array:

```
echo '[1, 2, 3, 4, 5, 6, 7]' | jq -c '.[1:-1]'
[2,3,4,5,6]
```

If you want specific values, you can specify those with comma separated indexes:

```
echo '[1, 2, 3, 4, 5, 6, 7]' | jq '.[1, 3, 5]'
2
4
6
```

#### `keys` Selector

If you want to a list all of the keys in an object, use the `keys` selector:

```
echo '{"z": "fourth", "a": "first", "y": "third", "b": "second"}' | jq -c 'keys'

["a","b","y","z"]
```


### Piping Results with `|`

Just like many shells, `jq` has a "pipe" mechanism that allows the results of a selector to be piped to another `jq` function.  Every result from the expression on the left of the `|` is fed into the expression on the right.


#### Finding the first element of an array


| first



#### `..` Recursive Decent Value Selector

The `..` selector will find all of the values under the current selection.



## still to document, post will be updated


jq examples:

- recursive find with ..
- ? in selects
- select for presence
  - array/object test
  - find a particular value with an id inside an array
  - as an if statement (select(.count > 1000))
- csv/tsv output
- create variables
  - 
- inject environment variables
- diff two json files, add in del() to remove properties that we don't care about
- find exec/xargs jq

    find bad_tcin_imperial -type f -exec cat {} \; |jq -r '[.tcin, .launch_date_time, .item_state, .buy_url, .product_description.title] | @tsv'

- create new json out of input that isn't json
- debug
- timestamps
- group_by and map
- run bigger command from a file

- jq from jsonb in psql
- jq from kt
- jq from ganda




### Further Resources

- https://github.com/stedolan/jq/wiki/Cookbook
- https://github.com/stedolan/jq/wiki/Advanced-Topics
- https://github.com/stedolan/jq/wiki/How-to:-Avoid-Pitfalls
