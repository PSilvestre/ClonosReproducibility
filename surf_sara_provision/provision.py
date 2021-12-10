import argparse
import os
import re
import time
import uuid

import oca

SURF_ENDPOINT = "https://api.hpccloud.surfsara.nl/RPC2"
SURF_USERNAME = "delta"

# NOTE There is a limit of 2048 GB Disk for surf sara group
defaults = {
   "coordinator_cpu": 8,
   "coordinator_memory": 16 * 1024,
   "coordinator_disk": 5 * 1024,

   "follower_cpu": 40,
   "follower_memory": 60 * 1024,
   "follower_disk": 100 * 1024,

   "num_followers": 6,

   "generator_cpu": 4,
   "generator_memory": 4 * 1024,

   "num_generators": 2
}

test = {
    "coordinator_cpu": 5,
    "coordinator_memory": 8 * 1024,
    "coordinator_disk": 32 * 1024,

    "follower_cpu": 10,
    "follower_memory": 10 * 1024,
    "follower_disk": 35 * 1024,

    "num_followers": 2,

    "generator_cpu": 4,
    "generator_memory": 4 * 1024,

    "num_generators": 0
}


def parse_args():
    parser = argparse.ArgumentParser(description='SurfSara Virtual Machine/Kubernetes Provisioning CLI')

    parser.add_argument("-cc", "--coordinator_cpu", type=int, default=defaults["coordinator_cpu"],
                        help="Number of CPUs for the coordinator")
    parser.add_argument("-cm", "--coordinator_memory", type=int, default=defaults["coordinator_memory"],
                        help="Memory in MB for the coordinator")
    parser.add_argument("-cd", "--coordinator_disk", type=int, default=defaults["coordinator_disk"],
                        help="Disk size in MB for the coordinator")

    parser.add_argument("-fc", "--follower_cpu", type=int, default=defaults["follower_cpu"],
                        help="Number of CPUs for the followers")
    parser.add_argument("-fm", "--follower_memory", type=int, default=defaults["follower_memory"],
                        help="Memory in MB for the followers")
    parser.add_argument("-fd", "--follower_disk", type=int, default=defaults["follower_disk"],
                        help="Disk size in MB for the follower")

    parser.add_argument("-nf", "--num_followers", type=int, default=defaults["num_followers"],
                        help="Number of followers")

    parser.add_argument("-gc", "--generator_cpu", type=int, default=defaults["generator_cpu"],
                        help="Number of CPUs for the generators")
    parser.add_argument("-gm", "--generator_memory", type=int, default=defaults["generator_memory"],
                        help="Memory in MB for the generators")
    parser.add_argument("-ng", "--num_generators", type=int, default=defaults["num_generators"],
                        help="Number of generators")

    parser.add_argument("-ssh", "--add_ssh_pkey", type=bool, default=True,
                        help="Whether to copy the public key at ~/.ssh/id_rsa.pub to the VMs")
    parser.add_argument("-pw", "--password", type=str, required=True)

    args = parser.parse_args()
    args = vars(args)
    if args["add_ssh_pkey"]:
        with open(os.path.join(os.path.expanduser('~'), ".ssh/id_rsa.pub"), 'r') as pub_fd:
            args["ssh_key"] = pub_fd.read()

    args["cluster_name"] = uuid.uuid4().hex

    return args


def read_template(args, template_path):
    with open(template_path, 'r') as file:
        data = file.read()
        for key, value in args.items():
            data = re.sub("<\\$" + key + ">", str(value), data)
        return data


def exec_create_generators(args, client):
    generator_template = read_template(args, "./Generator.def")

    ids = []
    for i in range(args["num_generators"]):
        id = oca.vm.VirtualMachine.allocate(client, generator_template)
        ids.append(id)
    time.sleep(60 * 5)
    ips = []
    for id in ids:
        vm = oca.VirtualMachine.new_with_id(client, id)
        vm.info()
        ip = vm.template.nics[0].ip
        ips.append("ubuntu@" + str(ip))

    print(";".join(ips))


def exec_create_followers(args, client):
    follower_template = read_template(args, "./Follower.def")
    for i in range(args["num_followers"]):
        oca.vm.VirtualMachine.allocate(client, follower_template)



def exec_create_coordinator(args, client):
    coordinator_template = read_template(args, "./Coordinator.def")
    coordinator_id = oca.vm.VirtualMachine.allocate(client, coordinator_template)

    time.sleep(60 * 5)

    coordinator = oca.VirtualMachine.new_with_id(client, coordinator_id)
    coordinator.info()
    coordinator_ip = coordinator.template.nics[0].ip
    print(str(coordinator_ip))


def main():
    args = parse_args()
    surf_password = args["password"]
    client = oca.Client(SURF_USERNAME + ":" + surf_password, SURF_ENDPOINT)

    exec_create_coordinator(args, client)
    exec_create_followers(args, client)
    exec_create_generators(args, client)



if __name__ == "__main__":
    main()
