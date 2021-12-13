import time
import uuid
import sys
from confluent_kafka.cimpl import Consumer, TopicPartition

current_milli_time = lambda: int(round(time.time() * 1000))


def exec_benchmark(duration_s, fps, kafka_loc, output_topic):
    """Measures throughput at the output Kafka topic,
    by checking the growth in all partitions"""

    start_time = current_milli_time()

    # c, topic_partitions = create_consumer(kafka_loc, output_topic)

    c = Consumer({"bootstrap.servers": kafka_loc,
                  'group.id': 'benchmark-' + str(uuid.uuid4()),
                  'auto.offset.reset': 'latest',
                  'isolation.level': 'read_uncommitted'})
    topic = c.list_topics(topic=output_topic)
    partitions = [TopicPartition(output_topic, partition) for partition in
                  list(topic.topics[output_topic].partitions.keys())]

    # Print column names
    # TIME THROUGHPUT PART-0 ... PART-N
    columns = "TIME\tTHROUGHPUT"
    for i in range(len(partitions)):
        columns += "\tPART-{}".format(str(i))
    print(columns, flush=True)

    throughput_measured_per_partition = {}
    last_high_watermark = {}

    for p in partitions:
        _, high_watermark = c.get_watermark_offsets(p)
        last_high_watermark[p.partition] = high_watermark

    ms_per_update = 1000 / fps

    last_time = start_time
    last_write_time = start_time

    lag = 0.0

    current_time = start_time

    while current_time < start_time + duration_s * 1000:
        elapsed = current_time - last_time
        last_time = current_time
        lag += elapsed
        while lag >= ms_per_update:
            records_delta = 0
            curr_time_for_print = current_milli_time()
            time_delta = ((curr_time_for_print - last_write_time) / 1000)
            if time_delta > 0:
                last_write_time = curr_time_for_print
                for p in partitions:
                    _, high_watermark = c.get_watermark_offsets(p)
                    partition_records_delta = high_watermark - last_high_watermark[p.partition]
                    records_delta += partition_records_delta
                    throughput_measured_per_partition[p.partition] = partition_records_delta / time_delta
                    last_high_watermark[p.partition] = high_watermark

                output = f"{curr_time_for_print}\t{records_delta / time_delta}"
                for p in partitions:
                    output += f"\t{throughput_measured_per_partition[p.partition]}"
                print(output, flush=True)

            lag -= ms_per_update
        time.sleep(ms_per_update / 10 / 1000)
        current_time = current_milli_time()

    c.close()


def main():
    if len(sys.argv) != 5:
        print("Error! Usage: python3 {} duration_in_seconds readings_per_second kafka_bootstrap output_topic")
        exit(1)

    exec_benchmark(int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4])


if __name__ == "__main__":
    main()
