# Kubernetes CPI Release

This is an experimental release of a BOSH Cloud Provider that targets
Kubernetes clusters. The goal is to deploy and management of BOSH packaged
software on Kubernetes nodes.

## Installation

### Requirements

* Configured Go Path
* [Go Binaries](https://golang.org/)
* [Godep](https://github.com/tools/godep)
* [Glide](https://github.com/Masterminds/glide)
* [Bosh CLI](https://bosh.io/docs/cli-v2/)
* [Docker](https://docs.docker.com/install/)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl) configured to access kubernetes

### Creating a stemcell

Clone the repository
```
$ git clone https://github.com/evoila/kubernetes-cpi-release.git
```

Get the required bosh agent  
```
$ go get github.com/cloudfoundry/bosh-agent
 ```
Edit the build script `kubernetes-cpi-release/stemcell/build-stemcell` and execute it.  
The latest version number you can use can be found [here](https://bosh.io/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent).  
Upload the latest stemcell to docker hub with the `push-image` script.

### Creating the kubernetes-cpi-release

Download the CPI submodule dependencies
```
$ cd kubernetes-cpi-release
$ git submodule init
$ git submodule update
```

Clone the kubernetes-cpi into GOPATH
```
$ mkdir -p $GOPATH/src/github.com/evoila
$ cd $GOPATH/src/github.com/evoila
$ git clone https://github.com/evoila/kubernetes-cpi.git
```
Download the dependencies of the kubernetes-cpi
```
$ cd $GOPATH/src/github.com/evoila/kubernetes-cpi/
$ glide update
```

Because the dependencies of the kubernetes-cpi won't automatically get copied into the kubernetes-cpi-release folder it is necessary to execute the glide update there too
```
$ cd kubernetes-cpi-release/src/github.com/evoila/kubernetes-cpi/
$ glide update
```

Sync the kubernetes-cpi package specs
```
$ cd kubernetes-cpi-release
$ ./scripts/sync-package-specs
```

Create the bosh release tarball
```
$ cd kubernetes-cpi-release
$ bosh create-release --tarball=./kubernetes-cpi-release-1.tgz --force
```

### Deploying the bosh director

**Note:** Make sure that Kubernetes got a default storageclass configured, else the deployment will fail.  

Create the necessary namespace and services for bosh
```
$ kubectl create -f ./scripts/services/
```
These services are needed for internal and external communication.  
Edit the files located in `./scripts/deployment/kubeconfig` that they match your certificates of your kubernetes cluster.  
Edit all variables marked with `<...>` in the deployment script `./scripts/start.sh` that it matches your configuration.  
Execute the script
```
$ cd kubernetes-cpi-release
$ ./scripts/start.sh
```
Wait for the deployment to finish.
Update the bosh director cloud-config (Login Credentials for the bosh deployment can be found in `./scripts/deployment/bosh-env/creds.yml`)
```
$ bosh -e kubernetes login
Using environment 'x.x.x.x:31003'

Username (): admin
Password ():

Using environment 'x.x.x.x:31003' as client 'admin'
$ bosh -e kubernetes update-cloud-config ./scripts/deployment/kubernetes-cpi/cloud-config.yml
```
Upload the stemcell to the bosh director
```
bosh -e kubernetes upload-stemcell ./stemcell/bosh-stemcell-xxxx.xx-kubernetes-ubuntu-trusty-go_agent.tgz
```
After that you will have a working bosh director in a kubernetes cluster.

## Current Status

* light stemcells can be created as docker images that are
  [built](stemcell/build-stemcell) from the [warden stemcell][warden-stemcell]
  tarball

See [issues](#issues) for additional information.

## Mapping BOSH to Kubernetes

### Virtual Machines

A `Pod` is used to implement a BOSH _virtual machine_. The pod consists of a
single privileged container that runs the BOSH agent. The container is
privileged to allow the agent to run commands like `mount` that require
elevated capabilities.

An `emptyDir` `Volume` is created to act as the ephemeral disk. The contents
of the volume are permanently deleted when the pod is deleted or moved to a
different Kubernetes node.

Pods are named after the BOSH agent they host and any Kubernetes objects
related to the agent are labeled with the agent ID. This allows for easy
identification and selection.

When possible, labels are used to hold BOSH _virtual machine_ metadata like
job name and index.

### Persistent Disks

A `PersistentVolumeClaim` is used to implement a BOSH _persistent disk_. When
a claim is created, Kubernetes searches for an available `PersistentVolume`
that satisfies its claim. When a match is found (or provisioned), the
persistent volume is bound to the claim.

When BOSH instructs the CPI to attach a _persistent disk_ to a _virtual
machine_, the `Pod` that backs the _virtual machine_ will be deleted and a new
`Pod` will be created with a `Volume` that references the persistent disk's
`PersistentVolumeClaim`. This implementation has some side effects that are
described in the [issues](#issues) below.

### Networks

The Kubernetes network model allocates a unique IP address to each pod that is
used in the cluster. That means that BOSH _dynamic_ networks are mostly
supported out of the box. Unfortunately, when a pod terminates or moves to a
new node, its IP address can change. This is a problem as BOSH assumes that
the IP address of an agent will not change after it assigned and will no
longer be able to connect to the agent.

## Deployments

Once the director is up, it's time to deploy something.

### Minikube Workarounds

Currently there is a bug, that minikube pods are unable to reach themselves through a service [minikube#1568](https://github.com/kubernetes/minikube/issues/1568).  
But there is a workaround known to solve this issue
```
$ minikube ssh
$ sudo ip link set docker0 promisc on
```

## Issues

BOSH was built to assume that it's managing _virtual machines_. These
assumptions don't always apply to containerized systems. For example, BOSH
assumes that once it's created a machine for a job, it can _reboot_ it; that's
obviously not true of a container.

#### BOSH Agent

BOSH assumes that its _agent_ is responsible for helping with many
configuration actions like setting up the network stack and mounting disks. In
some cases, like networking, the agent can be told to leave well enough alone;
in others, like mounting a disk, it just has to do *something*.

##### Networking

The `preconfigured` flag is set on all networks in the agent configuration to
prevent the agent from attempting to manage any aspect of the network
configuration.

##### Disk Management

The BOSH director uses the agent to mount and unmount disks after the CPI has
successfully performed the `attach_disk` and `detach_disk` operations. In the
context of Kubernetes, however, the kubelet is responsible for mounting
`Volumes` into the container. In order to make both happy, the `agent.json`
that is placed in the stemcell uses the `BindMountPersistentDisk` option.
Unfortunately, the agent has a [bug][bind-mount-bug] that attempts to use the
`—bind` option for all mounts - including temporary file systems. This causes
the agent to fail during bootstrap.

For the time being, a [patch](src/patches/mount-rundir-without-mounter.diff)
is being applied to correct this behavior.

##### Privileged Container Required

In its current form, the BOSH agent attempts to run actions in the container
that require `CAP_SYS_ADMIN`. At some point we need to identify what these
privileged actions are and whether or not they make sense when containerized.

#### Stable IP Addresses and Disk Management

Here are some facts:

1. BOSH assumes that once a _virtual machine_ has been created, its address
   won't change. This is true regardless of whether it's associated with a
   manual or dynamic network.
2. BOSH disk managmenent targets **running** _virtual machines_. This seems to
   be based on an assumption that the agent must `mount` the disk on the
   machine.
3. Kubernetes does not allow volumes to be added or removed from a pod after
   its creation.
4. The CPI implements disk management by recreating the pod with the
   appropriate persistent volume claims.
5. When a pod is recreated, its IP address can (and usually does) change.

Given the above, we have a bit of a problem. Since Kubernetes doesn't provide
a way to change the list of volumes and mounts on a running pod, we have to
recreate the pod to attach disks. When we do that, the IP address of the pod
changes and then BOSH gets really upset about it.

There's currently an open issue with Kubernetes to support [stable IPs][stable-ips]
but it still has a ways to go. Until then, _manual_ networks should always be
used to ensure IP address don't change.

[bosh-init]: https://github.com/cloudfoundry/bosh-init
[bosh-io]: https://bosh.io/
[calico]: https://www.projectcalico.org/
[cf-release]: https://github.com/cloudfoundry/cf-release
[diego-release]: https://github.com/cloudfoundry/diego-release
[concourse]: https://concourse.ci/
[diego-release]: https://github.com/cloudfoundry/diego-release
[garden-runc]: https://github.com/cloudfoundry/garden-runc-release
[jq]: https://stedolan.github.io/jq/
[minikube]: https://github.com/kubernetes/minikube
[warden]: https://github.com/cloudfoundry/warden
[warden-stemcell]: http://bosh.io/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent

[stable-ips]: https://github.com/kubernetes/kubernetes/issues/28969
[bind-mount-bug]: https://github.com/cloudfoundry/bosh-agent/issues/106
[calico-cni-ip]: https://github.com/projectcalico/cni-plugin/issues/223
[garden-apparmor]: https://github.com/cloudfoundry/garden-runc-release/pull/22
[bosh-mount-rundir-patch]: src/patches/bosh-mount-rundir-without-mounter.diff
[warden-ifb-patch]: src/patches/warden-ignore-ifb-errors.diff
[garden-runc-pr]: https://github.com/cloudfoundry/garden-runc-release/pull/22
[garden-release-pr]: https://github.com/cloudfoundry/diego-release/pull/255

# Credits
This is a branch from repository which was original developed by: Matthew Sykes (https://github.com/sykesm)
