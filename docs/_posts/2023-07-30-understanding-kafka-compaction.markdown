---
title: Understanding Kafka Compaction
---

## Understanding Kafka Compaction And Partition Cleaning

Without a [cleanup.policy](https://kafka.apache.org/documentation/#topicconfigs_cleanup.policy) Kafka topics would eventually accumulate enough events to fill the disk and be unable to accept new events.

We need a way to tell Kafka which events are OK to purge.  

The [cleanup.policy](https://kafka.apache.org/documentation/#topicconfigs_cleanup.policy) configuration value controls this.  It has three valid settings:

- `cleanup.policy=delete` - This is the default setting.  This policy gives Kafka permission to occasionally remove events older than [retention.ms](https://kafka.apache.org/documentation/#topicconfigs_retention.ms) (default: 7 days) or larger than [retention.bytes](https://kafka.apache.org/documentation/#topicconfigs_retention.bytes) (defaut: infinity).
- `cleanup.policy=compact` - This policy gives Kafka permission to occasionally remove events that share a key with a newer event as long as [min.compaction.lag.ms](https://kafka.apache.org/documentation/#topicconfigs_min.compaction.lag.ms) (default: `0`) has passed. 
- `cleanup.policy=compact,delete` - Both settings can be used, and this gives Kafka permission to occasionally remove events using the rules for each setting.  Think of this as an `OR` condition.  Events will be removed if `delete` OR `compact` says that event can be removed.  `compact,delete` removes the `compact`-only guarantee of keeping at least one event per key.

I intentionally say "permission to occasionally remove events" because there are no hard guarantees on when partition cleaning will happen.  Compacted topics will not immediately remove older events with duplicate keys.  `delete` policy topics will not instantly remove events exceeding the retention config settings.  There are lots of nuances to how cleaning works.

This post details what I've learned about partition cleaning from using Kafka since 2016; many details are not documented elsewhere.  I've only found the answers by digging into the [source code](https://github.com/apache/kafka).

## Frequently Asked Questions about Compaction

These are intended to be tl;dr entries for (relatively) quick answers.

Understanding the content below the FAQ will give a more thorough understanding of why I've given these answers.

#### Should I use topic compaction?

Maybe!  It depends on the requirements of the topic consumers.  

- Do new consumers want to see the latest value for every key?  
- Are the message keys finite (unique keys per partition no more than 10s to 100s of millions)?
- Will new events completely replace previous events with the same key?  (new events are not deltas from previous events)

If the answer to those questions is "yes," then compaction is worth considering.   If the answer to any of those questions is "no," compaction will not meet your requirements.

#### Can I tune compaction so there are never two events with the same key?

No.  You're looking for a database.  Try [PostgreSQL](https://www.postgresql.org/).

Even if all Kafka config values are tuned to constantly run compaction on a single partition (don't do this), duplicate events with the same key will exist.  Events are appended to the open segment log file on disk and do not replace previous events with the same key until the open segment is closed and the asynchronous background cleaning process selects this partition for cleaning.

With significant tuning, the lifetime of duplicates can be in the single-digit hour range.  I've never used compaction for anything short of 24 hours.

#### Can I trigger compaction to run?

No, not directly.  

The most direct lever would be to set the topic's [max.compaction.lag.ms](https://kafka.apache.org/documentation/#topicconfigs_max.compaction.lag.ms) to 24 hours to get it to run once a day.  This config is not set by default.

I prefer this over setting a low [min.cleanable.dirty.ratio](https://docs.confluent.io/platform/current/installation/configuration/topic-configs.html#min-cleanable-dirty-ratio) (default: 0.5), as that can cause compaction to run much more frequently than necessary on fast-moving topics and cause undue load on brokers. 

#### What is the "dirty ratio," and what does it mean for a partition to be dirty?

Kafka has no idea how many duplicate events you have on a topic. 

Kafka saves events in sequential append-only segment files on-disk for each topic partition.  Segment file name are zero-padded and denote the first `offset` that segment holds.

The dirty ratio is the ratio of the number of bytes in uncleaned, "dirty", segments (where duplicates might occur) to the total number of bytes for all closed segments.  

Here's an example showing how Kafka uses the dirty ratio as a proxy for how many cleanable duplicates a partition might have. 

![dirty ratio 0.25](/images/2023/07/dirty-ratio-1.png "dirty ratio 0.25"){: .center-image }

dirty ratio: `0.25` - clean

We have two previously cleaned closed segments:
- `000000.log` holding unique keys between offsets 0-14,999 and is 750MiB in size.  It likely does not have 15,000 events, as cleaning would have removed duplicates.
- `015000.log` holds unique keys for offsets between 15,000-41,999 and is also 750MiB in size.  Again, there will be gaps in offsets where duplicates were removed by cleaning.

We also have `042000.log`, a 500MiB closed, immutable segment that is dirty because it has not yet been cleaned.  Because it has not been cleaned, it contains all offsets between `42000` and `59999`. 

The currently open segment, `060000.log`, is where new records are appended.  It currently has `1GiB` of data.  It is ineligible for compaction.  The bytes in this file are not part of determining the dirty ratio.

We have `750MiB + 750MiB = 1.5GiB` of "clean" bytes on this partition.  We have `500MiB` of "dirty" bytes eligible for compaction that have not been cleaned on this partition.

This partition's dirty ratio is `0.25` (`500MiB dirty / 2iGB total closed`), and (with the default `min.cleanable.dirty.ratio=0.5`) it is considered "clean" and will not be selected for cleaning.

But what happens when we close the open segment?

![dirty ratio 0.5](/images/2023/07/dirty-ratio-2.png "dirty ratio 0.5"){: .center-image }

Dirty ratio: `0.5` - filthy!

Closing the open `060000.log` segment has added `1GiB` to the number of dirty bytes on this partition. 

We now have `1.5GiB` of clean bytes and `1.5GiB` of dirty bytes.  A `0.5` dirty ratio (`1.5GiB dirty/3.0GiB total closed`).  This partition is now eligible for cleaning.  The log cleaner thread will clean this partition on the following cleaning pass if it is the dirtiest
partition on the broker.

Once cleaning completes, it could look like this:

![dirty ratio 0.0](/images/2023/07/dirty-ratio-3.png "dirty ratio 0.0"){: .center-image }

Dirty ratio: `0.0` - squeaky clean!

Notice a couple of things about these new segments:
- The first starting segment has gone from `000000.log` to `001000.log`.  All keys for offsets between `0` and `999` 
must have had new events sharing the same key get purged as duplicates.  The first surviving offset on this topic is `1000`.
- We went from four closed segments to two.  As segments are compacted, they reconsolidate into larger segments.  `segment.bytes` determines the maximum segment size.

#### What configs should I change to get better compaction?

Short answer:

- [segment.ms](https://kafka.apache.org/documentation/#topicconfigs_segment.ms) (default: `604800000`, seven days) - change to `43200000` (12 hours)
- [max.compaction.lag.ms](https://kafka.apache.org/documentation/#topicconfigs_max.compaction.lag.ms) (default: infinity) - change to `86400000` (24 hours)

Changing `segment.ms` will close the open segment at least every 12 hours so that it is "dirty" and eligible to be compacted.  If this is not changed, slow-moving topics (less than `segment.ms=1GiB` of compacted data per week) will take one week to close the partition.

Changing `max.compaction.lag.ms` to 24 hours will make this partition eligible for compactions once per day.  

Longer answer:

Most people see `min.cleanable.dirty.ratio` (default `0.5`) and think that's the correct config to tweak.

Changing the `min.cleanable.dirty.ratio` is a poor choice for almost all topics.  Most people don't understand what this does and it leads to behavior that can be hard to understand.   It can also cause a partition to be cleaned far more often than is useful on fast-moving topics and can crowd out cleaning on other partitions.

I prefer setting `segment.ms` to 12 hours instead of 7 days, as closing a partition twice a day is not expensive.  This is better than changing `segment.bytes` (default `1GiB` of compacted data) as that can be dangerous for fast-moving topics.  Setting `segment.bytes` to `1MiB` on a topic producing gigabytes of data per day would create thousands of files on disk.  If we set `segment.ms` to 12 hours and it only has a few megabytes of data, compaction will reconsolidate those segments back into larger `segment.bytes`-sized segments when compaction runs.

Setting `max.compaction.lag.ms` to 24 hours will make the partition eligible for cleaning once per day.  It does 
not force the log cleaner to clean it exactly at the 24-hour mark.  The log cleaner will still clean the "dirtiest" eligible partition.  This setting makes the partition eligible once per day.

#### I published a new event with the same key as an older event, when will the older event be deleted?

With default topic settings on a slow-moving topic, duplicate events can take weeks to compact.  With a tuned topic, you're likely looking at ~24 hours before duplicates are removed.

Many things need to happen before an event is removed by compaction:

1.  The event's open log segment needs to be closed so it is no longer getting new events appended. 
2.  The partition must be eligible for cleaning either because `max.compaction.lag.ms` has elapsed or the `min.cleanable.dirty.ratio` for the topic has been breached.
3.  The partition needs to be selected for cleaning by the log cleaner.  The log cleaner always picks the "dirtiest" partition to clean, regardless of the `min.cleanable.dirty.ratio`.
4.  The log cleaner needs enough memory to clean all unique "dirty" keys in a single pass.  Otherwise, multiple cleaning passes will be necessary.  With default settings, the broker can [clean no more than ~5 million keys on a partition](#logmanager-and-logcleaner) in a single pass

[Another FAQ entry](#what-configs-should-i-change-to-get-better-compaction) has suggestions for configs to consider if you're not seeing the compaction you want.

#### How do I delete all events sharing a key on a compacted topic?

Publish a new event with the same key and a `null` body to the partition for that key.  This is called a "tombstone". Tombstones signal to the Kafka broker and consumers that the key should be removed.

If a new event is published after the tombstone with the same key, that new event will be kept by compaction. 


#### I still see tombstones on my partition, when will they be removed?

Tombstones must be cleaned at least twice before being removed from a partition.

The first time the log cleaner sees the tombstone, it is not deleted as that could cause a race condition for consumers.  If a tombstone was added to the open segment just before it is closed, then compaction runs right after it is closed.  That might not give consumers enough time to see the tombstone before it is deleted.

Kafka avoids this race condition with [delete.retention.ms](https://kafka.apache.org/documentation/#topicconfigs_delete.retention.ms) (default 24 hours).  This config value (which should be named `tombstone.retention.ms` IMO) determines how long the tombstone should be preserved in the logs after its first cleaning.

When the log cleaner first sees a tombstone, it writes it to the new segment along with a timestamp that it is safe to delete (cleaning time + `delete.retention.ms`).  Subsequent cleaning passes will only remove the tombstone if it is after that timestamp.

#### How can I tell if compaction has failed on a partition?

Partitions can be [marked as "uncleanable"](https://github.com/apache/kafka/blob/3ba718e1599dabcf737106df27d260ba518919e1/core/src/main/scala/kafka/log/LogCleaner.scala#L397-L399) if the log cleaner hits an exception while trying to clean it.  I've seen this happen when segment file on disk is corrupted and is unable to be parsed.

The `WARN`-level log message will look like this:

```
[kafka-log-cleaner-thread-0]: Unexpected exception thrown when cleaning log Log(dir=/data/kafka/fruit-prices-0, topic=fruit-prices, partition=0, highWatermark=1256427521, lastStableOffset=1256427521, logStartOffset=1165979137, logEndOffset=1256427521). Marking its partition (fruit-prices-0) as uncleanable
```

As cleaning is done independently on each broker, as long as the topic has a replication factor greater than one, the broker with the uncleanable partition can be removed from the topic.  A new broker will be elected as a partition replica, and it will copy the partition from another (hopefully healthy) replica.

#### When cleaning runs, is it guaranteed to clean all duplicates?

Nope.  

There are two reasons why duplicates will not be cleaned in a single pass.

1.  A newer key is in the open segment.  Cleaning looks at closed segments. 
If the latest event is still in the open segment (with default settings, this can take seven days), the log cleaner will not see the new event.

2.  The number of unique keys on a partition is more than the log cleaner can keep in memory.  The log cleaner will clean the subset it can remember.  The partition will then need to be selected again as the most "dirty" partition for subsequent cleaning.

Kafka brokers have config values controlling how many unique keys it can clean in a single pass. 

See ["Log Manager and Log Cleaner"](#logmanager-and-logcleaner) for a lot more detail.

#### How can I count the number of records on a topic?

The math is easy if the topic is not compacted (`cleanup.policy=delete`).  Take the offset of the latest record and subtract the offset of the earliest record still on the topic.  No compaction has happened on this partition, so all events between those offsets are guaranteed to exist still.

There's no quick and accurate answer if the topic is compacted (`cleanup.policy=compact`).  You've got a few options:

1.  Iterate over all events on the topic and count them.  Iterating is the only way to get an exact count.
2.  Iterate over all of the events on a partition and count them.  Then multiply that by the number of partitions.  You can check the size on the disk of all partitions to ensure a good distribution of events.
3.  Do an exact count once, then determine the average size of events given the compression ratio.  In the future, divide the current size of the partition by that known average event size for a reasonable estimate.

#### What signals tell if compaction cannot fully clean a partition in a single pass?

If you've got access to your Kafka brokers logs, look for messages like this that are a signal that the partition cannot be cleaned in a single pass:

`INFO` log level `kafka.log.LogCleaner`:

```
[kafka-log-cleaner-thread-2]:
  Log cleaner thread 2 cleaned log fruit-prices-12 (dirty section = [310715098, 325968881])
  25,706.8 MB of log processed in 1,554.6 seconds (16.5 MB/sec).
  Indexed 12,405.3 MB in 484.9 seconds (25.6 Mb/sec, 31.2% of total time)
  Buffer utilization: 90.0%
  Cleaned 25,706.8 MB in 1069.7 seconds (24.0 Mb/sec, 68.8% of total time)
  Start size: 25,706.8 MB (49,042,590 messages)
  End size: 13,219.4 MB (33,931,680 messages)
  48.6% size reduction (30.8% fewer messages)
```

`DEBUG` log level `kafka.log.LogCleaner`:

```
Cleaner 3: Offset map is full, 1 segments fully mapped, segment with base offset 470931255 is partially mapped
```

Notice the `Buffer utilization: 90%`?  That's our signal that we've hit the `0.9` default value for `log.cleaner.io.buffer.load.factor`.  The number of unique keys on this partition exceeds what can be cleaned in a single pass.

Not having enough room in the `OffsetMap` for all keys in a single segment is _very_ expensive.  Each cleaning pass needs to create a map of dirty keys and then compare those keys against all clean keys to remove duplicates. 

#### What is the maximum number of unique keys I should have per partition?

Low tens of millions with default settings to low hundreds of millions with modified cleaner settings.  

With default settings, ~5 million dirty keys on a partition can be cleaned in a single pass.  See ["Log Manager and Log Cleaner"](#logmanager-and-logcleaner) for more details.

#### How can I tell when compaction last ran on a partition?

Kafka broker logs are the best place to check.

If you don't have access to those, but you can consume from a topic using `kcat` and have GNU `awk` installed, you could try this script.  This will find the date of the earliest event where the prior offset is no longer present on the topic.  This is the last place where compaction provably happened. 

This script uses `kcat` to emit the offset (`%o`) and timestamp (`%T`) of each event on partition `0` of `my-topic` on `mybroker.example.com:9092`.  If your topic has security on it, you'll need to add additional flags to `kcat` to provide those credentials.

```shell
kcat -C -e -q -b "mybroker.example.com:9092" -t "my-topic" -p 0 -f '%o\t%T\n' |
  gawk'
    $1 > last_offset + 1 {
      last_gap_offset = $1
      last_gap_epoch = $2
      last_gap_row = NR
    }
    {
      last_offset = $1
      last_row = NR
    }
    END {
      print "last gap offset: ", last_gap_offset
      print "last gap row: ", last_gap_row
      print "last gap time: ", strftime("%Y-%m-%dT%H:%M:%S", substr(last_gap_epoch, 1, 10))
      print "last offset: ", last_offset
      print "last row: ", last_row
      print "contiguous ~dirty since gap: ", last_row - last_gap_row
    }
  '
last gap offset:  4156372102
last gap row:  39182297
last gap time:  2023-07-28T11:01:18
last offset:  4161793692
last row:  44603887
contiguous ~dirty rows since gap:  5421590
```

So this shows that the last time compaction ran on partition `0` on the lead broker was July 28th, 2023.

The `contiguous ~dirty rows since gap` value shows how many events are on the topic that could be dirty and eligible for compaction (once they are in a closed segment).

This script is the most accurate on fast-moving topics where duplicate events are relatively common.

#### Can a topic be compacted and use time-based deletion?

Yes!  If the topic uses `cleanup.policy=compact,delete`.

The partitions on this topic will delete all records older than [retention.ms](https://kafka.apache.org/documentation/#topicconfigs_retention.ms) (default: 7 days), even if they are the only record with that key.

Within that `retention.ms` period, closed segments will be compacted if the partition's "dirty ratio" (default `0.5`) threshold is surpassed.  The dirty ratio is the ratio of bytes on "dirty" closed segments that might have duplicates to total bytes (clean + dirty) in closed segments.

Compaction with deletion enabled removes the guarantee of preserving at least one value per key.  It adds a time horizon where even unique keys will be dropped.

`compact,delete` is used in situations where:
- values are time-sensitive and are not useful after some time
- downstream consumers do not need an explicit tombstone to signal deletion
- there is a periodic repopulation of all valid records on the topic

An example would be a topic with a 3-week `retention.ms`, and new values for the currently valid objects are published at least once per week.  This allows compaction within the 3-week window but values older than that will drop off the topic.

#### How can I use compaction but give consumers a guaranteed time window to see all messages before they are compacted?

You're looking for [min.compaction.lag.ms](https://kafka.apache.org/documentation/#topicconfigs_min.compaction.lag.ms) (default: `0`).  Set this to the number of hours/days that your consumers will be guaranteed to have consumed an event.

This gives you the advantages of compaction but guarantees consumers get time to see all events.


#### If I have a compacted topic, can I change the number of partitions?

Yes, but you will need to clear all data on the topic first.  Then change the number of partitions.  Finally, replay the upstream data so that all values are on the correct partition.  If you don't have a non-Kafka source of truth for the data, you could create a job to forward all existing events to a new topic with the desired partition count.

Kafka does not have any magic around re-partitioning.  Events are not shuffled as Kafka has no idea what partitioning strategy the publishers used to send messages.

If you do not do this, you will have old messages that live forever and that will never get updated.  Compaction is done per-partition and does not look at events that might share the same key on other partitions.  It assumes a consistent hashing strategy where all values with the same key are guaranteed to be on a single partition.

## How Topic Compaction Works

Kafka stores events published to a topic on a partition (topics have `3` partitions by default).  Each event has a `key`, a `value`, and optional `headers`.  Kafka appends new events to the end of that partition's open segment log file.  Events are assigned an `offset` that is a unique identifier for this event.  As events get appended to the end of the log, they do not share the `offset` or replace any previous events with the same key.

Events with the same key are [guaranteed to all be stored on the same partition](/2021/05/02/kafka-topic-partitioning-replication.html#how-are-kafka-topics-structured).  All new events will have an `offset` value one greater than the previous event.

Compaction happens at the partition-level, not at the topic-level.  If your topic somehow has the same key on multiple partitions, both partitions will keep a different event for that key (most common [if the number of partitions are changed](#if-i-have-a-compacted-topic-can-i-change-the-number-of-partitions)).

When compaction runs, it creates a map of the new keys on the partition paired with the highest offset of any event seen with that key.  It will then scan the partition from the beginning and purge older events now known to have been replaced by a newer event.

Compaction is enabled by setting the topic's [cleanup.policy](https://kafka.apache.org/documentation/#topicconfigs_cleanup.policy) configuration value to `compact`.

### Partition Compaction Example

Kafka stores partitions on disk in log files called "segments".  Each partition has one "open" segment where new event record batches will be appended.  Each event in the record batch will be assigned a monotonically increasing `offset`.  The first event on a partition will be at offset `0`. 

Here we've got a newly created topic, `fruit-prices`.  It likely has multiple partitions, but we're going to look at how events published to partition `0` are added and then compacted away.

The open segment file is `000.log` (the file name denotes the first `offset` in the segment with some zero-padding).

!["grape" event published to open segment](/images/2023/07/compaction-1.png "'grape' event published to open segment"){: .center-image }

The first event comes in with a key of `grape` and a value of `$2.69`.  It is appended to the open segment at offset `0`.

!['lime' event published to open segment](/images/2023/07/compaction-2.png "'lime' event published to open segment"){: .center-image }

A second event is published with the key `lime` and a value of `$0.49`.  It is appended to the open segment at offset `1`.

![new 'grape' tombstone event published to open segment](/images/2023/07/compaction-3.png "new 'grape' tombstone event published to open segment"){: .center-image }

A third event, with a `null` body, shares the `grape` key with our earlier event.  Events with `null` bodies are called "tombstones" and signal to Kafka and consumers to delete all prior `grape` values.  This event is appended to the open segment at offset `2`.  Notice that the previous `grape` value still exists at offset `0`.

!['lime' event published to open segment](/images/2023/07/compaction-4.png "'lime' event published to open segment"){: .center-image }

The next event also has the `lime` key, with an updated price value of `$1.59`.  This event is again appended to the open segment at offset `3`.  The `lime` event at offset `1` still exists and will be read by consumers, but they will eventually see `lime`'s updated price at offset `3`.

Until now, no compaction has occurred or could occur, as compaction never runs on the open segment.

A segment must be closed for it to be eligible for compaction.  Segments are closed for two reasons:

1.  Enough time passes.  When a segment has been open for [segment.ms](https://kafka.apache.org/documentation/#topicconfigs_segment.ms) it will be closed.  The default is `604800000` (seven days).
2.  Enough data has been published to the partition.  When the open segment has had [segment.bytes](https://kafka.apache.org/documentation/#topicconfigs_segment.bytes) of events written, it will be closed.  The default is `1073741824` bytes (`1GiB`).  This includes the event keys, bodies, headers, and a small number of bytes for each record batch.  When topic compression is used, this byte size is calculated after compression. 

If you're using a [compression.type](https://kafka.apache.org/documentation/#brokerconfigs_compression.type) of `zstd` and getting 90% compression on a topic with ten partitions, you'd need to write approximately ~100GiB of data to the topic for the open segment to exceed `1GiB` (default `segment.bytes`) and be closed in less than 7 days (default `segment.ms`).  1/10th of the keys are assigned to each partition, and each event is compressed to 1/10th of its original size, so we need to write ~100x the `segment.bytes` value within `segment.ms` for the open segment to be closed.

![close first segment, open new segment with new 'lime' value](/images/2023/07/compaction-5.png "close first segment, open new segment with new 'lime' value"){: .center-image }

For our example, let's say that seven days have passed since we wrote the first four events, hitting the default `segment.ms` threshold.  The `000.log` segment is closed and marked as "dirty," as it might have duplicates.  A new segment, `004.log`, is opened, and a new event with the key `lime` is appended to the open segment with an offset of `4`.

We need to talk about "dirty ratios". Kafka does not know how many duplicate keys are on a partition.  It only knows the number of uncleaned bytes in closed segments versus previously cleaned bytes in closed segments.  

The dirty ratio is the ratio of bytes for dirty events in closed segments divided by the total number of bytes in closed segments.  As this topic has never been cleaned, its dirty ratio is `1.0`.

This partition will be selected for cleaning when its dirty ratio exceeds the `0.5` value that is the default [min.cleanable.dirty.ratio](https://kafka.apache.org/documentation/#topicconfigs_min.cleanable.dirty.ratio).

![compaction runs on dirty closed segment, leaves tombstone](/images/2023/07/compaction-6.png "compaction runs on dirty closed segment, leaves tombstone"){: .center-image }

Kafka adds this partition to the list of partitions ready to be cleaned by a log cleaner thread.   The log cleaner scans the closed, dirty `000.log` segment where duplicates might occur.  It creates a map of 16-byte MD5 hashes of the keys and the highest offset (an 8-byte long) seen for that key within the dirty segment.  Each `md5(key)` and `offset` pair takes up 24 bytes of memory in the log cleaner's map.

```
md5(grape): 2
md5(lime): 3
```

Then the log cleaner starts reading from the beginning of the partition and creates a new "clean" segment file that keeps only the latest offsets for each key.  The new segment file is called `002.log` as offset `2` is the first offset it contains.  This new clean segment is closed when all unique dirty events in closed segments have been processed, or when the new segment hits the [segment.bytes](https://kafka.apache.org/documentation/#topicconfigs_segment.bytes) (default `1073741824`/`1GiB`). The new clean segment is swapped in to replace the old `000.log` segment.

The `grape` event at offset `0` and `lime` at offset `1` are not copied into the new segment as their offsets are less than the highest offset the log cleaner has found in the dirty section for those keys.

Notice that the `grape` tombstone at offset `2` was kept.  When written to `002.log`, Kafka added a timestamp to the tombstone when it is safe to delete (cleaning time + `delete.retention.ms`).  Kafka will keep tombstones (and transaction markers) to avoid race conditions for at least [delete.retention.ms](https://kafka.apache.org/documentation/#topicconfigs_delete.retention.ms) (default 24 hours) after the first cleaning.   

Tombstones _need to be cleaned at least twice_ before they are removed. 

I believe `delete.retention.ms` is a confusingly named config value.  It would be better with a name like "tombstone.retention.ms".  This property only controls when tombstones/transaction markers can be removed from the partition.  Many engineers I've talked with wrongly believe it controls how long Kafka will retain all events before deletion (it does not).

We also have a `lime` event in the open segment at offset `4`, but as the Kafka cleaner does not look at the open segment, we still have the `lime` event at offset `3` visible to consumers.

After compaction, the dirty ratio for the partition above is `0.0`.  All closed segments have been cleaned and are free of duplicates.  The partition will not be cleaned again until the open partition is closed.

![more events come into open segment, which is closed](/images/2023/07/compaction-7.png "more events come into open segment, which is closed"){: .center-image }

More time passes, and we've written a few more values for `guava` and `kiwi` to our `004.log` open segment.  After a week, segment `004.log` is closed and marked "dirty". A new segment, `008.log`, is opened, and a new value for `guava` is appended at offset `8`.

![compaction runs again and removes the 'lime' tombstone](/images/2023/07/compaction-8.png "compaction runs again and removes the 'lime' tombstone"){: .center-image }

Our dirty ratio (assuming all events are the same size) is now `0.67` (two events in the previously cleaned segment/six events in all closed segments).

The `0.67` dirty ratio exceeds the `min.cleanable.dirty.ratio` of `0.5`, and the partition is eligible to be cleaned.  The cleaner scans over the dirty offsets in the newly closed segment and creates a map MD5 key hashes to the highest offsets seen for that key:

```
md5(lime): 4
md5(guava): 6
md5(kiwi): 7
```

Notice that `grape` is not in the map.  That key only exists in the previously cleaned portion of the topic, where all keys are unique.

The log cleaner scans from the beginning of the partition and writes unique values to the new segment.

More than 24 hours (`delete.retention.ms`) have passed since first cleaning the `grape` tombstone, so it can finally be omitted from the new segment.

The new segment is named `004.log`; its first offset is `4`.

After cleaning, our partition again has a dirty ratio of `0.0`.  All closed segments are guaranteed to have unique keys.

Kafka's append-only design with background cleaning threads allows it to read and write quickly.  Writing never needs to read previous values.  It only appends them.  Reading can stream sequential segment files to consumers as they are already sorted by offset.  

## Log Cleaner Architecture and Configuration 

Kafka brokers have many configuration values that impact how cleaning works.  

If brokers aren't given enough cleaning resources, your partition might never get cleaned because the cleaning time is spent on the "dirtiest" partitions.

### LogManager and LogCleaner

Each broker has a single [LogManger](https://github.com/apache/kafka/blob/3.5/core/src/main/scala/kafka/log/LogManager.scala) thread and zero or more [LogCleaner](https://github.com/apache/kafka/blob/3.5/core/src/main/scala/kafka/log/LogCleaner.scala) threads.

The `LogManager` is responsible for:
- truncating any partitions with a `cleanup.policy` of `delete`
- creating any `LogCleaner` threads, `LogCleaner` threads handle any partitions with a `cleanup.policy` of `compact`

At startup, the `LogManager` checks to see if [log.cleaner.enable](https://kafka.apache.org/documentation/#brokerconfigs_log.cleaner.enable) is `true` (by default, it is on).  If it is enabled, it will create [log.cleaner.threads](https://kafka.apache.org/documentation/#brokerconfigs_log.cleaner.threads) (default: `1`)  `LogCleaner` instances.  


#### Topics with `cleanup.policy` of `delete` 

The `LogManager` removes events on partitions with a `cleanup.policy=delete` (but does not handle those with `compact` or `compact,delete`).

On startup, it [schedules](https://github.com/apache/kafka/blob/3.5/core/src/main/scala/kafka/log/LogManager.scala#L546-L550) a `kafka-log-retention` thread that will run every [log.retention.check.interval.ms](https://kafka.apache.org/documentation/#brokerconfigs_log.retention.check.interval.ms) (default 5 minutes).

When the `kafka-log-retention` job executes, it will start at the oldest log segment and [delete entire segments](https://github.com/apache/kafka/blob/938fee2b1fec52fa336f68118da120190bff4600/core/src/main/scala/kafka/log/LogManager.scala#L1253) where the newest events are older than `retention.ms` or that bring the partition log size above `retention.bytes`.

Note that this is intended to be a quick operation.  Segments are not split.  All events must be older than the retention period for a segment to be deleted.

#### Topics with a `cleanup.policy` of `compact`

If `log.cleaner.enable` is `true` and `log.cleaner.threads` is greater than `0`, the `LogManager` will instantiate independent `LogCleaner` threads that are responsible for compacting partitions with a `cleanup.policy` of `compact`.

Each `LogCleaner` thread runs independently, but locks ensure that two cleaning threads do not attempt to clean the same partition.

The high-level steps `LogCleaners` use for compacting topics are:

1.  Determine which partitions are eligible for cleaning.  A partition is eligible for cleaning either because:
  - the "dirty ratio" of uncleaned bytes in closed segments divided by bytes on all closed segments is compared against the [min.cleanable.dirty.ratio](https://kafka.apache.org/documentation/#topicconfigs_min.cleanable.dirty.ratio) (default `0.5`).  Note that this has nothing to do with the number of duplicate keys.  Kafka has no idea how many duplicate keys exist in a dirty segment till it is cleaned.
  - the partition has closed segments that have not been cleaned within [max.compaction.lag.ms](https://kafka.apache.org/documentation/#topicconfigs_max.compaction.lag.ms).  By default, this configuration is set to `9223372036854775807` (max long) so it is not enabled.  I recommend setting this value to the cadence you'd like cleaning to happen (ex: 24 hours) rather than changing the `min.cleanable.dirty.ratio`.  It will give much more predictable behavior.
  - if no partitions are eligible for cleaning, the thread sleeps for ~15 seconds and then checks again.
2.  Pick the partition with the highest dirty ratio from the list of partitions eligible for cleaning.
  - note that this means that if one high-traffic partition is constantly the dirtiest one, it can delay the cleaning of other less dirty partitions.
3.  Scan over the dirty events on the partition, add the 16-byte [MD5](https://github.com/apache/kafka/blob/3ba718e1599dabcf737106df27d260ba518919e1/storage/src/main/java/org/apache/kafka/storage/internals/log/CleanerConfig.java#L23) hash of the `key` and the current `offset` (an 8-byte `Long`) to the `OffsetMap`.
  - Each entry in the `OffsetMap` takes up 24 bytes of memory.
  - To prevent `OutOfMemoryError` exceptions, the size of the `OffsetMap` is constrained.   
  - [log.cleaner.dedupe.buffer.size](https://kafka.apache.org/documentation/#brokerconfigs_log.cleaner.dedupe.buffer.size) (default: `134217728`/128MiB) is divided equally across all `LogCleaner` threads.   If there is one thread, it gets all 128MiB.  If there are four threads, each one gets 32MiB.
  - [log.cleaner.io.buffer.load.factor](https://kafka.apache.org/documentation/#brokerconfigs_log.cleaner.io.buffer.load.factor) (default: `0.9`/90%) is the maximum amount of memory used in the `OffsetMap`.  Inserts into the `OffsetMap` are slower when the map approaches capacity.
  - So if we have a single cleaning thread with 128MiB of memory and a buffer load factor of 90%, we only have 115.2MiB of usable space.   
  - With each entry taking 24 bytes, we can fit slightly over 5 million keys into the 115.2MiB `ByteBuffer` backing the `OffsetMap`
  - If your partition has more than 5 million unique keys on it, it will not be able to be entirely cleaned in a single pass!  You can either increase the number of partitions on the topic or give the cleaner more memory.
4.  Scan from beginning of the partition and write events to a new clean segment if:
  - The `md5(key)` is absent in the `OffsetMap`.  This event has the key's highest known offset that we want to keep.
  - The `offset` for this event is the same as the `offset` stored at `md5(key)` in the `OffsetMap`.  This event is the newest seen with that key.
  - If the [compression.type](https://kafka.apache.org/documentation/#topicconfigs_compression.type) of the topic is `producer` (the default), maintain the compression type for this event's record batch.  Otherwise, use the compression type specified for the topic.

5.  If we find a tombstone or transaction marker in the "clean" section, check the age of the event's last cleaned timestamp.  If it is greater than `delete.retention.ms`, delete it.  Otherwise, preserve it.  Tombstones must be cleaned _at least twice_ before they're removed from the partition.
6.  If we write a maximum of `segment.bytes` (default: `1GiB` of data using the `compression.type`) to the new clean segment, close it and open a new segment.
7.  Swap completed segments in for the old segments and mark old segments for deletion.
8.  We're done if the `cleanup.policy` is just `compact`.  If `cleanup.policy=compact,delete`, the `LogCleaner` will then [delete segments](https://github.com/apache/kafka/blob/3ba718e1599dabcf737106df27d260ba518919e1/core/src/main/scala/kafka/log/LogCleaner.scala#L427) using the same logic above used by the `LogManager` for `cleanup.policy=delete`.
9.  GOTO #1, where the `LogCleaner` will recalculate the "filthiest" partition.  If this partition was not fully cleaned, it could pick the same partition again.



## Further Resources on Compaction

- The official [Confluent Kafka documentation on compaction](https://kafka.apache.org/documentation/#compaction)
- [Topic Compaction](https://developer.confluent.io/courses/architecture/compaction/), by Jun Rao, as part of Confluent's "Kafka Internals" video series.  
- [KIP-58: Make Log Compaction Point Configurable](https://cwiki.apache.org/confluence/display/KAFKA/KIP-58+-+Make+Log+Compaction+Point+Configurable)
- [KIP-71: Enable log compaction and deletion to co-exist](https://cwiki.apache.org/confluence/display/KAFKA/KIP-71%3A+Enable+log+compaction+and+deletion+to+co-exist)
- [KIP-87: Add Compaction Tombstone Flag](https://cwiki.apache.org/confluence/display/KAFKA/KIP-87+-+Add+Compaction+Tombstone+Flag)
- [KIP-280: Enhanced Log Compaction](https://cwiki.apache.org/confluence/display/KAFKA/KIP-280%3A+Enhanced+log+compaction)
- [KIP-354: Add a Maximum Log Compaction Lag](https://cwiki.apache.org/confluence/display/KAFKA/KIP-354%3A+Add+a+Maximum+Log+Compaction+Lag)