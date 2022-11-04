Service X Deployment
--------------------
> GitOps pipeline to deploy Ubiwhere's Service X.

Use OSM Ops to set up a GitOps pipeline in the Affordable5G Malaga
environment. Then connect this GitHub repo and watch OSM Ops create
a Service X KNF in the Malaga cluster. Finally, collect OSM Ops
service metrics.


## Setup

The lay of the land is pretty much the same as the Malaga 2021's
[demo][malaga.2021]. But we have K3s instead of MicroK8s and the
node IPs are different: `10.11.23.195` for `node1`, `10.11.23.196`
for `node2` and `10.11.23.194` for `osm`. Same same but different.


### Before you start...

Set up a VPN tunnel as we did for the Malaga 2021's [demo][malaga.2021].


### Kubernetes cluster

So here's the good news: the Malaga environment comes with a two-node
Kubernetes cluster pre-configured for the Affordable5G demo. Specifically,
there's a K3s (version `1.24.3`) cluster made up of the two boxes
we mentioned earlier—`node1` (`10.11.23.195`) and `node2` (`10.11.23.194`).

But we still need to take care of our own stuff:

* install and configure the FluxCD CLI on `node1`;
* deploy FluxCD and OSM Ops services to the Kubernetes cluster;
* configure OSM Ops.

So here goes! SSH into `node1`

```bash
$ ssh node1@10.11.23.195
```

and install Nix

```bash
$ curl -L https://nixos.org/nix/install | sh
$ . /home/node1/.nix-profile/etc/profile.d/nix.sh
```

Then download the OSM Ops demo bundle and use it to start a Nix shell
with the tools we'll need for the show

```bash
$ wget https://github.com/martel-innovate/osmops.malaga/archive/refs/tags/a5g-0.1.0.tar.gz
$ tar xzf a5g-0.1.0.tar.gz
$ cd osmops.malaga-a5g-0.1.0
$ nix-shell
```

Now there's a snag. The FluxCD command (`flux`) won't work with the
`kubectl` version installed on `node1` and it knows zilch about K3s,
so it can't obviously run `k3s kubectl` instead of plain `kubectl`.
But the Nix shell packs a `kubectl` version compatible with `flux`,
so all we need to do is make plain `kubectl` use the same config as
`k3s kubectl`.

```bash
$ mkdir -p ~/.kube
$ sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
$ sudo chown node1:node1 ~/.kube/config
```

With this little hack in place, we can deploy Source Controller

```bash
$ flux check --pre
$ flux install \
    --namespace=flux-system \
    --network-policy=false \
    --components=source-controller
```

Next up, our very own OSM Ops. First off, we need to tell OSM Ops how
to connect to the OSM NBI running on the `osm` box (`10.11.23.194`).
Create an `nbi-connection.yaml` file

```bash
$ nano nbi-connection.yaml
```

with the content below (replace the password with the actual one)

```yaml
hostname: 10.11.23.194:80
project: admin
user: admin
password: ***
```

Since we've got a password there, we'll stash this config away in a
Kubernetes secret:

```bash
$ kubectl -n flux-system create secret generic nbi-connection \
    --from-file nbi-connection.yaml
```

Finally, deploy the OSM Ops service to the Kubernetes cluster

```bash
$ kubectl apply -f deployment/osmops.deploy.yaml
```

If you open up `osmops.deploy.yaml`, you'll see the OSM Ops service
gets deployed to the same namespace of Source Controller, namely
`flux-system`, and runs under the same account. Also, notice our
secret above becomes available to OSM Ops at

    /etc/osmops/nbi-connection.yaml

More about it later.


### OSM cluster

The OSM cluster has already been set up for us, yay! In fact, the `osm`
node (`10.11.23.194`) hosts a fully-fledged OSM Release 11 instance
configured with a VIM account called `dummyvim` that's tied to the
Kubernetes (K3s) cluster. Also, the OSM config includes the Helm
chart repos below:

- https://charts.bitnami.com/bitnami
- https://cetic.github.io/helm-charts
- https://helm.elastic.co
- http://osm-download.etsi.org/ftp/Packages/vnf-onboarding-tf/helm/
- https://pencinarsanz-atos.github.io/nemergent-chart/
- https://affordable5gintegrations.github.io/affordable5g-chart

The last one is actually the only one we care about for this demo
since it hosts the Helm chart for "Service X" which is what we're
going to deploy through our GitOps pipeline. To create NS instances
from that chart there have to be an NSD and VNFD in OSM. Luckily,
OSM Ops supports installing both NSD and VNFD packages from a Git
repo. So we're going to set up our GitOps pipeline to do that too.


## Doing GitOps with OSM

After toiling away at prep steps, we're finally ready for some GitOps
action. In fact, we're going make OSM Ops create Service X KNF & NS
packages and then use them to instantiate a Service X KNF.

Specifically, we'll start off with the deployment configuration in
this repo at tag [a5g-0.2.0][a5g-0.2.0]. At this tag, the repo contains
a [deployment directory][a5g-0.2.0.deploy] with

* A [Service X KNF package source][a5g-0.2.0.knf].
* A [Service X NS package source][a5g-0.2.0.ns].

On processing the repo at tag `a5g-0.2.0`, OSM Ops will create the
Service X KNF and NS packages in OSM. The way OSM Ops handles
packages is a bit more involved, you can [read about it here][docs.pkgs],
but for the purpose of this demo all you need to know is that OSM
Ops can create or update OSM packages from source directories you
keep in your GitOps repo. Each source directory contains the files
you'd normally use to make an OSM package tarball, except for the
`checksums.txt` file which OSM Ops generates for you when making
the tarball.

After making OSM Ops create the packages, we'll simulate a commit
to this repo by switching over to tag [a5g-0.3.0][a5g-0.3.0]. The
repo's content at this tag is the same as at `a5g-0.2.0`, except for
a new

* [OSM Ops YAML file][a5g-0.3.0.kdu] requesting the OSM cluster
  to run a Service X KNF instantiated from NSD, VNFD and KDU
  descriptors found in the packages OSM Ops created earlier.

Read the [Local clusters][demo.local] demo's section about GitOps
for an explanation of the OSM Ops YAML file.


### Setting up the OSM Ops pipeline

The OSM Ops show starts as soon as you connect a Git repo through
FluxCD. As mentioned earlier, we're going to use this very repo on
GitHub at tag `a5g-0.2.0`. Go back to your SSH terminal on `node1`
and create an `osmops.malaga` Git source within Flux like so:

```bash
$ nix-shell
$ flux create source git osmops.malaga \
    --url=https://github.com/martel-innovate/osmops.malaga \
    --tag=a5g-0.2.0
```

This command creates a Kubernetes GitRepository custom resource. As
soon as Source Controller gets notified of this new custom resource,
it'll fetch the content of `a5g-0.2.0` and make it available to OSM
Ops which will then realise the deployment config in the OSM cluster.
As explained in the [Local clusters][demo.local] demo, OSM Ops figures
out which OSM cluster to connect to by reading the `osm_ops_config.yaml`
file in the root of the repo directory tree it gets from Source Controller.
At `a5g-0.2.0`, the content of that file is

```yaml
targetDir: deployment
fileExtensions:
  - .ops.yaml
connectionFile: /etc/osmops/nbi-connection.yaml
```

This configuration tells OSM Ops to get the OSM connection details
from `/etc/osmops/nbi-connection.yaml`. Ha! Remember that Kubernetes
secret mounted on the OSM Ops pod? Yep, that's how it happens! The
other fields tell OSM Ops to look for OSM Ops GitOps files in the
`deployment` directory (recursively) and only consider files with
an extension of `.ops.yaml`. As for OSM package sources, OSM Ops
looks for them in the `osm-pkgs` dir beneath the target dir, which
in our case is: `deployment/osm-pkgs`.


### Watching reconciliation as it happens

Now browse to the OSM Web UI (http://10.11.23.194/) and log in with
the OSM admin user—username: `admin`. You should be able to see that
OSM now has both a Service X KNF and NS package. If you grab the OSM
Ops logs, you should see what OSM Ops did. The log file should contain
entries similar to the ones below.

```bash
$ kubectl -n flux-system logs deployment/source-watcher
```

```log
2022-11-04T08:13:08.878Z	INFO	controller.gitrepository	New revision detected	{"reconciler group": "source.toolkit.fluxcd.io", "reconciler kind": "GitRepository", "name": "osmops.malaga", "namespace": "flux-system", "revision": "a5g-0.2.0/bc575d59ede0a618d5f82f243990ead44863eefd"}
2022-11-04T08:13:08.882Z	INFO	controller.gitrepository	Extracted tarball into /tmp/osmops.malaga469249219: 7 files, 4 dirs (775.722µs)	{"reconciler group": "source.toolkit.fluxcd.io", "reconciler kind": "GitRepository", "name": "osmops.malaga", "namespace": "flux-system"}
2022-11-04T08:13:08.882Z	INFO	controller.gitrepository	processing	{"reconciler group": "source.toolkit.fluxcd.io", "reconciler kind": "GitRepository", "name": "osmops.malaga", "namespace": "flux-system", "osm package": "/tmp/osmops.malaga469249219/deployment/osm-pkgs/servicex_knf"}
2022-11-04T08:13:09.106Z	INFO	controller.gitrepository	processing	{"reconciler group": "source.toolkit.fluxcd.io", "reconciler kind": "GitRepository", "name": "osmops.malaga", "namespace": "flux-system", "osm package": "/tmp/osmops.malaga469249219/deployment/osm-pkgs/servicex_ns"}
```

Let's ask OSM to instantiate a Service X KNF. As a rule, you'd do
that by committing an OSM Ops YAML to the repo. For the sake of making
this demo reproducible, we put together an [OSM Ops YAML file][a5g-0.3.0.kdu]
requesting OSM to run a Service X KNF instantiated from NSD, VNFD
and KDU descriptors found in the packages OSM Ops created earlier.
That file sits in this repo at tag [a5g-0.3.0][a5g-0.3.0]. So we're
going to simulate a commit by switching over to tag `a5g-0.3.0`.

```bash
$ flux create source git osmops.malaga \
    --url=https://github.com/martel-innovate/osmops.malaga \
    --tag=a5g-0.3.0
```

The OSM Web UI should show OSM is busy creating a new NS instance
called `servicex`, similar to what you see on the screenshot in the
[Local clusters][demo.local] demo. The OSM Ops log file should have
entries similar to the ones below.

```log
2022-11-04T08:31:38.102Z	INFO	controller.gitrepository	New revision detected	{"reconciler group": "source.toolkit.fluxcd.io", "reconciler kind": "GitRepository", "name": "osmops.malaga", "namespace": "flux-system", "revision": "a5g-0.3.0/0459397846367418f340cb03fb41a1b86c2dd3f2"}
2022-11-04T08:31:38.105Z	INFO	controller.gitrepository	Extracted tarball into /tmp/osmops.malaga821211462: 8 files, 5 dirs (1.021003ms)	{"reconciler group": "source.toolkit.fluxcd.io", "reconciler kind": "GitRepository", "name": "osmops.malaga", "namespace": "flux-system"}
2022-11-04T08:31:38.105Z	INFO	controller.gitrepository	processing	{"reconciler group": "source.toolkit.fluxcd.io", "reconciler kind": "GitRepository", "name": "osmops.malaga", "namespace": "flux-system", "osm package": "/tmp/osmops.malaga821211462/deployment/osm-pkgs/servicex_knf"}
2022-11-04T08:31:38.176Z	INFO	controller.gitrepository	processing	{"reconciler group": "source.toolkit.fluxcd.io", "reconciler kind": "GitRepository", "name": "osmops.malaga", "namespace": "flux-system", "osm package": "/tmp/osmops.malaga821211462/deployment/osm-pkgs/servicex_ns"}
2022-11-04T08:31:38.243Z	INFO	controller.gitrepository	processing	{"reconciler group": "source.toolkit.fluxcd.io", "reconciler kind": "GitRepository", "name": "osmops.malaga", "namespace": "flux-system", "file": "/tmp/osmops.malaga821211462/deployment/kdu/servicex.ops.yaml"}
```

Eventually, K3s should create two Kubernetes services as specified
in Service X's Helm chart. One service is called "api", the other
"web". In fact, if you can check what's going on in K3s land by
running the commands below.

```bash
# figure out in which namespace OSM put Service X's pods
$ kubectl get ns
#              ^ pick the one that looks like an UUID

# check Service X's pods are up and running
$ kubectl -n cf6786a7-cf47-42ce-9dbd-db7ffd509433 get pod
NAME                   READY   STATUS    RESTARTS   AGE
api-7d767f7fd5-7h9gv   1/1     Running   0          12m
web-846d8b957c-f6n4x   1/1     Running   0          12m

# logs should report no errors
$ kubectl -n cf6786a7-cf47-42ce-9dbd-db7ffd509433 logs svc/api
INFO:     Will watch for changes in these directories: ['/usr/src/app']
INFO:     Uvicorn running on http://0.0.0.0:5000 (Press CTRL+C to quit)
INFO:     Started reloader process [1] using StatReload
INFO:     Started server process [8]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
```

At this point, the OSM Web UI should also show the `servicex` NS
instance is fully operational with a green checkmark as in the
screenshot below.

![OSM done creating Service X instance.][osm-ui.done]


### Collecting OSM Ops metrics

OSM Ops publishes services metrics in OpenMetrics format. Metrics
scrapers can collect data from the OSM Ops HTTP endpoint on port
`8080` and path `/metrics`.

Here's an example of how do that manually with `curl`. Log onto
`node1` and port-forward the OSM Ops metrics endpoint:

```bash
$ kubectl port-forward -n flux-system deployment/source-watcher 8080:8080
```

Then in another terminal, still on `node1`, pull down the current
measurements

```bash
$ curl localhost:8080/metrics
```

[This file][metrics] contains the measurements we got during this
demo. On average reconciliation took about `0.6` seconds.




[a5g-0.2.0]: https://github.com/martel-innovate/osmops.malaga/tree/a5g-0.2.0
[a5g-0.2.0.deploy]: https://github.com/martel-innovate/osmops.malaga/tree/a5g-0.2.0/deployment
[a5g-0.2.0.knf]: https://github.com/martel-innovate/osmops.malaga/tree/a5g-0.2.0/deployment/osm-pkgs/servicex_knf
[a5g-0.2.0.ns]: https://github.com/martel-innovate/osmops.malaga/tree/a5g-0.2.0/deployment/osm-pkgs/servicex_ns
[a5g-0.3.0]: https://github.com/martel-innovate/osmops.malaga/tree/a5g-0.3.0
[a5g-0.3.0.kdu]: https://github.com/martel-innovate/osmops.malaga/tree/a5g-0.3.0/deployment/kdu
[demo.local]: https://github.com/martel-innovate/osmops/blob/main/docs/demos/local-clusters.md
[docs.pkgs]: https://github.com/martel-innovate/osmops/blob/main/docs/osm-pkgs.md
[osmops.malaga]: https://github.com/martel-innovate/osmops.malaga
[osm-ui.done]: ./osm-ui-done.png
[malaga.2021]: https://github.com/martel-innovate/osmops/blob/main/docs/demos/malaga.md
[metrics]: ./metrics.txt