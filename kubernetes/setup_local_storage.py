import os
import re
import subprocess


def get_kube_nodes():
    k = subprocess.Popen(("kubectl", "get", "nodes"), stdout=subprocess.PIPE)
    g = subprocess.Popen(("grep", "kubernetes"), stdin=k.stdout, stdout=subprocess.PIPE)
    a = subprocess.Popen(("awk", "{print $1}"), stdin=g.stdout, stdout=subprocess.PIPE)
    output = subprocess.check_output(('tr', "\"\\n\"", "\",\""), stdin=a.stdout)
    output = str(output)
    k.wait()
    g.wait()
    a.wait()
    nodenames = list(filter(lambda x: "kubernetes" in x, filter(None, output.split(","))))
    return nodenames


def create_pv_type_for_node(params, template, irange):
    # Assume args already correctly set
    for i in irange:
        data = template
        params["dir_id"] = str(i)
        params["pv_name"] = params["node_name"] + "-" + str(i)

        for key, val in params.items():
            data = re.sub(f"<\\${key}>", str(val), data)

        s = subprocess.Popen(f"echo \"{data}\" | kubectl apply -f -", shell=True, stdout=open(os.devnull, 'wb'),
                             stderr=subprocess.STDOUT, close_fds=True)
        s.wait()


def setup_storage(nodenames):
    print("Setting up storage classes")
    subprocess.check_call("kubectl apply -f ./charts/storage-small.yaml", shell=True, stdout=open(os.devnull, 'wb'),
                          close_fds=True)
    subprocess.check_call("kubectl apply -f ./charts/storage-large.yaml", shell=True, stdout=open(os.devnull, 'wb'),
                          close_fds=True)

    num_pvs_per_type = {"coordinator": {"small": 4, "large": 0}, "follower": {"small": 100, "large": 32}}

    storage_size = {"small": 8000, "large": 55000}

    with open('./charts/persistentVolume.yaml', 'r') as file:
        template = file.read()

    params = {}
    for node in nodenames:
        directory_cursor = 0
        node_type = "coordinator" if node == "kubernetes-coordinator" else "follower"
        print("Setting up storage for node " + node + " which is a " + node_type)
        for storage_type in ["small", "large"]:
            print("\tSetting up " + storage_type + " storage persistent volumes.")
            params["storage_type"] = storage_type
            params["disk_size_pv"] = storage_size[storage_type]
            params["node_name"] = node

            num_pvs = num_pvs_per_type[node_type][storage_type]
            create_pv_type_for_node(params, template, range(directory_cursor, directory_cursor + num_pvs))
            directory_cursor += num_pvs


def main():
    nodenames = get_kube_nodes()
    setup_storage(nodenames)


if __name__ == "__main__":
    main()
