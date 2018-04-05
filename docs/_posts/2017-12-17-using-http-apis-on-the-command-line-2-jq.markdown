---
title: "Using HTTP APIs on the Command Line - Part 2 - jq"
---

This is part 2 of a series of posts on Using HTTP APIs on the command line:
- [curl](/2017/11/26/using-http-apis-on-the-command-line-1-curl.html) - making requests on the command line
- [jq](/2017/12/17/using-http-apis-on-the-command-line-2-jq.html) - this post
- [ganda (with a little awk)](/2018/04/04/using-http-apis-on-the-command-line-3-ganda.html) - using `ganda` to make _many_ requests

## What is `jq`?

[`jq`](https://stedolan.github.io/jq/) is a command-line JSON stream editor.  It's like `awk` for JSON.

It is one of my favorite command line tools, it is _great_ at one thing, parsing JSON and composes well with other command line utilities (`curl`, `cat`, `awk`, etc).

It has an excellent [manual](https://stedolan.github.io/jq/manual/) on the web (most of which is also in the `man jq` page).

There is also an online "playground" called [jqplay](https://jqplay.org/) where you can try out `jq` input with expressions to see what the output would be without installing.

## Installation

Quick install instructions:

OSX, use [homebrew](https://brew.sh/)

    brew install jq

Debian/Ubuntu Linux:

    sudo apt-get install jq

Fedora:

    sudo dnf install jq

Full instructions, including downloadable binaries for all platforms, are [on the `jq` site](https://stedolan.github.io/jq/download/).


## `jq` basics

### simple value extraction

`jq` has a concise mini-programming language for selecting and transforming JSON.  The most basic expression is the `.` path selector, which simply selects the root of the current document. By itself it will work as a pretty-printer:

```
echo '{"foo": "bar", "baz": [1, 2, 3]}' | jq '.'
```

```
{
  "foo": "bar",
  "baz": [
    1,
    2,
    3
  ]
}
```

You can add the name of a field to narrow what `jq` will select:

```
echo '{"foo": "bar", "baz": [1, 2, 3]}' | jq '.foo'
```
```
"bar"
```

A nested value can be accessed with dot-notation, just like many programming languages:

```
echo '{"a": {"b": {"c": {"d": "value"}}}}' | jq '.a.b.c.d'
```
```
"value"
```

## Output Options

### Compact Output (reverse-pretty printing) with `-c`

This example uses a [heredoc](http://www.tldp.org/LDP/abs/html/here-docs.html) to give `jq` pretty-printed JSON and having it compact it to a single line:

input:
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
```

output:
```
{"foo":"bar","baz":[1,2,3]}
```

### Raw String Output with `-r`

By default, if the result is a string, `jq` will emit it with double-quotes around it:

```
echo '{"foo": "bar", "baz": [1, 2, 3]}' | jq '.foo'
```
```
"bar"
```

If you want those quotes stripped off (maybe for piping to another command), you can use `-r` for raw string output:

```
echo '{"foo": "bar", "baz": [1, 2, 3]}' | jq -r '.foo'
```
```
bar
```

### Output Sorted JSON Keys with `-S`

If you want the JSON that is emitted to have sorted keys (maybe for diffing/comparing to other output), you 

```
echo '{"z": "fourth", "a": "first", "y": "third", "b": "second"}' | jq -S '.'
```
```
{
  "a": "first",
  "b": "second",
  "y": "third",
  "z": "fourth"
}
```

### Formatting/Constructing Output

`jq`'s selectors (like `.` and `.foo`) will emit whatever matches their expression, but those selectors can be surrounded with valid JSON to create remixed JSON output.

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
```
```
{
  "first": "Ted",
  "last": "Naleid",
  "username": "tnaleid"
}
```

### Creating Arrays

if you want to turn a couple of JSON object values into an array, just use `[]` in your expression:

```
echo '{"first": "Ted", "last": "Naleid"}' | jq -c '[.first]'
```
```
["Ted"]
```

You can use multiple selectors in your expression to have multiple values in your output:

```
echo '{"first": "Ted", "last": "Naleid"}' | jq -c '[.first, .last]'
```
```
["Ted","Naleid"]
```

## Other Selectors


### Array Selectors

Each element in an array can be emitted with `[]`, this will "unwrap" the array:

```
echo '[1, 2, 3]' | jq '.[]'
```
```
1
2
3
```

It can also be done on arrays that are nested:

```
echo '{"ids":[1, 2, 3]}' | jq '.ids[]'
```
```
1
2
3
```

If you know you want a particular index or slice of an array, you can pass values to the `[]`. 

To get the first element out of an array pass a `0` (it is zero-based):

```
echo '[1, 2, 3]' | jq '.[0]'
```
```
1
```

Negative offsets can be used to get elements from the end of an array whose length you are unsure of:

```
echo '[1, 2, 3, 4, 5, 6, 7]' | jq '.[-1]'
```
```
7
```

```
echo '[1, 2, 3, 4, 5, 6, 7]' | jq '.[-3]'
```
```
5
```

Array slices can be created by giving the start and end element you want, here we get the "tail" of the array by getting the 2nd element (1 as it is zero-based) to the last element in the array:

```
echo '[1, 2, 3, 4, 5, 6, 7]' | jq -c '.[1:-1]'
```
```
[2,3,4,5,6]
```

If you want specific values, you can specify those with comma separated indexes:

```
echo '[1, 2, 3, 4, 5, 6, 7]' | jq '.[1, 3, 5]'
```
```
2
4
6
```

### `keys` Selector

If you want to a list all of the keys in an object, use the `keys` selector:

```
echo '{"z": "fourth", "a": "first", "y": "third", "b": "second"}' | jq -c 'keys'
```
```
["a","b","y","z"]
```


### Composing Filters with `|`, `,` and `()`

Just like many shells, `jq` has a "pipe" mechanism that allows the results of a selector to be piped to another `jq` function.  Every result from the expression on the left of the `|` is fed into the expression on the right.

The expression `.a.b.c` is equivalent to the expression `.a | .b | .c`:

```
echo '{"a": {"b": {"c": "value"}}}' | jq '.a.b.c'
```
```
"value"
```

```
echo '{"a": {"b": {"c": "value"}}}' | jq '.a | .b | .c'
```
```
"value"
```

A `,` is used to separate filters, and the results so far will be composed with each filter:


```
echo '{"a": {"b": {"c1": "value", "c2": "other"}}}' | jq '.a | .b | .c1, .c2'
```
```
"value"
"other"
```

Parenthesis can be used to group filters together:

```
echo '{"a1": {"b": {"c": "value"}}, "a2": "other"}' | jq '(.a1 | .b | .c), .a2'
```
```
"value"
"other"
```


### using `select` to filter results

If you only want particular values, you can give a boolean expression to `select` and it will return only the matches:

```
echo '[1, 2, 3, 4]' | jq '.[] | select(. > 2)'
```
```
3
4
```

It returns the full matching object that it was given:

```
echo '[{"a": 1}, {"a": 2}, {"a": 3}, {"a": 4}]' | jq -c '.[] | select(.a > 2)'
```
```
{"a":3}
{"a":4}
```

This can be useful if the thing you're testing isn't the actual result you want:

```
echo '[{"a": 1, "b": "bad"}, {"a": 4, "b": "good"}]' | jq -r '.[] | select(.a > 2) | .b'
```
```
good
```

### Using `?` for values that might not exist

Some expressions will work fine with some input:

```
echo '{"ids": [{"id": 123}, {"id": 456}]}' | jq '.ids[].id'
```
```
123
456
```

But will blow up if the chain of values doesn't exist:

```
echo '{}' | jq '.ids[].id'
```
```
jq: error (at <stdin>:1): Cannot iterate over null (null)
```

This can be gotten around using the `?` to tell `jq` that the value might be null and to ignore it:

```
echo '{}' | jq '.ids[]?.id'
```

### Values with Varying Types

Sometimes, when an API has a breaking change, a value that was a string has become an integer, if you want to ensure that you only find things that are integers, use the `type` in a select:

```
echo '[{"id": 123}, {"id": "456"}]' | jq '.[].id | select(type == "string")'
```
```
"456"
```

```
echo '[{"id": 123}, {"id": "456"}]' | jq '.[].id | select(type == "number")'
```
```
123
```

You can use `|` pipes _inside_ the select as part of your boolean expression.  This will modify what `select` evaluates, but will not modify what gets selected:


```
echo '[{"id": 123}, {"id": "456"}]' | jq '.[] | select(.id | type == "number")'
```
```
{
  "id": 123
}
```

Valid types are `number`, `boolean`, `array`, `object`, `null`, `string`.  There are also shortcut versions of these (and others) using the plural of the type:

```
echo '[{"id": 123}, {"id": "456"}]' | jq '.[].id | numbers'
```
```
123
```

#### `..` Recursive Decent Value Selector

The `..` selector will recursively descend down the currently selection and emit each:

```
echo '{"a": {"b": {"c": "value"}}}' | jq '.a | ..'
```
```
{
  "b": {
    "c": "value"
  }
}
{
  "c": "value"
}
"value"
```

This is most useful for combining with the `select` which can be used to filter output and search for matching structures:


```
cat <<EOF | jq -c '.. | select(.target? != null)'
{
  "object": {
     "target": "fromobject"
  },
  "values": [
    {
      "target": "fromarray"
    },
    {
      "ignored": "omitted"
    }
  ]
}
EOF
```
```
{"target":"fromobject"}
{"target":"fromarray"}
```

### Create JSON from stdin that isn't JSON

use `-R` to do raw input and then you can do this:

    seq 3 | jq -R '{id: ., body: ({id: .} | @json)}'
    {
      "id": "1",
      "body": "{\"id\":\"1\"}"
    }
    {
      "id": "2",
      "body": "{\"id\":\"2\"}"
    }
    {
      "id": "3",
      "body": "{\"id\":\"3\"}"
    }

For more advanced versions where you want to potentially split up the arguments, you can use `-Rn` and `input`/`inputs`

    seq 3 | jq -Rn 'inputs | {id: .}'
    {
      "id": "1"
    }
    {
      "id": "2"
    }
    {
      "id": "3"
    }

### Working with Dates

An ISO-8601 date string can be turned into a unix time:

```
echo '{"created_date_time":"2017-08-17T19:02:51Z"}' | jq '.created_date_time | fromdate'
```
```
1502996571
```

given a stream of events that have created_date_time field like this:

    {"id":"169","created_date_time":"2016-01-01T00:00:00Z"}
    {"id":"170","created_date_time":"2017-08-17T19:02:51Z"}
    {"id":"433","created_date_time":"2018-01-01T00:00:00Z"}

If we want to find all the ones that are less than or equal to "2017-08-17T19:02:51Z", we can use this:

```
cat <<EOF | jq -c 'select((.created_date_time | fromdate) <= ("2017-08-17T19:02:51Z" | fromdate))'
{"id":"169","created_date_time":"2016-01-01T00:00:00Z"}
{"id":"170","created_date_time":"2017-08-17T19:02:51Z"}
{"id":"433","created_date_time":"2018-01-01T00:00:00Z"}
EOF
```
```
{"id":"169","created_date_time":"2016-01-01T00:00:00Z"}
{"id":"170","created_date_time":"2017-08-17T19:02:51Z"}
```

You can also use variables in `jq` like this to reuse a value:

```
cat <<EOF | jq -c '(.created_date_time | fromdate) as $created | select($created <= 1512996571 and $created > 1500000000)'
{"id":"169","created_date_time":"2016-01-01T00:00:00Z"}
{"id":"170","created_date_time":"2017-08-17T19:02:51Z"}
{"id":"433","created_date_time":"2018-01-01T00:00:00Z"}
EOF
```
```
{"id":"170","created_date_time":"2017-08-17T19:02:51Z"}
```

### Debugging complex expressions with `debug`

Using `debug` in your pipeline expression will emit what the current value of something is and can be useful for figuring out what is causing errors:

This example shows us why the select that is looking for numbers we are picking `123` but not `"456"`:

```
echo '[{"id": 123}, {"id": "456"}]' | jq '.[] | select(.id | debug | type == "number")'
```
```
["DEBUG:",123]
{
  "id": 123
}
["DEBUG:","456"]
```

### Output in CSV/TSV format

It can be useful to emit values other than JSON.  The first step is to emit the results as an array:

```
cat <<EOF | jq '[.id, .value]'
{"id":"169","value": 1}
{"id":"170","value": 2}
{"id":"433","value": 3}
EOF
```
```
[
  "169",
  1
]
[
  "170",
  2
]
[
  "433",
  3
]
```

Then, pipe that array either through the `@tsv` or `@csv` formatter to get valid output (also use `-r` to get the "raw" output):


```
cat <<EOF | jq -r '[.id, .value] | @csv'
{"id":"169","value": 1}
{"id":"170","value": 2}
{"id":"433","value": 3}
EOF
```
```
"169",1
"170",2
"433",3
```


```
cat <<EOF | jq -r '[.id, .value] | @tsv'
{"id":"169","value": 1}
{"id":"170","value": 2}
{"id":"433","value": 3}
EOF
```
```
169	1
170	2
433	3
```

I've often turned `jq` output into tab-separated output for later processing with other unix command tools like `awk`, `sort`, `uniq` etc


### Working with Objects That Want to be Arrays

Sometimes, you're given an object that has keys and values that you want to work with as if they are an array of key/value pairs, the `to_entries` operator can help:

```
cat <<EOF | jq -r '.states | to_entries[] | [.key, .value.at] | @tsv'
{
  "states": {
    "running": {
      "at": "2017-12-14T18:08:11Z"
    },
    "stopped": {
      "at": "2018-01-01T00:08:11Z"
    }
  }
}
EOF
```

```
running	2017-12-14T18:08:11Z
stopped	2018-01-01T00:08:11Z
```

### Further Resources

There are _many_ features and uses of `jq` that I haven't documented here, I've only scratched the surface of what it can do.  Here are some further links for reading:

- [`jq` manual](https://stedolan.github.io/jq/manual/v1.5/)
- [Cookbook](https://github.com/stedolan/jq/wiki/Cookbook)
- [Advanced Topics](https://github.com/stedolan/jq/wiki/Advanced-Topics)
- [Avoiding Pitfalls](https://github.com/stedolan/jq/wiki/How-to:-Avoid-Pitfalls)

### Using `jq` across _many_ http requests

If you want to see how you can map over many http requests and process the results with `jq` check out the [next blog post in this series](/2018/04/04/using-http-apis-on-the-command-line-3-ganda.html).

