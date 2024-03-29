+++
title = "Kubernetes resource management and you"
description = "I’ll explain what scheduling and resource management exactly is, how you configure and use them, and go into some best practices."
[taxonomies]
tags = ["kubernetes"]
+++

Scheduling and resource management is a topic many Kubernetes users seem to struggle with, even though it is vital to understand it and correctly configure your workload to ensure optimal resource usage and application availability. In this article, I'll explain what scheduling and resource management exactly is, how you configure and use them, and go into some best practices.

<!-- more -->

I have written this article as part of my work at [VSHN AG](https://www.vshn.ch/). It was first published in the [VSHN Knowledge Base](https://kb.vshn.ch/cloud-kubernetes/explanations/kubernetes_resource_management.html). By the way, if you like this kind of stuff, [we're usually hiring](https://www.vshn.ch/en/jobs/)!

**Target audience**: This is a technical article targeting developers deploying applications onto Kubernetes, as well as cluster administrators.

## Resource Requests & Limits on Pods & Containers

### Requests vs Limits

When creating a Pod in Kubernetes, it's possible to specify its resource requirements for its containers. This is done using two concepts called _requests_ and _limits_:

{% admonition(type="TIP") %}
Resource requests and limits are defined on a _Container_ level, however since a _Pod_ is the smallest schedulable unit I use the term "a Pod's resources" in this article. A _Pod's_ resources is simply the sum of its _Containers'_ resources.
{% end %}

<dl>
{% definition(title="Requests" ) %}
An amount of resources that a container must have _guaranteed_ to have available. When a Pod is running on a Node, those resources will be reserved for that pod.
{% end %}

{% definition(title="Limits" ) %}
As the name implies, a _limit_ of how much of a given resource the container may contain for short periods of time. I'll explain what happens when a container exceeds this limits later in this article.
{% end %}
</dl>

### Resource Types

The two resource types that can be configured are **CPU** and **Memory**.

(for Kubernetes 1.14+ there's also the "huge pages" resource type, but we'll not go into those in this article.)

<dl>
{% definition(title="CPU") %}
Resource requests and limits for CPU are measured in "CPU units". One CPU (vCPU/Core on cloud providers, hyper thread on bare metal) is equivalent to 1 CPU unit.

CPU requests and limits can be expressed as mCPU (milli CPU), or "millicore" as they are often referred to as. Each CPU can be divided into 1000 mCPU (because, you know, that's what "milli" means).

- `500m` - half a CPU
- `1000m` == `1` - one CPU
- `100m` - one tenth of a CPU

The smallest allowed precision is `1m`.
{% end %}

{% admonition(type="TIP") %}
CPU units are always measured as an absolute quantity, not as relative ones. So "1 CPU unit" is the same amount of CPU on a single core system as it is on a 256 core machine. However the single core system will only have one CPU unit capacity (we'll come to that later), while the 256 core machine will have 256 CPU units capacity.
{% end %}

{% definition(title="Memory") %}
Resource requests and limits for Memory are measured in bytes. You can use the following suffixes = K, M, G, T, P, E, Ki, Mi, Gi, Ti, Pi, Ei:

- `1K` == 1000
- `1Ki` == 1024
- `1M` == `1000K` == 1'000'000
- `1Mi` == `1024Ki` == 1'048'576
- ... and so on

Usually the "power of two" suffixes (Ki, Mi, Gi, ...) are used, so if you're unsure what to use, stick to them.
{% end %}
</dl>


### Configuring Requests & Limits

Configuring resource requests & limits is done by setting the `.spec.containers[].resources` field on a **container** spec:

```yaml,hl_lines=10-16
# Example Pod
apiVersion: v1
kind: Pod
metadata:
  name: resource-example
spec:
  containers:
    - name: app
      image: app
      resources:
        requests:
          cpu: "100m" # <1>
          memory: "128Mi" # <2>
        limits:
          cpu: "1" # <3>
          memory: "1Gi" # <4>
```

1. CPU requests
2. Memory requests
3. CPU limits
4. Memory limits

{% admonition(type="NOTE") %}
Since pods usually are created by Deployments (or DeploymentConfigs if you are using OpenShift), you would instead set the deployment's `.spec.template.spec.containers[].resources` field.
{% end %}

It is not necessary to set _all_ of the values. For example it's possible to configure only Memory requests and CPU limits.

{% admonition(type="TIP") %}
The usage of resource requests and limits can be enforced using LimitRanges. They can define the range of possible values as well as **default values that will be applied if you do NOT specify any resource requests or limits**.
{% end %}

## Scheduling

In order to understand resource management properly, we first have to understand how `kube-scheduler`, the default scheduler for Kubernetes, works.

> In Kubernetes, scheduling refers to making sure that Pods are matched to Nodes so that Kubelet can run them.
>
> _-- Kubernetes documentation_

The job of the scheduler is to take new Pods and assign them to a Node in the cluster.

{% admonition(type="TIP") %}
It is possible to implement your own scheduler, however for most use cases the default `kube-scheduler` is sufficient -- especially since it can be [customized using scheduling policies](https://kubernetes.io/docs/reference/scheduling/policies/).

Word is that CERN implemented its own scheduler to achieve workload packing (= avoiding workloads to be spread across nodes), however today [this can be achieved using scheduler policies](https://clouddocs.web.cern.ch/containers/tutorials/scheduling.html).
{% end %}

### `kube-scheduler`

Whenever kube-scheduler sees a new Pod that is not assigned to a Node (indicated by the fact that the Pod's `.spec.nodeName` is not set), it assigns the Pod to a Node in two phases:

<dl>
{% definition(title="Filtering") %}
During this phase, the scheduler determines which nodes are eligible for the Pod to be scheduled on. In the beginning, all nodes are candidates. The scheduler then applies various filter plugins, for example: Does the Node fit the Pods `nodeSelector`? Has the Node sufficient resources available? Has the Node any taints that are not tolerated by the pod? Is the Node marked as unschedulable? Does the Pod request any special features, for example a GPU?

If after this step no Nodes are left, the Pod will not be assigned to a Node and stay in "Pending" state. An Event is added to the Pod explaining why scheduling failed.

[Scheduling policy predicates](https://kubernetes.io/docs/reference/scheduling/policies/) can be used to configure the _Filtering_ step of scheduling.
{% end %}

{% admonition(type="TIP") %}
If a pod stays in "Pending", use `kubectl describe pod/<POD>` and check the "Events" section to see why it failed.
{% end %}

{% definition(title="Scoring") %}
In the second phase, the remaining Nodes are ranked. Again, various scoring plugins are used.

The default configuration tries to spread workload as even across the cluster as possible, minimizing the impact of a node becoming unavailable.
{% end %}
</dl>

Once these two steps are completed, the scheduler will assign the Pod to the highest-ranking Node, and the Kubelet on that node will spin up its containers.

### Resources and scheduling

As we can see, both the _Filtering_ and _Scoring_ phases of scheduling take "resources" into consideration, so let's have a look at them next.

The two most important resources are CPU and Memory (RAM). Kubernetes tracks other resources as well (like disk space, available PIDs or network ports) but we'll focus on this two.

Upon startup, the Kubelet determine how much resources the system it runs on has available. This is called the node's _capacity_. Next, it reserves a certain amount of CPU and Memory for itself and the system. What's left is called the Node's _allocatable_ resources. The Kubelet will communicate this information back to the control plane.

{% admonition(type="TIP") %}
If you are cluster-admin, you can view a Node's resources using the `kubectl describe node <NODE>` command (watch for the `Capacity` and `Allocatable` keys) or in the Node object's `.status.capacity` and `.status.allocatable` fields.
{% end %}

During scheduling, this information is used to determine whether a Pod would "fit" onto a Node or not by taking a Node's _allocatable_ resources and subtracting the _requests_ of all Pods already running on the Node. If the remaining resources are greater than the _requests_ of the Pod, it will fit.

## Out of resource handling

Before we look into what happens when a node runs out of a resource, we first have to cover another concept: Quality of Service classes

### QoS Classes

Kubernetes knows three QoS classes: "Guaranteed", "Burstable" and "BestEffort".

When a Pod starts, its QoS class is determine based on the resource requests and limits of its containers:

**Guaranteed** is assigned when

- every container has both requests and limits set for both CPU and Memory
- for each container, the requests and limits have the same values set.

The Pod is _guaranteed_ to have the resources it has requested available.

**Burstable** is assigned when a Pod does not qualify for the "Guaranteed" QoS class, but at least one container has CPU or Memory requests set.

The Pod has its requested resources available, but may use more resources for a short period (aka _burst_).

**BestEffort** is assigned to Pods that have no requests or limits set at all.

The Pod may use resources available on a _best effort_ basis.

### What happens when a Pod exceeds its resource limits

**CPU** is a so-called "compressible" resource. This means, when a container exceeds its CPU usage limits, it will simply be throttled. A container with a CPU limit of "100m" cannot use more than 0.1 seconds of CPU time each second.

**Memory** on the other hand is not "compressible", so when a container exceeds its memory limit, it will be terminated (and restarted of course).

### What happens when a node runs out of resources

Again, since **CPU** is a "compressible" resource, the Kubelet does not act on CPU starvation. Each container will have the CPU resources available that it _requested_ - yes, this means that "BestEffort" Pods really get into a tight spot...

Out of **Memory** handling however triggers an _eviction_. While evictions (and how they can be configured) would cover a whole blog post on its own, it usually ends with Pods being terminated and moved to different nodes. This is where the QoS classes play an important role: They decide, _who_ gets killed:

First in line are pods that exceed their memory requests are killed, based on their memory usage in relation to their memory requests. Since "BestEffort" pods do not have any requests at all, they will be killed first. However, "Burstable" Pods might also be killed if they exceed their requests.

Since "Guaranteed" pods cannot exceed their requests (because they are equal to their limits), they are never killed because of another pods resource usage.

However, in the rare case that system services on a node (not running in Kubernetes) use more resources than was reserved for them (see "resource reservations" in "Resources and scheduling"), even "Burstable" or "Guaranteed" pods will be killed.

### What happens when a cluster runs out of resources

This is the case if your overall resource requests exceed the allocateable resources within your cluster. In this case, when a new pod that has resource requests for the starved resource, it cannot be scheduled and will remain in status "Pending".

## Best practices

You should now have a fairly good understanding of how scheduling works on Kubernetes. As a conclusion, I want to share a few best practices:

- **Use requests and limits extensively** - it helps the scheduler to distribute your workload more evenly across your cluster.
- **Use QoS classes to your advantage**, for example by making sure all production workloads are assigned a "Guaranteed" QoS class. This means that in case of an out of resource situation, your production environment is not killed by the OOM killer.

For cluster administrators, there are some more points:

- **Plan AT LEAST one node worth of CPU and memory as "leftover".** This allows your cluster to tolerate the loss of a node - both planned (during maintenance) or unplanned (node crashes).

## Further reading

- Kubernetes docs
  - [Kubernetes Scheduler](https://kubernetes.io/docs/concepts/scheduling-eviction/)
  - [Assign Memory Resources to Containers and Pods](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/)
  - [Assign CPU Resources to Containers and Pods](https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/)
  - [Configure Quality of Service for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/)
  - [Configure Out of Resource Handling](https://kubernetes.io/docs/tasks/administer-cluster/out-of-resource/)
