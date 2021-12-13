import argparse
import time
import uuid
import json

from confluent_kafka.cimpl import Consumer, TopicPartition, OFFSET_END

current_milli_time = lambda: int(round(time.time() * 1000))


def sample_output_topic(args):
    num_partitions = int(args["num_partitions"])
    mps = int(args["measures_per_second"])
    experiment_duration = int(args["duration"])
    topic = args["output_topic"]
    input_ts_in_msg = args["input_ts_in_msg"]

    consumers = create_consumers(args, num_partitions)

    ms_per_update = 1000 / mps

    start_time = current_milli_time()
    last_time = start_time
    current_time = start_time

    lag = 0.0

    while current_time < start_time + experiment_duration * 1000:
        elapsed = current_time - last_time
        last_time = current_time
        lag += elapsed
        while lag >= ms_per_update:
            step(consumers, topic, input_ts_in_msg)
            lag -= ms_per_update
        time.sleep((ms_per_update / 10) / 1000)
        current_time = current_milli_time()

    for i in range(num_partitions):
        consumers[i].close()


def step(consumers, topic, input_ts_in_msg):
    # Get one message from each consumer
    output = ""
    for partition, c in enumerate(consumers):
        msg = poll_next_message(c, partition, topic)
        tup = process_message(msg, input_ts_in_msg)
        output += f"\t{tup[0]}\t{tup[1]}\t{tup[2]}\t{tup[3]}"
    print(output.strip(), flush=True)


def poll_next_message(c, partition, topic):
    msg = None
    while msg is None:
        try:
            c.seek(TopicPartition(topic, partition, OFFSET_END))
            msg = c.poll(timeout=0.05)
        except Exception as e:
            continue

    return msg


def process_message(msg, input_ts_in_msg, visibility_ts=0):
    if input_ts_in_msg:
        dict_msg = json.loads(msg.value())
        input_ts = int(dict_msg["inputTS"])
    else:
        input_ts = int(str(msg.value().decode('utf-8')).split(",")[0])

    output_ts = int(msg.timestamp()[1])
    if visibility_ts == 0:
        return input_ts, output_ts, visibility_ts, output_ts - input_ts
    else:
        return input_ts, output_ts, visibility_ts, visibility_ts - input_ts


def create_consumers(args, num_partitions):
    consumers = []
    for i in range(num_partitions):
        oc = Consumer({
            'bootstrap.servers': args["kafka"],
            'group.id': str(uuid.uuid4()),
            'auto.offset.reset': 'latest',
            'api.version.request': True,
            'isolation.level': 'read_uncommitted',
        })
        oc.assign([TopicPartition(args["output_topic"], i)])
        oc.poll(0.5)
        consumers.append(oc)
    return consumers


def get_latency(args):
    num_partitions = int(args["num_partitions"])

    print_header(num_partitions)
    sample_output_topic(args)


def print_header(num_partitions):
    header = "INPUT-0\tOUTPUT-0\tVISIBLE-0\tLATENCY-0"
    for i in range(1, num_partitions):
        header += "\tINPUT-{}\tOUTPUT-{}\tVISIBLE-{}\tLATENCY-{}".format(i, i, i, i)
    print(header, flush=True)


def parse_args():
    parser = argparse.ArgumentParser(description='End to end latency measurer')
    parser.add_argument("-k", "--kafka", help="The location of kafka. A comma separated list of ip:port pairs.")
    parser.add_argument("-o", "--output-topic", help="The output topic")
    parser.add_argument("-d", "--duration", help="Duration of experiment", default=120)
    parser.add_argument("-mps", "--measures-per-second",
                        help="The number of measurements to perform every second",
                        default=2)
    parser.add_argument("-p", "--num-partitions", help="The number of partitions", default=1)
    parser.add_argument('--nexmark', dest='input_ts_in_msg', action='store_false')
    parser.add_argument('--synthetic', dest='input_ts_in_msg', action='store_true')
    args = parser.parse_args()
    args = vars(args)
    return args


def main():
    args = parse_args()
    get_latency(args)


if __name__ == "__main__":
    main()
