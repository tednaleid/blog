---
title: Kafka Topic Partitioning and Replication Critical Configuration Tips
---

#### tl;dr - Kafka configs you should consider using

##### Broker/Topic Configs
- `min.insync.replicas=2` (default: 1)
- `compression.type=producer` (keep this default)
- create topics with a partition replication factor of `3`

##### Producer Configs
- `acks=all` (default: `1`) 
- `compression.type=lz4` (default: `none`)
- `linger.ms=100` (default: `0`, Kafka Streams uses `100` ms)
- `max.request.size=4194304` (4MB, default: `1048576` - 1MB)
- `batch.size` - increase for larger batches or bigger messages (default: `16384` - 16KB)
- `buffer.memory` - increase for high-throughput apps (default: `33554432` - 32MB) 
- if order matters
  - add a `key` to all of your messages
  - `max.in.flight.requests.per.connection=1` (default: `5`)

There are caveats for all of these, read on for further discussion.

## Who is this post intended for?

This is the information about understanding Kafka partitioning and replication that I've been trying to search for
the last couple of years.  I finally stopped searching and [read the source code](https://github.com/apache/kafka/tree/trunk/core/src/main).

This post assumes quite a bit of familiarity with how Kafka works at the 10k foot level. It dives into the details
and describes which config settings you should be looking at when tuning your system.

## How are Kafka Topics structured?

Kafka topics hold a series of ordered events (also called records). The `mango` record is the oldest and `pear` is 
the newest.  Any new records would be added after `pear`.  

![Kafka Topic](/images/2021/05/kafka_topic.png "Kafka Topic"){: .center-image }

This conceptual model breaks down when you learn more about Kafka. In reality, Kafka topics have a number of components 
to increase the reliability and throughput of each topic. These components also increase complexity and are worth
learning more about if you want to be able to reason about how your data will flow through the system.

### Topic Partitions

A topic is split into one or more zero-based partitions, with each partition having approximately the same fraction
of records on it.

It is the Kafka producer's job to create new records and decide which partition a record should go to.  It uses a
[partitioning strategy](https://kafka.apache.org/documentation/#producerconfigs_partitioner.class)
to decide which partition a record should be sent to. 

The 
[default partitioner](https://github.com/apache/kafka/blob/2.8/clients/src/main/java/org/apache/kafka/clients/producer/internals/DefaultPartitioner.java#L25-L33)
uses this algorithm:

1. if the user assigned an explicit partition, use it
2. else if the record has a key, use the key's hash to determine the partition
3. else add the record to a batch and send it to a random partition

### Default Partitioner Algorithm Details
#### 1. If the user assigned an explicit partition, use it 
    
If the producer has manually assigned a record to a partition, it will honor that choice.  If explicit partitions are used, it 
is the producer's responsibility to ensure that records are balanced across the partitions.

This is useful when you want to partition your records using something other than just the key.  

Kafka [uses this strategy internally on its `__consumer_offsets` topic](https://docs.confluent.io/platform/current/clients/consumer.html#consumer-groups) 
that tracks the state all consumers' `group.id`s. Messages are keyed on `group.id` + topic name + partition, but are 
partitioned on just the `groupId`.  This allows new consumers to subscribe to a single partition that will hold all 
updates for their `group.id`.

Example command to see data on the `__consumer_offsets` topic
```
kafka-console-consumer --bootstrap-server localhost:9092 --topic __consumer_offsets \
  --formatter 'kafka.coordinator.group.GroupMetadataManager$OffsetsMessageFormatter' \
  --partition 0 --from-beginning
```

Here are two example output lines for from `__consumer_offsets` partition `0`. It shows two records
for the `my-group-id-39` group id on the `fruit-prices` topic.  One for partition `1` with a 
commit value at `offset=5497`, and another for partition `0` with a value of `offset=3550`.

```
[my-group-id-39,fruit-prices,1]::OffsetAndMetadata(offset=5497, leaderEpoch=Optional.empty, metadata=, commitTimestamp=1619425537926, expireTimestamp=None)
[my-group-id-39,fruit-prices,0]::OffsetAndMetadata(offset=3550, leaderEpoch=Optional.empty, metadata=, commitTimestamp=1619425553694, expireTimestamp=None)
```

#### 2. else if the record has a key, use the key's hash to determine the partition


If the record hasn't been assigned an explicit partition, but it does have a key, then the partition is determined by 
calculating the [`murmur2` 32-bit hash of the key](https://github.com/apache/kafka/blob/2.8/clients/src/main/java/org/apache/kafka/clients/producer/internals/DefaultPartitioner.java#L71)
modulus the number of partitions on the topic[^kafkapartitions].

```
murmur2_32("mango").absoluteValue % 3  -> partition 0
murmur2_32("banana").absoluteValue % 3 -> partition 1
murmur2_32("apple").absoluteValue % 3  -> partition 1
murmur2_32("lime").absoluteValue % 3   -> partition 0
murmur2_32("grape").absoluteValue % 3  -> partition 2
murmur2_32("pear").absoluteValue % 3   -> partition 2
``` 

![Keys to Partitions](/images/2021/05/kafka_keys_to_partitions.png "Keys to Partitions"){: .center-image }

Each record is stored with an `offset` number. An `offset` is a monotonically increasing sequence number that starts 
at `0`.  A partition will never change the offset assigned to a record and will never assign a different record to 
that offset.

Example: The record with the key `"lime"` hashes to partition `0`.  It was assigned an offset of `1` because it is
the second record on that partition.

Adding a `key` to a record will ensure that all messages with the same key will be sent to the same partition.  This
is useful for consumers who only care about a subset of the data.  It also ensures that there aren't race conditions
when updating a value or, if you're using a compacted topic, that the latest value is preserved.

#### 3. else add the record to a batch and send it to a random partition

If the record wasn't assigned an explicit partition and it doesn't have a key, it will be added to a batch of records 
that will be [sent to a random partition](https://github.com/apache/kafka/blob/2.8/clients/src/main/java/org/apache/kafka/clients/producer/internals/StickyPartitionCache.java#L60-L63).

After each record batch is sent, a new partition [will be picked for the next batch](https://github.com/apache/kafka/blob/2.8/clients/src/main/java/org/apache/kafka/clients/producer/internals/DefaultPartitioner.java#L76-L82)
(assuming there is more than one partition for the topic).

### Producer Record Batching

Once the partition for a record has been determined, the producer will add that record to a [record batch](https://kafka.apache.org/documentation/#recordbatch) 
destined for that topic partition.

Record batches have a few benefits:

- more efficient compression, all records in the batch are compressed together
- they reduce the number of individual requests to the Kafka brokers which reduces overhead and increases throughput

#### Record Batch Compression

Compressing record batches trades a little bit of CPU for a significant reduction in network bandwidth and disk space 
usage.

Unless the values of your records are already compressed, your producers should be using compression. 
Start with [`compression.type`](https://kafka.apache.org/documentation/#producerconfigs_compression.type) of `lz4` in 
your producer config.  It can be worth comparing `lz4` compressed size and performance with `snappy` and `zstd` 
with your real data.  

Don't use `gzip`, it is almost always strictly worse than the other options.

Even if your individual record values are already compressed, there can be advantages to using compression as the 
entire [record (including the key, value, headers and other attributes)](https://kafka.apache.org/documentation/#record)
will be added to a [record batch](https://kafka.apache.org/documentation/#recordbatch).  This lets the compression
algorithm find repeated sections across all records in the batch.

Most broker/topic configs should keep the default [`compression.type`](https://kafka.apache.org/documentation/#brokerconfigs_compression.type)
of `producer`. This lets the Kafka broker know that the [producer will handle compression](https://github.com/apache/kafka/blob/2.8/core/src/main/scala/kafka/message/CompressionCodec.scala#L61-L66) 
and it will not spend time re-compressing the record batch.

If your broker specifies a codec that [is different than the producer's codec](https://github.com/apache/kafka/blob/2.8/core/src/main/scala/kafka/log/LogValidator.scala#L377) 
it will re-encode the batch with the broker's preferred codec.  This can put significant burden on the brokers' memory
and CPU. It is better to offload compression to the producers if possible.

### How Many Records will fit in a Batch?

Napkin math: (average compressed record's size in bytes)/(batch.size bytes - 61 bytes) 

The batch record header always takes up [61 bytes](https://github.com/apache/kafka/blob/2.8/clients/src/main/java/org/apache/kafka/common/record/DefaultRecordBatch.java#L127).

So if your average compressed record (including key, value, and headers) is 500 bytes and you use the `batch.size` of
`16384`, you can expect to have 32 records in the average batch.

If your average compressed record takes up 32KB, every "batch" will be a record by itself.  

#### Batch Config Details 

A producer will batch up to [`batch.size`](https://kafka.apache.org/documentation/#producerconfigs_batch.size) bytes 
(default `16384` - 16KB) of compressed records (minus a little overhead for the batch's metadata) per topic partition.

If a single compressed message is larger than `batch.size`, that record will be in a batch by itself.

Additionally, the producer will allocate a pool of [`buffer.memory`](https://kafka.apache.org/documentation/#producerconfigs_buffer.memory)
(default: `33554432` - 32MB) bytes that is shared for all active and in-flight compressed record batches across every 
topic partition.

The pool of `buffer.memory` will be allocated in `batch.size` chunks that are cleared and reused by the producer for
garbage collection efficiency reasons.

If a batch isn't full it will wait up to [`linger.ms`](https://kafka.apache.org/documentation/#producerconfigs_linger.ms) 
milliseconds (default `0`) after the last message has been added to the batch before sending it. `linger.ms` is not enabled by 
default, but can help reduce the number of requests sent without much additional latency if you set it to a low value.

So if your average compressed record is 32KB, you'll want to test out significantly increasing `batch.size` by  
10-20x and possibly also `buffer.memory` depending on how many unique topic partitions you could produce to.

### What Configs Limit the Maximum Record Size?

The producer's [`max.request.size`](https://kafka.apache.org/documentation/#producerconfigs_max.request.size) (default 1MB)
config controls the maximum size of a record in **uncompressed bytes**[^gorydetailsmaxrequestsize].  

This can be a very confusing setting, because there is a similar sounding
[broker](https://kafka.apache.org/documentation/#brokerconfigs_message.max.bytes) / [topic](https://kafka.apache.org/documentation/#topicconfigs_max.message.bytes)
config called `message.max.bytes` that _also_ has a default of 1MB, but `message.max.bytes` is what the broker 
will accept **after compression**.  

This means that if you're compressing messages on the producer and want to send **compressed** records as large as
1MB over the wire, you will want to increase the producer's `max.request.size` by 400%+ to 4MB (this assumes your 
compressed messages are <25% the uncompressed size).  The broker will still reject batches with compressed records 
that are above its `message.max.bytes` limit with a `RecordTooLargeException`.

### Will a Broker ever store records in a different order than they were sent?

With the default settings? Yes, record batches on the same partition can end up in a different order than intended.

Records within a record batch will always be in the order that they were sent.

By default, a producer will [retry failed requests](https://kafka.apache.org/documentation/#producerconfigs_retries)
and it also allows [multiple concurrent record batches to be in-flight to a broker simultaneously](https://kafka.apache.org/documentation/#producerconfigs_max.in.flight.requests.per.connection).

With these settings, if record batch `A` fails and is retried, it could arrive after record batch `B` has been 
saved and acknowledged by the broker.

Some options for preventing this:
1. Set `max.in.flight.requests.per.connection=1` to allow only one batch to be sent to a broker at a time[^guaranteemessageorder].
2. Set `retries=0` and crash before committing if a publish fails.  On restart, the messages will be tried again.
3. Keep track of the offset assigned to records in the producer's `send` callback and crash before committing if they are ever out of order.  On restart, the messages will be sent again.
4. Turn on idempotent messages with [`enable.idempotence=true`](https://kafka.apache.org/documentation/#producerconfigs_enable.idempotence) or `processing.guarantee=exactly_once` [with Kafka Streams](https://www.confluent.io/blog/enabling-exactly-once-kafka-streams/).  This adds transactions and ["exactly once" delivery of messages](https://cwiki.apache.org/confluence/display/KAFKA/KIP-447%3A+Producer+scalability+for+exactly+once+semantics) which have their own costs.

Option #1 is probably the easiest, though it's worth testing the effect of your system's throughput.

## Partition Leader and Replicas

For each topic partition, there will be a broker that is the partition's "leader", and zero or more "replicas".  

A topic has a [replication factor](https://kafka.apache.org/documentation.html#basic_ops_add_topic) that determines how 
many copies of data should be kept. A replication factor of `1` means that the records will only exist on the partition
leader.  If that broker crashes, the data can be lost.  All replicas after the first are backup copies of the data. 
Their data will only be used if the leader dies, or a new leader is elected.

**Data is written to, and read from, the broker that is the partition's leader.**  If you try to consume directly
from a replica, it will redirect you to the current leader for the partition.[^rackawareconsumer]

For topics where you want to avoid data loss, you should have a replication factor of `3` (all data on the leader + 2 replicas)
and set [`min.insync.replicas=2`](https://kafka.apache.org/documentation.html#topicconfigs_min.insync.replicas) 
to ensure that the leader and at least one replica must acknowledge receipt of the record.

The producer should use [`acks=all`](https://docs.confluent.io/platform/current/clients/producer.html#ak-producer-configuration) (default: `1`).
This tells the producer to wait for the leader and all currently in-sync replicas to acknowledge that they've 
persisted the record.  The default of `1` will only wait for the leader to acknowledge it, if the leader dies before
the data is replicated those records could be lost.

### Replication Example

Our `fruit-prices` topic has `3` partitions, a `replication-factor` of `3`, `min.insync.replicas=2` and a producer using 
`acks=all`.

#### Scenario 1: all replicas are in-sync with the leader

When producing a record, it will be sent to the leader (Broker 101) as well as both in-sync replicas 
(Brokers 100 and 104).

When consumers read a record, it will always come from the leader (Broker 101).

![Happy Kafka Partition Replication](/images/2021/05/kafka_replication_happy.png "Happy Kafka Replication"){: .center-image }

If you `describe` a kafka topic in this state you'll see: 

```
kafka-topics --bootstrap-server 127.0.0.1:9092 --topic user-events --describe
Topic:user-events	PartitionCount:3	ReplicationFactor:3	Configs:min.insync.replicas=2,cleanup.policy=compact,segment.bytes=1073741824,retention.ms=172800000,min.cleanable.dirty.ratio=0.5,delete.retention.ms=86400000
Topic: user-events  Partition: 0	Leader: 101	Replicas: 101,100,104	Isr: 101,100,104
Topic: user-events  Partition: 1	Leader: 104	Replicas: 104,101,102	Isr: 104,101,102
Topic: user-events  Partition: 2	Leader: 102	Replicas: 102,100,103	Isr: 102,100,103
```

The `Isr` ("In Sync Replicas") column shows that all replicas are in-sync with the leader of the partition.

#### Scenario 2: only one replica is in-sync with the leader

If one broker becomes unreachable, or is lagging behind for some reason, you're still able to produce to the topic and
consume from it.

This is why having a replication factor of 3 is often desirable.  The cluster can tolerate a broker being down but still
maintain guarantees about not having the data in a single, vulnerable place.

![Kafka Partition Replication Caution](/images/2021/05/kafka_replication_caution.png "Kafka Replication Caution"){: .center-image }

The `"guava"` record is able to be produced to Broker 101 and replicated to Broker 100.  The consumer is able to 
consume the `"guava"` record from the leader, Broker 101.  Broker 104 being out of sync doesn't stop the cluster from continuing to work.

If you `describe` a Kafka topic in this state it will look like this: 

```
kafka-topics --bootstrap-server 127.0.0.1:9092 --topic user-events --describe
Topic:user-events	PartitionCount:3	ReplicationFactor:3	Configs:min.insync.replicas=2,cleanup.policy=compact,segment.bytes=1073741824,retention.ms=172800000,min.cleanable.dirty.ratio=0.5,delete.retention.ms=86400000
Topic: user-events  Partition: 0	Leader: 101	Replicas: 101,100,104	Isr: 101,100
Topic: user-events  Partition: 1	Leader: 104	Replicas: 104,101,102	Isr: 104,101,102
Topic: user-events  Partition: 2	Leader: 102	Replicas: 102,100,103	Isr: 102,100,103
```

The `Replicas` column shows that there are three replicas, but only 2 `Isr` (In Sync Replicas): 101 and 100. Broker 
104 is a replica, but it is not in-sync.  It is likely trying to catch up, but this is a signal that the broker should 
be looked at to see why it is not caught up if it lasts more than a minute or two.

#### Scenario 3: no replicas in-sync with the leader

No replicas are currently in-sync with the leader, all producers are halted because the cluster cannot meet 
the `min.insync.replicas=2` setting.

Consumers _can_ still retrieve any values they haven't seen (as long as they can reach the leader), but will soon
run out of events to process.

![Kafka Partition Replication Unhappy](/images/2021/05/kafka_replication_unhappy.png "Unhappy Kafka Replication"){: .center-image }

If you `describe` this Kafka topic you'll see that there is only a single `Isr` ("In Sync Replica"), Broker 101, the leader.

```
kafka-topics --bootstrap-server 127.0.0.1:9092 --topic user-events --describe
Topic:user-events	PartitionCount:3	ReplicationFactor:3	Configs:min.insync.replicas=2,cleanup.policy=compact,segment.bytes=1073741824,retention.ms=172800000,min.cleanable.dirty.ratio=0.5,delete.retention.ms=86400000
Topic: user-events  Partition: 0	Leader: 101	Replicas: 101,100,104	Isr: 101
Topic: user-events  Partition: 1	Leader: 104	Replicas: 104,101,102	Isr: 104,101,102
Topic: user-events  Partition: 2	Leader: 102	Replicas: 102,100,103	Isr: 102,100,103
```

One way to get in this situation would be if the other replicas' brokers crashed and new brokers were picked to
be replicas for the partition. Those brokers will start streaming the existing records from the leader, but will not 
be "in sync" till they have replicated all the data on the leader.

The leader [checks that there are enough in-sync replicas](https://github.com/apache/kafka/blob/2.8/core/src/main/scala/kafka/cluster/Partition.scala#L1062-L1063)
before persisting the record batch, but there is a possible race condition where it can persist to its log before 
discovering the outage. In this case, it will [return an error to the producer](https://github.com/apache/kafka/blob/2.8/core/src/main/scala/kafka/cluster/Partition.scala#L845-L848) 
so it will resend the record batch.

[^kafkapartitions]: I've created a [simple kotlin script](https://github.com/tednaleid/kotlin-scripts/blob/master/scripts/kafkapartition.main.kts) that can determine the partition for a given key.
[^gorydetailsmaxrequestsize]: If you want the gory details for where the producer calculates the uncompressed size of a record look at the [`KafkaProducer`](https://github.com/apache/kafka/blob/2.8/clients/src/main/java/org/apache/kafka/clients/producer/KafkaProducer.java#L937-L939) and [`AbstractRecords`](https://github.com/apache/kafka/blob/2.8/clients/src/main/java/org/apache/kafka/common/record/AbstractRecords.java#L135) classes.
[^guaranteemessageorder]: Kafka translates this [setting to `guaranteeMessageOrder` on the `Sender` class](https://github.com/apache/kafka/blob/2.8/clients/src/main/java/org/apache/kafka/clients/producer/KafkaProducer.java#L475) and will "mute" other partitions from being sent while that one is in-flight.
[^rackawareconsumer]: One caveat to this is if you're using Kafka's [rudimentary rack awareness feature](https://kafka.apache.org/documentation/#basic_ops_racks) with this, it is possible for the read to [come from a replica](https://cwiki.apache.org/confluence/display/KAFKA/KIP-392%3A+Allow+consumers+to+fetch+from+closest+replica) where the [`broker.rack`](https://kafka.apache.org/documentation.html#brokerconfigs_broker.rack) matches the [`client.rack`](https://kafka.apache.org/documentation.html#consumerconfigs_client.rack).

