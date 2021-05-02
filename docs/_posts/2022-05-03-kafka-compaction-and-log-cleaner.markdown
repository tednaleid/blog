---
title: Kafka Compaction and Log Cleaner Deep Dive
---

TODO: add link to prior post

# Kafka Cleanup Policies

## TODO start here
Disk space on Kafka brokers isn't infinite.  There are two supported cleanup policies that 
can be specified as a [broker default]() or overridden [per-topic]().

### Cleanup Policy: `delete`

TODO - what code does the actual deleting of old segments?

### Cleanup Policy: `compact`

delete vs compact (or both)

other future compaction strategies [^futurecompactionstrategies]

basic logical topic compaction, with replication to multiple brokers

## What happens when the Log Cleaner isn't keeping up

This chart shows disk usage for a cluster of Kafka brokers that maintain compacted topics.  

![Kafka Brokers Disk Usage](/images/2021/04/kafka_brokers_disk_usage.png "Kafka Brokers Disk Usage")

Prior to 3/26, the brokers were using ~15% of disk space.  A little more data was added causing the Log Cleaner
to slowly fall behind.  Disk usage spiked up by 6x over the next few weeks. On 4/22 the Log Cleaner
was tuned to have enough resources and bring disk usage back down to ~20%.

Failing to tune Kafka compaction can have compounding effects where topics that have uncompacted messages are
read by consumers who then produce more messages than necessary.  This starts slowly, but can quickly get out
of hand.


## Kafka Topic Storage

Topic -> Partitions -> replication factor

broker -> segments -> active segment list

segments -> index
         -> record batch https://kafka.apache.org/documentation/#recordbatch
                      -> records https://kafka.apache.org/documentation/#record
                           -> offset, schema, key, value, headers, tombstones



# open questions

- details about the filthiest log.  Does changing from 0.5 to 0.1 make the log more filthy (by 0.4?)



---

# Kafka Log Cleaning Architecture



LogCleanerManager.scala: https://github.com/apache/kafka/blob/trunk/core/src/main/scala/kafka/log/LogCleanerManager.scala


LogCleaner.scala: https://github.com/apache/kafka/blob/trunk/core/src/main/scala/kafka/log/LogCleaner.scala

The LogCleanerManager keeps an updated list of the partitions and segments that are compacted and will need cleaning.

It spins up `log.cleaner.threads` number of LogCleaner threads to do the actual cleaning work.

It periodically checks each partition to see how much data has been written to it since the last cleaning.  If that ratio is greater than the topic's `min.cleanable.dirty.ratio` then it will be added to the list of `dirtyLogs`.  It will also add those topics who have gone without cleaning for more than `max.compaction.lag.ms` to this list (but this value does not affect how dirty that log is).

This list is recomputed _every time_ a cleaner asks for the "filthiest" log.


Each `LogCleaner` will wake up, and ask for the currently "filthiest" log.

TODO: insert filthiest log details

- for all partitions find:

clean section bytes (if there's a partially cleaned segment, how is this factored)
dirty section bytes (doesn't include the active log segment!), takes the full segment size if partially clean

if the ratio is > topic/brokers dirty ratio setting, it enters the list of logs to be cleaned

alternatively, a topic can get in the list if it is past its `max.compaction.lag.ms` but this doesn't make the log
any dirtier! So if the cleaner is always busy this log will almost never be picked




If there are no logs needing cleaning, the thread sleeps for ~15 seconds and then asks again.

If there is a log to clean, it will:

1. find the first "dirty" offset (the offset after the ones that were last cleaned)
2. start reading the "dirty" records into a buffer (`log.cleaner.io.buffer.size` at a time)
- for each, it will calculate the MD5 hash of the key and put it into an `OffsetMap`
    - the max size of this offset map is `log.cleaner.dedupe.buffer.size` * `log.cleaner.io.buffer.load.factor`
    - when it hits that size it is "full" and that is as far as that cleaning/compaction run on that partition will go
- so the "newest" offset with a key hash that is the same as a prior offset will overwrite that offset
3. when the offset map is "full", or it gets to the end of the "cleanable" segments (so not the active/open segment) it then will then:
- find the old segments (and possibly group them if they are smaller than the segment size when combined)
- create a new segment to start to fill to take the place of the old segment
- iterate over the records in those old segments and see if their hash is in the OffsetMap
    - if it is in the offset map, that value is dropped
    - otherwise, write it to the new segment
- if the offset map had stopped collecting part way through as segment
  -when that segment is compacted, it will dedupe till that offset, then copy/and retain the remaining records in that segment after that point
    - this means that if we don't even have enough room in our offset map for a full segment that it is _very_ expensive to do this multiple times on the same segment
- when the old segment group is finished reading, it will close the new segment
- when all segments through the dirty segments represented in the offset map have been re-created, it will swap them out



## Properties that Affect Compaction

### Broker Properties


### Topic Properties









# Cleaning/Compaction Tuning

there is no way to force a broker to run cleaning on a particular topic/partition, or to prioritize it above others that meet the threshold

this means you want the cleaners to be getting a break periodically, otherwise they won't be cleaning least dirty logs
which might be the most important ones


Topic level settings that affect compaction:

https://docs.confluent.io/platform/current/installation/configuration/topic-configs.html


- cleanup.policy
    - default "delete"
    - must be changed to "compact" for compaction to run

- min.cleanable.dirty.ratio
    - default 0.5
    - ratio of _bytes_ that need to be written to the partition before it is eligible for compaction.
        - The default setting of 0.5 means that after the last cleaning, that another 50% of bytes need to be written to the log for it to be eligible again
            - ex if a
        - If it was not able to fully clean a partition because of memory constraints in the offset map, it will partially clean that partition and update the offset
            - signal for this is this message:
                - Cleaner 3: Offset map is full, 1 segments fully mapped, segment with base offset 470931255 is partially mapped
            - messages like this mean that the cleaner does not have a big enough map to hold the cardinality of all unique keys in that partition
        - This means that the dirty ratio will possibly be under the threshold for this partition and that it wasn't fully cleaned!


- delete.retention.ms
    - default 1 day
    - tombstones will be retained for this long, but can be reaped after this

- max.compaction.lag.ms
    - default max long
    - if set to something like 24 hours, then this partition will be in the list of things to clean after 24 hours
        - but this setting does not affect how "dirty" the log is considered, so it will be at the bottom of the list unless lots of data has been written to it
        - if your cleaner threads are _always_ busy, then this will have very little to no affect

- segment.bytes
    - default 1GB
    - a new segment will get rolled when this many bytes at most have been written to the log
    - the currently open segment is _not_ eligible for compaction
    - this is a per-partition setting, so if you have 10 partitions, you'll need to write ~10GB to your topic to roll new segments

- segment.ms
    - default 1 week of milliseconds
    - used to roll a new segment for a partition with relatively low traffic.
    - if you only write a single message a day to a partition, a new segment will be rolled after 7 messages


Broker level settings that affect compaction:

https://docs.confluent.io/platform/current/installation/configuration/broker-configs.html

- log.cleaner.threads
    - default 1
    - the number of concurrent `LogCleaner` threads that are pulling the "filthiest" logs from the list maintained by the `LogCleanerManager`

- log.cleaner.dedupe.buffer.size
    - default: 128MB in bytes
    - this value is broker level and is divided across the number of cleaner threads so if you increase the number of cleaner threads, you'll likely want to increase this
    - used to allocate an "OffsetMap" that is owned by the `LogCleaner`
    - Filled with
        - key: the hash of the key (default MD5 and 16 bytes) from the "dirty" segment of the log
        - value: the latest offset (8 bytes) in the "dirty" segment for that key/hash
    - if this is too small to hold all unique key hashes and offsets in the dirty section, you'll see a debug log message like:
        - Cleaner 3: Offset map is full, 1 segments fully mapped, segment with base offset 470931255 is partially mapped
    - or an INFO level report that says Buffer Utilization is 90.0%:
        - Buffer utilization: 90.0%
    - when the map is "full", it will not clean any further for that run

  So this should be set to a value that could hold at least the "dirty.ratio" worth of unique key hashes + offsets.
  ex: if you have compacted topics with:
    - 100M unique keys
    - spread across 10 partitions
    - min.cleanable.dirty.ratio of the default 0.5
    - each partition will have ~10M unique keys
        - so holding _all_ unique hash/offsets would be 24 * 10,000,000 = ~228M for all keys
        - dirty ratio of 0.5 means take about half of that, so ~114M if we expect that most of the keys that will have been written since the last cleaning to be unique
        - tweak depending on how many duplicates in the dirty segment you expect to see, plus some extra for the lag between when the dirty ratio is hit and when compaction runs
        - need to multiply that value by the number of `log.cleaner.threads`


- log.cleaner.io.buffer.size
    - default: 512KB
    - actual memory usage for this is 2x this value as there is a read and a write buffer
    - this value is broker level and is divided across the number of cleaner threads so if you increase the number of cleaner threads, you'll likely want to increase this
    - used to read in records from the segment
        - if a message is too large, it will double the size of the buffer and try reading the record again, until it hits the max message size
        - it will then reduce the size of the buffer back to configured size after the offset map is finished
        - example where the starting buffer is 64k, but the message is > 128k, you'll see 2 consecutive messages in the logs:
            - Cleaner 2: Growing cleaner I/O buffers from 65536 bytes to 131072 bytes.
            - Cleaner 2: Growing cleaner I/O buffers from 131072 bytes to 262144 bytes.


- log.cleaner.io.buffer.load.factor
    - default 0.9
    - will only use this percent of the `log.cleaner.dedupe.buffer.size` allocated to this thread
    - so 1 thread given 128MB in dedupe buffer will only actually use ~115MB of that buffer






# TODO fix this napkin math, include 0.9 ratio

longer term, this is the napkin math for what we'll need, but we have an important topic right now where the cardinality is around 1.5-2 billion unique keys (our layers topic):
- there are 24 bytes used up for each map entry (16 for MD5 hash of the key, and 8 bytes for the offset of the latest record)
- we will have at least ~350M unique keys that are percolating through many topics
- each topic has 24 partitions, so there will be 14.5M unique keys per partition
- with a dirty ratio of 0.5, compaction will get triggered at the earliest at around 7.25M keys added (assuming they're mostly unique)
- so the offset map will need 24 bytes * 7.25M slots = 174000000 bytes (~165MB)
- each of the 4 threads needs this much so a total of: 696000000 bytes (~663MB)


## Topic Compaction - Frequently Asked Questions

### How can I have only one value on a topic for a key?

This is not possible with just Kafka, what you want is a key/value datastore. 

Even if you set your dirty ratio to zero and rolled a new segment every millisecond (BTW: don't do either of these 
things) to try to force log cleaning to run constantly, it'd never be fast enough.

### Ok, I'm fine with some duplicates, but want to reasonably minimize them on a specific topic, what are my options?

First, make sure that you're giving enough resources to the log cleaner threads (and that you have enough log cleaner 
threads).  If log cleaning is already constantly running, there aren't really options for forcing it to prioritize
some topics over others.

Next, we need to make sure records aren't stuck in the open segment that the broker is writing to.  Records are 
not eligibile for cleaning until they are in a closed segment.

Segments are closed either when they reach a particular size
([`segment.bytes` default 1GB per partition](https://kafka.apache.org/documentation.html#topicconfigs_segment.bytes)) 
or when segment hits a maximum age
([`segment.ms` default 1 week](https://kafka.apache.org/documentation.html#topicconfigs_segment.ms)).

I tend to favor modifying `segment.ms` to something like `43200000` (12 hours).  Rolling a new segment per partition
twice a day (or even once every 6 hours) isn't too expensive.  Keeping `segment.bytes` relatively large lets the log 
cleaner consolidate smaller segments together back into larger segments.

Now that records will be in cleanable segments, you'll want to configure Kafka to consider the partition for cleaning.

With default topic settings, the only config value that will cause a partition to get cleaned is
[`min.cleanable.dirty.ratio`](https://kafka.apache.org/documentation.html#topicconfigs_min.cleanable.dirty.ratio) which
is defaulted to `0.5`.  People often try to lower this value, but it is hard to tune because it is so dependent on 
the amount of data being written to the topic.  For a slow moving topic, it can take _weeks_ for enough data to be 
written to the topic for it to be cleaned.  If you make the value too low, it can put significant stress on the 
log cleaner by forcing it to be constantly cleaning this partition.

Using [`max.compaction.lag.ms`](https://kafka.apache.org/documentation.html#topicconfigs_max.compaction.lag.ms) is 
easier to control and reason about.  

#### tl;dr - minimize duplicates
- give your brokers enough cleaning resources
- have your topic use something like these values to ensure that at least half the new values written every day can be cleaned:
  - `segment.ms=43200000` (12 hours)
  - `max.compaction.lag.ms=86400000` (24 hours) 


### Can I force compaction to run on a particular partition?

Nope.

Your best bet is to ensure that your broker is giving enough resources to cleaning.

Then either configure the topic to run cleaning periodically via [`max.compaction.lag.ms`](https://kafka.apache.org/documentation.html#topicconfigs_max.compaction.lag.ms).

As discussed above, this doesn't guarantee that compaction _will_ be run that often only that it is eligible.  This
is why it is important to tune the cleaning resources to ensure every partition that wants to be cleaned is cleaned.

### I have old tombstones that are never going away, even though compaction _is_ running, why?

Let me guess:

- Is it a relatively low volume topic where the all of the data fits into a few segments?
- Are all of the tombstones that aren't getting compacted near the beginning of the topic?
- And (maybe) was the `min.cleanable.dirty.ratio` was previously lowered below the `0.5` default

You are probably hitting this Open/Unresolved issue: ["Tombstones can survive forever"](https://issues.apache.org/jira/browse/KAFKA-8522)

Possible solutions till [KIP-534](https://cwiki.apache.org/confluence/display/KAFKA/KIP-534%3A+Retain+tombstones+and+transaction+markers+for+approximately+delete.retention.ms+milliseconds) 
is implemented, there are some risks to this:

- set `delete.retention.ms` to `0` so that tombstones are always deleted during cleaning regardless of the 
- set `max.compaction.lag.ms` to a low value to signal that this topic should be cleaned
  
You'll want to revert these changes after the tombstones are reaped.

or you can change the `segment.bytes` to a value lower than the default 1GB so that the tombstones
aren't always having new values folded into the same segment (which is updating the timestamp of the segment again
and making the records look "new").  Be wary about making this value too low as this can add considerable strain on 
brokers.

### What log statements are interesting to monitor for tuning log cleaning?

Setting `kafka.log.LogCleaner` to `INFO` will emit messages like this in your logs:

```
[kafka-log-cleaner-thread-1]:
  Log cleaner thread 2 cleaned log fruit-prices-2 (dirty section = [310715098, 325968881])
  25,706.8 MB of log processed in 1,554.6 seconds (16.5 MB/sec).
  Indexed 12,405.3 MB in 484.9 seconds (25.6 Mb/sec, 31.2% of total time)
  Buffer utilization: 90.0%
  Cleaned 25,706.8 MB in 1069.7 seconds (24.0 Mb/sec, 68.8% of total time)
  Start size: 25,706.8 MB (49,042,590 messages)
  End size: 13,219.4 MB (33,931,680 messages)
  48.6% size reduction (30.8% fewer messages)
```

One of the most interesting values here to watch is the `Buffer utilization` value.  This tells you how
full the `LogCleaner`'s `OffsetMap` was during this cleaning run.  A value of `90.0%` means you've 
totally filled the `OffsetMap`[^whyninety] and it was unable to fully clean the partition.  Consider increasing the
[`log.cleaner.io.buffer.load.factor`](https://kafka.apache.org/documentation.html#brokerconfigs_log.cleaner.io.buffer.load.factor)
value to give the `LogCleaner` more memory to hold unique keys.




[^futurecompactionstrategies]: [KIP-280](https://cwiki.apache.org/confluence/display/KAFKA/KIP-280%3A+Enhanced+log+compaction) describes some alternative log cleaning strategies that are not available as of 2.8.0.
[^whyninety]: It's 90% and not 100% because [log.cleaner.io.buffer.load.factor](https://kafka.apache.org/documentation.html#brokerconfigs_log.cleaner.io.buffer.load.factor) is `0.9` but you probably don't want to mess with this value as increasing it will cause more map lookup collissions.

